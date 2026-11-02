import SwiftUI
import UniformTypeIdentifiers

/// Step 1: pick the camera's storage (or its DCIM folder) in the Files picker.
struct ConnectView: View {
    @Environment(AppModel.self) private var app
    @State private var isPicking = false
    @State private var showsLog = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "cable.connector")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Connect Osmo Action 6")
                    .font(.title2.bold())
                Text("Connect the camera with a USB-C cable, then choose its internal storage or SD card, or the DCIM folder inside it.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let message = app.connectMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Button {
                    isPicking = true
                } label: {
                    Label("Choose Camera Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Try Last Folder Again") { app.reconnect() }
                Spacer()
            }
            .padding(24)
            .toolbar {
                ToolbarItem {
                    Button("Log", systemImage: "doc.text.magnifyingglass") { showsLog = true }
                }
            }
            .sheet(isPresented: $showsLog) { LogView() }
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): app.open(pickedFolder: url)
                case .failure(let error): app.log.error("Folder picker: \(error)")
                }
            }
            .task { app.reconnect() }
        }
    }
}
