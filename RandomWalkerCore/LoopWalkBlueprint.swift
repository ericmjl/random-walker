import Foundation

/// A loop begins at ``center``, visits ``intermediateWaypoints`` in order, then returns to ``center``.
public struct LoopWalkBlueprint: Sendable, Equatable {
    public let center: GeodesicWaypoint
    public let intermediateWaypoints: [GeodesicWaypoint]
    public let targetWalkingDuration: TimeInterval
    public let randomSalt: UInt64

    public init(
        center: GeodesicWaypoint,
        intermediateWaypoints: [GeodesicWaypoint],
        targetWalkingDuration: TimeInterval,
        randomSalt: UInt64
    ) {
        self.center = center
        self.intermediateWaypoints = intermediateWaypoints
        self.targetWalkingDuration = targetWalkingDuration
        self.randomSalt = randomSalt
    }

    /// Ordered visit list: center → intermediates → center (duplicate final return).
    public var visitSequenceCoordinates: [GeodesicWaypoint] {
        [center] + intermediateWaypoints + [center]
    }
}
