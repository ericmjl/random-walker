# Developer documentation

Start here. These pages capture **product intent** and **technical decisions** so future changes stay aligned with why the app exists and how it is built.

## Contents

| Document | What it covers |
|----------|----------------|
| [product-intent.md](product-intent.md) | Goals, platform choices, and what “success” means for the product. |
| [repository-layout.md](repository-layout.md) | Directory roles, XcodeGen, iOS vs watch schemes, embedding notes. |
| [architecture.md](architecture.md) | Layers, planning flow, watch payloads, and how pieces connect. |
| [history-and-persistence.md](history-and-persistence.md) | **When** `WalkRecord` rows are written, trace vs planned polyline, field semantics. |
| [map-and-location.md](map-and-location.md) | MapKit UI (camera, zoom), Core Location permissions, and planning coordinates. |
| [walking-pace.md](walking-pace.md) | Personalized walking speed (Health, saved walks), `planLoop` wiring, **simulator Health fixtures**, testing. |
| [in-app-navigation.md](in-app-navigation.md) | Turn-by-turn after **Start**, step progression, chase camera, completion → History. |
| [monetization.md](monetization.md) | Freemium / Pro unlock recommendation, pricing posture, and models to avoid. |
| [build-and-test.md](build-and-test.md) | Commands for generating the project, building, and running core tests. |
| [code-conventions.md](code-conventions.md) | Where to put logic, testing expectations, and documentation style in source. |

## Audience

Human developers and coding agents working in this repository.

## Conventions

- All files under `docs/` use **kebab-case** names (this directory only contains `*.md` in that form).
- The repo overview at the root is [README.md](../README.md) (the **only** all-caps markdown filename; standard for repository hosts).

## Keeping docs current

When you change **behavior** (planning, navigation, history, map, location, watch, schemes), update the **relevant** page(s) above in the same change-set. If you add a new topic that does not fit an existing page, add a new **kebab-case** file and link it in **this** table. [AGENTS.md](../AGENTS.md) repeats this for coding agents.
