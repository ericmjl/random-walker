import CoreLocation
import Foundation
import Observation
import SwiftData
import RandomWalkerCore

@MainActor
@Observable
final class WalkSessionViewModel {
    var isPlanning = false
    var planningError: String?
    var refinedWalk: RoutedWalk?
    var activeBlueprint: LoopWalkBlueprint?
    var refinementSummary: String?

    /// True while the user is following on-phone guidance for `refinedWalk`.
    var isNavigating = false
    /// Shown once when automatic step progression reaches the end of the route.
    var navigationCompletionNotice: String?

    /// True while recomputing directions from the current GPS fix after a deviation.
    var isReplanningFromDeviation = false

    private var routeNavigator: WalkRouteNavigator?

    @ObservationIgnored
    private var recordedNavigationPath: [CLLocationCoordinate2D] = []
    @ObservationIgnored
    private var navigationStartedAt: Date?
    /// Where the user stood when **Start** was tapped (return-to-start completion).
    @ObservationIgnored
    private var navigationStartCoordinate: CLLocationCoordinate2D?
    @ObservationIgnored
    private var hasVenturedFromStart: Bool = false
    @ObservationIgnored
    private var returnToStartEnteredAt: Date?

    private let targetDuration: TimeInterval = 3_600
    private let durationToleranceLower: Double = 0.72
    private let durationToleranceUpper: Double = 1.38
    private let maxAttempts = 8

    private static let returnToStartRadiusMeters: CLLocationDistance = 40
    private static let returnToStartDwellSeconds: TimeInterval = 10
    private static let ventureOutMinMeters: CLLocationDistance = 90

    func planHourLoop(
        around center: GeodesicWaypoint,
        connectivity: PhoneConnectivityManager
    ) async {
        guard !isPlanning else { return }
        discardNavigationWithoutSaving()
        isPlanning = true
        planningError = nil
        refinementSummary = nil
        defer { isPlanning = false }

        let configuration = RandomWalkGenerator.Configuration(targetDuration: targetDuration)
        var radiusScale = 1.0

        for attempt in 0 ..< maxAttempts {
            var rng = SplitMix64RNG(seed: UInt64.random(in: .min ... .max))
            let blueprint = RandomWalkGenerator.makeBlueprint(
                center: center,
                configuration: configuration,
                rng: &rng,
                radiusScale: radiusScale
            )

            do {
                let routed = try await RoutingService.routeWalkingLoop(blueprint: blueprint)
                let ratio = routed.expectedTravelTime / targetDuration

                if ratio.isFinite && ratio >= durationToleranceLower && ratio <= durationToleranceUpper {
                    refinedWalk = routed
                    activeBlueprint = blueprint
                    refinementSummary = "Matched your hour window on attempt \(attempt + 1)."
                    connectivity.sendActiveWalk(routed.makeWatchSnapshot(startedAt: .now))
                    return
                }

                let adjustedScale = radiusScale * (targetDuration / max(routed.expectedTravelTime, 120))
                radiusScale = min(2.8, max(0.35, adjustedScale))
                refinementSummary =
                    "Refining loop length (attempt \(attempt + 1)): Maps suggested \(Int(routed.expectedTravelTime / 60)) min."
            } catch {
                planningError = error.localizedDescription
                refinedWalk = nil
                activeBlueprint = nil
                return
            }
        }

        planningError = "Could not find a walking loop close to one hour after \(maxAttempts) tries. Try again."
        refinedWalk = nil
        activeBlueprint = nil
    }

    var navigationStepIndex: Int {
        routeNavigator?.currentIndex ?? 0
    }

    var navigationStepCount: Int {
        routeNavigator?.steps.count ?? 0
    }

    func startNavigation(seedLocation: CLLocation?) {
        guard let walk = refinedWalk else { return }
        let steps = WalkRouteNavigator.flattenedSteps(from: walk)
        guard !steps.isEmpty else { return }
        recordedNavigationPath = []
        navigationStartedAt = .now
        navigationStartCoordinate = seedLocation?.coordinate ?? walk.coordinates.first
        hasVenturedFromStart = false
        returnToStartEnteredAt = nil
        if let coord = seedLocation?.coordinate {
            recordedNavigationPath.append(coord)
        }
        routeNavigator = WalkRouteNavigator(steps: steps)
        navigationCompletionNotice = nil
        isNavigating = true
    }

