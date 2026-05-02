# In-app navigation (turn-by-turn)

After a loop is **planned** (`planHourLoop`), **Start** begins guidance modeled on Apple Maps walking directions (simplified, in-app only—not opening the Maps app).

## Behavior

- **Steps** come from MapKit’s walking `MKRoute` steps, flattened across all legs. Each step stores text, distances, and a **maneuver coordinate** (end of the step polyline) for progress and map heading.
- **`WalkRouteNavigator`** keeps a current step index. On location updates, it requires **two consecutive** GPS readings within ~32 m of the maneuver point before advancing (reduces jitter).
- **UI**: Primary instruction, **distance to maneuver** (straight-line), **“Then …”** preview, and step index. **Stop guidance** ends the session without clearing the route.
- **Map**: In navigation mode the map uses a **chase camera** (pitch + heading from GPS **course** when valid, otherwise bearing toward the maneuver). It recenters when **Start** is tapped and when the **step index** changes. While navigating, **`onMapCameraChange` does not write back** into `cameraPosition`, because that can fight programmatic camera updates and **hang the app** (watchdog kill / SIGTERM). In **plan** mode, pinch/zoom still syncs via `onMapCameraChange`.
- **Completion**: When the last step is satisfied, guidance stops, a **`WalkRecord`** is written to **History**, and an alert confirms the loop is finished.
- **History**: Only **completed** Start sessions are saved. While navigating, GPS is sampled about every **8 m**; if there are at least two points, that **trace** becomes the stored polyline and distance. With fewer samples, the **planned** polyline and routed distance are used as a fallback. **Stop guidance** throws away the recording without saving. Planning alone never creates a history row. See [history-and-persistence.md](history-and-persistence.md).

## Code touchpoints

- `RandomWalker/WalkRouteNavigator.swift` — step list, `ingest`, bearing helper.
- `RandomWalker/RoutingService.swift` — `RoutedStep.maneuverCoordinate` from each `MKRoute.Step` polyline.
- `RandomWalker/WalkSessionViewModel.swift` — `planHourLoop`, `startNavigation(seedLocation:)`, `stopNavigation`, `ingestNavigationLocation(_:modelContext:)`, private `persistCompletedWalk` on completion.
- `RandomWalker/ContentView.swift` — guidance card, Start / Stop, location-driven ingest with `modelContext`, alert, `WalkMapCard` navigation bindings.
- `RandomWalker/WalkHistoryView.swift` — browse saved `WalkRecord`s.

## XcodeGen

New Swift files under `RandomWalker/` are picked up the next time you run `xcodegen generate`.
