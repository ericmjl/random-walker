import Foundation
import SwiftData
import RandomWalkerCore

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
        title: String = ""
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
    }

    var centerWaypoint: GeodesicWaypoint {
        GeodesicWaypoint(latitude: centerLatitude, longitude: centerLongitude)
    }

    var decodedCoordinates: [GeodesicWaypoint] {
        PolylineCodec.decode(polyline: encodedPolyline)
    }
}
