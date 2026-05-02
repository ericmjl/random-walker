# Walking pace (personalized planning)

Random Walker no longer assumes a single fixed walking speed for everyone when converting **target duration ↔ loop length** and when generating blueprints. Pace comes from **`WalkingPaceService`**, which blends **Apple Health** walking-speed samples (if the user authorizes read access) with a **learned** pace updated from **saved walks** (GPS / watch path length and elapsed time). If neither source exists, the app uses **`RandomWalkGenerator.defaultWalkingSpeedMetersPerSecond`** (~brisk urban walking).

## What this affects

| Affected | Not affected |
|----------|----------------|
| **`RandomWalkGenerator.Configuration`** and **`planLoop`** duration matching — for a **time** goal, the planner compares target seconds to **your** implied duration `distanceMeters ÷ effectiveWalkingSpeedMetersPerSecond` (same pace as the UI), not MapKit’s stitched **`expectedTravelTime`**. | **Per-step** turn hints still use **MapKit** leg shapes and relative step durations from directions (navigation UX). |
| **Planned route summary** (“About *X* min at your pace…”) — **X** ≈ `distance ÷ effective speed`. **Adjusting route…** copy during retries uses the same basis. | Historical **`WalkRecord`** rows are not rewritten when pace changes; only **future** plans use the new value. |
| **New route sheet** — switching between “Walking time” and “Route distance” converts sliders using the same effective pace. | — |

## Components

### `RandomWalker/WalkingPaceService.swift`

- **`effectiveWalkingSpeedMetersPerSecond`** — clamped to **1.0…2.3 m/s** (~3.6…8.3 km/h), published for SwiftUI.
- **`paceDetail`** — short user-facing explanation (default vs Health vs learned vs blended).
- **`bootstrapFromHistoryIfNeeded(modelContext:)`** — if there is no stored EMA yet, computes a **median** pace from up to the **20 most recent** `WalkRecord`s that pass filters: duration ≥ **120 s**, distance ≥ **250 m**, pace between **0.9…2.6 m/s**. Writes seed to UserDefaults then recomputes.
- **`linkAppleHealthWalkingSpeed()`** — requests **read** authorization for **`HKQuantityTypeIdentifier.walkingSpeed`**, queries roughly the last **120 days** (up to **200** samples), takes **median** m/s (samples outside **0.9…2.7 m/s** dropped), caches internally, recomputes.
- **`ingestObservedWalk(distanceMeters:durationSeconds:)`** — updates learned pace with an **EMA** (`alpha = 0.38`) when duration ≥ **120 s** and distance ≥ **300 m**. Pace fed into the EMA is clamped to the same global band as `effectiveWalkingSpeedMetersPerSecond`.
- **`refreshAuthorizedHealthKitData()`** — re-queries HealthKit when read access is already **`.sharingAuthorized`** (e.g. app relaunch).

**Blending** when recomputing the effective speed:

- Both learned (UserDefaults) and Health median present: **52% learned + 48% Health**, then clamp.
- Only one source: use it (still clamped).
- Neither: default generator speed.

**Persistence:**

- Learned EMA: UserDefaults key **`randomwalker.walkingPace.learnedEMA`**.
- Health median is kept in memory (`cachedHealthMedianPace`) until the next successful query.
- Simulator seeding flag: **`randomwalker.debug.simulatorWalkingSpeedSeeded`** (see below) — avoids re-inserting the default fixture batch on every launch.

### HealthKit app configuration

- **Entitlements**: `RandomWalker/RandomWalker.entitlements` — `com.apple.developer.healthkit` = true. **`project.yml`** duplicates this under `targets.RandomWalker.entitlements.properties` so **`xcodegen generate`** merges the capability into the plist (avoids an empty entitlements file after regeneration).
- **Info.plist**: **`NSHealthShareUsageDescription`** (read walking speed for planning); **`NSHealthUpdateUsageDescription`** — on **simulator**, the app may save sample walking-speed fixtures for testing; on **device**, it does not write Health data (production use is read-only via **`linkAppleHealthWalkingSpeed`**).

### Wiring (iOS app)

- **`ContentView`** — owns `@StateObject WalkingPaceService`, passes it into **`PlanWalkView`**, calls **`bootstrapFromHistoryIfNeeded`**, **`refreshAuthorizedHealthKitData()`**, and (on **simulator only**) **`seedSimulatorWalkingSpeedFixtures()`** from **`.task`**. **`session.onWalkSavedObservedPace`** is set in **`.onAppear`** to **`ingestObservedWalk`**.
- **`PlanWalkView`** — **Your walking pace** card (`paceDetail`, optional **Use Apple Health** / Settings if denied). On **simulator**, an extra **Simulator: sample Health data** section documents fixtures and exposes **Write sample walking speeds again** (`seedSimulatorWalkingSpeedFixtures(force: true)`). Passes **`effectiveWalkingSpeedMetersPerSecond`** into **`NewRoutePlanningSheet`** and **`planLoop`**.
- **`WalkingPaceService`** (simulator builds only, `#if targetEnvironment(simulator)`) — **`seedSimulatorWalkingSpeedFixtures(force:)`** requests read **and** write for **`HKQuantityTypeIdentifier.walkingSpeed`**, saves ~10 `HKQuantitySample`s (~**1.38–1.68 m/s**) on staggered past **`Date`s**, then refreshes the Health median. The non-forced path no-ops after the first successful seed (see **`randomwalker.debug.simulatorWalkingSpeedSeeded`** above) but still refreshes if already authorized.
- **`WalkSessionViewModel`** — after **`persistWalk`** saves a `WalkRecord`, invokes **`onWalkSavedObservedPace?(distanceMeters, elapsedSeconds)`** using the same distance and wall-clock duration stored on the row (trace/watch path when available).

## Testing (manual)

1. **Build and run**: [build-and-test.md](build-and-test.md) — e.g. `./scripts/run_ios_watch_sim_pair.py` or Xcode with **RandomWalker** on an iPhone simulator/device.
2. **Simulator + Health**: On first launch the app asks for Health access (read/write for **Walking Speed**) and, if you allow, inserts sample data automatically (once per install unless you reset the app or UserDefaults). The **Plan** tab’s pace card has **Write sample walking speeds again** to append another batch. **Use Apple Health walking speed** remains the read-focused path once authorization is no longer “not determined.” Details: keys and sample ranges under **Persistence** and **Wiring** above.
3. **Device**: Tap **Use Apple Health walking speed** on the Plan tab when shown; confirm Health **Sharing** → **Random Walker** allows **Walking Speed** (read). The app does not write Health data on device builds.
4. **Learning**: Complete at least one **Start** → save path with sufficient duration/distance; reopen the app and confirm **`paceDetail`** mentions saved walks or a blended line. Plan a **time** target and note loop length vs before (faster learned pace → longer loop for the same minutes).
5. **New route sheet**: Toggle **Walking time** / **Route distance** and confirm the paired value updates consistently with the pace shown in the card.

## Related

- [architecture.md](architecture.md) — planning flow and `planLoop`.
- [history-and-persistence.md](history-and-persistence.md) — what a `WalkRecord` stores (feeds bootstrap and EMA).
- [map-and-location.md](map-and-location.md) — where planning is anchored.
