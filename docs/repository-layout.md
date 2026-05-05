# Repository layout

## Top-level paths

| Path | Role |
|------|------|
| `project.yml` | XcodeGen source of truth; run `xcodegen generate` after edits. |
| `RandomWalker.xcodeproj` | Generated; do not hand-edit for structural changes. |
| `RandomWalkerCore/` | Shared **Swift Package** (`Package.swift`) linked from Xcode for iPhone + Watch: geometry, blueprint, codec, watch payload models. |
| `RandomWalker/` | iOS app (**embeds** `RandomWalkerWatch` under `RandomWalker.app/Watch/` so WatchConnectivity sees an installed companion). |
| `RandomWalkerWatch/` | watchOS app (built through the embedding relationship; **`RandomWalkerWatch` scheme** remains for watch-only debugging). |
| `RandomWalkerCoreTests/` | XCTest targets exercised via root `Package.swift` (`swift test` on macOS). |
| `docs/` | Developer documentation ([index.md](index.md)). |

## iOS vs watch schemes

`project.yml` embeds **`RandomWalkerWatch`** in **`RandomWalker`** (`embed: true`). The **`RandomWalker`** scheme is the usual CLI/dev entry: one `xcodebuild` yields `RandomWalker.app` including `Watch/RandomWalkerWatch.app`.

`RandomWalkerCore` is referenced from Xcode via the repo-root **`Package.swift`** SPM package (`packages.RandomWalkerCoreSPM` in `project.yml`), which keeps multi-SDK linking reliable next to an embedded Watch target.
