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

## Physical iPhone (USB / trusted developer device)

CLI install uses **automatic signing**, your logged-in Xcode Apple ID team, CoreDevice tooling, and a known derived-data path:

```bash
# One connected iPhone/iPodtouch; if multiple, set RANDOM_WALKER_IOS_DEVICE_UDID first.
scripts/print_ios_physical_device_destination.py --list
scripts/install_randomwalker_ios_device.py
scripts/install_randomwalker_ios_device.py --skip-xcodegen   # Xcode project already current
scripts/install_randomwalker_ios_device.py --skip-build --no-launch --skip-xcodegen   # reinstall last build
```

- **Provisioning**: Xcode must already have downloaded a provisioning profile for `dev.ericmjl.randomwalker` (open the project once in Xcode or rely on `-allowProvisioningUpdates` during the scripted build).
- **Launch**: Automatic launch after install may fail while the phone is **locked**. Unlock first, open the icon, or run the `devicectl process launch …` line the script prints.
- **Apple Watch companion**: Not covered here; simulator pairing still uses `./scripts/run_ios_watch_sim_pair.py`.

Details and prerequisites for automation agents live in **[AGENTS.md](../AGENTS.md)** (physical iPhone subsection).

For where code should live and how to test it, see [code-conventions.md](code-conventions.md).
