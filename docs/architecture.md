# Architecture

## Layers

- **RandomWalkerCore**: Pure domain and shared models—waypoints, blueprint generation, polyline encoding, watch payload types. Tested on macOS via `swift test`.
- **RandomWalker (iOS)**: SwiftUI app shell, `RoutingService` (MapKit), `WalkSessionViewModel`, `WalkingPaceService` (HealthKit + learned pace), SwiftData `WalkRecord`, `LocationService`, `PhoneConnectivityManager`.
- **RandomWalkerWatch**: Consumes messages/context from the phone and presents step hints; records GPS during **Start** sessions and sends `WatchRecordedTrack` back.

Keep **MapKit-specific** types out of the core framework where possible (for example snapshot types like `RoutedStep` on the app side instead of storing `MKRoute.Step` in shared structs).

## Planning flow (`planLoop`)

1. User grants location → blueprint centered on `GeodesicWaypoint` from current coordinates (see [map-and-location.md](map-and-location.md)).
2. **`WalkingPaceService`** supplies **`walkingSpeedMetersPerSecond`** (Health + learned saves, or default); see [walking-pace.md](walking-pace.md).
3. `RandomWalkGenerator` builds a **`LoopWalkBlueprint`** from **`WalkLengthGoal`** (duration or distance) and that pace.
4. `RoutingService` walks each blueprint leg with `MKDirections` (walking only), with **retries**, **alternate routes** when MapKit offers them (prefers longer leg options first), and merges polylines and step hints.
5. `WalkSessionViewModel` may **retry** with scaled radius so routed duration/distance falls in an acceptable band around the chosen goal. **`MKDirections`** failures on one layout no longer abort all attempts; the planner keeps trying other blueprints. If nothing lands **in** the usual ratio band but at least one layout **routed**, the app still shows the **best near-miss** loop (closest to the target by ratio, with the same anti-backtracking ranking as in-band picks).
6. On success, `refinedWalk` / `activeBlueprint` are set and **`ActiveWalkSnapshot`** is sent to the watch via `PhoneConnectivityManager`. **No** `WalkRecord` is written at this stage.

## In-app guidance and history

After planning, **Start** runs turn-by-turn navigation ([in-app-navigation.md](in-app-navigation.md)). A **`WalkRecord`** is written when guidance **finishes all steps**, when the walker **returns near the start** after venturing out, or when they **save on stop**; otherwise **Discard** clears the trace. Stored path prefers the GPS **trace** when enough samples exist. Details: [history-and-persistence.md](history-and-persistence.md).

## Related docs

- [product-intent.md](product-intent.md) — why this design exists.
- [map-and-location.md](map-and-location.md) — map UI and location semantics.
- [walking-pace.md](walking-pace.md) — personalized walking speed for planning.
