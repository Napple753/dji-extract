import AVFoundation
import DJIExtractCore
import Foundation

/// What the editor plays: the LRF when usable, otherwise the main file.
///
/// Both are read straight from the camera. The LRF's data rate is low enough for USB, so it is
/// not copied first (copying a long recording's LRF took too long before playback could start).
public struct PreviewSource: @unchecked Sendable {
    public enum Kind: Sendable { case lrf, mainFile }

    public let kind: Kind
    /// Asset to play.
    public let asset: AVURLAsset
    /// Converts between player positions and main-file positions. `nil` for `.mainFile`.
    public let mapping: PreviewTimeMapping?

    /// Main-file position (seconds) for a player position.
    public func mainPosition(forPlayer position: TimeInterval) -> TimeInterval {
        mapping?.mainPosition(forPreview: position) ?? position
    }

    public func playerPosition(forMain position: TimeInterval) -> TimeInterval {
        mapping?.previewPosition(forMain: position) ?? position
    }

    /// Opens the video's LRF and checks it against the main file. Falls back to the main file
    /// when there is no usable LRF.
    public static func prepare(for video: CameraVideo, mainMetadata: VideoMetadata, in library: CameraLibrary) async -> PreviewSource {
        let fallback = PreviewSource(kind: .mainFile, asset: library.asset(for: video.main), mapping: nil)
        guard let preview = video.preview else { return fallback }
        let asset = library.asset(for: preview)
        guard let metadata = try? await VideoMetadataReader.read(asset),
              let mapping = PreviewTimeMapping(previewDuration: metadata.duration, mainDuration: mainMetadata.duration)
        else { return fallback }
        return PreviewSource(kind: .lrf, asset: asset, mapping: mapping)
    }
}
