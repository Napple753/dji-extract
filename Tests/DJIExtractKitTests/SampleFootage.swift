import Foundation

/// The sample recording kept at the repository root (not committed; see docs/findings.md).
enum SampleFootage {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let main = root.appending(path: "DJI_20261102220407_0073_D.MP4")
    static let preview = root.appending(path: "DJI_20261102220407_0073_D.LRF")

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: main.path) && FileManager.default.fileExists(atPath: preview.path)
    }

    /// AVFoundation does not open `.LRF`, so tests use a copy with an `.mp4` extension,
    /// the same way the app does.
    static func previewCopy() throws -> URL {
        let copy = FileManager.default.temporaryDirectory.appending(path: "sample-preview-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: preview, to: copy)
        return copy
    }
}
