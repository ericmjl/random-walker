import Foundation

/// Maps flattened turn-by-turn progress to the next major visit index in a loop blueprint.
public enum RoutedWalkNavigationProgress: Sendable {
    /// Returns the visit-sequence index of the **next** waypoint after the current navigator step.
    ///
    /// Leg *i* of a routed walk travels from ``visitSequence[i]`` to ``visitSequence[i + 1]``.
    /// While the user is still on that leg, the next major waypoint is at index *i + 1*.
    /// - Parameters:
    ///   - flattenedStepIndex: Zero-based index into concatenated MapKit-derived walk-leg steps (`WalkLegHint` / ``WalkRouteNavigator``).
    ///   - legStepCounts: Number of MapKit steps per leg, in visit order.
    /// - Returns: Next visit index, or `nil` if the navigator index is past all steps.
    public static func nextVisitSequenceIndex(
        flattenedStepIndex: Int,
        legStepCounts: [Int]
    ) -> Int? {
        guard flattenedStepIndex >= 0 else { return nil }
        var remaining = flattenedStepIndex
        for (legIndex, stepCount) in legStepCounts.enumerated() where stepCount > 0 {
            if remaining < stepCount {
                return legIndex + 1
            }
            remaining -= stepCount
        }
        return nil
    }
}
