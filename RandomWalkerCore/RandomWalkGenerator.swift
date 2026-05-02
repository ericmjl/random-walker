import CoreLocation
import Foundation

/// Builds irregular loop blueprints around a start coordinate without calling into MapKit.
public enum RandomWalkGenerator {
    /// Default brisk urban walking speed used to translate duration → rough loop length.
    public static let defaultWalkingSpeedMetersPerSecond: Double = 1.34 // ≈ 4.8 km/h

    public struct Configuration: Sendable, Equatable {
        public var targetDuration: TimeInterval
        public var walkingSpeedMetersPerSecond: Double
        public var minIntermediateStops: Int
        public var maxIntermediateStops: Int
        public var radiusJitter: ClosedRange<Double>
        public var angularJitterRadians: ClosedRange<Double>

        public init(
            targetDuration: TimeInterval,
            walkingSpeedMetersPerSecond: Double = RandomWalkGenerator.defaultWalkingSpeedMetersPerSecond,
            minIntermediateStops: Int = 4,
            maxIntermediateStops: Int = 7,
            radiusJitter: ClosedRange<Double> = 0.82 ... 1.18,
            angularJitterRadians: ClosedRange<Double> = (-0.55) ... 0.55
        ) {
            self.targetDuration = targetDuration
            self.walkingSpeedMetersPerSecond = walkingSpeedMetersPerSecond
            self.minIntermediateStops = minIntermediateStops
            self.maxIntermediateStops = maxIntermediateStops
            self.radiusJitter = radiusJitter
            self.angularJitterRadians = angularJitterRadians
        }
    }

    /// - Parameters:
    ///   - center: The loop’s start/end coordinate.
    ///   - configuration: Duration and variability controls.
    ///   - rng: Randomness source.
    ///   - radiusScale: Multiplier for the loop’s spatial extent (routing may refine duration).
    public static func makeBlueprint(
        center: GeodesicWaypoint,
        configuration: Configuration = Configuration(targetDuration: 3_600),
        rng: inout some RandomWalkRNG,
        radiusScale: Double = 1.0
    ) -> LoopWalkBlueprint {
        let salt = rng.nextUInt64()
        let stops = max(1, rng.intUniform(in: configuration.minIntermediateStops ... configuration.maxIntermediateStops))

        let targetMeters = max(400, configuration.targetDuration * configuration.walkingSpeedMetersPerSecond)
        // Rough perimeter budget for an irregular polygon: scale radius from desired chord budget.
        let meanRadius = max(120, targetMeters / (2 * .pi * Double(stops) * 0.35)) * radiusScale

        var angles: [Double] = []
        angles.reserveCapacity(stops)
        let phase = rng.unitUniform(in: 0 ... (2 * .pi))
        for index in 0 ..< stops {
            let base = (2 * .pi * Double(index) / Double(stops)) + phase
            angles.append(base + rng.unitUniform(in: configuration.angularJitterRadians))
        }

        var points: [GeodesicWaypoint] = []
        points.reserveCapacity(stops)
        for angle in angles {
            let r = meanRadius * rng.unitUniform(in: configuration.radiusJitter)
            points.append(offsetMeters(center: center, metersNorth: cos(angle) * r, metersEast: sin(angle) * r))
        }

        let perimeter = straightLineLoopPerimeter(center: center, intermediates: points)
        // Nudge radius so straight-line loop length tracks the duration-derived budget loosely.
        let scale = min(2.8, max(0.35, targetMeters / max(perimeter, 1)))
        let scaled = points.map { p in
            interpolate(from: center, toward: p, fraction: scale)
        }

        return LoopWalkBlueprint(
            center: center,
            intermediateWaypoints: scaled,
            targetWalkingDuration: configuration.targetDuration,
            randomSalt: salt
        )
    }

    private static func straightLineLoopPerimeter(center: GeodesicWaypoint, intermediates: [GeodesicWaypoint]) -> Double {
        guard !intermediates.isEmpty else { return 0 }
        var total = center.distanceMeters(to: intermediates[0])
        if intermediates.count >= 2 {
            for idx in 1 ..< intermediates.count {
                total += intermediates[idx - 1].distanceMeters(to: intermediates[idx])
            }
        }
        total += intermediates[intermediates.count - 1].distanceMeters(to: center)
        return total
    }

    private static func offsetMeters(
        center: GeodesicWaypoint,
        metersNorth: Double,
        metersEast: Double
    ) -> GeodesicWaypoint {
        let lat = center.latitude + (metersNorth / 111_111)
        let lon = center.longitude + metersEast / (111_111 * max(0.15, cos(center.latitude * .pi / 180)))
        return GeodesicWaypoint(latitude: lat, longitude: lon)
    }

    private static func interpolate(
        from origin: GeodesicWaypoint,
        toward target: GeodesicWaypoint,
        fraction: Double
    ) -> GeodesicWaypoint {
        GeodesicWaypoint(
            latitude: origin.latitude + (target.latitude - origin.latitude) * fraction,
            longitude: origin.longitude + (target.longitude - origin.longitude) * fraction
        )
    }
}
