import AVFoundation
import DJIExtractCore
import Foundation
import Testing
@testable import DJIExtractKit

@Suite(.enabled(if: SampleFootage.isAvailable, "sample footage not present"), .serialized)
final class CameraLibraryTests {
    let root: URL
    let defaults: UserDefaults

    /// Builds `<tmp>/CARD/DCIM/DJI_001/` with hard links to the sample files.
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "CameraLibraryTests-\(UUID().uuidString)/CARD")
        let folder = root.appending(path: "DCIM/DJI_001")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Resolve symlinks first: linking a symlink would not give a regular file.
        for file in [SampleFootage.main, SampleFootage.preview].map({ $0.resolvingSymlinksInPath() }) {
            let target = folder.appending(path: file.lastPathComponent)
            do { try FileManager.default.linkItem(at: file, to: target) } catch { try FileManager.default.copyItem(at: file, to: target) }
        }
        try Data("x".utf8).write(to: folder.appending(path: "NOTES.TXT"))
        defaults = UserDefaults(suiteName: "CameraLibraryTests-\(UUID().uuidString)")!
    }

    deinit {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    @Test func scansDCIMAndReopensFromBookmark() throws {
        let library = try CameraLibrary.open(pickedFolder: root, defaults: defaults)
        #expect(library.dcimURL.lastPathComponent == "DCIM")
        let videos = try library.scan()
        #expect(videos.map(\.id) == ["DJI_001/DJI_20261102220407_0073_D.MP4"])
        #expect(videos.first?.preview?.relativePath == "DJI_001/DJI_20261102220407_0073_D.LRF")

        let reopened = try CameraLibrary.reopen(defaults: defaults)
        #expect(try reopened.scan().map(\.id) == videos.map(\.id))
    }

    @Test func reopenWithoutBookmarkFails() {
        #expect(throws: CameraLibraryError.noSavedFolder) { try CameraLibrary.reopen(defaults: self.defaults) }
    }

    @Test func thumbnailIsGeneratedOnceAndCached() async throws {
        let library = try CameraLibrary.open(pickedFolder: root, defaults: defaults)
        let video = try #require(try library.scan().first)
        let cache = ThumbnailCache(directory: root.deletingLastPathComponent().appending(path: "Thumbs"))
        let image = try await cache.thumbnail(for: video, in: library)
        #expect(max(image.width, image.height) <= 320)
        #expect(FileManager.default.fileExists(atPath: cache.fileURL(for: video).path))
        _ = try await cache.thumbnail(for: video, in: library)
    }

    @Test func previewPlaysLRFInPlace() async throws {
        let library = try CameraLibrary.open(pickedFolder: root, defaults: defaults)
        let video = try #require(try library.scan().first)
        let metadata = try await VideoMetadataReader.read(library.url(for: video.main))
        let preview = await PreviewSource.prepare(for: video, mainMetadata: metadata, in: library)
        #expect(preview.kind == .lrf)
        #expect(preview.asset.url == library.url(for: try #require(video.preview)))
        #expect(abs(preview.mainPosition(forPlayer: 12) - 12) < 0.001)
    }
}
