# Random Walker

iOS (and optional watchOS) app for **about–one-hour random walking loops** that **return to your start**, built with **MapKit**, **SwiftData**, and **WatchConnectivity**.

**Developer documentation:** [docs/index.md](docs/index.md) (product intent, architecture, history rules, navigation, map behavior, [personalized walking pace](docs/walking-pace.md), build commands).

**History:** Completed walks (after **Start** through the last step) are saved to SwiftData; planning alone does not create a history entry. Details: [docs/history-and-persistence.md](docs/history-and-persistence.md).

## Quick start

```bash
xcodegen generate
open RandomWalker.xcodeproj
```

Run the **RandomWalker** scheme on an iPhone Simulator or device. **Simulator:** after allowing Health access, walking-speed fixtures load automatically for pace testing ([walking-pace.md](docs/walking-pace.md)). Core logic tests: `swift test`.
