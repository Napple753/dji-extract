import AVKit
import DJIExtractCore
import DJIExtractKit
import SwiftUI

/// Step 3: find the frame, see its capture time, choose photo / Live Photo / video.
struct EditorView: View {
    let app: AppModel
    @State private var model: EditorModel?
    @State private var scrubPosition: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var showsAdjustment = false
    private let video: CameraVideo

    init(video: CameraVideo, app: AppModel) {
        self.video = video
        self.app = app
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(video.fileName)
        .task {
            guard model == nil, let library = app.library else { return }
            let model = EditorModel(video: video, app: app, library: library)
            self.model = model
            await model.load()
        }
        .onDisappear { model?.close() }
    }

    @ViewBuilder
    private func content(_ model: EditorModel) -> some View {
        @Bindable var model = model
        if let error = model.loadError {
            ContentUnavailableView("Cannot Open", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    VideoPlayer(player: model.player)
                        .aspectRatio(aspectRatio(model), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    captureTime(model)
                    transport(model)
                    actions(model)
                }
                .padding()
            }
            .toolbar {
                ToolbarItem {
                    Button("Date", systemImage: "clock.badge.questionmark") { showsAdjustment = true }
                }
            }
            .sheet(isPresented: $showsAdjustment) {
                AdjustmentView(settings: $model.settings, hasCreationTime: model.recordingStart != nil)
            }
            .navigationDestination(item: $model.saveModel) { save in
                SaveView(model: save)
            }
        }
    }

    private func aspectRatio(_ model: EditorModel) -> CGFloat {
        guard let size = model.metadata?.displaySize, size.height > 0 else { return 16 / 9 }
        return size.width / size.height
    }

    private func captureTime(_ model: EditorModel) -> some View {
        VStack(spacing: 4) {
            if let stamp = model.currentTimestamp {
                Text(stamp.displayString)
                    .font(.title3.monospacedDigit().bold())
            } else {
                Label("No capture date in this file. You will enter it when saving.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Text(Formatting.position(model.mainPosition))
                Text("Δ \(Formatting.offset(model.settings.adjustment.offset))")
                Text(model.settings.adjustment.timeZoneIdentifier)
                if model.source?.kind == .mainFile {
                    Text("Main file").foregroundStyle(.orange)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func transport(_ model: EditorModel) -> some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubPosition : model.position },
                    set: { value in
                        scrubPosition = value
                        model.seek(to: value, exact: false)
                    }),
                in: 0...max(model.playerDuration, 0.1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing { model.seek(to: scrubPosition, exact: true) }
                })
            HStack(spacing: 20) {
                Button("Back 1 Frame", systemImage: "backward.frame") { model.step(-1) }
                Button(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                    model.togglePlay()
                }
                .font(.title2)
                Button("Forward 1 Frame", systemImage: "forward.frame") { model.step(1) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
        }
    }

    private func actions(_ model: EditorModel) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button("Photo", systemImage: "photo") { model.beginSave(.photo) }
                Button("Live Photo", systemImage: "livephoto") { model.beginSave(.livePhoto) }
            }
            .buttonStyle(.borderedProminent)

            GroupBox("Video") {
                HStack {
                    Button("In") { model.markInHere() }
                    Text(model.markIn.map(Formatting.position) ?? "–").monospacedDigit()
                    Spacer()
                    Text(model.markOut.map(Formatting.position) ?? "–").monospacedDigit()
                    Button("Out") { model.markOutHere() }
                }
                .buttonStyle(.bordered)
                Button("Save Video", systemImage: "film") {
                    if let start = model.markIn, let end = model.markOut {
                        model.beginSave(.video(start: start, end: end))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExportClip)
            }
        }
    }
}
