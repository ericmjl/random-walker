# Agent instructions (Random Walker)

## Documentation

- **Entry point**: [docs/index.md](docs/index.md) — product intent, architecture, **history / SwiftData**, map/location, navigation, build commands, and code conventions.
- **Filenames**: All markdown under `docs/` uses **kebab-case** (e.g. `product-intent.md`, `history-and-persistence.md`). Do not add `docs/SOME_NAME.md` or `docs/SomeName.md`; use hyphenated lowercase names only.
- **Repo overview**: [`README.md`](README.md) at the repository root is the **only** all-caps doc name (common Git/hosting convention).

When adding new developer-facing pages, update `docs/index.md` so the table of contents stays accurate.

### Keeping docs in sync (required)

After changing **user-visible or data behavior**, update the relevant docs in the **same change-set**:

- Planning / retries / `planHourLoop` → [docs/architecture.md](docs/architecture.md)
- History, `WalkRecord`, when rows are created, completion labels → [docs/history-and-persistence.md](docs/history-and-persistence.md)
- **Start** / **Stop** / return-to-start / replan / steps / GPS trace / completion → [docs/in-app-navigation.md](docs/in-app-navigation.md)
- Map camera, zoom, location permissions → [docs/map-and-location.md](docs/map-and-location.md)
- Goals and principles → [docs/product-intent.md](docs/product-intent.md)
- Repo paths / schemes → [docs/repository-layout.md](docs/repository-layout.md)
- Top-level README blurb → [README.md](README.md) when the product summary changes

If no page fits, add a new **kebab-case** file under `docs/` and link it from `docs/index.md`.

## Code

- Follow [docs/code-conventions.md](docs/code-conventions.md) for where to place logic (Core vs app) and docstring style.
- After editing `project.yml` or **adding new source files** under an XcodeGen-managed folder, run `xcodegen generate` before claiming the Xcode project is current.
- **Always run a build** after you change implementation code (Swift, shared Core, or anything that affects compilation). Do not treat the work as done until the iOS target builds successfully using the flow in [docs/build-and-test.md](docs/build-and-test.md). Run `swift test` when you touch `RandomWalkerCore` or its tests.

## iOS Simulator (CLI and agents)

- **Do not hard-code** a simulator OS in `xcodebuild` examples (e.g. `OS=18.6`): different machines install different runtimes.
- For local and agent builds, use the repo helper so the destination tracks the **newest usable iOS Simulator runtime on that Mac** (a runtime with at least one available iPhone):

  ```bash
  xcodebuild -project RandomWalker.xcodeproj -scheme RandomWalker \
    -destination "$(scripts/print_ios_sim_destination.py)" build
  ```

  See [docs/build-and-test.md](docs/build-and-test.md).

- **Why not `OS=latest`?** `xcodebuild`’s `OS=latest` follows the **device** SDK line; if the newest SDK runtime has no simulator devices yet, matching destinations disappear. The script uses `simctl` and picks a device on the highest installed simulator runtime that is actually runnable.
- **Xcode UI** does not store “always latest” in the shared scheme; pick an iPhone simulator with the newest iOS you have installed when running from the IDE.
