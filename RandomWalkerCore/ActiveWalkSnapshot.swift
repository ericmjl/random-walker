import Foundation

/// Codable payloads exchanged with the watch via WatchConnectivity.
public struct ActiveWalkSnapshot: Codable, Sendable, Equatable {
    public var routeId: UUID
    public var startedAt: Date
    public var legs: [WalkLegHint]
    public var totalDistanceMeters: Double
    public var expectedDurationSeconds: TimeInterval
    /// When non-`nil`, the wearer tapped **Start** on iPhone and the watch should record GPS for this session.
    public var navigationSessionId: UUID?
    /// Wall-clock start of navigation on the phone (used with ``navigationSessionId``).
    public var recordingStartedAt: Date?

    public init(
        routeId: UUID,
        startedAt: Date,
        legs: [WalkLegHint],
        totalDistanceMeters: Double,
        expectedDurationSeconds: TimeInterval,
        navigationSessionId: UUID? = nil,
        recordingStartedAt: Date? = nil
    ) {
        self.routeId = routeId
        self.startedAt = startedAt
        self.legs = legs
        self.totalDistanceMeters = totalDistanceMeters
        self.expectedDurationSeconds = expectedDurationSeconds
        self.navigationSessionId = navigationSessionId
        self.recordingStartedAt = recordingStartedAt
    }
}

public struct WalkLegHint: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var distanceMeters: Double
    public var expectedTravelTime: TimeInterval
    /// Turn maneuver location (Maps step end point). Older payloads omit both; omitting disables GPS advancement on Watch.
    public var maneuverLatitude: Double?
    public var maneuverLongitude: Double?

    public init(
        id: UUID = UUID(),
        title: String,
        distanceMeters: Double,
        expectedTravelTime: TimeInterval,
        maneuverLatitude: Double? = nil,
        maneuverLongitude: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.distanceMeters = distanceMeters
        self.expectedTravelTime = expectedTravelTime
        self.maneuverLatitude = maneuverLatitude
        self.maneuverLongitude = maneuverLongitude
    }
}

public enum WatchMessageKey: String {
    case activeWalk
    case clearWalk
    case recordedTrack
    case requestRecordingFlush
}

/// GPS samples and timing recorded on Apple Watch during a navigation session.
public struct WatchRecordedTrack: Codable, Sendable, Equatable {
    public var routeId: UUID
    public var navigationSessionId: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var samples: [GeodesicWaypoint]

    public init(
        routeId: UUID,
        navigationSessionId: UUID,
        startedAt: Date,
        endedAt: Date,
        samples: [GeodesicWaypoint]
    ) {
        self.routeId = routeId
        self.navigationSessionId = navigationSessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.samples = samples
    }
}
