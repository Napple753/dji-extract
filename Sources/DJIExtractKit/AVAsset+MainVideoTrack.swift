import AVFoundation

public enum MediaError: Error {
    case noVideoTrack
}

extension AVAsset {
    /// The camera's main video track.
    ///
    /// DJI files also carry an MJPEG thumbnail as a second video track, which is skipped.
    func mainVideoTrack() async throws -> AVAssetTrack {
        let tracks = try await loadTracks(withMediaType: .video)
        for track in tracks {
            let formats = try await track.load(.formatDescriptions)
            if let format = formats.first, CMFormatDescriptionGetMediaSubType(format) != kCMVideoCodecType_JPEG {
                return track
            }
        }
        guard let first = tracks.first else { throw MediaError.noVideoTrack }
        return first
    }
}
