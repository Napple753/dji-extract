import AVFoundation
import DJIExtractCore
import Foundation

/// How a clip is cut from the source.
public enum ClipExportMode: String, CaseIterable, Codable, Sendable {
    /// Passthrough. Fast and lossless, but the start snaps back to the previous keyframe.
    case lossless
    /// Re-encodes, so the clip starts at the requested frame.
    case accurate
}

/// An exported movie ready to be added to Photos.
public struct ExportedClip: Sendable {
    public let url: URL
    public let timestamp: CaptureTimestamp
    /// Where the exported movie actually starts in the source, in seconds.
    public let actualStart: TimeInterval
    public let duration: TimeInterval
}

public enum ClipExporter {
    /// Exports `range` of the source as a MOV.
    ///
    /// The creation date is computed from the exported file's actual first frame, which for
    /// `.lossless` may be earlier than `range.start`.
    public static func export(
        from asset: AVAsset,
        range: CMTimeRange,
        mode: ClipExportMode,
        clock: CaptureClock,
        workspace: ExportWorkspace,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ExportedClip {
        let metadata = try await VideoMetadataReader.read(asset)
        let start: CMTime
        let preset: String
        switch mode {
        case .lossless:
            start = try await keyframe(atOrBefore: range.start, in: asset)
            preset = AVAssetExportPresetPassthrough
        case .accurate:
            start = snapToFrame(range.start, frameDuration: metadata.frameDuration)
            preset = AVAssetExportPresetHEVCHighestQuality
        }
        let exportRange = CMTimeRange(start: start, end: range.end)
        try workspace.ensureFreeSpace(Int64(metadata.estimatedBytesPerSecond * exportRange.duration.seconds))

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.exportFailed("Export preset \(preset) is not available")
        }
        let timestamp = clock.timestamp(at: start.seconds)
        session.timeRange = exportRange
        session.metadata = QuickTimeMetadata.items(timestamp: timestamp)
        session.shouldOptimizeForNetworkUse = false

        let url = workspace.file(named: "clip.mov")
        // Only `states` is read from the monitor, which the session supports from any thread.
        nonisolated(unsafe) let observed = session
        let monitor = Task {
            guard let progress else { return }
            for await state in observed.states(updateInterval: 0.25) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: url, as: .mov)

        return ExportedClip(url: url, timestamp: timestamp, actualStart: start.seconds, duration: exportRange.duration.seconds)
    }

    /// The presentation time of the nearest sync sample at or before `time`.
    static func keyframe(atOrBefore time: CMTime, in asset: AVAsset) async throws -> CMTime {
        let track = try await asset.mainVideoTrack()
        guard try await track.load(.canProvideSampleCursors),
              let cursor = track.makeSampleCursor(presentationTimeStamp: time)
        else { return time }
        while !cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue {
            if cursor.stepInDecodeOrder(byCount: -1) == 0 { break }
        }
        return CMTimeMinimum(cursor.presentationTimeStamp, time)
    }

    /// Rounds `time` down to a frame boundary.
    static func snapToFrame(_ time: CMTime, frameDuration: CMTime) -> CMTime {
        guard frameDuration.isValid, frameDuration.value > 0 else { return time }
        let converted = time.convertScale(frameDuration.timescale, method: .roundTowardNegativeInfinity)
        let frames = converted.value / frameDuration.value
        return CMTime(value: frames * frameDuration.value, timescale: frameDuration.timescale)
    }
}
