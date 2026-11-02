import AVFoundation
import DJIExtractCore
import Foundation

/// A HEIC + MOV pair ready to be added to Photos as one Live Photo.
public struct ExportedLivePhoto: Sendable {
    public let photoURL: URL
    public let videoURL: URL
    /// Capture time of the still frame, used for both files and for Photos.
    public let timestamp: CaptureTimestamp
    /// Position of the still frame in the source, in seconds.
    public let stillPosition: TimeInterval
    public let contentIdentifier: String
}

public enum LivePhotoExporter {
    /// Longest side of the paired video. Live Photo videos are not meant to be full 4K.
    static let maximumVideoDimension: CGFloat = 1920

    /// Exports a Live Photo whose still is the frame at `stillTime`, with about `length`
    /// seconds of video centered on it (truncated at the ends of the source).
    public static func export(
        from asset: AVAsset,
        stillTime: CMTime,
        clock: CaptureClock,
        workspace: ExportWorkspace,
        length: TimeInterval = LivePhotoRange.defaultLength
    ) async throws -> ExportedLivePhoto {
        let metadata = try await VideoMetadataReader.read(asset)
        try workspace.ensureFreeSpace(Int64(metadata.estimatedBytesPerSecond * length))

        let frame = try await FrameExporter.frame(of: asset, at: stillTime)
        let stillPosition = frame.time.seconds
        let timestamp = clock.timestamp(at: stillPosition)
        let identifier = UUID().uuidString

        let photoURL = workspace.file(named: "live.heic")
        try FrameExporter.writeHEIC(frame.image, timestamp: timestamp, contentIdentifier: identifier, to: photoURL)

        let range = LivePhotoRange(stillPosition: stillPosition, sourceDuration: metadata.duration, length: length)
        let videoURL = workspace.file(named: "live.mov")
        try await writeMovie(
            from: asset,
            metadata: metadata,
            range: CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 600_000),
                duration: CMTime(seconds: range.duration, preferredTimescale: 600_000)),
            stillTime: frame.time,
            items: QuickTimeMetadata.items(timestamp: timestamp, contentIdentifier: identifier),
            to: videoURL)

        return ExportedLivePhoto(
            photoURL: photoURL, videoURL: videoURL, timestamp: timestamp,
            stillPosition: stillPosition, contentIdentifier: identifier)
    }

    static func writeMovie(
        from asset: AVAsset,
        metadata: VideoMetadata,
        range: CMTimeRange,
        stillTime: CMTime,
        items: [AVMetadataItem],
        to url: URL
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = items
        var transfers: [SampleTransfer] = []

        // Video: decode to 8-bit and re-encode as HEVC, scaled down.
        let videoTrack = try await asset.mainVideoTrack()
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        let size = scaledSize(metadata.naturalSize)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
        ])
        videoInput.transform = metadata.preferredTransform
        videoInput.expectsMediaDataInRealTime = false
        reader.add(videoOutput)
        writer.add(videoInput)
        transfers.append(SampleTransfer(output: videoOutput, input: videoInput))

        // Audio: decode to PCM and re-encode as AAC.
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 128_000,
            ])
            audioInput.expectsMediaDataInRealTime = false
            reader.add(audioOutput)
            writer.add(audioInput)
            transfers.append(SampleTransfer(output: audioOutput, input: audioInput))
        }

        // Timed metadata marking the still frame.
        let stillAdaptor = try makeStillImageTimeAdaptor()
        writer.add(stillAdaptor.assetWriterInput)

        guard reader.startReading() else {
            throw reader.error ?? ExportError.exportFailed("Cannot read source")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? ExportError.exportFailed("Cannot write Live Photo video")
        }
        writer.startSession(atSourceTime: range.start)

        stillAdaptor.append(AVTimedMetadataGroup(
            items: [stillImageTimeItem()],
            timeRange: CMTimeRange(start: stillTime, duration: CMTime(value: 1, timescale: 100))))
        stillAdaptor.assetWriterInput.markAsFinished()

        await withTaskGroup(of: Void.self) { group in
            for transfer in transfers {
                group.addTask { await transfer.run() }
            }
        }

        if reader.status == .failed || writer.status == .failed {
            let error = reader.error ?? writer.error
            reader.cancelReading()
            writer.cancelWriting()
            throw error ?? ExportError.exportFailed("Live Photo video failed")
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? ExportError.exportFailed("Live Photo video failed")
        }
    }

    static func scaledSize(_ size: CGSize) -> CGSize {
        let scale = min(1, maximumVideoDimension / max(size.width, size.height))
        // Encoders want even dimensions.
        func even(_ value: CGFloat) -> CGFloat { (value * scale / 2).rounded() * 2 }
        return CGSize(width: even(size.width), height: even(size.height))
    }

    static let stillImageTimeIdentifier = AVMetadataIdentifier("mdta/com.apple.quicktime.still-image-time")

    static func stillImageTimeItem() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = stillImageTimeIdentifier
        item.value = NSNumber(value: Int8(-1))
        item.dataType = kCMMetadataBaseDataType_SInt8 as String
        return item
    }

    static func makeStillImageTimeAdaptor() throws -> AVAssetWriterInputMetadataAdaptor {
        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: stillImageTimeIdentifier.rawValue,
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String,
        ]
        var description: CMFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &description)
        guard status == noErr, let description else {
            throw ExportError.exportFailed("Cannot create still-image-time format (\(status))")
        }
        let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    }
}

/// Copies samples from one reader output to one writer input on its own queue.
private final class SampleTransfer: @unchecked Sendable {
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private let queue = DispatchQueue(label: "LivePhotoExporter.SampleTransfer")

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput) {
        self.output = output
        self.input = input
    }

    func run() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            input.requestMediaDataWhenReady(on: queue) { [self] in
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    // `nil` means the range is done or reading failed; the caller checks which.
                    guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                        finished = true
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }
}
