# In-app navigation (turn-by-turn)

After a loop is **planned** (`planLoop`), **Start** begins guidance modeled on Apple Maps walking directions (simplified, in-app only—not opening the Maps app).

## Behavior

- **UI (active guidance)**: **Layout (Apple Maps–style)**: **map-first** and **full-bleed**—the map extends under the status area and home indicator (no navigation bar, no outer card padding, no rounded map mask); trip UI uses **symmetric horizontal insets** and a full-width maneuver pager (page `TabView` is forced to `maxWidth: .infinity` so the banner does not hug the leading edge). Overlays use **safe area** padding for the card, floating controls, and trip sheet. **Chase mode** uses a **pitched, heading-locked Map camera** (closer and steeper than before); **pan and rotate are disabled** during chase so the map does not ease back to flat north-up (**pinch zoom stays on**)—use **Route overview** or **browse** another step for a draggable north-up preview. A **dark top instruction card** shows **distance** (large, rounded type), a **maneuver SF Symbol** inferred from MapKit step text, primary instruction, and a **“Then …”** line; **paged** instructions (no page dots) with **subtle edge chevrons** (stronger when another step exists that way). VoiceOver combines the card and includes a swipe hint. **Follow live** appears when the open page is not the live GPS step; while browsing (and not in route overview), the map uses a **north-up overview** framed to show **your position and that page’s maneuver**. On the **live** step (and not in route overview), the map uses the **chase camera** behind you. A **bottom trip drawer** (top-rounded **`UnevenRoundedRectangle`**, edge-to-edge frosted **`Material`**, drag **grabber**, content inset with **`safeAreaPadding`** above the home indicator) shows **Arrive** (clock time from remaining distance ÷ **WalkingPaceService** pace), **Time** remaining, **Distance** remaining (live-step-based), and **End walk** (opens the stop confirmation dialog). **Floating circular controls**: **route overview** (north-up fit of the full loop vs return to chase), and a muted **speaker** placard labeled as voice guidance unavailable. Distance **In …** on the card uses your current GPS fix to the maneuver shown on the page; trip stats always follow the **live** step. While you stay on the live step, GPS advances the maneuver; when your live step catches up to a step you had selected for browsing, browse mode clears. **Live map**: polyline, user puck (**white** travel arrow, optional **orange** bearing arrow), and **Turn** marker for the **displayed** maneuver. Tab bar stays hidden.
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
- `RandomWalker/WalkSessionViewModel.swift` — `planLoop`, `startNavigation`, `discardNavigationWithoutSaving`, `stopAndSaveToHistory`, `replanFromCurrentLocation`, `ingestNavigationLocation`, `ingestWatchRecording`, `navigationBrowseStepIndex` / `navigationDisplayedStepIndex`, `navigationRemainingDistanceApprox` / `navigationRemainingDurationApprox`, per-step copy helpers, browse reset on replan / session end / when live catches the browsed step, `persistWalk`, `onWalkSavedObservedPace`.
- `RandomWalker/ContentView.swift` — paged turn-by-turn during navigation, plan-mode map and **Start walk**, **End walk** + stop confirmation, `WalkMapCard` (plan vs guidance), location ingest, completion alert.
- `RandomWalker/PhoneConnectivityManager.swift` — `sendActiveWalk`, `requestWatchRecording`, `clearWalkOnWatch`, `onWatchRecordedTrack`.
- `RandomWalkerWatch/WatchWalkCoordinator.swift` — receives snapshots, records GPS, replies with `WatchRecordedTrack`.
- `RandomWalker/WalkHistoryView.swift` — browse saved `WalkRecord`s.
- `RandomWalkerCore/ActiveWalkSnapshot.swift` — `WatchRecordedTrack`, `WatchMessageKey`.

## XcodeGen

New Swift files under `RandomWalker/` are picked up the next time you run `xcodegen generate`.

## Related

- [walking-pace.md](walking-pace.md) — saved walks feed `WalkingPaceService` via `onWalkSavedObservedPace`.
