import AVFoundation
import DJIExtractCore
import Foundation
import ImageIO
import Testing
@testable import DJIExtractKit

@Suite(.enabled(if: SampleFootage.isAvailable, "sample footage not present"), .serialized)
struct LivePhotoExporterTests {
    let manila = TimeZone(identifier: "Asia/Manila")!

    @Test(arguments: [(10.0, 3.0, 1.5), (0.5, 2.0, 0.5)])
    func exportsPairedPhotoAndVideo(still: Double, expectedDuration: Double, expectedStillOffset: Double) async throws {
        let workspace = try ExportWorkspace.create()
        defer { workspace.remove() }
        let asset = AVURLAsset(url: SampleFootage.main)
        let metadata = try await VideoMetadataReader.read(asset)
        let start = try CaptureTimeCalculator().recordingStart(creationTime: metadata.creationTime, duration: metadata.duration)
        let clock = CaptureClock(recordingStart: start, adjustment: .init(timeZone: manila))

        let live = try await LivePhotoExporter.export(
            from: asset, stillTime: CMTime(seconds: still, preferredTimescale: 600), clock: clock, workspace: workspace)

        // Photo carries the identifier and the still's capture time.
        let source = try #require(CGImageSourceCreateWithURL(live.photoURL as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
        #expect(makerApple?["17"] as? String == live.contentIdentifier)
        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == live.timestamp.exifDateTime)

        // Video carries the same identifier, the creation date and a still-image-time marker.
        let movie = AVURLAsset(url: live.videoURL)
        let duration = try await movie.load(.duration).seconds
        #expect(abs(duration - expectedDuration) < 0.1)
        let items = try await movie.load(.metadata)
        let identifier = try await AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: AVMetadataIdentifier("mdta/com.apple.quicktime.content.identifier"))
            .first?.load(.stringValue)
        #expect(identifier == live.contentIdentifier)
        let creation = try await AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .quickTimeMetadataCreationDate)
            .first?.load(.stringValue)
        #expect(creation == live.timestamp.quickTimeCreationDate)

        let metadataTrack = try #require(try await movie.loadTracks(withMediaType: .metadata).first)
        let reader = try AVAssetReader(asset: movie)
        let output = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
        reader.add(output)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
        reader.startReading()
        let group = try #require(adaptor.nextTimedMetadataGroup())
        #expect(group.items.first?.identifier == LivePhotoExporter.stillImageTimeIdentifier)
        #expect(abs(group.timeRange.start.seconds - expectedStillOffset) < 0.05)

        let videoTrack = try #require(try await movie.loadTracks(withMediaType: .video).first)
        #expect(try await videoTrack.load(.naturalSize) == CGSize(width: 1920, height: 1080))
        #expect(try await movie.loadTracks(withMediaType: .audio).count == 1)
    }
}
