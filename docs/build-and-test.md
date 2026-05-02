# Build and test

```bash
xcodegen generate
xcodebuild -project RandomWalker.xcodeproj -scheme RandomWalker -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' build
swift test   # RandomWalkerCore tests via SwiftPM on macOS
```

Adjust the `-destination` for your installed simulator runtime or use a connected device.

For where code should live and how to test it, see [code-conventions.md](code-conventions.md).
