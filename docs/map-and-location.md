# Map and location

## Permissions

- **When-in-use** location is required to anchor the loop at **the user’s current position**.
- The app requests authorization on launch and surfaces **in-UI copy + actions** (`notDetermined` / `denied`) so the user understands why access is needed.
- **Planning** uses `coordinateForWalkStart()` so a **fresh** fix is preferred (`requestLocation` plus a short wait) instead of only the last streamed update.

## Map behavior (Plan tab)

- The map shows **“You”** and the **route polyline** when present.
- **Programmatic camera**: Fit the camera to the **route** when the polyline changes, or to a **default region around the user** when there is no route—**not** on every GPS update, so **pinch zoom and manual framing are preserved** in plan mode.
- **`onMapCameraChange` (plan mode only)**: After the user finishes a pinch, pan, rotation, or tilt, the app stores the resulting **`MapCamera`** in state. Without this, SwiftUI re-applies a stale `MapCameraPosition` on the next layout and **zoom appears broken** (map snaps back). While **`isNavigating`** is true, this callback **does not** update state (see [in-app-navigation.md](in-app-navigation.md)) to avoid a main-thread feedback loop / watchdog kill.
- `interactionModes: .all` keeps **pan, zoom, rotate, and pitch** available where the SDK allows.

Implementation detail: a small state flag records when the “user-only” map has been auto-framed so ongoing location updates do not fight user zoom during planning.
