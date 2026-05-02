# In-app navigation (turn-by-turn)

After a loop is **planned** (`planLoop`), **Start** begins guidance modeled on Apple Maps walking directions (simplified, in-app only—not opening the Maps app).

## Behavior

- **Steps** come from MapKit’s walking `MKRoute` steps, flattened across all legs. Each step stores text, distances, and a **maneuver coordinate** (end of the step polyline) for progress and map heading.
- **`WalkRouteNavigator`** keeps a current step index. On location updates, it requires **two consecutive** GPS readings within ~32 m of the maneuver point before advancing (reduces jitter).
- **UI**: Primary instruction, **distance to maneuver** (straight-line), **“Then …”** preview, and step index. **Stop guidance** opens a confirmation: **Save to history**, **Discard**, or cancel. **Recalculate route from here** calls `RoutingService.routeWalkingResume` from the current fix through the rest of the blueprint waypoints, replaces `refinedWalk` + guidance steps, and refreshes the watch snapshot.
- **Map**: In navigation mode the map uses a **chase camera** (pitch + heading from GPS **course** when valid, otherwise bearing toward the maneuver). It recenters when **Start** is tapped and when the **step index** changes. While navigating, **`onMapCameraChange` does not write back** into `cameraPosition`, because that can fight programmatic camera updates and **hang the app** (watchdog kill / SIGTERM). In **plan** mode, pinch/zoom still syncs via `onMapCameraChange`.
- **Completion (guided)**: When the last step is satisfied, guidance stops, a **`WalkRecord`** is written (`guidedComplete`), and an alert confirms.
- **Return-to-start**: After **Start**, if GPS moves **about 90 m** or farther from the start coordinate, then stays within **about 40 m** of that start for **about 10 s**, a **`WalkRecord`** is saved (`returnedToStart`) and guidance ends.
- **History saves**: Same trace rules as before (~**8 m** sampling; ≥2 points → trace polyline, else planned route fallback). **Save to history** on stop uses `savedOnStop`. **Discard** on stop does not save. Planning alone never creates a row. See [history-and-persistence.md](history-and-persistence.md).
- **Apple Watch**: After **Plan**, the phone pushes turn cues in `ActiveWalkSnapshot` (no `navigationSessionId`). After **Start**, the phone pushes again with `navigationSessionId` + `recordingStartedAt`; the watch runs **CoreLocation** (~8 m, aligned with the phone) and can show **Recording path for iPhone**. When the session ends, the phone requests a `WatchRecordedTrack` flush (`requestRecordingFlush` + reply when reachable, else the watch may use `transferUserInfo`). History **prefers** ≥2 watch samples for the stored polyline and watch wall time when merging succeeds.

## Code touchpoints

- `RandomWalker/WalkRouteNavigator.swift` — step list, `ingest`, bearing helper.
- `RandomWalker/RoutingService.swift` — `RoutedStep.maneuverCoordinate`, `routeWalkingLoop`, `routeWalkingResume`.
- `RandomWalker/WalkSessionViewModel.swift` — `planLoop(around:connectivity:walkingSpeedMetersPerSecond:)`, `startNavigation(seedLocation:connectivity:)`, `discardNavigationWithoutSaving(connectivity:)`, `stopAndSaveToHistory`, `replanFromCurrentLocation`, `ingestNavigationLocation`, `ingestWatchRecording`, private `persistWalk`, `onWalkSavedObservedPace` (pace learning).
- `RandomWalker/PhoneConnectivityManager.swift` — `sendActiveWalk`, `requestWatchRecording`, `clearWalkOnWatch`, `onWatchRecordedTrack`.
- `RandomWalkerWatch/WatchWalkCoordinator.swift` — receives snapshots, records GPS, replies with `WatchRecordedTrack`.
- `RandomWalker/ContentView.swift` — guidance card, Start / Stop, location-driven ingest with `modelContext`, alert, `WalkMapCard` navigation bindings.
- `RandomWalker/WalkHistoryView.swift` — browse saved `WalkRecord`s.
- `RandomWalkerCore/ActiveWalkSnapshot.swift` — `WatchRecordedTrack`, `WatchMessageKey`.

## XcodeGen

New Swift files under `RandomWalker/` are picked up the next time you run `xcodegen generate`.

## Related

- [walking-pace.md](walking-pace.md) — saved walks feed `WalkingPaceService` via `onWalkSavedObservedPace`.
