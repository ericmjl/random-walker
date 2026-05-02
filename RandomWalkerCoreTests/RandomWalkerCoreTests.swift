import RandomWalkerCore
import XCTest

final class RandomWalkGeneratorTests: XCTestCase {
    func testBlueprintClosurePerimeterStableWithSeed() {
        var rng = SplitMix64RNG(seed: 42)
        let center = GeodesicWaypoint(latitude: 37.3349, longitude: -122.0090)
        let blueprint = RandomWalkGenerator.makeBlueprint(
            center: center,
            configuration: RandomWalkGenerator.Configuration(targetDuration: 3_600),
            rng: &rng
        )

        XCTAssertGreaterThanOrEqual(blueprint.intermediateWaypoints.count, 1)
        XCTAssertEqual(blueprint.center, center)

        let sequence = blueprint.visitSequenceCoordinates
        XCTAssertEqual(sequence.first, center)
        XCTAssertEqual(sequence.last, center)

        var rngAgain = SplitMix64RNG(seed: 42)
        let duplicate = RandomWalkGenerator.makeBlueprint(
            center: center,
            configuration: RandomWalkGenerator.Configuration(targetDuration: 3_600),
            rng: &rngAgain
        )
        XCTAssertEqual(blueprint, duplicate)

        var rngAnother = SplitMix64RNG(seed: 7)
        let different = RandomWalkGenerator.makeBlueprint(
            center: center,
            configuration: RandomWalkGenerator.Configuration(targetDuration: 3_600),
            rng: &rngAnother
        )
        XCTAssertNotEqual(different.intermediateWaypoints, duplicate.intermediateWaypoints)
    }

    func testDistanceGoalYieldsLongerNominalDurationThanShortWalk() {
        let short = RandomWalkGenerator.Configuration(targetDuration: 600)
        let long = RandomWalkGenerator.Configuration(lengthGoal: .distance(meters: 8_000))
        XCTAssertGreaterThan(long.nominalTargetDuration, short.nominalTargetDuration)
    }

    func testRadiusScaleChangesGeometryWithSameSeed() {
        let center = GeodesicWaypoint(latitude: 40.0, longitude: -74.0)
        var rngSmall = SplitMix64RNG(seed: 99)
        var rngLarge = SplitMix64RNG(seed: 99)

        let small = RandomWalkGenerator.makeBlueprint(
            center: center,
            configuration: RandomWalkGenerator.Configuration(targetDuration: 1_800),
            rng: &rngSmall,
            radiusScale: 0.5
        )
        let large = RandomWalkGenerator.makeBlueprint(
            center: center,
            configuration: RandomWalkGenerator.Configuration(targetDuration: 1_800),
            rng: &rngLarge,
            radiusScale: 1.5
        )

        XCTAssertNotEqual(small.intermediateWaypoints, large.intermediateWaypoints)
    }
}

final class RewalkProximityTests: XCTestCase {
    func testFoldedOutAndBackScoresHigherThanOpenArc() {
        var folded: [GeodesicWaypoint] = []
        let base = GeodesicWaypoint(latitude: 40.0, longitude: -74.0)
        for k in 0 ..< 9 {
            folded.append(
                GeodesicWaypoint(latitude: 40.0 + 0.000_15 * Double(k), longitude: -74.0 + 0.000_05 * Double(k))
            )
        }
        for k in (0 ..< 9).reversed() {
            folded.append(
                GeodesicWaypoint(latitude: 40.0 + 0.000_15 * Double(k), longitude: -74.0 + 0.000_05 * Double(k))
            )
        }

        var arc: [GeodesicWaypoint] = [base]
        for k in 1 ..< 16 {
            let t = Double(k) / 15
            arc.append(
                GeodesicWaypoint(
                    latitude: 40.0 + 0.002 * sin(t * .pi),
                    longitude: -74.0 + 0.002 * cos(t * .pi)
                )
            )
        }

        let foldedDebt = RewalkProximity.debtMeters(polyline: folded)
        let arcDebt = RewalkProximity.debtMeters(polyline: arc)
        XCTAssertGreaterThan(foldedDebt, arcDebt, "Backtracking along the same corridor should cost more than a spreading arc.")
    }

    func testShortPolylineHasZeroDebt() {
        let pts = [
            GeodesicWaypoint(latitude: 1, longitude: 2),
            GeodesicWaypoint(latitude: 1.001, longitude: 2),
        ]
        XCTAssertEqual(RewalkProximity.debtMeters(polyline: pts), 0, accuracy: 0.001)
    }

    /// Regression: downsampling used to subscript `cumulative[count]` when the last sample target met or exceeded length due to FP rounding.
    func testLongPolylineDownsampleProducesFiniteDebt() {
        var pts: [GeodesicWaypoint] = []
        for i in 0 ..< 200 {
            pts.append(
                GeodesicWaypoint(latitude: 40.0 + 0.000_1 * Double(i), longitude: -74.0)
            )
        }
        let debt = RewalkProximity.debtMeters(polyline: pts, maxVertices: 48)
        XCTAssertTrue(debt.isFinite)
        XCTAssertGreaterThanOrEqual(debt, 0)
    }
}

