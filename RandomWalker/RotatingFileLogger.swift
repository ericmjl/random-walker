import Foundation

/// Append-only UTF-8 log with size-based rotation under Application Support. Safe from any thread.
///
/// Files: ``RandomWalker/Logs/diagnostics.log`` (active), then ``diagnostics.1.log`` … ``diagnostics.5.log``.
/// When the active file would exceed ``maxFileBytes``, it becomes ``.1.log`` and older indices shift up until ``.5.log`` is dropped.
final class RotatingFileLogger: @unchecked Sendable {
    static let shared = RotatingFileLogger()

    private let maxFileBytes: UInt64 = 512 * 1024
    private let maxRotatedIndex: Int = 5
    private let queue = DispatchQueue(label: "dev.ericmjl.randomwalker.RotatingFileLogger")
    private let directory: URL
    private let baseName = "diagnostics"

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = appSupport.appendingPathComponent("RandomWalker/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Human-readable log folder path for support / docs (e.g. Finder → Library → Application Support).
    var directoryPath: String {
        directory.path
    }

    func log(_ category: String, _ message: String) {
        let stamp = iso8601.string(from: Date())
        let line = "[\(stamp)] [\(category)] \(message)\n"
        let payload = Data(line.utf8)
        queue.async { self.appendSync(payload) }
    }

    private func activeFileURL() -> URL {
        directory.appendingPathComponent("\(baseName).log", isDirectory: false)
    }

    private func appendSync(_ data: Data) {
        let url = activeFileURL()
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path),
           let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64,
           size + UInt64(data.count) > maxFileBytes {
            rotateSync()
        }
        if fm.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
            } catch {}
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func rotateSync() {
        let fm = FileManager.default
        let oldest = directory.appendingPathComponent("\(baseName).\(maxRotatedIndex).log")
        try? fm.removeItem(at: oldest)
        for index in (1 ..< maxRotatedIndex).reversed() {
            let from = directory.appendingPathComponent("\(baseName).\(index).log")
            let to = directory.appendingPathComponent("\(baseName).\(index + 1).log")
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.removeItem(at: to)
            try? fm.moveItem(at: from, to: to)
        }
        let active = activeFileURL()
        let firstRotated = directory.appendingPathComponent("\(baseName).1.log")
        guard fm.fileExists(atPath: active.path) else { return }
        try? fm.removeItem(at: firstRotated)
        try? fm.moveItem(at: active, to: firstRotated)
    }
}
