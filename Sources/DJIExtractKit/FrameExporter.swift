import AVFoundation
import CoreGraphics
import DJIExtractCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A decoded frame and its exact position in the source.
public struct VideoFrame: @unchecked Sendable {
    public let image: CGImage
    /// Presentation time of the decoded frame (may be earlier than the requested time).
    public let time: CMTime
}

/// An exported still image ready to be added to Photos.
public struct ExportedPhoto: Sendable {
    public let url: URL
    public let timestamp: CaptureTimestamp
    /// Position of the frame in the source, in seconds.
    public let position: TimeInterval
}

public enum FrameExporter {
    /// Decodes the exact frame displayed at `time` (zero tolerance), rotated upright.
    public static func frame(of asset: AVAsset, at time: CMTime, maximumSize: CGSize? = nil) async throws -> VideoFrame {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true
        // 10-bit HDR to SDR conversion is an open question in the spec; tone map to SDR for now.
        generator.dynamicRangePolicy = .forceSDR
        if let maximumSize { generator.maximumSize = maximumSize }
        let (image, actualTime) = try await generator.image(at: time)
        return VideoFrame(image: image, time: actualTime)
    }

    /// Exports the frame at `time` as a full-resolution HEIC with capture date metadata.
    public static func exportPhoto(
        from asset: AVAsset,
        at time: CMTime,
        clock: CaptureClock,
        to url: URL,
        contentIdentifier: String? = nil
    ) async throws -> ExportedPhoto {
        let frame = try await frame(of: asset, at: time)
        let position = frame.time.seconds
        let timestamp = clock.timestamp(at: position)
        try writeHEIC(frame.image, timestamp: timestamp, contentIdentifier: contentIdentifier, to: url)
        return ExportedPhoto(url: url, timestamp: timestamp, position: position)
    }

    /// Writes `image` as HEIC with EXIF/TIFF dates, camera identity and, for Live Photos,
    /// the Apple MakerNote content identifier (key 17).
    public static func writeHEIC(
        _ image: CGImage,
        timestamp: CaptureTimestamp,
        contentIdentifier: String? = nil,
        to url: URL
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw ExportError.cannotCreateDestination
        }
        CGImageDestinationAddImage(destination, image, properties(timestamp: timestamp, contentIdentifier: contentIdentifier) as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.exportFailed("HEIC encoding failed")
        }
    }

    static func properties(timestamp: CaptureTimestamp, contentIdentifier: String?) -> [CFString: Any] {
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: timestamp.exifDateTime,
                kCGImagePropertyExifDateTimeDigitized: timestamp.exifDateTime,
                kCGImagePropertyExifSubsecTimeOriginal: timestamp.exifSubSecond,
                kCGImagePropertyExifSubsecTimeDigitized: timestamp.exifSubSecond,
                kCGImagePropertyExifOffsetTimeOriginal: timestamp.exifOffset,
                kCGImagePropertyExifOffsetTimeDigitized: timestamp.exifOffset,
                kCGImagePropertyExifOffsetTime: timestamp.exifOffset,
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: CameraIdentity.make,
                kCGImagePropertyTIFFModel: CameraIdentity.model,
                kCGImagePropertyTIFFDateTime: timestamp.exifDateTime,
            ],
        ]
        if let contentIdentifier {
            properties[kCGImagePropertyMakerAppleDictionary] = ["17": contentIdentifier]
        }
        return properties
    }
}
