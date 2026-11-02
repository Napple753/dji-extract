import DJIExtractCore
import SwiftUI

/// Step 2: videos on the camera, newest first.
struct VideoListView: View {
    @Environment(AppModel.self) private var app
    @State private var showsLog = false

    var body: some View {
        List(app.videos) { video in
            let details = app.details[video.id]
            let isReadable = details?.failure == nil
            NavigationLink(value: video) {
                VideoRow(video: video, details: details)
            }
            .disabled(!isReadable)
            .task { await app.loadDetails(for: video) }
        }
        .overlay {
            if app.videos.isEmpty {
                ContentUnavailableView("No Videos", systemImage: "video.slash",
                                       description: Text("No MP4 or MOV files were found under DCIM."))
            }
        }
        .navigationTitle("Videos")
        .refreshable { try? app.refresh() }
        .toolbar {
            ToolbarItem {
                Button("Log", systemImage: "doc.text.magnifyingglass") { showsLog = true }
            }
            ToolbarItem {
                Menu("Camera", systemImage: "ellipsis.circle") {
                    Button("Reload", systemImage: "arrow.clockwise") { try? app.refresh() }
                    Button("Choose Another Folder", systemImage: "folder") { app.forgetFolder() }
                }
            }
        }
        .sheet(isPresented: $showsLog) { LogView() }
    }
}

private struct VideoRow: View {
    @Environment(AppModel.self) private var app
    let video: CameraVideo
    let details: VideoDetails?
    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let thumbnail {
                    Image(frame: thumbnail).resizable().scaledToFill()
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(startText).font(.headline)
                HStack(spacing: 8) {
                    if let duration = details?.metadata?.duration {
                        Text(Formatting.duration(duration))
                    }
                    Text(Formatting.bytes(video.main.size))
                    if video.preview == nil {
                        Text("No LRF").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(video.fileName).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .opacity(details?.failure == nil ? 1 : 0.4)
        .task { thumbnail = await app.thumbnail(for: video) }
    }

    private var startText: String {
        if details?.failure != nil { return "Cannot read" }
        guard let details else { return "…" }
        guard let start = details.recordingStart else { return "No date" }
        let settings = app.settings.settings(for: video)
        return start.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, timeZone: settings.adjustment.timeZone))
    }
}
