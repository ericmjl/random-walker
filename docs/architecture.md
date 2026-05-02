# Architecture

## Layers

- **RandomWalkerCore**: Pure domain and shared models—waypoints, blueprint generation, polyline encoding, watch payload types. Tested on macOS via `swift test`.
- **RandomWalker (iOS)**: SwiftUI app shell, `RoutingService` (MapKit), `WalkSessionViewModel`, SwiftData `WalkRecord`, `LocationService`, `PhoneConnectivityManager`.
- **RandomWalkerWatch**: Consumes messages/context from the phone and presents step hints.

Keep **MapKit-specific** types out of the core framework where possible (for example snapshot types like `RoutedStep` on the app side instead of storing `MKRoute.Step` in shared structs).

## Data flow (planning a walk)

1. User grants location → blueprint centered on `GeodesicWaypoint` from current coordinates (see [map-and-location.md](map-and-location.md)).
2. `RoutingService` walks each blueprint leg with `MKDirections` (walking only) and merges polylines and step hints.
3. `WalkSessionViewModel` may **retry** with scaled radius so routed duration falls in an acceptable band around one hour.
4. A `WalkRecord` is stored in SwiftData; an `ActiveWalkSnapshot` is sent to the watch when connectivity allows.

## In-app guidance

After planning, the user can tap **Start** for **turn-by-turn style** instructions driven by the same MapKit step text and maneuver points (see [in-app-navigation.md](in-app-navigation.md)).

## Related docs

- [product-intent.md](product-intent.md) — why this design exists.
- [map-and-location.md](map-and-location.md) — map UI and location semantics.
