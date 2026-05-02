import Foundation
import RandomWalkerCore

extension RoutedWalk {
    private enum WatchExport {
        static let maxHints = 96
    }

    func makeWatchSnapshot(startedAt: Date) -> ActiveWalkSnapshot {
        let hints = legs
            .flatMap(\.steps)
            .prefix(WatchExport.maxHints)
            .map { step in
                WalkLegHint(
                    title: sanitized(step.instructions),
                    distanceMeters: step.distance,
                    expectedTravelTime: step.expectedTravelTime
                )
            }

        return ActiveWalkSnapshot(
            routeId: id,
            startedAt: startedAt,
            legs: hints,
            totalDistanceMeters: distanceMeters,
            expectedDurationSeconds: expectedTravelTime
        )
    }

    private func sanitized(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Continue" : trimmed
    }
}
