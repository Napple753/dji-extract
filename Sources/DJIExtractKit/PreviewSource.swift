import AVFoundation
import DJIExtractCore
import Foundation

/// What the editor plays: a local copy of the LRF when usable, otherwise the main file.
public struct PreviewSource: Sendable {
    public enum Kind: Sendable { case localPreview, mainFile }

    public let kind: Kind
    /// URL to play. For `.localPreview` this is a temporary `.mp4` copy owned by the caller.
    public let url: URL
    /// Converts between player positions and main-file positions. `nil` for `.mainFile`.
    public let mapping: PreviewTimeMapping?

    /// Main-file position (seconds) for a player position.
    public func mainPosition(forPlayer position: TimeInterval) -> TimeInterval {
        mapping?.mainPosition(forPreview: position) ?? position
    }

    public func playerPosition(forMain position: TimeInterval) -> TimeInterval {
        mapping?.previewPosition(forMain: position) ?? position
    }

    /// Removes the temporary LRF copy, if any.
    public func discard() {
        if kind == .localPreview { try? FileManager.default.removeItem(at: url) }
    }

    /// Copies the video's LRF into the temporary area as `.mp4` and checks it against the
    /// main file. Falls back to the main file when there is no usable LRF.
    public static func prepare(for video: CameraVideo, mainMetadata: VideoMetadata, in library: CameraLibrary) async -> PreviewSource {
        let fallback = PreviewSource(kind: .mainFile, url: library.url(for: video.main), mapping: nil)
        guard let preview = video.preview else { return fallback }
        let copy = FileManager.default.temporaryDirectory.appending(path: "Preview-\(UUID().uuidString).mp4")
        do {
            try FileManager.default.copyItem(at: library.url(for: preview), to: copy)
            let metadata = try await VideoMetadataReader.read(copy)
            guard let mapping = PreviewTimeMapping(previewDuration: metadata.duration, mainDuration: mainMetadata.duration) else {
                try? FileManager.default.removeItem(at: copy)
                return fallback
            }
            return PreviewSource(kind: .localPreview, url: copy, mapping: mapping)
        } catch {
            try? FileManager.default.removeItem(at: copy)
            return fallback
        }
    }
}
