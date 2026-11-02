import AVFoundation
import DJIExtractCore
import DJIExtractKit
import Foundation
import Observation

enum SaveKind: Hashable {
    case photo
    case livePhoto
    /// Main-file seconds.
    case video(start: TimeInterval, end: TimeInterval)

    var title: String {
        switch self {
        case .photo: "Photo"
        case .livePhoto: "Live Photo"
        case .video: "Video"
        }
    }
}

/// Step 4: confirm the frame on the main file, confirm the date, export and add to Photos.
@MainActor @Observable
final class SaveModel: Identifiable, Hashable {
    enum State {
        case ready
        case exporting(progress: Double?)
        case saved(CaptureTimestamp)
        case failed(String, needsSettings: Bool)
    }

    let kind: SaveKind
    let video: CameraVideo
    private let asset: AVURLAsset
    private let metadata: VideoMetadata
    private let grid: FrameGrid
    private unowned let editor: EditorModel
    private let app: AppModel

    /// Frame index in the main file of the still (photo, Live Photo) or the start (video).
    private(set) var frameIndex: Int
    private(set) var frame: CGImage?
    private(set) var state: State = .ready
    var clipMode: ClipExportMode = .lossless
    /// Time of the current frame entered by hand, used only when the file has no usable date.
    var manualDate = Date()

    init(kind: SaveKind, video: CameraVideo, asset: AVURLAsset, metadata: VideoMetadata,
         position: TimeInterval, editor: EditorModel, app: AppModel) {
        self.kind = kind
        self.video = video
        self.asset = asset
        self.metadata = metadata
        self.grid = FrameGrid(metadata: metadata)
        self.editor = editor
        self.app = app
        self.frameIndex = grid.index(of: position)
    }

    nonisolated static func == (a: SaveModel, b: SaveModel) -> Bool { a === b }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var position: TimeInterval { grid.time(of: frameIndex).seconds }
    var needsManualDate: Bool { editor.clock == nil }
    var timeZone: TimeZone { editor.settings.adjustment.timeZone }

    /// Capture time of the confirmed frame. For lossless video the final value is computed from
    /// the exported file's actual start.
    var timestamp: CaptureTimestamp? {
        if let clock = editor.clock { return clock.timestamp(at: position) }
        return nil
    }

    var isBusy: Bool {
        if case .exporting = state { return true }
        return false
    }

    // MARK: Frame confirmation (reads the main file)

    func loadFrame() async {
        do {
            let frame = try await FrameExporter.frame(of: asset, at: grid.time(of: frameIndex), maximumSize: CGSize(width: 1280, height: 1280))
            // Ignore results that arrive after the user stepped again.
            if grid.index(of: frame.time.seconds) == frameIndex || frame.time.seconds <= position {
                self.frame = frame.image
            }
        } catch {
            app.log.error("Read main frame \(frameIndex): \(error)")
            if !app.isCameraReachable {
                app.disconnect(message: "The camera was disconnected. Reconnect it and choose the folder again.")
            }
        }
    }

    func step(_ frames: Int) async {
        let limit: Int
        if case .video(_, let end) = kind { limit = grid.index(of: end) - 1 } else { limit = grid.frameCount - 1 }
        frameIndex = min(max(frameIndex + frames, 0), max(limit, 0))
        await loadFrame()
    }

    // MARK: Export and save

    func save() async {
        if needsManualDate {
            editor.setManualTime(manualDate, forFrameAt: position)
        }
        guard let clock = editor.clock else { return }
        guard app.isCameraReachable else {
            app.disconnect(message: "The camera is not connected. Reconnect it and choose the folder again.")
            return
        }
        state = .exporting(progress: nil)
        let workspace: ExportWorkspace
        do {
            workspace = try ExportWorkspace.create()
        } catch {
            state = .failed("Cannot create a temporary folder. \(error.localizedDescription)", needsSettings: false)
            return
        }
        defer { workspace.remove() }

        do {
            let time = grid.time(of: frameIndex)
            let item: PhotoLibraryItem
            let stamp: CaptureTimestamp
            switch kind {
            case .photo:
                try workspace.ensureFreeSpace(Int64(metadata.naturalSize.width * metadata.naturalSize.height))
                let photo = try await FrameExporter.exportPhoto(from: asset, at: time, clock: clock, to: workspace.file(named: "photo.heic"))
                (item, stamp) = (.photo(photo.url), photo.timestamp)
            case .livePhoto:
                let live = try await LivePhotoExporter.export(from: asset, stillTime: time, clock: clock, workspace: workspace)
                (item, stamp) = (.livePhoto(photo: live.photoURL, pairedVideo: live.videoURL), live.timestamp)
            case .video(_, let end):
                let range = CMTimeRange(start: time, end: CMTime(seconds: end, preferredTimescale: time.timescale))
                let clip = try await ClipExporter.export(
                    from: asset, range: range, mode: clipMode, clock: clock, workspace: workspace,
                    progress: { [weak self] value in Task { @MainActor in self?.state = .exporting(progress: value) } })
                (item, stamp) = (.video(clip.url), clip.timestamp)
            }
            try await PhotoLibrarySaver.save(item, creationDate: stamp.date)
            app.log.info("Saved \(kind.title) from \(video.fileName) at \(stamp.displayString)")
            state = .saved(stamp)
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: any Error) {
        app.log.error("Save \(kind.title) failed: \(error)")
        switch error {
        case PhotoLibraryError.accessDenied:
            state = .failed("Photos access is off. Allow adding photos in Settings.", needsSettings: true)
        case ExportError.insufficientSpace(let required, let available):
            state = .failed("Not enough space on this iPhone. Needs \(Formatting.bytes(required)), \(Formatting.bytes(available)) available.", needsSettings: false)
        default:
            if !app.isCameraReachable {
                app.disconnect(message: "The camera was disconnected during export. Nothing was saved. Reconnect it and try again.")
            } else {
                state = .failed("Export failed. Nothing was saved. \(error.localizedDescription)", needsSettings: false)
            }
        }
    }
}
