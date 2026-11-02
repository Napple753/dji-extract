import AVFoundation
import DJIExtractCore
import Foundation
import Testing
@testable import DJIExtractKit

@Suite(.enabled(if: SampleFootage.isAvailable, "sample footage not present"), .serialized)
struct ClipExporterTests {
    let manila = TimeZone(identifier: "Asia/Manila")!

    func clock(for asset: AVAsset) async throws -> CaptureClock {
        let metadata = try await VideoMetadataReader.read(asset)
        let start = try CaptureTimeCalculator().recordingStart(creationTime: metadata.creationTime, duration: metadata.duration)
        return CaptureClock(recordingStart: start, adjustment: .init(timeZone: manila))
    }

    @Test(arguments: ClipExportMode.allCases)
    func exportsRangeWithCreationDateOfActualStart(mode: ClipExportMode) async throws {
        let workspace = try ExportWorkspace.create()
        defer { workspace.remove() }
        let asset = AVURLAsset(url: SampleFootage.main)
        let clock = try await clock(for: asset)
        let range = CMTimeRange(start: CMTime(seconds: 10.3, preferredTimescale: 600), end: CMTime(seconds: 12, preferredTimescale: 600))

        let clip = try await ClipExporter.export(from: asset, range: range, mode: mode, clock: clock, workspace: workspace)

        #expect(clip.actualStart <= 10.3)
        if mode == .accurate { #expect(10.3 - clip.actualStart < 1.0 / 23.976) }
        #expect(clip.timestamp == clock.timestamp(at: clip.actualStart))

        let exported = AVURLAsset(url: clip.url)
        let duration = try await exported.load(.duration).seconds
        #expect(abs(duration - (12 - clip.actualStart)) < 0.1)
        let items = try await exported.load(.metadata)
        let creation = try await AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .quickTimeMetadataCreationDate)
            .first?.load(.stringValue)
        #expect(creation == clip.timestamp.quickTimeCreationDate)

        // The exported first frame must be the source frame at `actualStart`, and differ from
        // its neighbours, otherwise the creation date would be off by a frame or more.
        let size = CGSize(width: 192, height: 108)
        let first = try await FrameExporter.frame(of: exported, at: .zero, maximumSize: size).image
        let fd = 1001.0 / 24000.0
        func source(_ seconds: Double) async throws -> CGImage {
            try await FrameExporter.frame(of: asset, at: CMTime(seconds: seconds, preferredTimescale: 240000), maximumSize: size).image
        }
        let same = try difference(first, await source(clip.actualStart + fd / 2))
        let next = try difference(first, await source(clip.actualStart + fd * 1.5))
        #expect(same < next, "same \(same), next \(next)")
    }

    /// Mean absolute difference of two images in 8-bit grayscale.
    func difference(_ a: CGImage, _ b: CGImage) throws -> Double {
        func pixels(_ image: CGImage) throws -> [UInt8] {
            let (w, h) = (96, 54)
            var buffer = [UInt8](repeating: 0, count: w * h)
            let context = try #require(CGContext(
                data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return buffer
        }
        let (pa, pb) = (try pixels(a), try pixels(b))
        return zip(pa, pb).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(pa.count)
    }

    @Test func keyframeLookupNeverMovesForward() async throws {
        let asset = AVURLAsset(url: SampleFootage.main)
        for seconds in [0.0, 5.0, 10.3, 20.7] {
            let time = CMTime(seconds: seconds, preferredTimescale: 24000)
            let keyframe = try await ClipExporter.keyframe(atOrBefore: time, in: asset)
            #expect(keyframe <= time)
        }
    }

    @Test func snapToFrameRoundsDown() {
        let frame = CMTime(value: 1001, timescale: 24000)
        let snapped = ClipExporter.snapToFrame(CMTime(seconds: 0.35, preferredTimescale: 600), frameDuration: frame)
        #expect(snapped == CMTime(value: 8 * 1001, timescale: 24000))
    }
}
