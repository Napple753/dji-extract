import AVFoundation
import DJIExtractCore
import DJIExtractKit
import Foundation
import Observation

/// Step 3: playback, frame stepping and choosing what to cut.
///
/// Plays the local LRF copy when possible; all positions handed to export are main-file seconds.
@MainActor @Observable
final class EditorModel {
    let video: CameraVideo
    private let app: AppModel
    private let library: CameraLibrary

    private(set) var metadata: VideoMetadata?
    private(set) var source: PreviewSource?
    private(set) var loadError: String?
    let player = AVPlayer()

    /// Player position in seconds (preview timeline).
    private(set) var position: TimeInterval = 0
    private(set) var isPlaying = false
    /// In/out points for a video cut, in main-file seconds.
    var markIn: TimeInterval?
    var markOut: TimeInterval?
    /// Non-nil while the save screen is shown.
    var saveModel: SaveModel?

    var settings: VideoSettings {
        didSet { app.settings.save(settings, for: video) }
    }

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init(video: CameraVideo, app: AppModel, library: CameraLibrary) {
        self.video = video
        self.app = app
        self.library = library
        self.settings = app.settings.settings(for: video)
    }

    // MARK: Loading

    func load() async {
        guard metadata == nil else { return }
        do {
            let metadata = try await VideoMetadataReader.read(library.asset(for: video.main))
            self.metadata = metadata
            let source = await PreviewSource.prepare(for: video, mainMetadata: metadata, in: library)
            self.source = source
            app.log.info("Opened \(video.fileName) (\(source.kind == .localPreview ? "LRF preview" : "main file"))")
            attach(AVPlayerItem(url: source.url))
        } catch {
            loadError = "Cannot read this video. \(error.localizedDescription)"
            app.log.error("Open \(video.fileName): \(error)")
        }
    }

    private func attach(_ item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.position = time.seconds
                self?.isPlaying = self?.player.timeControlStatus != .paused
            }
        }
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.playbackFailed(item.error) }
        }
    }

    private func playbackFailed(_ error: (any Error)?) {
        player.pause()
        app.log.error("Playback failed: \(String(describing: error))")
        // Only the main file is read from the camera during playback.
        if source?.kind == .mainFile || !app.isCameraReachable {
            app.disconnect(message: "Playback stopped. Reconnect the camera and choose the folder again.")
        }
    }

    func close() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation = nil
        source?.discard()
    }

    // MARK: Transport

    var playerDuration: TimeInterval {
        guard let source, let metadata else { return 0 }
        return source.mapping?.previewDuration ?? metadata.duration
    }

    func togglePlay() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
        isPlaying = player.timeControlStatus != .paused
    }

    /// Rough seeking while dragging, exact once released.
    func seek(to seconds: TimeInterval, exact: Bool) {
        position = seconds
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if exact {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: time)
        }
    }

    func step(_ frames: Int) {
        player.pause()
        player.currentItem?.step(byCount: frames)
        position = player.currentTime().seconds
    }

    // MARK: Timing

    /// Current position in the main file, snapped to its frame grid.
    var mainPosition: TimeInterval {
        guard let source, let metadata else { return 0 }
        return FrameGrid(metadata: metadata).snap(source.mainPosition(forPlayer: position))
    }

    var recordingStart: Date? {
        if let start = app.details[video.id]?.recordingStart { return start }
        if let metadata, let start = try? app.calculator.recordingStart(creationTime: metadata.creationTime, duration: metadata.duration) {
            return start
        }
        return settings.manualRecordingStart
    }

    var clock: CaptureClock? {
        recordingStart.map { CaptureClock(recordingStart: $0, adjustment: settings.adjustment) }
    }

    var currentTimestamp: CaptureTimestamp? {
        clock?.timestamp(at: mainPosition)
    }

    // MARK: Cutting

    func markInHere() {
        markIn = mainPosition
        if let markOut, markOut <= mainPosition { self.markOut = nil }
    }

    func markOutHere() {
        markOut = mainPosition
        if let markIn, markIn >= mainPosition { self.markIn = nil }
    }

    var canExportClip: Bool {
        guard let markIn, let markOut else { return false }
        return markOut > markIn
    }

    func beginSave(_ kind: SaveKind) {
        guard let metadata else { return }
        player.pause()
        let position: TimeInterval
        switch kind {
        case .photo, .livePhoto: position = mainPosition
        case .video(let start, _): position = start
        }
        saveModel = SaveModel(
            kind: kind,
            video: video,
            asset: library.asset(for: video.main),
            metadata: metadata,
            position: position,
            editor: self,
            app: app)
    }

    /// Called by the save screen when the user typed the time of a frame by hand.
    func setManualTime(_ date: Date, forFrameAt position: TimeInterval) {
        settings.manualRecordingStart = date.addingTimeInterval(-position - settings.adjustment.offset)
    }
}

/// Frame boundaries of the main file.
struct FrameGrid {
    let frameDuration: CMTime
    let duration: TimeInterval

    init(metadata: VideoMetadata) {
        frameDuration = metadata.frameDuration.isValid && metadata.frameDuration.value > 0
            ? metadata.frameDuration
            : CMTime(value: 1, timescale: CMTimeScale(max(metadata.nominalFrameRate.rounded(), 1)))
        duration = metadata.duration
    }

    var frameCount: Int { max(Int((duration / frameDuration.seconds).rounded(.down)), 1) }

    func index(of seconds: TimeInterval) -> Int {
        min(max(Int((seconds / frameDuration.seconds).rounded()), 0), frameCount - 1)
    }

    func time(of index: Int) -> CMTime {
        CMTime(value: CMTimeValue(index) * frameDuration.value, timescale: frameDuration.timescale)
    }

    func snap(_ seconds: TimeInterval) -> TimeInterval {
        time(of: index(of: seconds)).seconds
    }
}
