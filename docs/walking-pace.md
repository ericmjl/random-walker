# Walking pace (personalized planning)

Random Walker no longer assumes a single fixed walking speed for everyone when converting **target duration ↔ loop length** and when generating blueprints. Pace comes from **`WalkingPaceService`**, which blends **Apple Health** walking-speed samples (if the user authorizes read access) with a **learned** pace updated from **saved walks** (GPS / watch path length and elapsed time). If neither source exists, the app uses **`RandomWalkGenerator.defaultWalkingSpeedMetersPerSecond`** (~brisk urban walking).

## What this affects

| Affected | Not affected |
|----------|----------------|
| **`RandomWalkGenerator.Configuration`** and **`planLoop`** duration matching — for a **time** goal, the planner compares target seconds to **your** implied duration `distanceMeters ÷ effectiveWalkingSpeedMetersPerSecond` (same pace as the UI), not MapKit’s stitched **`expectedTravelTime`**. | **Per-step** turn hints still use **MapKit** leg shapes and relative step durations from directions (navigation UX). |
| **Plan tab route line** (“About *X* min at your pace…”) — **X** ≈ `distance ÷ effective speed`. | Historical **`WalkRecord`** rows are not rewritten when pace changes; only **future** plans use the new value. |
| **New route sheet** — switching between “Walking time” and “Route distance” converts sliders using the same effective pace. | — |

## Diagnostics log (rotation)

Verbose planning and pace messages are **not** shown in the main UI. They go to **`RotatingFileLogger`**, which appends UTF-8 lines under:

**`Library/Application Support/RandomWalker/Logs/diagnostics.log`**

Rotation: when the active file would exceed **512 KiB**, it is renamed to **`diagnostics.1.log`**, previous numbered files shift up (`2` ← `1`, …), and **`diagnostics.5.log`** is deleted — so up to **six** files total (active + five rotated). Each line looks like **`[ISO8601] [category] message`**; categories include **`planning`**, **`pace`**, and **`routing`** (per-leg MapKit failures with WGS84 coordinates).

On Simulator, logs live under the app container; open the container from **Devices and Simulators** in Xcode, or use **Console** with the process filter.

## Components

### `RandomWalker/RotatingFileLogger.swift`

Singleton **`RotatingFileLogger.shared.log(_ category:message:)`** — thread-safe, async append on a serial queue.

### `RandomWalker/RoutingService.swift`

On **`MKDirections`** failure for a single hop, logs one **`routing`** line: operation (`routeWalkingLoop` or `routeWalkingResume(…)`), **`leg i/n`**, **`latitude,longitude` → `latitude,longitude`**, and the error text, then rethrows.

### `RandomWalker/WalkingPaceService.swift`

- **`effectiveWalkingSpeedMetersPerSecond`** — clamped to **1.0…2.3 m/s** (~3.6…8.3 km/h), published for SwiftUI (used by **`planLoop`** and the Plan summary line only).
- **`bootstrapFromHistoryIfNeeded(modelContext:)`** — if there is no stored EMA yet, computes a **median** pace from up to the **20 most recent** `WalkRecord`s that pass filters: duration ≥ **120 s**, distance ≥ **250 m**, pace between **0.9…2.6 m/s**. Writes seed to UserDefaults then recomputes.
- **`requestWalkingSpeedReadAccessIfNeeded()`** — if **`HKAuthorizationStatus`** is **`.notDetermined`**, requests **read** for **`HKQuantityTypeIdentifier.walkingSpeed`** (system sheet on first launch). Called from **`ContentView`** **`.task`** before **`refreshAuthorizedHealthKitData()`**.
- **`ingestObservedWalk(distanceMeters:durationSeconds:)`** — updates learned pace with an **EMA** (`alpha = 0.38`) when duration ≥ **120 s** and distance ≥ **300 m**. Pace fed into the EMA is clamped to the same global band as `effectiveWalkingSpeedMetersPerSecond`.
- **`refreshAuthorizedHealthKitData()`** — re-queries HealthKit when read access is already **`.sharingAuthorized`** (e.g. app relaunch).

When the effective speed **changes**, **`recomputeEffective()`** writes a **`pace`** line to **`RotatingFileLogger`**.

**Blending** when recomputing the effective speed:

- Both learned (UserDefaults) and Health median present: **52% learned + 48% Health**, then clamp.
- Only one source: use it (still clamped).
- Neither: default generator speed.

**Persistence:**

- Learned EMA: UserDefaults key **`randomwalker.walkingPace.learnedEMA`**.
- Health median is kept in memory (`cachedHealthMedianPace`) until the next successful query.
- Simulator seeding flag: **`randomwalker.debug.simulatorWalkingSpeedSeeded`** — avoids re-inserting the default fixture batch on every launch.

### HealthKit app configuration

- **Entitlements**: `RandomWalker/RandomWalker.entitlements` — `com.apple.developer.healthkit` = true. **`project.yml`** duplicates this under `targets.RandomWalker.entitlements.properties` so **`xcodegen generate`** merges the capability into the plist (avoids an empty entitlements file after regeneration).
- **Info.plist**: **`NSHealthShareUsageDescription`** (read walking speed for planning); **`NSHealthUpdateUsageDescription`** — on **simulator**, the app may save sample walking-speed fixtures for testing; on **device**, it does not write Health data.

### Wiring (iOS app)

- **`ContentView`** — owns `@StateObject WalkingPaceService`, passes it into **`PlanWalkView`**, calls **`bootstrapFromHistoryIfNeeded`**, **`requestWalkingSpeedReadAccessIfNeeded()`**, **`refreshAuthorizedHealthKitData()`**, and (on **simulator only**) **`seedSimulatorWalkingSpeedFixtures()`** from **`.task`**. **`session.onWalkSavedObservedPace`** is set in **`.onAppear`** to **`ingestObservedWalk`**.
- **`PlanWalkView`** — passes **`effectiveWalkingSpeedMetersPerSecond`** into **`NewRoutePlanningSheet`** and **`planLoop`**. No pace / Health marketing card on the Plan screen.
- **`WalkingPaceService`** (simulator builds only, `#if targetEnvironment(simulator)`) — **`seedSimulatorWalkingSpeedFixtures(force:)`** requests read **and** write for walking speed, saves ~10 samples, logs outcome to **`RotatingFileLogger`**.
- **`WalkSessionViewModel`** — **`planLoop`** and replan log **`planning`** lines via **`RotatingFileLogger`**; **`refinementSummary`** was removed. Hard failures stay in **`planningError`**.

## Testing (manual)

1. **Build and run**: [build-and-test.md](build-and-test.md).
2. **Health**: On first launch, allow **Walking Speed** read when the system sheet appears (simulator seeding may also request write once for fixtures).
3. **Logs**: Plan a route and inspect **`diagnostics.log`** for **`[planning]`** / **`[pace]`** lines.
4. **Learning**: Save a walk from **Start**; after relaunch, confirm **`planLoop`** behavior and logs reflect updated pace.

## Related

- [architecture.md](architecture.md) — planning flow and `planLoop`.
- [history-and-persistence.md](history-and-persistence.md) — what a `WalkRecord` stores (feeds bootstrap and EMA).
- [map-and-location.md](map-and-location.md) — where planning is anchored.
