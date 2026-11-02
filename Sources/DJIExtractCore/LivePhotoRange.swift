import Foundation

/// The span of the source video used for a Live Photo, and where the still frame sits in it.
public struct LivePhotoRange: Hashable, Sendable {
    public static let defaultLength: TimeInterval = 3.0

    /// Start of the span, in source seconds.
    public let start: TimeInterval
    /// Length of the span in seconds.
    public let duration: TimeInterval
    /// Position of the still frame relative to `start`.
    public let stillOffset: TimeInterval

    /// Centers a span of `length` seconds on `stillPosition`, truncating it at the start and end
    /// of the source and moving the still offset accordingly.
    public init(stillPosition: TimeInterval, sourceDuration: TimeInterval, length: TimeInterval = defaultLength) {
        let still = min(max(stillPosition, 0), sourceDuration)
        let start = max(still - length / 2, 0)
        let end = min(still + length / 2, sourceDuration)
        self.start = start
        self.duration = end - start
        self.stillOffset = still - start
    }
}
