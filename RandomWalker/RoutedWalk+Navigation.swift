import CoreLocation
import Foundation
import RandomWalkerCore

extension RoutedWalk {
    /// Next ``LoopWalkBlueprint.visitSequenceCoordinates`` index to route toward when replanning from a deviation.
    func nextVisitSequenceIndex(afterNavigatorStep flattenedStepIndex: Int) -> Int? {
        RoutedWalkNavigationProgress.nextVisitSequenceIndex(
            flattenedStepIndex: flattenedStepIndex,
            legStepCounts: legs.map(\.steps.count)
        )
    }
}