final class PolylineCodecTests: XCTestCase {
    func testRoundTripPreservesCoordinates() {
        let original = [
            GeodesicWaypoint(latitude: 38.5, longitude: -90.21),
            GeodesicWaypoint(latitude: 40.7, longitude: -89.1),
            GeodesicWaypoint(latitude: 43.252, longitude: -126.453),
        ]

        let encoded = PolylineCodec.encode(coordinates: original)
        XCTAssertFalse(encoded.isEmpty)

        let decoded = PolylineCodec.decode(polyline: encoded)
        XCTAssertEqual(decoded.count, original.count)

        for pair in zip(original, decoded) {
            XCTAssertEqual(pair.0.latitude, pair.1.latitude, accuracy: 0.000_01)
            XCTAssertEqual(pair.0.longitude, pair.1.longitude, accuracy: 0.000_01)
        }
    }

    func testMapCoordinatesBridge() {
        let points = [
            GeodesicWaypoint(latitude: 12.34, longitude: 56.78),
            GeodesicWaypoint(latitude: -1.5, longitude: 2.25),
        ]

        let mapped = PolylineCodec.mapCoordinates(from: points)
        XCTAssertEqual(mapped.count, 2)
        XCTAssertEqual(mapped[0].latitude, 12.34, accuracy: 0.000_001)
        XCTAssertEqual(mapped[1].longitude, 2.25, accuracy: 0.000_001)
    }
}

final class RoutedWalkNavigationProgressTests: XCTestCase {
    func testNextVisitIndexWithinFirstLeg() {
        XCTAssertEqual(
            RoutedWalkNavigationProgress.nextVisitSequenceIndex(flattenedStepIndex: 0, legStepCounts: [4, 3, 2]),
            1
        )
        XCTAssertEqual(
            RoutedWalkNavigationProgress.nextVisitSequenceIndex(flattenedStepIndex: 3, legStepCounts: [4, 3, 2]),
            1
        )
    }

    func testNextVisitIndexCrossesIntoLaterLeg() {
        XCTAssertEqual(
            RoutedWalkNavigationProgress.nextVisitSequenceIndex(flattenedStepIndex: 4, legStepCounts: [4, 3, 2]),
            2
        )
        XCTAssertEqual(
            RoutedWalkNavigationProgress.nextVisitSequenceIndex(flattenedStepIndex: 6, legStepCounts: [4, 3, 2]),
            2
        )
        XCTAssertEqual(
            RoutedWalkNavigationProgress.nextVisitSequenceIndex(flattenedStepIndex: 7, legStepCounts: [4, 3, 2]),
            3
        )
    }

    func testNextVisitIndexPastStepsReturnsNil() {
        XCTAssertNil(
            RoutedWalkNavigationProgress.nextVisitSequenceIndex(flattenedStepIndex: 9, legStepCounts: [4, 3, 2])
        )
    }
}

final class ActiveWalkSnapshotTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let snapshot = ActiveWalkSnapshot(
            routeId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            legs: [
                WalkLegHint(title: "Turn left", distanceMeters: 120, expectedTravelTime: 90),
            ],
            totalDistanceMeters: 450,
            expectedDurationSeconds: 600
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ActiveWalkSnapshot.self, from: data)
        XCTAssertEqual(decoded.routeId, snapshot.routeId)
        XCTAssertEqual(decoded.legs.count, 1)
        XCTAssertEqual(decoded.legs.first?.title, "Turn left")
        XCTAssertNil(decoded.navigationSessionId)
    }

    func testSnapshotWithNavigationSessionRoundTrip() throws {
        let sid = UUID()
        let recStart = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = ActiveWalkSnapshot(
            routeId: UUID(),
            startedAt: .now,
            legs: [],
            totalDistanceMeters: 100,
            expectedDurationSeconds: 60,
            navigationSessionId: sid,
            recordingStartedAt: recStart
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ActiveWalkSnapshot.self, from: data)
        XCTAssertEqual(decoded.navigationSessionId, sid)
        XCTAssertEqual(decoded.recordingStartedAt, recStart)
    }

    func testWatchRecordedTrackJSONRoundTrip() throws {
        let track = WatchRecordedTrack(
            routeId: UUID(),
            navigationSessionId: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_600),
            samples: [
                GeodesicWaypoint(latitude: 1, longitude: 2),
                GeodesicWaypoint(latitude: 1.0001, longitude: 2.0001),
            ]
        )
        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(WatchRecordedTrack.self, from: data)
        XCTAssertEqual(decoded.samples.count, 2)
        XCTAssertEqual(decoded.samples[0].latitude, 1, accuracy: 0.000_001)
    }
}
