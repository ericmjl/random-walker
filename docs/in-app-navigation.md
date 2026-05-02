# In-app navigation (turn-by-turn)

After a loop is **planned** (`planHourLoop`), **Start** begins guidance modeled on Apple Maps walking directions (simplified, in-app only—not opening the Maps app).

## Behavior

- **Steps** come from MapKit’s walking `MKRoute` steps, flattened across all legs. Each step stores text, distances, and a **maneuver coordinate** (end of the step polyline) for progress and map heading.
- **`WalkRouteNavigator`** keeps a current step index. On location updates, it requires **two consecutive** GPS readings within ~32 m of the maneuver point before advancing (reduces jitter).
- **UI**: Primary instruction, **distance to maneuver** (straight-line), **“Then …”** preview, and step index. **Stop guidance** opens a confirmation: **Save to history**, **Discard**, or cancel. **Recalculate route from here** calls `RoutingService.routeWalkingResume` from the current fix through the rest of the blueprint waypoints, replaces `refinedWalk` + guidance steps, and refreshes the watch snapshot.
- **Map**: In navigation mode the map uses a **chase camera** (pitch + heading from GPS **course** when valid, otherwise bearing toward the maneuver). It recenters when **Start** is tapped and when the **step index** changes. While navigating, **`onMapCameraChange` does not write back** into `cameraPosition`, because that can fight programmatic camera updates and **hang the app** (watchdog kill / SIGTERM). In **plan** mode, pinch/zoom still syncs via `onMapCameraChange`.
- **Completion (guided)**: When the last step is satisfied, guidance stops, a **`WalkRecord`** is written (`guidedComplete`), and an alert confirms.
- **Return-to-start**: After **Start**, if GPS moves **about 90 m** or farther from the start coordinate, then stays within **about 40 m** of that start for **about 10 s**, a **`WalkRecord`** is saved (`returnedToStart`) and guidance ends.
- **History saves**: Same trace rules as before (~**8 m** sampling; ≥2 points → trace polyline, else planned route fallback). **Save to history** on stop uses `savedOnStop`. **Discard** on stop does not save. Planning alone never creates a row. See [history-and-persistence.md](history-and-persistence.md).

## Code touchpoints

- `RandomWalker/WalkRouteNavigator.swift` — step list, `ingest`, bearing helper.
- `RandomWalker/RoutingService.swift` — `RoutedStep.maneuverCoordinate`, `routeWalkingLoop`, `routeWalkingResume`.
- `RandomWalker/WalkSessionViewModel.swift` — `planHourLoop`, `startNavigation(seedLocation:)`, `discardNavigationWithoutSaving`, `stopAndSaveToHistory`, `replanFromCurrentLocation`, `ingestNavigationLocation(_:modelContext:)`, private `persistWalk`.
- `RandomWalker/ContentView.swift` — guidance card, Start / Stop, location-driven ingest with `modelContext`, alert, `WalkMapCard` navigation bindings.
- `RandomWalker/WalkHistoryView.swift` — browse saved `WalkRecord`s.

## XcodeGen

New Swift files under `RandomWalker/` are picked up the next time you run `xcodegen generate`.
