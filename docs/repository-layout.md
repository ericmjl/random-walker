# Repository layout

## Top-level paths

| Path | Role |
|------|------|
| `project.yml` | XcodeGen source of truth; run `xcodegen generate` after edits. |
| `RandomWalker.xcodeproj` | Generated; do not hand-edit for structural changes. |
| `RandomWalkerCore/` | Shared framework (iOS + watchOS): geometry, random loop blueprint, polyline codec, watch payload models. |
| `RandomWalker/` | iOS app: SwiftUI shell, SwiftData models, MapKit routing, location, connectivity. |
| `RandomWalkerWatch/` | watchOS app: receives context/hints (scheme is separate from the phone target). |
| `RandomWalkerCoreTests/` | XCTest targets exercised via root `Package.swift` (`swift test` on macOS). |
| `docs/` | Developer documentation ([index.md](index.md)). |

## iOS vs watch schemes

The **Watch app is not embedded** in the iOS target so **Simulator/CLI builds** do not require a matching watchOS runtime.

For an App Store-style **single bundle** with an embedded watch app, restore in `project.yml` a dependency on `RandomWalkerWatch` with `embed: true` and add that target back to the main scheme’s build list.
