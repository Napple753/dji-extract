import AVFoundation
import DJIExtractCore
import Foundation

public enum CameraLibraryError: Error, Equatable {
    case accessDenied
    case noSavedFolder
    /// The bookmark no longer resolves (camera disconnected or card swapped).
    case bookmarkInvalid
}

/// Read-only access to the camera's folder, chosen with the folder picker.
///
/// Holds the security-scoped access for as long as the library is open. Nothing is ever
/// written to the camera.
public final class CameraLibrary: @unchecked Sendable {
    public let rootURL: URL
    /// The DCIM folder (or the chosen folder if it has none).
    public let dcimURL: URL
    private let accessing: Bool

    private init(rootURL: URL) throws {
        self.accessing = rootURL.startAccessingSecurityScopedResource()
        self.rootURL = rootURL
        self.dcimURL = Self.locateDCIM(in: rootURL)
        guard (try? dcimURL.checkResourceIsReachable()) == true else {
            if accessing { rootURL.stopAccessingSecurityScopedResource() }
            throw CameraLibraryError.accessDenied
        }
    }

    deinit {
        if accessing { rootURL.stopAccessingSecurityScopedResource() }
    }

    // MARK: Opening

    private static let bookmarkKey = "CameraLibrary.bookmark"

    /// Opens a folder returned by the folder picker and remembers it for next time.
    public static func open(pickedFolder url: URL, defaults: UserDefaults = .standard) throws -> CameraLibrary {
        let library = try CameraLibrary(rootURL: url)
        if let bookmark = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmark, forKey: bookmarkKey)
        }
        return library
    }

    /// Reopens the previously chosen folder, if its bookmark still resolves.
    public static func reopen(defaults: UserDefaults = .standard) throws -> CameraLibrary {
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { throw CameraLibraryError.noSavedFolder }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: bookmarkResolutionOptions, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw CameraLibraryError.bookmarkInvalid
        }
        let library = try CameraLibrary(rootURL: url)
        if stale, let fresh = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: bookmarkKey)
        }
        return library
    }

    public static func forgetSavedFolder(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bookmarkKey)
    }

    #if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    static func locateDCIM(in root: URL) -> URL {
        if root.lastPathComponent.uppercased() == "DCIM" { return root }
        let candidates = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return candidates.first { $0.lastPathComponent.uppercased() == "DCIM" } ?? root
    }

    // MARK: Listing

    /// Lists videos under DCIM, newest first, with their LRF previews.
    public func scan() throws -> [CameraVideo] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: dcimURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { throw CameraLibraryError.accessDenied }
        let basePath = dcimURL.standardizedFileURL.path(percentEncoded: false)
        var entries: [CameraFileEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            var path = url.standardizedFileURL.path(percentEncoded: false)
            if path.hasPrefix(basePath) { path.removeFirst(basePath.count) }
            entries.append(CameraFileEntry(
                relativePath: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                size: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate))
        }
        return CameraFileIndex.videos(from: entries)
    }

    public func url(for entry: CameraFileEntry) -> URL {
        dcimURL.appending(path: entry.relativePath)
    }

    /// An asset for a camera file. LRFs are opened as MP4 without copying.
    public func asset(for entry: CameraFileEntry) -> AVURLAsset {
        let url = url(for: entry)
        if url.pathExtension.uppercased() == CameraFileIndex.previewExtension {
            return AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"])
        }
        return AVURLAsset(url: url)
    }
}
