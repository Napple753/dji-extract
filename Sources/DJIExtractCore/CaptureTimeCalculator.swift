import Foundation

/// How the camera's `creation_time` relates to the recording.
public enum CreationTimeReference: String, Codable, Sendable {
    /// `creation_time` marks the start of the recording.
    case start
    /// `creation_time` marks the end of the recording.
    case end
}

/// Camera-specific facts needed to turn file metadata into capture times.
///
/// See `docs/findings.md` for how the Osmo Action 6 values were measured.
public struct CameraTimingProfile: Codable, Hashable, Sendable {
    /// Whether `creation_time` is the start or the end of the recording.
    public var reference: CreationTimeReference
    /// Seconds between `creation_time` (start reference) and the real capture time of frame 0.
    public var startLatency: TimeInterval

    public init(reference: CreationTimeReference, startLatency: TimeInterval) {
        self.reference = reference
        self.startLatency = startLatency
    }

    /// Measured on 2026-11-02: `creation_time` is UTC start, ~1.69 s before frame 0.
    public static let osmoAction6 = CameraTimingProfile(reference: .start, startLatency: 1.7)
}

/// Per-video correction chosen by the user.
public struct CaptureTimeAdjustment: Codable, Hashable, Sendable {
    /// User offset Δ in seconds. Defaults to 0.
    public var offset: TimeInterval
    /// Time zone of the shooting location, used for EXIF offsets and display only.
    public var timeZoneIdentifier: String

    public init(offset: TimeInterval = 0, timeZone: TimeZone = .current) {
        self.offset = offset
        self.timeZoneIdentifier = timeZone.identifier
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}

public enum CaptureTimeError: Error, Equatable, Sendable {
    /// The file has no `creation_time`, or it is clearly wrong (clock never set, far future).
    case missingOrInvalidCreationTime
}

/// Computes `T_capture = T_start + t + Δ`.
///
/// Independent of AVFoundation so it can be unit tested directly.
public struct CaptureTimeCalculator: Sendable {
    public var profile: CameraTimingProfile

    /// Creation times before this are treated as "camera clock not set".
    public static let earliestPlausibleDate = Date(timeIntervalSince1970: 1_577_836_800)  // 2020-01-01Z
    /// Tolerance for creation times slightly in the future (clock drift).
    public static let futureTolerance: TimeInterval = 24 * 60 * 60

    public init(profile: CameraTimingProfile = .osmoAction6) {
        self.profile = profile
    }

    /// Returns whether `creationTime` looks like a real camera clock reading.
    public static func isPlausible(_ creationTime: Date, now: Date = Date()) -> Bool {
        creationTime >= earliestPlausibleDate && creationTime <= now.addingTimeInterval(futureTolerance)
    }

    /// The absolute time at which frame 0 of the file was captured (`T_start`).
    ///
    /// - Parameters:
    ///   - creationTime: The file's `creation_time`, interpreted as UTC.
    ///   - duration: The file's duration in seconds.
    public func recordingStart(creationTime: Date?, duration: TimeInterval, now: Date = Date()) throws -> Date {
        guard let creationTime, Self.isPlausible(creationTime, now: now) else {
            throw CaptureTimeError.missingOrInvalidCreationTime
        }
        switch profile.reference {
        case .start:
            return creationTime.addingTimeInterval(profile.startLatency)
        case .end:
            return creationTime.addingTimeInterval(-duration)
        }
    }

    /// Start time of a split segment derived from the previous segment, for when the
    /// segment's own `creation_time` turns out to be unreliable.
    public func chainedRecordingStart(previousStart: Date, previousDuration: TimeInterval) -> Date {
        previousStart.addingTimeInterval(previousDuration)
    }

    /// The capture time of the frame at `position` seconds from the start of the file.
    public func captureTime(
        recordingStart: Date,
        position: TimeInterval,
        adjustment: CaptureTimeAdjustment
    ) -> CaptureTimestamp {
        CaptureTimestamp(
            date: recordingStart.addingTimeInterval(position + adjustment.offset),
            timeZone: adjustment.timeZone
        )
    }
}
