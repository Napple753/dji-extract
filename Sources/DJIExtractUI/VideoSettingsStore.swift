import DJIExtractCore
import Foundation

/// Per-video settings, kept so the next cut of the same video reuses them.
struct VideoSettings: Codable, Hashable {
    var adjustment = CaptureTimeAdjustment()
    /// Set when the file had no usable `creation_time` and the user entered the time by hand.
    var manualRecordingStart: Date?
}

@MainActor
final class VideoSettingsStore {
    private let defaults: UserDefaults
    private let key = "VideoSettings"
    private var cache: [String: VideoSettings]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cache = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: VideoSettings].self, from: $0) } ?? [:]
    }

    func settings(for video: CameraVideo) -> VideoSettings {
        cache[Self.key(for: video)] ?? VideoSettings()
    }

    func save(_ settings: VideoSettings, for video: CameraVideo) {
        cache[Self.key(for: video)] = settings
        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: key)
        }
    }

    private static func key(for video: CameraVideo) -> String {
        "\(video.id)|\(video.main.size)"
    }
}
