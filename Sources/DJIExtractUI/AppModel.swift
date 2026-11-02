import AVFoundation
import DJIExtractCore
import DJIExtractKit
import Foundation
import Observation

/// What the list shows for a video once its metadata has been read.
struct VideoDetails {
    var metadata: VideoMetadata?
    /// `T_start` from `creation_time`; `nil` if missing or implausible.
    var recordingStart: Date?
    /// Set when the file could not be read; the row is shown disabled.
    var failure: String?
}

/// App-wide state: the connected camera, its videos and navigation.
@MainActor @Observable
public final class AppModel {
    private(set) var library: CameraLibrary?
    private(set) var videos: [CameraVideo] = []
    private(set) var details: [String: VideoDetails] = [:]
    var path: [CameraVideo] = []
    /// Shown on the connect screen after an automatic disconnect.
    var connectMessage: String?

    let settings = VideoSettingsStore()
    let thumbnails = ThumbnailCache()
    let calculator = CaptureTimeCalculator()
    let log = AppLog.shared

    public init() {}

    // MARK: Connection

    /// Tries the saved bookmark; stays on the connect screen if it does not resolve.
    func reconnect() {
        do {
            try connect(CameraLibrary.reopen())
        } catch CameraLibraryError.noSavedFolder {
            return
        } catch {
            log.info("Saved folder unavailable: \(error)")
        }
    }

    func open(pickedFolder url: URL) {
        do {
            try connect(CameraLibrary.open(pickedFolder: url))
        } catch {
            log.error("Cannot open \(url.lastPathComponent): \(error)")
            connectMessage = "Cannot read this folder. Choose the camera's storage or its DCIM folder."
        }
    }

    private func connect(_ library: CameraLibrary) throws {
        self.library = library
        connectMessage = nil
        log.info("Connected: \(library.dcimURL.path(percentEncoded: false))")
        try refresh()
    }

    func refresh() throws {
        guard let library else { return }
        videos = try library.scan()
        log.info("Found \(videos.count) videos")
    }

    /// Returns to the connect screen, e.g. after the cable was pulled.
    func disconnect(message: String? = nil) {
        if let message { log.error(message) }
        library = nil
        videos = []
        details = [:]
        path = []
        connectMessage = message
    }

    func forgetFolder() {
        CameraLibrary.forgetSavedFolder()
        disconnect()
    }

    /// Whether the camera is still attached.
    var isCameraReachable: Bool {
        guard let library else { return false }
        return (try? library.dcimURL.checkResourceIsReachable()) == true
    }

    // MARK: Video details

    func loadDetails(for video: CameraVideo) async {
        guard details[video.id] == nil, let library else { return }
        do {
            let metadata = try await VideoMetadataReader.read(library.asset(for: video.main))
            let start = try? calculator.recordingStart(creationTime: metadata.creationTime, duration: metadata.duration)
            details[video.id] = VideoDetails(metadata: metadata, recordingStart: start)
        } catch {
            log.error("Cannot read \(video.fileName): \(error)")
            details[video.id] = VideoDetails(failure: error.localizedDescription)
        }
    }

    func thumbnail(for video: CameraVideo) async -> CGImage? {
        guard let library else { return nil }
        return try? await thumbnails.thumbnail(for: video, in: library)
    }
}
