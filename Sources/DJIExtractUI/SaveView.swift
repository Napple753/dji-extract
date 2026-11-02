import DJIExtractCore
import DJIExtractKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Step 4: shows the main file's frame (the LRF can be a frame off), the date, then saves.
struct SaveView: View {
    @Bindable var model: SaveModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ZStack {
                    Rectangle().fill(.black)
                    if let frame = model.frame {
                        Image(frame: frame).resizable().scaledToFit()
                    } else {
                        ProgressView()
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .listRowInsets(EdgeInsets())
                HStack {
                    Button("Back 1 Frame", systemImage: "backward.frame") { Task { await model.step(-1) } }
                    Spacer()
                    Text(Formatting.position(model.position)).monospacedDigit()
                    Spacer()
                    Button("Forward 1 Frame", systemImage: "forward.frame") { Task { await model.step(1) } }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(model.isBusy)
            } header: {
                Text(frameHeader)
            } footer: {
                Text("This frame is read from the full-resolution file. Step to fix any offset from the preview.")
            }

            Section("Capture Date") {
                if model.needsManualDate {
                    Label("This file has no usable date. Enter the time of this frame.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    DatePicker("Time of frame", selection: $model.manualDate, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, model.timeZone)
                } else if let stamp = model.timestamp {
                    LabeledContent("Date", value: stamp.displayString)
                        .monospacedDigit()
                }
                LabeledContent("Time zone", value: model.timeZone.identifier)
                if case .video = model.kind, model.clipMode == .lossless {
                    Text("Lossless export starts at the previous keyframe; the saved date follows the actual start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .video(let start, let end) = model.kind {
                Section("Video") {
                    LabeledContent("Length", value: Formatting.position(end - start))
                    Picker("Mode", selection: $model.clipMode) {
                        Text("Lossless").tag(ClipExportMode.lossless)
                        Text("Accurate").tag(ClipExportMode.accurate)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                status
            }
        }
        .navigationTitle("Save \(model.kind.title)")
        .navigationBarBackButtonHidden(model.isBusy)
        .task { await model.loadFrame() }
    }

    private var frameHeader: String {
        if case .video = model.kind { return "Start Frame" }
        return "Frame"
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .ready:
            Button {
                Task { await model.save() }
            } label: {
                Label("Save to Photos with This Date", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case .exporting(let progress):
            if let progress {
                ProgressView("Exporting…", value: progress)
            } else {
                ProgressView("Exporting…")
            }
        case .saved(let stamp):
            Label("Saved to Photos at \(stamp.displayString)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("Back to Video") { dismiss() }
        case .failed(let message, let needsSettings):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
            if needsSettings {
                Button("Open Settings") { openSettings() }
            }
            Button("Try Again") { Task { await model.save() } }
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }
}
