import AVFoundation
import CoreGraphics
import Foundation

/// The metadata of a camera file that the app needs for preview, export and timing.
public struct VideoMetadata: Sendable {
    /// Movie-level `creation_time`, interpreted as UTC. `nil` if absent.
    public var creationTime: Date?
    public var duration: TimeInterval
    public var nominalFrameRate: Float
    /// Duration of one frame (from the track's minimum frame duration).
    public var frameDuration: CMTime
    /// Encoded size, before the rotation in `preferredTransform`.
    public var naturalSize: CGSize
    public var preferredTransform: CGAffineTransform
    /// Bits per component of the video (8 or 10), if known.
    public var bitDepth: Int?
    /// Estimated total data rate in bytes per second (all tracks).
    public var estimatedBytesPerSecond: Double

    /// Size after applying `preferredTransform`.
    public var displaySize: CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
}

public enum VideoMetadataReader {
    public static func read(_ url: URL) async throws -> VideoMetadata {
        try await read(AVURLAsset(url: url))
    }

    public static func read(_ asset: AVAsset) async throws -> VideoMetadata {
        let (duration, creationItem, tracks) = try await asset.load(.duration, .creationDate, .tracks)
        let videoTrack = try await asset.mainVideoTrack()
        let (frameRate, minFrameDuration, naturalSize, transform, formats) = try await videoTrack.load(
            .nominalFrameRate, .minFrameDuration, .naturalSize, .preferredTransform, .formatDescriptions)

        var bytesPerSecond = 0.0
        for track in tracks {
            bytesPerSecond += Double(try await track.load(.estimatedDataRate)) / 8
        }

        return VideoMetadata(
            creationTime: try await creationItem?.load(.dateValue),
            duration: duration.seconds,
            nominalFrameRate: frameRate,
            frameDuration: minFrameDuration,
            naturalSize: naturalSize,
            preferredTransform: transform,
            bitDepth: formats.first.flatMap(bitDepth(of:)),
            estimatedBytesPerSecond: bytesPerSecond
        )
    }

    private static func bitDepth(of format: CMFormatDescription) -> Int? {
        let extensions = CMFormatDescriptionGetExtensions(format) as? [CFString: Any]
        if let depth = extensions?[kCMFormatDescriptionExtension_BitsPerComponent] as? Int {
            return depth
        }
        // HEVC Main10 profile signals 10-bit when BitsPerComponent is absent.
        if CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_HEVC,
           let atoms = extensions?[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [String: Any],
           let hvcC = atoms["hvcC"] as? Data, hvcC.count > 1 {
            // general_profile_idc lives in the low 5 bits of byte 1; 2 = Main10.
            return hvcC[hvcC.startIndex + 1] & 0x1F == 2 ? 10 : 8
        }
        // DJI LRF previews are 8-bit H.264.
        if CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264 {
            return 8
        }
        return nil
    }
}
