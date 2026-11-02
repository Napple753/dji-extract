import Foundation

/// An absolute capture time plus the time zone it should be presented in.
public struct CaptureTimestamp: Hashable, Sendable {
    public var date: Date
    public var timeZone: TimeZone

    public init(date: Date, timeZone: TimeZone) {
        self.date = date
        self.timeZone = timeZone
    }

    /// Whole seconds since 1970, rounded down, and the millisecond remainder.
    private var splitMilliseconds: (seconds: TimeInterval, milliseconds: Int) {
        let totalMilliseconds = (date.timeIntervalSince1970 * 1000).rounded(.down)
        let seconds = (totalMilliseconds / 1000).rounded(.down)
        return (seconds, Int(totalMilliseconds - seconds * 1000))
    }

    private func format(_ pattern: String, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private var wholeSecondDate: Date {
        Date(timeIntervalSince1970: splitMilliseconds.seconds)
    }

    /// EXIF `DateTimeOriginal` (local time, `yyyy:MM:dd HH:mm:ss`).
    public var exifDateTime: String {
        format("yyyy:MM:dd HH:mm:ss", wholeSecondDate)
    }

    /// EXIF `SubSecTimeOriginal` (milliseconds, three digits).
    public var exifSubSecond: String {
        String(format: "%03d", splitMilliseconds.milliseconds)
    }

    /// EXIF `OffsetTimeOriginal` (`+08:00`).
    public var exifOffset: String {
        format("xxx", wholeSecondDate)
    }

    /// Value for `com.apple.quicktime.creationdate` (ISO 8601 with offset, e.g. `2026-11-02T22:04:10+0800`).
    public var quickTimeCreationDate: String {
        format("yyyy-MM-dd'T'HH:mm:ssxx", wholeSecondDate)
    }

    /// Human readable local time with milliseconds, for the UI.
    public var displayString: String {
        format("yyyy-MM-dd HH:mm:ss", wholeSecondDate) + "." + exifSubSecond + " " + format("xxx", wholeSecondDate)
    }
}
