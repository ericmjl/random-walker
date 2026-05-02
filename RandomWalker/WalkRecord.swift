import Foundation
import SwiftData
import RandomWalkerCore

/// How a history row was produced after **Start** (all cases require an active navigation session).
enum WalkCompletionKind: String, Codable, CaseIterable, Sendable {
    /// Completed every turn-by-turn maneuver in order.
    case guidedComplete
    /// Ended by dwelling back near the session start coordinates without finishing guidance.
    case returnedToStart
    /// User chose *Save to history* when stopping guidance early.
    case savedOnStop

    var historyListSubtitle: String {
        switch self {
        case .guidedComplete:
            return "Guided loop completed"
        case .returnedToStart:
            return "Returned to start"
        case .savedOnStop:
            return "Saved when stopped"
        }
    }
}

@Model
final class WalkRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var targetDurationSeconds: Double
    var routedDistanceMeters: Double
    var routedExpectedDurationSeconds: Double
    var encodedPolyline: String
    var blueprintSalt: UInt64
    var centerLatitude: Double
    var centerLongitude: Double
    var title: String
    /// Persisted ``WalkCompletionKind/rawValue`` for SwiftData (`nil` in legacy rows → treated as guided).
    var completionKindRaw: String?

    /// Convenience wrapper around ``completionKindRaw``.
    var completionKind: WalkCompletionKind {
        get {
            if let raw = completionKindRaw, let kind = WalkCompletionKind(rawValue: raw) {
                return kind
            }
            return .guidedComplete
        }
        set { completionKindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        targetDurationSeconds: Double,
        routedDistanceMeters: Double,
        routedExpectedDurationSeconds: Double,
        encodedPolyline: String,
        blueprintSalt: UInt64,
        centerLatitude: Double,
        centerLongitude: Double,
        title: String = "",
        completionKindRaw: String? = WalkCompletionKind.guidedComplete.rawValue
    ) {
        self.id = id
        self.createdAt = createdAt
        self.targetDurationSeconds = targetDurationSeconds
        self.routedDistanceMeters = routedDistanceMeters
        self.routedExpectedDurationSeconds = routedExpectedDurationSeconds
        self.encodedPolyline = encodedPolyline
        self.blueprintSalt = blueprintSalt
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.title = title
        self.completionKindRaw = completionKindRaw
    }

    var centerWaypoint: GeodesicWaypoint {
        GeodesicWaypoint(latitude: centerLatitude, longitude: centerLongitude)
    }

    var decodedCoordinates: [GeodesicWaypoint] {
        PolylineCodec.decode(polyline: encodedPolyline)
    }
}
