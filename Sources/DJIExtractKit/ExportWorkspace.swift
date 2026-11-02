import Foundation

public enum ExportError: Error, Equatable {
    /// Not enough free space on the phone. Values are in bytes.
    case insufficientSpace(required: Int64, available: Int64)
    case cannotCreateDestination
    case exportFailed(String)
}

/// A scratch directory in the app's temporary area for one export.
///
/// Files are written here first and removed after they have been added to Photos
/// (or when the export fails), so nothing is ever written to the camera.
public struct ExportWorkspace: Sendable {
    public let directory: URL

    public static func create() throws -> ExportWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ExportWorkspace(directory: directory)
    }

    public func file(named name: String) -> URL {
        directory.appending(path: name)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Throws `insufficientSpace` unless `bytes` (plus a safety margin) fit on the volume.
    public func ensureFreeSpace(_ bytes: Int64) throws {
        let required = bytes + bytes / 5 + 50_000_000
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < required {
            throw ExportError.insufficientSpace(required: required, available: available)
        }
    }
}
