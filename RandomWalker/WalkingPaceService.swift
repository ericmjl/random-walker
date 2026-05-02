import Combine
import Foundation
import HealthKit
import RandomWalkerCore
import SwiftData

/// Blends **Apple Health** walking-speed samples (when authorized) with **observed pace** from saved walks
/// to parameterize ``RandomWalkGenerator`` distance↔duration planning. Falls back to ``RandomWalkGenerator/defaultWalkingSpeedMetersPerSecond``.
///
/// Behavior, persistence keys, and manual testing: `docs/walking-pace.md` in the repository.
@MainActor
final class WalkingPaceService: ObservableObject {
    @Published private(set) var effectiveWalkingSpeedMetersPerSecond: Double = RandomWalkGenerator
        .defaultWalkingSpeedMetersPerSecond

    private let healthStore = HKHealthStore()
    private var cachedHealthMedianPace: Double?
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let learnedEMA = "randomwalker.walkingPace.learnedEMA"
    }

    private static let paceClamp: ClosedRange<Double> = 1.0 ... 2.3

    init() {
        recomputeEffective()
    }

    private var walkingSpeedQuantityType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .walkingSpeed)
    }

    /// Seeds pace from recent **History** when we have no EMA yet, then recomputes. Safe to call often (e.g. app launch).
    func bootstrapFromHistoryIfNeeded(modelContext: ModelContext) {
        if defaults.object(forKey: DefaultsKey.learnedEMA) != nil {
            recomputeEffective()
            return
        }
        let descriptor = FetchDescriptor<WalkRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let records = try? modelContext.fetch(descriptor), !records.isEmpty else {
            recomputeEffective()
            return
        }
        let paces: [Double] = records.prefix(20).compactMap { record in
            let t = record.routedExpectedDurationSeconds
            let d = record.routedDistanceMeters
            guard t >= 120, d >= 250 else { return nil }
            let p = d / t
            guard p >= 0.9, p <= 2.6 else { return nil }
            return p
        }
        guard !paces.isEmpty else {
            recomputeEffective()
            return
        }
        let sorted = paces.sorted()
        let median = sorted[sorted.count / 2]
        defaults.set(median, forKey: DefaultsKey.learnedEMA)
        RotatingFileLogger.shared.log("pace", "Bootstrapped learned pace from history: median sample ≈ \(String(format: "%.2f", median)) m/s")
        recomputeEffective()
    }

    /// If walking-speed read access is still undetermined, requests it (system sheet). Safe to call on launch.
    func requestWalkingSpeedReadAccessIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable(), let type = walkingSpeedQuantityType else {
            RotatingFileLogger.shared.log("pace", "HealthKit not available.")
            return
        }
        guard healthStore.authorizationStatus(for: type) == .notDetermined else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [type])
            await refreshHealthKitWalkingSpeedMedian()
            recomputeEffective()
            let after = healthStore.authorizationStatus(for: type)
            RotatingFileLogger.shared.log("pace", "Walking-speed read authorization finished; status=\(String(describing: after)).")
        } catch {
            RotatingFileLogger.shared.log("pace", "Walking-speed read authorization error: \(error.localizedDescription)")
        }
    }

    private func refreshHealthKitWalkingSpeedMedian() async {
        guard let type = walkingSpeedQuantityType else {
            cachedHealthMedianPace = nil
            return
        }
        guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
            cachedHealthMedianPace = nil
            return
        }
        let calendar = Calendar.current
        guard let start = calendar.date(byAdding: .day, value: -120, to: Date()) else {
            cachedHealthMedianPace = nil
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictEndDate)
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 200,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
        let unit = HKUnit.meter().unitDivided(by: .second())
        let values = samples
            .map { $0.quantity.doubleValue(for: unit) }
            .filter { $0 >= 0.9 && $0 <= 2.7 }
        guard !values.isEmpty else {
            cachedHealthMedianPace = nil
            return
        }
        let sorted = values.sorted()
        cachedHealthMedianPace = sorted[sorted.count / 2]
    }

    /// Call after each saved walk with **observed** distance and **elapsed** time (seconds).
    func ingestObservedWalk(distanceMeters: Double, durationSeconds: TimeInterval) {
        guard durationSeconds >= 120, distanceMeters >= 300 else { return }
        var pace = distanceMeters / durationSeconds
        pace = min(max(pace, Self.paceClamp.lowerBound), Self.paceClamp.upperBound)
        let alpha = 0.38
        let prior = defaults.object(forKey: DefaultsKey.learnedEMA) as? Double ?? pace
        let ema = alpha * pace + (1 - alpha) * prior
        defaults.set(ema, forKey: DefaultsKey.learnedEMA)
        recomputeEffective()
    }

    private func recomputeEffective() {
        let learned = defaults.object(forKey: DefaultsKey.learnedEMA) as? Double
        let health = cachedHealthMedianPace
        let merged: Double
        let blurb: String
        switch (learned, health) {
        case let (l?, h?):
            merged = 0.52 * l + 0.48 * h
            blurb =
                String(
                    format: "Blended your walks and Apple Health (about %.1f km/h). Longer routes for the same time.",
                    merged * 3.6
                )
        case let (l?, nil):
            merged = l
            blurb = String(format: "Pace from saved walks (about %.1f km/h).", merged * 3.6)
        case let (nil, h?):
            merged = h
            blurb = String(
                format: "From Apple Health (about %.1f km/h).",
                merged * 3.6
            )
        default:
            merged = RandomWalkGenerator.defaultWalkingSpeedMetersPerSecond
            blurb = String(
                format: "Default brisk pace (~%.1f km/h). Save walks or link Health to personalize.",
                merged * 3.6
            )
        }
        let newSpeed = min(max(merged, Self.paceClamp.lowerBound), Self.paceClamp.upperBound)
        if abs(newSpeed - effectiveWalkingSpeedMetersPerSecond) > 0.000_1 {
            RotatingFileLogger.shared.log(
                "pace",
                "\(blurb) effectiveWalkingSpeedMetersPerSecond=\(String(format: "%.3f", newSpeed))"
            )
        }
        effectiveWalkingSpeedMetersPerSecond = newSpeed
    }

    /// Re-fetches HealthKit median if already authorized (e.g. when returning to the app).
    func refreshAuthorizedHealthKitData() async {
        guard let type = walkingSpeedQuantityType,
              healthStore.authorizationStatus(for: type) == .sharingAuthorized
        else {
            return
        }
        await refreshHealthKitWalkingSpeedMedian()
        recomputeEffective()
    }
}

