import AVFoundation
import CryptoKit
import DJIExtractCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JPEG thumbnails stored in the app's caches, so reconnecting does not re-read the camera.
public struct ThumbnailCache: Sendable {
    public let directory: URL
    public static let maximumSize = CGSize(width: 320, height: 320)

    public init(directory: URL = URL.cachesDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    /// Cache key changes whenever the file's path, size or modification date changes.
    func fileURL(for video: CameraVideo) -> URL {
        let identity = "\(video.main.relativePath)|\(video.main.size)|\(video.main.modificationDate?.timeIntervalSince1970 ?? 0)"
        let hash = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(hash).jpg")
    }

    /// Returns the cached thumbnail, generating it from the LRF (or the main file) if needed.
    public func thumbnail(for video: CameraVideo, in library: CameraLibrary) async throws -> CGImage {
        let url = fileURL(for: video)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        let asset = library.asset(for: video.preview ?? video.main)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.maximumSize
        let (image, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
        return image
    }
}
