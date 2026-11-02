import Foundation

/// A file found under the camera's DCIM folder.
public struct CameraFileEntry: Hashable, Sendable {
    /// Path relative to the DCIM folder, using `/` separators.
    public var relativePath: String
    public var size: Int64
    public var modificationDate: Date?

    public init(relativePath: String, size: Int64, modificationDate: Date?) {
        self.relativePath = relativePath
        self.size = size
        self.modificationDate = modificationDate
    }

    var directory: Substring {
        guard let slash = relativePath.lastIndex(of: "/") else { return "" }
        return relativePath[..<slash]
    }

    var fileName: Substring {
        guard let slash = relativePath.lastIndex(of: "/") else { return Substring(relativePath) }
        return relativePath[relativePath.index(after: slash)...]
    }

    var baseName: Substring {
        guard let dot = fileName.lastIndex(of: ".") else { return fileName }
        return fileName[..<dot]
    }

    var fileExtension: String {
        guard let dot = fileName.lastIndex(of: ".") else { return "" }
        return fileName[fileName.index(after: dot)...].uppercased()
    }
}

/// A recording on the camera: the main file and, if present, its low-resolution preview.
public struct CameraVideo: Identifiable, Hashable, Sendable {
    /// Relative path of the main file; stable across reconnects.
    public var id: String { main.relativePath }
    public var main: CameraFileEntry
    public var preview: CameraFileEntry?

    public var fileName: String { String(main.fileName) }
}

public enum CameraFileIndex {
    public static let videoExtensions: Set<String> = ["MP4", "MOV"]
    public static let previewExtension = "LRF"

    /// Pairs main files with same-named LRFs in the same folder and sorts newest first.
    public static func videos(from entries: [CameraFileEntry]) -> [CameraVideo] {
        var previews: [String: CameraFileEntry] = [:]
        for entry in entries where entry.fileExtension == previewExtension {
            previews[key(entry)] = entry
        }
        return entries
            .filter { videoExtensions.contains($0.fileExtension) && !$0.fileName.hasPrefix(".") }
            .map { CameraVideo(main: $0, preview: previews[key($0)]) }
            .sorted { a, b in
                let (da, db) = (a.main.modificationDate ?? .distantPast, b.main.modificationDate ?? .distantPast)
                return da != db ? da > db : a.main.fileName > b.main.fileName
            }
    }

    private static func key(_ entry: CameraFileEntry) -> String {
        "\(entry.directory)/\(entry.baseName)".uppercased()
    }
}
