import Foundation
import Testing
@testable import DJIExtractCore

@Suite struct CameraFileIndexTests {
    func entry(_ path: String, _ modified: TimeInterval? = nil) -> CameraFileEntry {
        CameraFileEntry(relativePath: path, size: 1, modificationDate: modified.map(Date.init(timeIntervalSince1970:)))
    }

    @Test func pairsPreviewInSameFolder() {
        let videos = CameraFileIndex.videos(from: [
            entry("DJI_001/DJI_20261102220407_0073_D.MP4", 10),
            entry("DJI_001/DJI_20261102220407_0073_D.LRF", 10),
            entry("DJI_001/DJI_20261102221000_0074_D.MP4", 20),
            entry("DJI_002/DJI_20261102221000_0074_D.LRF", 20),
        ])
        #expect(videos.map(\.id) == ["DJI_001/DJI_20261102221000_0074_D.MP4", "DJI_001/DJI_20261102220407_0073_D.MP4"])
        #expect(videos[0].preview == nil)
        #expect(videos[1].preview?.relativePath == "DJI_001/DJI_20261102220407_0073_D.LRF")
    }

    @Test func filtersByExtensionCaseInsensitively() {
        let videos = CameraFileIndex.videos(from: [
            entry("a.mov"), entry("b.MP4"), entry("c.JPG"), entry("d.LRF"), entry("._e.MP4"), entry("f.mp4.txt"),
        ])
        #expect(Set(videos.map(\.fileName)) == ["a.mov", "b.MP4"])
    }

    @Test func sortsNewestFirstThenByName() {
        let videos = CameraFileIndex.videos(from: [entry("A.MP4"), entry("C.MP4"), entry("B.MP4", 5)])
        #expect(videos.map(\.fileName) == ["B.MP4", "C.MP4", "A.MP4"])
    }
}
