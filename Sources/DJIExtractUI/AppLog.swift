import Foundation
import Observation
import os

/// In-app log, viewable while the camera occupies the USB-C port and Xcode logs are unavailable.
@MainActor @Observable
public final class AppLog {
    public static let shared = AppLog()

    public struct Entry: Identifiable, Sendable {
        public enum Level: Sendable { case info, error }
        public let id = UUID()
        public let date = Date()
        public let level: Level
        public let message: String
    }

    public private(set) var entries: [Entry] = []
    private let logger = Logger(subsystem: "DJIExtract", category: "app")
    private let limit = 500

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append(Entry(level: .info, message: message))
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append(Entry(level: .error, message: message))
    }

    public func clear() {
        entries.removeAll()
    }

    private func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }
}
