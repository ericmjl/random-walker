# Agent instructions (Random Walker)

## Documentation

- **Entry point**: [docs/index.md](docs/index.md) — product intent, architecture, map/location behavior, build commands, and code conventions.
- **Filenames**: All markdown under `docs/` uses **kebab-case** (e.g. `product-intent.md`, `build-and-test.md`). Do not add `docs/SOME_NAME.md` or `docs/SomeName.md`; use hyphenated lowercase names only.
- **Repo overview**: [`README.md`](README.md) at the repository root is the **only** all-caps doc name (common Git/hosting convention).

When adding new developer-facing pages, update `docs/index.md` so the table of contents stays accurate.

## Code

- Follow [docs/code-conventions.md](docs/code-conventions.md) for where to place logic (Core vs app) and docstring style.
- After editing `project.yml` or **adding new source files** under an XcodeGen-managed folder, run `xcodegen generate` before claiming the Xcode project is current.
