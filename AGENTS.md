# Agent instructions (Random Walker)

## Documentation

- **Entry point**: [docs/index.md](docs/index.md) — product intent, architecture, **history / SwiftData**, map/location, navigation, build commands, and code conventions.
- **Filenames**: All markdown under `docs/` uses **kebab-case** (e.g. `product-intent.md`, `history-and-persistence.md`). Do not add `docs/SOME_NAME.md` or `docs/SomeName.md`; use hyphenated lowercase names only.
- **Repo overview**: [`README.md`](README.md) at the repository root is the **only** all-caps doc name (common Git/hosting convention).

When adding new developer-facing pages, update `docs/index.md` so the table of contents stays accurate.

### Keeping docs in sync (required)

After changing **user-visible or data behavior**, update the relevant docs in the **same change-set**:

- Planning / retries / `planHourLoop` → [docs/architecture.md](docs/architecture.md)
- History, `WalkRecord`, when rows are created → [docs/history-and-persistence.md](docs/history-and-persistence.md)
- **Start** / steps / GPS trace / completion → [docs/in-app-navigation.md](docs/in-app-navigation.md)
- Map camera, zoom, location permissions → [docs/map-and-location.md](docs/map-and-location.md)
- Goals and principles → [docs/product-intent.md](docs/product-intent.md)
- Repo paths / schemes → [docs/repository-layout.md](docs/repository-layout.md)
- Top-level README blurb → [README.md](README.md) when the product summary changes

If no page fits, add a new **kebab-case** file under `docs/` and link it from `docs/index.md`.

## Code

- Follow [docs/code-conventions.md](docs/code-conventions.md) for where to place logic (Core vs app) and docstring style.
- After editing `project.yml` or **adding new source files** under an XcodeGen-managed folder, run `xcodegen generate` before claiming the Xcode project is current.
