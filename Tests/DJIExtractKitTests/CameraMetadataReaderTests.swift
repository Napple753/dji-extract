import AVFoundation
import DJIExtractCore
import Testing
@testable import DJIExtractKit

@Suite(.enabled(if: SampleFootage.isAvailable, "sample footage not present"))
struct CameraMetadataReaderTests {
    @Test func readsModelAndExposureFromSample() async {
        let asset = AVURLAsset(url: SampleFootage.main)
        let info = await CameraMetadataReader.read(asset, frameAt: CMTime(value: 100 * 1001, timescale: 24000))
        #expect(info.make == "DJI")
        #expect(info.model == "OsmoAction6")
        #expect(info.exposure?.iso == 3057)
        #expect(info.exposure?.exposureTime == .init(1, 200))
    }

    @Test func omitsExposureWithoutFrame() async throws {
        let asset = AVURLAsset(url: SampleFootage.main)
        let info = await CameraMetadataReader.read(asset)
        #expect(info.model == "OsmoAction6")
        #expect(info.exposure == nil)
    }
}
