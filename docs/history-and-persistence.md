# History and SwiftData persistence

## When a row is created

| Action | SwiftData |
|--------|-----------|
| **Plan** succeeds (`planHourLoop`) | **No** `WalkRecord`. The route exists only in session state + watch payload. |
| **Start** → walk → **last step** completes | **Yes** — one `WalkRecord` is inserted. |
| **Stop guidance** (before completion) | **No** — recorded GPS trace is discarded. |
| **Clear map** | Clears the active session and watch context only; **does not** delete existing history rows. |

## What gets stored

- **`WalkRecord`** holds the loop that was **actually finished** after **Start**, not every planned variant the user browses before walking.
- **Polyline**: Prefer the **GPS trace** sampled during navigation (~every **8 m**). If there are fewer than **two** recorded points, the app stores the **planned** route polyline instead (fallback when fixes are sparse).
- **Distance** (`routedDistanceMeters`): Length along the stored polyline (trace length, or planned distance in the fallback case). Field name is legacy; value reflects **actual walk** when the trace is used.
- **Duration** (`routedExpectedDurationSeconds`): **Wall-clock** time from **Start** to completion. Name is legacy.
- **`targetDurationSeconds`**: Planning target (~1 hour), for context.
- **Center / `blueprintSalt`**: From the blueprint used for that plan (tie-back to generator metadata).

## Code touchpoints

- `RandomWalker/WalkRecord.swift` — SwiftData model.
- `RandomWalker/WalkHistoryView.swift` — list + detail map.
- `RandomWalker/WalkSessionViewModel.swift` — `planHourLoop` (no history write), `ingestNavigationLocation` → `persistCompletedWalk` on completion.

## Related

- [in-app-navigation.md](in-app-navigation.md) — sampling and completion rules.
- [architecture.md](architecture.md) — full planning and data flow.
