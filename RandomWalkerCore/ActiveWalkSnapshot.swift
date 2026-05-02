import Foundation

/// Codable payloads exchanged with the watch via WatchConnectivity.
public struct ActiveWalkSnapshot: Codable, Sendable, Equatable {
    public var routeId: UUID
    public var startedAt: Date
    public var legs: [WalkLegHint]
    public var totalDistanceMeters: Double
    public var expectedDurationSeconds: TimeInterval

    public init(
        routeId: UUID,
        startedAt: Date,
        legs: [WalkLegHint],
        totalDistanceMeters: Double,
        expectedDurationSeconds: TimeInterval
    ) {
        self.routeId = routeId
        self.startedAt = startedAt
        self.legs = legs
        self.totalDistanceMeters = totalDistanceMeters
        self.expectedDurationSeconds = expectedDurationSeconds
    }
}

public struct WalkLegHint: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var distanceMeters: Double
    public var expectedTravelTime: TimeInterval

    public init(id: UUID = UUID(), title: String, distanceMeters: Double, expectedTravelTime: TimeInterval) {
        self.id = id
        self.title = title
        self.distanceMeters = distanceMeters
        self.expectedTravelTime = expectedTravelTime
    }
}

public enum WatchMessageKey: String {
    case activeWalk
    case clearWalk
}
