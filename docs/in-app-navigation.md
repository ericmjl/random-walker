# In-app navigation (turn-by-turn)

After a loop is **planned** (`planLoop`), **Start** begins guidance modeled on Apple Maps walking directions (simplified, in-app only—not opening the Maps app).

## Behavior

- **UI (active guidance)**: **Layout**: turn-by-turn occupies the **top third** of the guidance screen; the **map uses the bottom two-thirds** (proportional `GeometryReader` split). Copy is slightly condensed (smaller type scale, line limits) to fit the top band. **Paged** instructions: swipe horizontally to preview any step; page dots and **subtle edge chevrons** (stronger when another step exists that way) hint at paging without instructional copy. VoiceOver gets an accessibility hint on the pager. **Follow live** appears when the open page is not the live GPS step; while browsing, the map uses a **north-up overview** framed to show **your position and that page’s maneuver** (so street names match the card). On the **live** step, the map returns to the **chase camera** behind you. Distance **In …** uses your current GPS fix to the maneuver shown on the page. While you stay on the live step, GPS advances the maneuver; when your live step catches up to a step you had selected for browsing, browse mode clears. Below: **live map** with polyline, user puck (**white** travel arrow, optional **orange** bearing arrow), and **Turn** marker for the **displayed** maneuver. Tab bar stays hidden; **End walk** still opens save/discard/cancel.
- **UI (planning / before Start)**: Map, status, **Start walk**, **New route**, and **Clear map** behave as before.
- **Steps** come from MapKit’s walking `MKRoute` steps, flattened across all legs. Each step stores text, distances, and a **maneuver coordinate** (end of the step polyline) for progress and map annotations. While navigating, the map **follows** the user as the GPS fix updates (`WalkMapCard` reapplies the chase camera on coordinate changes).
- **`WalkRouteNavigator`** keeps a current step index. On location updates, it requires **two consecutive** GPS readings within ~32 m of the maneuver point before advancing (reduces jitter).
- **Recalculate from current location** (`RoutingService.routeWalkingResume`) remains available from code (`WalkSessionViewModel.replanFromCurrentLocation`) but is not shown during the simplified guidance screen; end guidance and plan again if you need a new route.
- **Completion (guided)**: When the last step is satisfied, guidance stops, a **`WalkRecord`** is written (`guidedComplete`), and an alert confirms.
- **Return-to-start**: After **Start**, if GPS moves **about 90 m** or farther from the start coordinate, then stays within **about 40 m** of that start for **about 10 s**, a **`WalkRecord`** is saved (`returnedToStart`) and guidance ends.
- **History saves**: Same trace rules as before (~**8 m** sampling; ≥2 points → trace polyline, else planned route fallback). **Save to history** on stop uses `savedOnStop`. **Discard** on stop does not save. Planning alone never creates a row. See [history-and-persistence.md](history-and-persistence.md).
- **Apple Watch**: After **Plan**, the phone pushes turn cues in `ActiveWalkSnapshot` (no `navigationSessionId`). After **Start**, the phone pushes again with `navigationSessionId` + `recordingStartedAt`; the watch runs **CoreLocation** (~8 m, aligned with the phone) and can show **Recording path for iPhone**. When the session ends, the phone requests a `WatchRecordedTrack` flush (`requestRecordingFlush` + reply when reachable, else the watch may use `transferUserInfo`). History **prefers** ≥2 watch samples for the stored polyline and watch wall time when merging succeeds.

## Code touchpoints

- `RandomWalker/WalkRouteNavigator.swift` — step list, `ingest`, bearing helper.
- `RandomWalker/RoutingService.swift` — `RoutedStep.maneuverCoordinate`, `routeWalkingLoop`, `routeWalkingResume`.
- `RandomWalker/WalkSessionViewModel.swift` — `planLoop`, `startNavigation`, `discardNavigationWithoutSaving`, `stopAndSaveToHistory`, `replanFromCurrentLocation`, `ingestNavigationLocation`, `ingestWatchRecording`, `navigationBrowseStepIndex` / `navigationDisplayedStepIndex`, per-step copy helpers, browse reset on replan / session end / when live catches the browsed step, `persistWalk`, `onWalkSavedObservedPace`.
- `RandomWalker/ContentView.swift` — paged turn-by-turn during navigation, plan-mode map and **Start walk**, **End walk** + stop confirmation, `WalkMapCard` (plan vs guidance), location ingest, completion alert.
- `RandomWalker/PhoneConnectivityManager.swift` — `sendActiveWalk`, `requestWatchRecording`, `clearWalkOnWatch`, `onWatchRecordedTrack`.
- `RandomWalkerWatch/WatchWalkCoordinator.swift` — receives snapshots, records GPS, replies with `WatchRecordedTrack`.
- `RandomWalker/WalkHistoryView.swift` — browse saved `WalkRecord`s.
- `RandomWalkerCore/ActiveWalkSnapshot.swift` — `WatchRecordedTrack`, `WatchMessageKey`.

## XcodeGen

New Swift files under `RandomWalker/` are picked up the next time you run `xcodegen generate`.

## Related

- [walking-pace.md](walking-pace.md) — saved walks feed `WalkingPaceService` via `onWalkSavedObservedPace`.
