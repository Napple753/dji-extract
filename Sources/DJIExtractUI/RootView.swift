import DJIExtractCore
import SwiftUI

/// Connect → list → editor → save. The app's only entry point.
public struct RootView: View {
    @State private var app = AppModel()

    public init() {}

    public var body: some View {
        Group {
            if app.library == nil {
                ConnectView()
            } else {
                NavigationStack(path: $app.path) {
                    VideoListView()
                        .navigationDestination(for: CameraVideo.self) { video in
                            EditorView(video: video, app: app)
                        }
                }
            }
        }
        .environment(app)
    }
}
