import Foundation

/// Estimates how much a walking polyline **re-traces the same corridors**—when non-adjacent parts of the path pass close together.
///
/// Used during planning to prefer loops that spread out instead of folding back on themselves. The value is **not** a physical distance walked twice; it is a weighted penalty (meter-equivalent) suitable for ranking routes.
public enum RewalkProximity {
    /// Accumulated penalty when non-adjacent segments pass within ``proximityThresholdMeters``.
    ///
    /// :param polyline: Route vertices in order (e.g. from MapKit polylines).
    /// :param maxVertices: Downsamples long polylines so scoring stays cheap on device.
    /// :param minSegmentIndexGap: Minimum index gap between segment starts so consecutive legs are ignored.
    /// :param proximityThresholdMeters: Pairs closer than this contribute penalty.
    /// :returns: Non-negative score; lower is better (less apparent re-walking).
    public static func debtMeters(
        polyline: [GeodesicWaypoint],
        maxVertices: Int = 192,
        minSegmentIndexGap: Int = 3,
        proximityThresholdMeters: Double = 22
    ) -> Double {
        guard polyline.count >= minSegmentIndexGap + 2 else { return 0 }

        let ring = downsampleEvenSpacing(polyline, maxVertices: max(16, maxVertices))
        guard ring.count >= minSegmentIndexGap + 2 else { return 0 }

        var debt = 0.0
        let n = ring.count
        for i in 0 ..< (n - 1) {
            let a = ring[i]
            let b = ring[i + 1]
            let lenAB = a.distanceMeters(to: b)
            guard lenAB >= 0.5 else { continue }

            let jMin = i + minSegmentIndexGap
            guard jMin < n - 1 else { continue }

            for j in jMin ..< (n - 1) {
                let c = ring[j]
                let d = ring[j + 1]
                let lenCD = c.distanceMeters(to: d)
                guard lenCD >= 0.5 else { continue }

                let separation = approximateSegmentSeparationMeters(a: a, b: b, c: c, d: d)
                if separation < proximityThresholdMeters {
                    let shortfall = proximityThresholdMeters - separation
                    let span = min(lenAB, lenCD)
                    debt += shortfall * (span / max(proximityThresholdMeters, 1))
                }
            }
        }
        return debt
    }

    /// Evenly spaced resampling along cumulative geodesic length so sparse polylines stay representative.
    private static func downsampleEvenSpacing(_ polyline: [GeodesicWaypoint], maxVertices: Int) -> [GeodesicWaypoint] {
        guard polyline.count > 2, maxVertices >= 2 else { return polyline }

        var cumulative: [Double] = [0]
        cumulative.reserveCapacity(polyline.count)
        for idx in 0 ..< (polyline.count - 1) {
            let leg = polyline[idx].distanceMeters(to: polyline[idx + 1])
            cumulative.append(cumulative.last! + leg)
        }
        let total = cumulative.last!
        guard total > 0 else { return polyline }

        let vertexBudget = min(maxVertices, polyline.count)
        if polyline.count <= vertexBudget {
            return polyline
        }

        var result: [GeodesicWaypoint] = []
        result.reserveCapacity(vertexBudget)
        let lastK = vertexBudget - 1
        for k in 0 ..< vertexBudget {
            let target: Double
            if k == 0 {
                target = 0
            } else if k == lastK {
                target = total
            } else {
                target = total * Double(k) / Double(lastK)
            }

            var hi = 1
            while hi < cumulative.count, cumulative[hi] < target {
                hi += 1
            }
            // `hi` can equal cumulative.count when `target` is rounded up to `total` or from FP noise; clamp for subscripts.
            let i = min(max(1, hi), cumulative.count - 1)
            let prevDist = cumulative[i - 1]
            let segLen = cumulative[i] - prevDist
            let t = segLen > 0 ? (target - prevDist) / segLen : 0
            let clampedT = min(1, max(0, t))
            result.append(
                interpolate(polyline[i - 1], polyline[i], fraction: clampedT)
            )
        }
        return result
    }

    private static func interpolate(
        _ u: GeodesicWaypoint,
        _ v: GeodesicWaypoint,
        fraction: Double
    ) -> GeodesicWaypoint {
        GeodesicWaypoint(
            latitude: u.latitude + (v.latitude - u.latitude) * fraction,
            longitude: u.longitude + (v.longitude - u.longitude) * fraction
        )
    }

    /// Conservative underestimate of how close two geodesic segments pass; good enough for ranking.
    private static func approximateSegmentSeparationMeters(
        a: GeodesicWaypoint,
        b: GeodesicWaypoint,
        c: GeodesicWaypoint,
        d: GeodesicWaypoint
    ) -> Double {
        min(
            minSamplesFromSegmentToPoint(segmentStart: a, segmentEnd: b, point: c),
            minSamplesFromSegmentToPoint(segmentStart: a, segmentEnd: b, point: d),
            minSamplesFromSegmentToPoint(segmentStart: c, segmentEnd: d, point: a),
            minSamplesFromSegmentToPoint(segmentStart: c, segmentEnd: d, point: b)
        )
    }

    private static func minSamplesFromSegmentToPoint(
        segmentStart: GeodesicWaypoint,
        segmentEnd: GeodesicWaypoint,
        point: GeodesicWaypoint
    ) -> Double {
        var best = point.distanceMeters(to: segmentStart)
        best = min(best, point.distanceMeters(to: segmentEnd))
        let steps = 10
        for step in 1 ..< steps {
            let t = Double(step) / Double(steps)
            let q = interpolate(segmentStart, segmentEnd, fraction: t)
            best = min(best, point.distanceMeters(to: q))
        }
        return best
    }
}
