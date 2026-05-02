import CoreLocation
import Foundation

/// A lightweight, value-type coordinate used by the planner and routing layers.
public struct GeodesicWaypoint: Sendable, Equatable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

public extension GeodesicWaypoint {
    /// Haversine distance in meters (Earth mean radius).
    func distanceMeters(to other: GeodesicWaypoint) -> Double {
        let r: Double = 6_371_000
        let φ1 = latitude * .pi / 180
        let φ2 = other.latitude * .pi / 180
        let Δφ = (other.latitude - latitude) * .pi / 180
        let Δλ = (other.longitude - longitude) * .pi / 180

        let a = sin(Δφ / 2) * sin(Δφ / 2)
            + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}
