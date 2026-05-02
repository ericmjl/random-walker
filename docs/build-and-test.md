# Build and test

```bash
xcodegen generate
xcodebuild -project RandomWalker.xcodeproj -scheme RandomWalker \
  -destination "$(scripts/print_ios_sim_destination.py)" build
swift test   # RandomWalkerCore tests via SwiftPM on macOS
```

`scripts/print_ios_sim_destination.py` picks the **newest installed iOS Simulator runtime that actually has an iPhone device** and prints an xcodebuild `-destination` (by device id). That stays correct when you add iOS 26 simulators and avoids hard-coding `OS=18.x`.

For a physical device or a specific simulator, pass your own `-destination` instead. In **Xcode**, the scheme does not pin a simulator OS: use the run destination menu and choose an iPhone on the highest iOS version you care about (install extra runtimes under Xcode → Settings → Platforms).

## Phone + Watch simulators in one step

Xcode does not run two schemes with one ⌘R. From the repo root, use:

```bash
./scripts/run_ios_watch_sim_pair.py
```

This picks a paired iPhone + Watch (defaults to the **iPhone 17** pair if present), boots both, runs `xcodegen generate`, builds **RandomWalker** and **RandomWalkerWatch**, installs them, and launches both apps. Override UDIDs with `RANDOM_WALKER_PHONE_UDID` and `RANDOM_WALKER_WATCH_UDID`, or run `./scripts/run_ios_watch_sim_pair.py --list-pairs` to see pairs.

On the **iOS Simulator**, accept the Health permission when prompted if you want **walking-speed** sample data for [`WalkingPaceService`](walking-pace.md) (see **Simulator + Health** in that page).

For where code should live and how to test it, see [code-conventions.md](code-conventions.md).
