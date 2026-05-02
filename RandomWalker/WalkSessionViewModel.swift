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
    /// Correlates watch GPS recording with this navigation session (`WatchConnectivity`).
    @ObservationIgnored
    private var watchNavigationSessionId: UUID?
    @ObservationIgnored
    private var mergedWatchTrack: WatchRecordedTrack?

    /// Pace used for **duration** goals and user-facing ETAs (`distance / pace`), aligned with ``planLoop(around:connectivity:walkingSpeedMetersPerSecond:)``.
    @ObservationIgnored
    private var planningPaceMetersPerSecond: Double = RandomWalkGenerator.defaultWalkingSpeedMetersPerSecond

    /// User-chosen target for the next ``planLoop(around:connectivity:walkingSpeedMetersPerSecond:)`` (Plan sheet).
    var planningLengthGoal: WalkLengthGoal = .duration(3_600)

    /// After a walk is saved, receives observed `(distanceMeters, durationSeconds)` for pace learning.
    var onWalkSavedObservedPace: ((Double, Double) -> Void)?

    private let lengthToleranceLower: Double = 0.72
    private let lengthToleranceUpper: Double = 1.38
    private let maxAttempts = 8

    /// In-range routes are ranked by lower **re-walk** debt first, then closeness to the exact length target.
    private struct LoopPlanCandidate {
        let routed: RoutedWalk
        let blueprint: LoopWalkBlueprint
        let ratioGap: Double
        let rewalkDebt: Double
        let attempt: Int
    }

    private static let returnToStartRadiusMeters: CLLocationDistance = 40
    private static let returnToStartDwellSeconds: TimeInterval = 10
    private static let ventureOutMinMeters: CLLocationDistance = 90

    func planLoop(
        around center: GeodesicWaypoint,
        connectivity: PhoneConnectivityManager,
        walkingSpeedMetersPerSecond: Double
    ) async {
        guard !isPlanning else { return }
        discardNavigationWithoutSaving(connectivity: connectivity)
        isPlanning = true
        planningError = nil
        refinementSummary = nil
        planningPaceMetersPerSecond = max(0.5, walkingSpeedMetersPerSecond)
        defer { isPlanning = false }

        let configuration = RandomWalkGenerator.Configuration(
            lengthGoal: planningLengthGoal,
            walkingSpeedMetersPerSecond: walkingSpeedMetersPerSecond
        )
        var radiusScale = 1.0
        var best: LoopPlanCandidate?
        var bestNearMiss: LoopPlanCandidate?
        var inBandCount = 0
        var lastRoutingError: String?

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
                let (targetMetric, routedMetric) = planningTargetMetrics(using: planningLengthGoal, routed: routed)
                let ratio = routedMetric / targetMetric

                if ratio.isFinite && ratio >= lengthToleranceLower && ratio <= lengthToleranceUpper {
                    let polyline = routed.coordinates.map(GeodesicWaypoint.init(_:))
                    let debt = RewalkProximity.debtMeters(polyline: polyline)
                    let ratioGap = abs(1.0 - ratio)
                    let candidate = LoopPlanCandidate(
                        routed: routed,
                        blueprint: blueprint,
                        ratioGap: ratioGap,
                        rewalkDebt: debt,
                        attempt: attempt + 1
                    )
                    inBandCount += 1
                    if best == nil || prefersNewLoopCandidate(candidate, over: best!) {
                        best = candidate
                    }
                } else if ratio.isFinite {
                    let polyline = routed.coordinates.map(GeodesicWaypoint.init(_:))
                    let debt = RewalkProximity.debtMeters(polyline: polyline)
                    let ratioGap = abs(1.0 - ratio)
                    let candidate = LoopPlanCandidate(
                        routed: routed,
                        blueprint: blueprint,
                        ratioGap: ratioGap,
                        rewalkDebt: debt,
                        attempt: attempt + 1
                    )
                    if bestNearMiss == nil || prefersNewLoopCandidate(candidate, over: bestNearMiss!) {
                        bestNearMiss = candidate
                    }
                }

                let routedFloor: Double = switch planningLengthGoal {
                case .duration:
                    120
                case .distance:
                    250
                }
                let adjustedScale = radiusScale * (targetMetric / max(routedMetric, routedFloor))
                radiusScale = min(2.8, max(0.35, adjustedScale))
                refinementSummary =
                    "Adjusting route (attempt \(attempt + 1)): about \(paceBasedWalkMinutes(routed: routed)) min at your pace • \(Int(routed.distanceMeters)) m."
            } catch {
                lastRoutingError = error.localizedDescription
                refinementSummary =
                    "Maps did not return walking directions for layout \(attempt + 1). Trying another shape…"
            }
        }

        if let pick = best {
            refinedWalk = pick.routed
            activeBlueprint = pick.blueprint
            refinementSummary = refinementSuccessSummary(pick: pick, inBandCount: inBandCount)
            connectivity.sendActiveWalk(
                pick.routed.makeWatchSnapshot(startedAt: .now, navigationSessionId: nil, recordingStartedAt: nil)
            )
            return
        }

        if let pick = bestNearMiss {
            refinedWalk = pick.routed
            activeBlueprint = pick.blueprint
            refinementSummary = refinementNearMissSummary(pick: pick)
            planningError = nil
            connectivity.sendActiveWalk(
                pick.routed.makeWatchSnapshot(startedAt: .now, navigationSessionId: nil, recordingStartedAt: nil)
            )
            return
        }

        if let err = lastRoutingError {
            planningError =
                "Could not get a complete walking loop from Maps after \(maxAttempts) tries. \(err) Try moving slightly or changing your time/distance."
        } else {
            planningError = planningFailureMessage
        }
        refinedWalk = nil
        activeBlueprint = nil
    }

    /// Prefer lower self-overlap debt, then closeness to the nominal target ratio.
    private func prefersNewLoopCandidate(_ next: LoopPlanCandidate, over previous: LoopPlanCandidate) -> Bool {
        let debtEps = max(25, previous.routed.distanceMeters * 0.002)
        if abs(next.rewalkDebt - previous.rewalkDebt) > debtEps {
            return next.rewalkDebt < previous.rewalkDebt
        }
        return next.ratioGap < previous.ratioGap
    }

    private func planningTargetMetrics(using goal: WalkLengthGoal, routed: RoutedWalk) -> (Double, Double) {
        let speed = planningPaceMetersPerSecond
        switch goal {
        case .duration(let seconds):
            return (Double(seconds), routed.distanceMeters / speed)
        case .distance(let meters):
            return (meters, routed.distanceMeters)
        }
    }

    private func paceBasedWalkMinutes(routed: RoutedWalk) -> Int {
        max(1, Int(round(routed.distanceMeters / planningPaceMetersPerSecond / 60)))
    }

    private func refinementSuccessSummary(pick: LoopPlanCandidate, inBandCount: Int) -> String {
        let base: String
        switch planningLengthGoal {
        case .duration(let seconds):
            let minutes = Int(seconds / 60)
            base = "Matched your \(minutes) min target on attempt \(pick.attempt)."
        case .distance(let meters):
            if meters >= 1_000 {
                base = String(format: "Matched your %.1f km target on attempt %d.", meters / 1_000, pick.attempt)
            } else {
                base = "Matched your \(Int(meters)) m target on attempt \(pick.attempt)."
            }
        }
        if inBandCount > 1 {
            return base + " Picked the least backtracking route among \(inBandCount) in-range options."
        }
        return base
    }

    private func refinementNearMissSummary(pick: LoopPlanCandidate) -> String {
        let (targetMetric, routedMetric) = planningTargetMetrics(using: planningLengthGoal, routed: pick.routed)
        let pct = max(1, min(999, Int(round(100 * routedMetric / max(targetMetric, 1)))))
        let mins = paceBasedWalkMinutes(routed: pick.routed)
        let meters = Int(pick.routed.distanceMeters)
        return
            "Could not match your target within the usual range — showing the closest loop we could route (~\(mins) min at your pace • \(meters) m, about \(pct)% of your goal, attempt \(pick.attempt))."
    }

    private var planningFailureMessage: String {
        switch planningLengthGoal {
        case .duration(let seconds):
            return
                "Could not find a walking loop near \(Int(seconds / 60)) minutes after \(maxAttempts) tries. Try another duration or move slightly."
        case .distance(let meters):
            if meters >= 1_000 {
                return String(
                    format: "Could not find a loop near %.1f km after %d tries. Try another distance or move slightly.",
                    meters / 1_000,
                    maxAttempts
                )
            }
            return
                "Could not find a loop near \(Int(meters)) m after \(maxAttempts) tries. Try another distance or move slightly."
        }
    }

    var navigationStepIndex: Int {
        routeNavigator?.currentIndex ?? 0
    }

    var navigationStepCount: Int {
        routeNavigator?.steps.count ?? 0
    }

    func startNavigation(seedLocation: CLLocation?, connectivity: PhoneConnectivityManager) {
        guard let walk = refinedWalk else { return }
        let steps = WalkRouteNavigator.flattenedSteps(from: walk)
        guard !steps.isEmpty else { return }
        recordedNavigationPath = []
        navigationStartedAt = .now
        navigationStartCoordinate = seedLocation?.coordinate ?? walk.coordinates.first
        hasVenturedFromStart = false
        returnToStartEnteredAt = nil
        watchNavigationSessionId = UUID()
        mergedWatchTrack = nil
        if let coord = seedLocation?.coordinate {
            recordedNavigationPath.append(coord)
        }
        routeNavigator = WalkRouteNavigator(steps: steps)
        navigationCompletionNotice = nil
        isNavigating = true

        connectivity.sendActiveWalk(
            walk.makeWatchSnapshot(
                startedAt: navigationStartedAt!,
                navigationSessionId: watchNavigationSessionId,
                recordingStartedAt: navigationStartedAt
            )
        )
    }

    /// Ends guidance without persisting (e.g. *Discard* on the stop confirmation).
    func discardNavigationWithoutSaving(connectivity: PhoneConnectivityManager) {
        watchNavigationSessionId = nil
        mergedWatchTrack = nil
        connectivity.clearWalkOnWatch()
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
    func stopAndSaveToHistory(modelContext: ModelContext, connectivity: PhoneConnectivityManager) async {
        guard isNavigating, let routed = refinedWalk, let blueprint = activeBlueprint else {
            discardNavigationWithoutSaving(connectivity: connectivity)
            return
        }
        await pullWatchTrackIfNeeded(connectivity: connectivity)
        persistWalk(
            routed: routed,
            blueprint: blueprint,
            modelContext: modelContext,
            completionKind: .savedOnStop
        )
        clearNavigationAfterSessionEnds(connectivity: connectivity)
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
        watchNavigationSessionId = nil
        mergedWatchTrack = nil
    }

    func ingestWatchRecording(_ track: WatchRecordedTrack) {
        guard let sid = watchNavigationSessionId, sid == track.navigationSessionId else { return }
        mergedWatchTrack = track
    }

    func ingestNavigationLocation(
        _ location: CLLocation,
        modelContext: ModelContext,
        connectivity: PhoneConnectivityManager
    ) {
        guard isNavigating, var navigator = routeNavigator else { return }
        appendRecordedSample(location.coordinate)
        navigator.ingest(userLocation: location)
        routeNavigator = navigator

        if navigator.isComplete {
            let routed = refinedWalk
            let blueprint = activeBlueprint
            isNavigating = false
            routeNavigator = nil
            guard let routed, let blueprint else { return }
            Task {
                await finishSessionSaving(
                    routed: routed,
                    blueprint: blueprint,
                    completionKind: .guidedComplete,
                    modelContext: modelContext,
                    notice: "You finished the loop. Saved to History.",
                    connectivity: connectivity
                )
            }
            return
        }

        evaluateReturnToStartProximity(location: location, modelContext: modelContext, connectivity: connectivity)
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
            connectivity.sendActiveWalk(
                resumed.makeWatchSnapshot(
                    startedAt: navigationStartedAt ?? .now,
                    navigationSessionId: watchNavigationSessionId,
                    recordingStartedAt: navigationStartedAt
                )
            )
            refinementSummary = "Updated route from your position."
        } catch {
            planningError = error.localizedDescription
        }
    }

    private func evaluateReturnToStartProximity(
        location: CLLocation,
        modelContext: ModelContext,
        connectivity: PhoneConnectivityManager
    ) {
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
                    let routed = refinedWalk
                    let blueprint = activeBlueprint
                    isNavigating = false
                    routeNavigator = nil
                    guard let routed, let blueprint else { return }
                    Task {
                        await finishSessionSaving(
                            routed: routed,
                            blueprint: blueprint,
                            completionKind: .returnedToStart,
                            modelContext: modelContext,
                            notice: "You returned near your start. Saved to History.",
                            connectivity: connectivity
                        )
                    }
                    return
                }
            } else {
                returnToStartEnteredAt = now
            }
        } else {
            returnToStartEnteredAt = nil
        }
    }

    private func pullWatchTrackIfNeeded(connectivity: PhoneConnectivityManager) async {
        guard let sid = watchNavigationSessionId else { return }
        if let track = await connectivity.requestWatchRecording(for: sid) {
            ingestWatchRecording(track)
        }
    }

    private func finishSessionSaving(
        routed: RoutedWalk,
        blueprint: LoopWalkBlueprint,
        completionKind: WalkCompletionKind,
        modelContext: ModelContext,
        notice: String,
        connectivity: PhoneConnectivityManager
    ) async {
        await pullWatchTrackIfNeeded(connectivity: connectivity)
        persistWalk(
            routed: routed,
            blueprint: blueprint,
            modelContext: modelContext,
            completionKind: completionKind
        )
        navigationCompletionNotice = notice
        clearNavigationAfterSessionEnds(connectivity: connectivity)
    }

    private func clearNavigationAfterSessionEnds(connectivity: PhoneConnectivityManager) {
        isNavigating = false
        routeNavigator = nil
        recordedNavigationPath = []
        navigationStartedAt = nil
        navigationStartCoordinate = nil
        hasVenturedFromStart = false
        returnToStartEnteredAt = nil
        watchNavigationSessionId = nil
        mergedWatchTrack = nil
        connectivity.clearWalkOnWatch()
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
        let elapsedSeconds: TimeInterval

        if let wt = mergedWatchTrack,
           let sid = watchNavigationSessionId,
           wt.navigationSessionId == sid,
           wt.samples.count >= 2 {
            pathCoordinates = wt.samples.map(\.coordinate)
            distanceMeters = Self.pathLengthMeters(pathCoordinates)
            elapsedSeconds = max(1, wt.endedAt.timeIntervalSince(wt.startedAt))
        } else if let wt = mergedWatchTrack,
                  let sid = watchNavigationSessionId,
                  wt.navigationSessionId == sid {
            elapsedSeconds = max(1, wt.endedAt.timeIntervalSince(wt.startedAt))
            if recordedNavigationPath.count >= 2 {
                pathCoordinates = recordedNavigationPath
                distanceMeters = Self.pathLengthMeters(recordedNavigationPath)
            } else {
                pathCoordinates = routed.coordinates
                distanceMeters = routed.distanceMeters
            }
        } else if recordedNavigationPath.count >= 2 {
            pathCoordinates = recordedNavigationPath
            distanceMeters = Self.pathLengthMeters(recordedNavigationPath)
            elapsedSeconds = navigationStartedAt.map { Date().timeIntervalSince($0) } ?? routed.expectedTravelTime
        } else {
            pathCoordinates = routed.coordinates
            distanceMeters = routed.distanceMeters
            elapsedSeconds = navigationStartedAt.map { Date().timeIntervalSince($0) } ?? routed.expectedTravelTime
        }

        let points = pathCoordinates.map(GeodesicWaypoint.init(_:))
        let encoded = PolylineCodec.encode(coordinates: points)

        let titleDate = DateFormatter.walkTitle.string(from: .now)
        let record = WalkRecord(
            id: UUID(),
            targetDurationSeconds: blueprint.targetWalkingDuration,
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
        onWalkSavedObservedPace?(distanceMeters, elapsedSeconds)
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
        discardNavigationWithoutSaving(connectivity: connectivity)
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