    /// Ends guidance without persisting (e.g. *Discard* on the stop confirmation).
    func discardNavigationWithoutSaving() {
        isNavigating = false
        routeNavigator = nil
        navigationCompletionNotice = nil
        recordedNavigationPath = []
        navigationStartedAt = nil
        navigationStartCoordinate = nil
        hasVenturedFromStart = false
        returnToStartEnteredAt = nil
    }

    /// Persists the trace so far, then ends guidance (planned route stays on the map).
    func stopAndSaveToHistory(modelContext: ModelContext) {
        guard isNavigating, let routed = refinedWalk, let blueprint = activeBlueprint else {
            discardNavigationWithoutSaving()
            return
        }
        persistWalk(
            routed: routed,
            blueprint: blueprint,
            modelContext: modelContext,
            completionKind: .savedOnStop
        )
        discardNavigationWithoutSaving()
        navigationCompletionNotice = "Saved your walk so far to History."
    }

    func acknowledgeNavigationCompletion() {
        navigationCompletionNotice = nil
        routeNavigator = nil
        recordedNavigationPath = []
        navigationStartedAt = nil
        navigationStartCoordinate = nil
        hasVenturedFromStart = false
        returnToStartEnteredAt = nil
    }

    func ingestNavigationLocation(_ location: CLLocation, modelContext: ModelContext) {
        guard isNavigating, var navigator = routeNavigator else { return }
        appendRecordedSample(location.coordinate)
        navigator.ingest(userLocation: location)
        routeNavigator = navigator

        if navigator.isComplete {
            if let routed = refinedWalk, let blueprint = activeBlueprint {
                finishSessionSaving(
                    routed: routed,
                    blueprint: blueprint,
                    completionKind: .guidedComplete,
                    modelContext: modelContext,
                    notice: "You finished the loop. Saved to History."
                )
            }
            return
        }

        evaluateReturnToStartProximity(location: location, modelContext: modelContext)
    }

    func navigationInstructionText() -> String? {
        guard let raw = routeNavigator?.currentStep?.instruction else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Continue" : trimmed
    }

    func navigationThenText() -> String? {
        guard let next = routeNavigator?.upcomingStep else { return nil }
        let text = next.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : "Then \(text)"
    }

    func distanceToNavigationManeuver(from location: CLLocation) -> CLLocationDistance? {
        routeNavigator?.distanceToCurrentManeuver(from: location)
    }

    func maneuverCoordinateForNavigation() -> CLLocationCoordinate2D? {
        routeNavigator?.currentStep?.maneuverCoordinate
    }

    /// Re-fetches walking legs from the current fix through the rest of the planned waypoints.
    func replanFromCurrentLocation(_ location: CLLocation, connectivity: PhoneConnectivityManager) async {
        guard isNavigating, let walk = refinedWalk, let blueprint = activeBlueprint, let navigator = routeNavigator
        else { return }
        guard !isReplanningFromDeviation else { return }

        guard let nextIdx = walk.nextVisitSequenceIndex(afterNavigatorStep: navigator.currentIndex) else {
            planningError = "Route already complete in guidance — nothing to recalculate."
            return
        }

        isReplanningFromDeviation = true
        planningError = nil
        defer { isReplanningFromDeviation = false }

        do {
            let resumed = try await RoutingService.routeWalkingResume(
                from: location.coordinate,
                visitSequence: blueprint.visitSequenceCoordinates,
                nextVisitIndex: nextIdx
            )
            refinedWalk = resumed
            routeNavigator = WalkRouteNavigator(steps: WalkRouteNavigator.flattenedSteps(from: resumed))
            connectivity.sendActiveWalk(resumed.makeWatchSnapshot(startedAt: navigationStartedAt ?? .now))
            refinementSummary = "Updated route from your position."
        } catch {
            planningError = error.localizedDescription
        }
    }

