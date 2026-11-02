import Foundation

/// Maps positions between the low-resolution preview (LRF) and the main file.
///
/// Positions are kept in seconds. When the two durations differ the position is scaled by
/// their ratio, as the spec requires.
public struct PreviewTimeMapping: Hashable, Sendable {
    /// Largest duration difference for which the LRF is still used as preview.
    public static let maximumDurationDifference: TimeInterval = 1.0

    public let previewDuration: TimeInterval
    public let mainDuration: TimeInterval

    /// Returns `nil` when the LRF should not be used (spec: duration differs by more than 1 s).
    public init?(previewDuration: TimeInterval, mainDuration: TimeInterval) {
        guard previewDuration > 0, mainDuration > 0,
              abs(previewDuration - mainDuration) <= Self.maximumDurationDifference
        else { return nil }
        self.previewDuration = previewDuration
        self.mainDuration = mainDuration
    }

    public func mainPosition(forPreview position: TimeInterval) -> TimeInterval {
        clamp(position * mainDuration / previewDuration, to: mainDuration)
    }

    public func previewPosition(forMain position: TimeInterval) -> TimeInterval {
        clamp(position * previewDuration / mainDuration, to: previewDuration)
    }

    private func clamp(_ value: TimeInterval, to upper: TimeInterval) -> TimeInterval {
        min(max(value, 0), upper)
    }
}
