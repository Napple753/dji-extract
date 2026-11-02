import Foundation
import Testing
@testable import DJIExtractKit

@Suite(.enabled(if: SampleFootage.isAvailable, "sample footage not present"))
struct VideoMetadataReaderTests {
    @Test func readsMainFile() async throws {
        let metadata = try await VideoMetadataReader.read(SampleFootage.main)
        #expect(metadata.creationTime == Date(timeIntervalSince1970: 1_793_628_249))  // 2026-11-02T14:04:09Z
        #expect(abs(metadata.duration - 30.739042) < 0.001)
        #expect(abs(metadata.nominalFrameRate - 23.976) < 0.01)
        #expect(metadata.frameDuration.value == 1001 && metadata.frameDuration.timescale == 24000)
        #expect(metadata.naturalSize == CGSize(width: 3840, height: 2160))
        #expect(metadata.displaySize == CGSize(width: 3840, height: 2160))
        #expect(metadata.bitDepth == 10)
    }

    @Test func previewMatchesMainFile() async throws {
        let copy = try SampleFootage.previewCopy()
        defer { try? FileManager.default.removeItem(at: copy) }
        let preview = try await VideoMetadataReader.read(copy)
        let main = try await VideoMetadataReader.read(SampleFootage.main)
        #expect(preview.creationTime == main.creationTime)
        #expect(abs(preview.duration - main.duration) < 0.001)
        #expect(preview.naturalSize == CGSize(width: 1280, height: 720))
        #expect(preview.bitDepth == 8)
    }
}