#if targetEnvironment(simulator)
extension WalkingPaceService {
    private enum SimulatorSeedDefaultsKey {
        static let didSeed = "randomwalker.debug.simulatorWalkingSpeedSeeded"
    }

    /// Writes walking-speed samples into the **simulator** Health database for development testing.
    ///
    /// Requests read **and** write access for walking speed. When `force` is false, sample insertion runs once per install unless you call again with `force: true`.
    ///
    /// - Parameter force: When true, saves another batch even if this install already seeded once.
    func seedSimulatorWalkingSpeedFixtures(force: Bool = false) async {
        guard HKHealthStore.isHealthDataAvailable(), let type = walkingSpeedQuantityType else {
            RotatingFileLogger.shared.log("pace", "Simulator seed skipped: Health not available.")
            return
        }
        if !force, defaults.bool(forKey: SimulatorSeedDefaultsKey.didSeed) {
            await refreshHealthKitWalkingSpeedMedian()
            recomputeEffective()
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [type], read: [type])
        } catch {
            RotatingFileLogger.shared.log("pace", "Simulator seed: Health authorization failed — \(error.localizedDescription)")
            return
        }

        guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
            RotatingFileLogger.shared.log("pace", "Simulator seed: walking speed not authorized after request.")
            return
        }

        let unit = HKUnit.meter().unitDivided(by: .second())
        let calendar = Calendar.current
        let now = Date()
        let dayOffsetsAndSpeeds: [(Int, Double)] = [
            (1, 1.42),
            (3, 1.55),
            (5, 1.38),
            (7, 1.68),
            (10, 1.52),
            (14, 1.61),
            (21, 1.49),
            (35, 1.58),
            (45, 1.50),
            (55, 1.64),
        ]
        var samples: [HKQuantitySample] = []
        samples.reserveCapacity(dayOffsetsAndSpeeds.count)
        for (dayBack, metersPerSecond) in dayOffsetsAndSpeeds {
            guard let start = calendar.date(byAdding: .day, value: -dayBack, to: now) else { continue }
            let end = start.addingTimeInterval(1_200)
            let quantity = HKQuantity(unit: unit, doubleValue: metersPerSecond)
            samples.append(
                HKQuantitySample(
                    type: type,
                    quantity: quantity,
                    start: start,
                    end: end,
                    device: HKDevice.local(),
                    metadata: nil
                )
            )
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.save(samples) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard success else {
                        continuation.resume(
                            throwing: NSError(
                                domain: "WalkingPaceService",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "HealthKit save did not succeed."]
                            )
                        )
                        return
                    }
                    continuation.resume()
                }
            }
        } catch {
            RotatingFileLogger.shared.log("pace", "Simulator seed: save failed — \(error.localizedDescription)")
            return
        }

        defaults.set(true, forKey: SimulatorSeedDefaultsKey.didSeed)
        await refreshHealthKitWalkingSpeedMedian()
        recomputeEffective()
        RotatingFileLogger.shared.log("pace", "Simulator walking-speed fixtures saved (\(samples.count) samples).")
    }
}
#endif
