import Foundation

/// Appends events as JSON Lines to a rotating file. Thread-safe via a serial queue.
final class FileSink: LogSink, @unchecked Sendable {
    private let directory: URL
    private let fileName: String
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "com.minicapsule.filesink")
    private let encoder: JSONEncoder

    init(directory: URL? = nil, fileName: String = "session.jsonl", maxBytes: Int = 5_000_000) {
        self.directory = directory ?? FileSink.defaultDirectory()
        self.fileName = fileName
        self.maxBytes = maxBytes
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Mini Capsule/logs", isDirectory: true)
    }

    var fileURL: URL { directory.appendingPathComponent(fileName) }

    func write(_ event: LogEvent) {
        queue.sync {
            rotateIfNeeded()
            guard var data = try? encoder.encode(event) else { return }
            data.append(0x0A) // '\n'
            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > maxBytes else { return }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let base = (fileName as NSString).deletingPathExtension
        let rotated = directory.appendingPathComponent("\(base)-\(stamp).jsonl")
        try? FileManager.default.moveItem(at: fileURL, to: rotated)
    }
}
