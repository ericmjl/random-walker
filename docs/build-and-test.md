# Build and test

```bash
xcodegen generate
xcodebuild -project RandomWalker.xcodeproj -scheme RandomWalker \
  -destination "$(scripts/print_ios_sim_destination.py)" build
swift test   # RandomWalkerCore tests via SwiftPM on macOS
```

`scripts/print_ios_sim_destination.py` picks the **newest installed iOS Simulator runtime that actually has an iPhone device** and prints an xcodebuild `-destination` (by device id). That stays correct when you add iOS 26 simulators and avoids hard-coding `OS=18.x`.

For a physical device or a specific simulator, pass your own `-destination` instead. In **Xcode**, the scheme does not pin a simulator OS: use the run destination menu and choose an iPhone on the highest iOS version you care about (install extra runtimes under Xcode → Settings → Platforms).

For where code should live and how to test it, see [code-conventions.md](code-conventions.md).
