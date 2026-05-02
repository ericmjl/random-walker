import CoreLocation
import Foundation

/// Encodes a sequence of coordinates using the polyline algorithm (5-bit chars).
public enum PolylineCodec {
    /// :param precision: Decimal digits after floating point (Google default 5).
    public static func encode(coordinates: [GeodesicWaypoint], precision: UInt32 = 5) -> String {
        var previousLat = 0
        var previousLon = 0
        var result = ""
        let multiplier = pow(10.0, Double(precision)).rounded()

        func encodeSigned(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : (value << 1)
            while v >= 0x20 {
                let char = (0x20 | (v & 0x1F)) + 63
                result.unicodeScalars.append(UnicodeScalar(char)!)
                v >>= 5
            }
            result.unicodeScalars.append(UnicodeScalar(v + 63)!)
        }

        for coord in coordinates {
            let lat = Int((coord.latitude * multiplier).rounded())
            let lon = Int((coord.longitude * multiplier).rounded())
            encodeSigned(lat - previousLat)
            encodeSigned(lon - previousLon)
            previousLat = lat
            previousLon = lon
        }
        return result
    }

    public static func decode(polyline: String, precision: UInt32 = 5) -> [GeodesicWaypoint] {
        var coordinates: [GeodesicWaypoint] = []
        var lat = 0
        var lon = 0
        let bytes = Array(polyline.utf8)
        var offset = 0
        let multiplier = pow(10.0, Double(precision))

        func decodeOne() -> Int {
            var result = 0
            var shift = 0
            var byte: UInt8 = 0
            repeat {
                guard offset < bytes.count else { return 0 }
                byte = bytes[offset] &- 63
                offset += 1
                result |= Int(byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }

        while offset < bytes.count {
            lat += decodeOne()
            lon += decodeOne()
            coordinates.append(
                GeodesicWaypoint(
                    latitude: Double(lat) / multiplier,
                    longitude: Double(lon) / multiplier
                )
            )
        }
        return coordinates
    }

    public static func mapCoordinates(from points: [GeodesicWaypoint]) -> [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }
}
