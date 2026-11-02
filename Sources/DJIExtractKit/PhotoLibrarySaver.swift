import Foundation
import Photos

public enum PhotoLibraryError: Error, Equatable {
    /// Add-only access was denied or restricted; the user must change it in Settings.
    case accessDenied
    case saveFailed(String)
}

/// What to add to Photos. All files are removed by the caller after saving.
public enum PhotoLibraryItem: Sendable {
    case photo(URL)
    case livePhoto(photo: URL, pairedVideo: URL)
    case video(URL)
}

/// Saves exported files to Photos with an explicit creation date.
///
/// Uses add-only access, so the app never asks to read the library.
public enum PhotoLibrarySaver {
    public static func requestAccess() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return status == .authorized || status == .limited
        default:
            return false
        }
    }

    /// Adds `item` as a single asset. `performChanges` is atomic, so a failure leaves nothing behind.
    public static func save(_ item: PhotoLibraryItem, creationDate: Date) async throws {
        guard await requestAccess() else { throw PhotoLibraryError.accessDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = creationDate
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                switch item {
                case .photo(let url):
                    request.addResource(with: .photo, fileURL: url, options: options)
                case .livePhoto(let photo, let video):
                    request.addResource(with: .photo, fileURL: photo, options: options)
                    request.addResource(with: .pairedVideo, fileURL: video, options: options)
                case .video(let url):
                    request.addResource(with: .video, fileURL: url, options: options)
                }
            }
        } catch {
            throw PhotoLibraryError.saveFailed(error.localizedDescription)
        }
    }
}
