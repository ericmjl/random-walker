# Developer documentation

Start here. These pages capture **product intent** and **technical decisions** so changes stay aligned with why the app exists and how it is built.

## Contents

| Document | What it covers |
|----------|----------------|
| [product-intent.md](product-intent.md) | Goals, platform choices, and what “success” means for the product. |
| [repository-layout.md](repository-layout.md) | Directory roles, XcodeGen, iOS vs watch schemes, embedding notes. |
| [architecture.md](architecture.md) | Layers, main flows, and how routing, session, persistence, and watch fit together. |
| [map-and-location.md](map-and-location.md) | MapKit UI (camera, zoom), Core Location permissions, and planning coordinates. |
| [in-app-navigation.md](in-app-navigation.md) | Turn-by-turn style guidance after **Start**, step progression, and chase camera. |
| [build-and-test.md](build-and-test.md) | Commands for generating the project, building, and running core tests. |
| [code-conventions.md](code-conventions.md) | Where to put logic, testing expectations, and documentation style in code. |

## Audience

Human developers and coding agents working in this repository.

## Conventions

- All files under `docs/` use **kebab-case** names (this directory only contains `*.md` in that form).
- The repo overview at the root is [README.md](../README.md) (the **only** all-caps markdown filename; standard for repository hosts).
