import AVFoundation
import DJIExtractCore
import Foundation
import ImageIO
import Testing
@testable import DJIExtractKit

@Suite(.enabled(if: SampleFootage.isAvailable, "sample footage not present"))
struct FrameExporterTests {
    let manila = TimeZone(identifier: "Asia/Manila")!

    @Test func exportsFullResolutionHEICWithCaptureDate() async throws {
        let workspace = try ExportWorkspace.create()
        defer { workspace.remove() }
        let asset = AVURLAsset(url: SampleFootage.main)
        let metadata = try await VideoMetadataReader.read(asset)
        let start = try CaptureTimeCalculator().recordingStart(
            creationTime: metadata.creationTime, duration: metadata.duration)
        let clock = CaptureClock(recordingStart: start, adjustment: .init(timeZone: manila))

        // Live Photo identifiers are UUIDs; ImageIO stores MakerApple key 17 as a 36-byte field.
        let contentIdentifier = UUID().uuidString
        // Frame 8 is where the on-screen UTC clock flips to 14:04:11 (22:04:11 local).
        let time = CMTime(value: 8 * 1001, timescale: 24000)
        let photo = try await FrameExporter.exportPhoto(
            from: asset, at: time, clock: clock, to: workspace.file(named: "frame.heic"), contentIdentifier: contentIdentifier)

        #expect(abs(photo.position - time.seconds) < 0.001)
        #expect(photo.timestamp.exifDateTime == "2026:11:02 22:04:11")

        let source = try #require(CGImageSourceCreateWithURL(photo.url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 3840)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 2160)
        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:11:02 22:04:11")
        #expect(exif[kCGImagePropertyExifSubsecTimeOriginal] as? String == photo.timestamp.exifSubSecond)
        #expect(exif[kCGImagePropertyExifOffsetTimeOriginal] as? String == "+08:00")
        let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFMake] as? String == "DJI")
        #expect(tiff[kCGImagePropertyTIFFModel] as? String == "Osmo Action 6")
        let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
        #expect(makerApple?["17"] as? String == contentIdentifier)
    }
}