    private func evaluateReturnToStartProximity(location: CLLocation, modelContext: ModelContext) {
        guard let anchor = navigationStartCoordinate else { return }
        let anchorLoc = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
        let distanceFromStart = location.distance(from: anchorLoc)
        let now = Date()

        if distanceFromStart >= Self.ventureOutMinMeters {
            hasVenturedFromStart = true
        }
        guard hasVenturedFromStart else { return }

        if distanceFromStart <= Self.returnToStartRadiusMeters {
            if let enteredAt = returnToStartEnteredAt {
                if now.timeIntervalSince(enteredAt) >= Self.returnToStartDwellSeconds {
                    if let routed = refinedWalk, let blueprint = activeBlueprint {
                        finishSessionSaving(
                            routed: routed,
                            blueprint: blueprint,
                            completionKind: .returnedToStart,
                            modelContext: modelContext,
                            notice:
                            "You returned near your start. Saved to History."
                        )
                    }
                }
            } else {
                returnToStartEnteredAt = now
            }
        } else {
            returnToStartEnteredAt = nil
        }
    }

    private func finishSessionSaving(
        routed: RoutedWalk,
        blueprint: LoopWalkBlueprint,
        completionKind: WalkCompletionKind,
        modelContext: ModelContext,
        notice: String
    ) {
        persistWalk(
            routed: routed,
            blueprint: blueprint,
            modelContext: modelContext,
            completionKind: completionKind
        )
        isNavigating = false
        routeNavigator = nil
        navigationCompletionNotice = notice
        recordedNavigationPath = []
        navigationStartedAt = nil
        navigationStartCoordinate = nil
        hasVenturedFromStart = false
        returnToStartEnteredAt = nil
    }

    private func appendRecordedSample(_ coordinate: CLLocationCoordinate2D) {
        if let last = recordedNavigationPath.last {
            let previous = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let next = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard previous.distance(from: next) >= WalkSessionViewModel.recordedSampleMinSeparationMeters else {
                return
            }
        }
        recordedNavigationPath.append(coordinate)
    }

    private static let recordedSampleMinSeparationMeters: CLLocationDistance = 8

    private func persistWalk(
        routed: RoutedWalk,
        blueprint: LoopWalkBlueprint,
        modelContext: ModelContext,
        completionKind: WalkCompletionKind
    ) {
        let pathCoordinates: [CLLocationCoordinate2D]
        let distanceMeters: CLLocationDistance
        if recordedNavigationPath.count >= 2 {
            pathCoordinates = recordedNavigationPath
            distanceMeters = Self.pathLengthMeters(recordedNavigationPath)
        } else {
            pathCoordinates = routed.coordinates
            distanceMeters = routed.distanceMeters
        }

        let elapsedSeconds = navigationStartedAt.map { Date().timeIntervalSince($0) } ?? routed.expectedTravelTime
        let points = pathCoordinates.map(GeodesicWaypoint.init(_:))
        let encoded = PolylineCodec.encode(coordinates: points)

        let titleDate = DateFormatter.walkTitle.string(from: .now)
        let record = WalkRecord(
            id: UUID(),
            targetDurationSeconds: targetDuration,
            routedDistanceMeters: distanceMeters,
            routedExpectedDurationSeconds: max(1, elapsedSeconds),
            encodedPolyline: encoded,
            blueprintSalt: blueprint.randomSalt,
            centerLatitude: blueprint.center.latitude,
            centerLongitude: blueprint.center.longitude,
            title: titleDate,
            completionKindRaw: completionKind.rawValue
        )

        modelContext.insert(record)
        try? modelContext.save()
    }

    private static func pathLengthMeters(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count >= 2 else { return 0 }
        var total: CLLocationDistance = 0
        for index in 1 ..< coordinates.count {
            let a = CLLocation(
                latitude: coordinates[index - 1].latitude,
                longitude: coordinates[index - 1].longitude
            )
            let b = CLLocation(
                latitude: coordinates[index].latitude,
                longitude: coordinates[index].longitude
            )
            total += a.distance(from: b)
        }
        return total
    }

    func clearActiveWalk(connectivity: PhoneConnectivityManager) {
        discardNavigationWithoutSaving()
        refinedWalk = nil
        activeBlueprint = nil
        connectivity.clearWalkOnWatch()
    }
}

private extension DateFormatter {
    static let walkTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
