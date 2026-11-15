import AVFoundation
import DJIExtractCore
import Foundation

/// Reads the camera model and per-frame exposure from the DJI `djmd` timed metadata track.
///
/// Best effort: anything missing or unreadable is left out instead of failing the export.
public enum CameraMetadataReader {
    /// Camera info for the file, with the exposure of the frame at `time` when given.
    public static func read(_ asset: AVAsset, frameAt time: CMTime? = nil) async -> CameraInfo {
        guard let url = (asset as? AVURLAsset)?.url else { return .unknown }
        return await Task.detached(priority: .userInitiated) { read(url, frameAt: time?.seconds) }.value
    }

    static func read(_ url: URL, frameAt seconds: Double?) -> CameraInfo {
        guard let track = try? MP4TimedMetadataTrack(url: url, format: "djmd") else { return .unknown }
        var info = CameraInfo.unknown
        if let header = try? track.sample(index: 0) {
            info.model = DJIMetadataParser.model(fromHeader: header)
        }
        if let seconds, let frame = try? track.sample(at: seconds) {
            info.exposure = DJIMetadataParser.exposure(fromFrame: frame)
        }
        return info
    }
}
