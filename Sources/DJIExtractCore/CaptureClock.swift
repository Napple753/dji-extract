import Foundation

/// Converts positions in one file into capture timestamps, with the user's adjustment applied.
public struct CaptureClock: Hashable, Sendable {
    /// `T_start` of the file.
    public var recordingStart: Date
    public var adjustment: CaptureTimeAdjustment

    public init(recordingStart: Date, adjustment: CaptureTimeAdjustment) {
        self.recordingStart = recordingStart
        self.adjustment = adjustment
    }

    public func timestamp(at position: TimeInterval) -> CaptureTimestamp {
        CaptureTimestamp(
            date: recordingStart.addingTimeInterval(position + adjustment.offset),
            timeZone: adjustment.timeZone
        )
    }
}

/// Camera identity written into exported files.
public enum CameraIdentity {
    public static let make = "DJI"
    public static let model = "Osmo Action 6"
}
