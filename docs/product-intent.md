# Product intent

## Goals

- **One-tap hour loops**: The user gets a walking route of roughly **one hour** that **returns to the start**, with **minimal choices** (no manual waypoint picking).
- **Variety**: Stops and geometry come from a **seeded random blueprint** (`RandomWalkGenerator`); MapKit supplies real **walking directions** stitched into a closed loop.
- **Review past walks**: History rows are created only after **Start**, when the user **finishes** turn-by-turn guidance, **returns near their start** after walking out, or **saves on stop**—not for every planned route. See [history-and-persistence.md](history-and-persistence.md).

## Platform principles

- **Trust Apple platforms only**: **MapKit** / `MKDirections`, **SwiftData** for history, **WatchConnectivity** for the watch app. **No Google** APIs.
- **Phone optional for navigation**: The watch can show **turn-style hints** from a payload derived on the phone; the long-term goal is that the user can follow cues on the watch without holding the phone.

For folder and module structure, see [repository-layout.md](repository-layout.md). For end-to-end flow, see [architecture.md](architecture.md).
