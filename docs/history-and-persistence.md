# History and SwiftData persistence

## When a row is created

| Action | SwiftData |
|--------|-----------|
| **Plan** succeeds (`planLoop`) | **No** `WalkRecord`. The route exists only in session state + watch payload. |
| **Start** → walk → **last step** completes | **Yes** — `WalkRecord` with completion **Guided loop completed**. |
| **Start** → after walking **≥ ~90 m** from the start point, dwell **≥ ~10 s** within **~40 m** of that start | **Yes** — **Returned to start** (same GPS trace / fallback rules as below). |
| **Stop guidance** → **Save to history** | **Yes** — **Saved when stopped** (incomplete guidance allowed). |
| **Stop guidance** → **Discard** | **No** — trace discarded. |
| **Clear map** | Clears the active session and watch context only; **does not** delete existing history rows. |

In **History**, swipe left on a row and tap **Delete** to remove that `WalkRecord`.

## Completion labels (`WalkRecord`)

Stored as `completionKindRaw` (legacy rows treat `nil` as guided complete):

- **Guided loop completed** — every turn-by-turn maneuver advanced to the end.
- **Returned to start** — automatic save after venturing out and coming back to the session start.
- **Saved when stopped** — user chose **Save to history** from the stop confirmation.

## What gets stored

- **`WalkRecord`** holds what you walked after **Start** for one of the save paths above, not every planned variant you browse before walking.
- **Polyline**: Prefer the **GPS trace** sampled during navigation (~every **8 m**). If there are fewer than **two** recorded points, the app stores the **planned** route polyline instead (fallback when fixes are sparse). When Apple Watch recorded the same **navigation session** with at least two samples, History uses the **watch** path and the watch’s **startedAt–endedAt** duration for that row.
- **Distance** (`routedDistanceMeters`): Length along the stored polyline (trace length, or planned distance in the fallback case). Field name is legacy; value reflects **actual walk** when the trace is used.
- **Duration** (`routedExpectedDurationSeconds`): **Wall-clock** time from **Start** to completion. Name is legacy.
- **`targetDurationSeconds`**: Planning target (seconds from the blueprint’s duration goal), for context.
- **Center / `blueprintSalt`**: From the blueprint used for that plan (tie-back to generator metadata).

## Pace learning

Eligible saves also drive **`WalkingPaceService`**: after insert, `WalkSessionViewModel` forwards **stored** `routedDistanceMeters` and **`routedExpectedDurationSeconds`** (wall-clock) to **`ingestObservedWalk`**, so future **time ↔ distance** planning and blueprint generation track how fast you actually walked. See [walking-pace.md](walking-pace.md).

## Code touchpoints

- `RandomWalker/WalkRecord.swift` — SwiftData model.
- `RandomWalker/WalkHistoryView.swift` — list (swipe to delete) + detail map.
- `RandomWalker/WalkSessionViewModel.swift` — `planLoop` (no history write), `ingestNavigationLocation` (guided complete + return-to-start), `stopAndSaveToHistory`, `RoutingService.routeWalkingResume` for replan (no history by itself).

## Related

- [in-app-navigation.md](in-app-navigation.md) — sampling and completion rules.
- [architecture.md](architecture.md) — full planning and data flow.
- [walking-pace.md](walking-pace.md) — Health + EMA pace from saved walks.
