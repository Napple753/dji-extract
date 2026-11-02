import Foundation
import Testing
@testable import DJIExtractCore

private func utc(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: string)!
}

private let now = utc("2026-11-02T15:00:00.000Z")
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

@Suite struct CaptureTimeCalculatorTests {
    let calculator = CaptureTimeCalculator()

    @Test func startReferenceAddsLatency() throws {
        let calc = CaptureTimeCalculator(profile: .init(reference: .start, startLatency: 1.5))
        let start = try calc.recordingStart(creationTime: utc("2026-11-02T14:04:09.000Z"), duration: 30, now: now)
        #expect(start == utc("2026-11-02T14:04:10.500Z"))
    }

    @Test func endReferenceSubtractsDuration() throws {
        let calc = CaptureTimeCalculator(profile: .init(reference: .end, startLatency: 99))
        let start = try calc.recordingStart(creationTime: utc("2026-11-02T14:04:40.000Z"), duration: 30.5, now: now)
        #expect(start == utc("2026-11-02T14:04:09.500Z"))
    }

    @Test func missingCreationTimeThrows() {
        #expect(throws: CaptureTimeError.missingOrInvalidCreationTime) {
            try calculator.recordingStart(creationTime: nil, duration: 10, now: now)
        }
    }

    @Test(arguments: ["2016-01-01T00:00:00.000Z", "1970-01-01T00:00:00.000Z", "2026-11-04T00:00:00.000Z"])
    func implausibleCreationTimeThrows(value: String) {
        #expect(throws: CaptureTimeError.missingOrInvalidCreationTime) {
            try calculator.recordingStart(creationTime: utc(value), duration: 10, now: now)
        }
    }

    @Test func captureTimeAddsPositionAndOffset() {
        let start = utc("2026-11-02T14:04:10.000Z")
        let adjustment = CaptureTimeAdjustment(offset: -2.25, timeZone: shanghai)
        let stamp = calculator.captureTime(recordingStart: start, position: 12.5, adjustment: adjustment)
        #expect(stamp.date == utc("2026-11-02T14:04:20.250Z"))
        #expect(stamp.timeZone == shanghai)
    }

    @Test func chainedStartFollowsPreviousSegment() {
        let start = calculator.chainedRecordingStart(previousStart: utc("2026-11-02T14:00:00.000Z"), previousDuration: 600.5)
        #expect(start == utc("2026-11-02T14:10:00.500Z"))
    }

    /// Ground truth from the sample clip (docs/findings.md): the on-screen UTC clock flips to the
    /// given second at the given frame index. With the Osmo Action 6 profile and Δ = 0 the
    /// computed time must be within one frame plus a small margin of the flip.
    @Test(arguments: [(8, "14:04:11"), (56, "14:04:13"), (703, "14:04:40"), (727, "14:04:41")])
    func osmoAction6SampleMatchesOnScreenClock(frame: Int, flipsTo: String) throws {
        let frameDuration = 1001.0 / 24000.0
        let start = try calculator.recordingStart(
            creationTime: utc("2026-11-02T14:04:09.000Z"), duration: 30.739042, now: now)
        let stamp = calculator.captureTime(
            recordingStart: start, position: Double(frame) * frameDuration, adjustment: .init(timeZone: shanghai))
        let flip = utc("2026-11-02T\(flipsTo).000Z")
        let error = stamp.date.timeIntervalSince(flip)
        #expect(abs(error) < frameDuration + 0.05, "error \(error) s at frame \(frame)")
    }
}

@Suite struct CaptureTimestampTests {
    @Test func exifFieldsUseLocalTimeAndOffset() {
        let stamp = CaptureTimestamp(date: utc("2026-11-02T14:04:10.6875Z"), timeZone: shanghai)
        #expect(stamp.exifDateTime == "2026:11:02 22:04:10")
        #expect(stamp.exifSubSecond == "687")
        #expect(stamp.exifOffset == "+08:00")
        #expect(stamp.quickTimeCreationDate == "2026-11-02T22:04:10+0800")
        #expect(stamp.displayString == "2026-11-02 22:04:10.687 +08:00")
    }

    /// US daylight saving time ends on 2026-11-01, so the offset is the standard -08:00.
    @Test func negativeOffsetAndDayRollover() {
        let stamp = CaptureTimestamp(date: utc("2026-11-02T02:30:00.050Z"), timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(stamp.exifDateTime == "2026:11:01 18:30:00")
        #expect(stamp.exifSubSecond == "050")
        #expect(stamp.exifOffset == "-08:00")
    }

    @Test func daylightSavingOffset() {
        let stamp = CaptureTimestamp(date: utc("2026-07-01T12:00:00.000Z"), timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(stamp.exifDateTime == "2026:07:01 05:00:00")
        #expect(stamp.exifOffset == "-07:00")
    }

    @Test func halfHourZone() {
        let stamp = CaptureTimestamp(date: utc("2026-11-02T14:04:10.000Z"), timeZone: TimeZone(identifier: "Asia/Kolkata")!)
        #expect(stamp.exifDateTime == "2026:11:02 19:34:10")
        #expect(stamp.exifOffset == "+05:30")
    }
}

@Suite struct PreviewTimeMappingTests {
    @Test func identicalDurationsMapOneToOne() throws {
        let mapping = try #require(PreviewTimeMapping(previewDuration: 30.739042, mainDuration: 30.739042))
        #expect(mapping.mainPosition(forPreview: 12.3) == 12.3)
    }

    @Test func differentDurationsScaleByRatio() throws {
        let mapping = try #require(PreviewTimeMapping(previewDuration: 10, mainDuration: 10.5))
        #expect(mapping.mainPosition(forPreview: 5) == 5.25)
        #expect(mapping.previewPosition(forMain: 10.5) == 10)
        #expect(mapping.mainPosition(forPreview: 20) == 10.5)
    }

    @Test func largeDifferenceRejectsPreview() {
        #expect(PreviewTimeMapping(previewDuration: 10, mainDuration: 11.01) == nil)
        #expect(PreviewTimeMapping(previewDuration: 0, mainDuration: 1) == nil)
    }
}

@Suite struct LivePhotoRangeTests {
    @Test func centeredInTheMiddle() {
        let range = LivePhotoRange(stillPosition: 10, sourceDuration: 30)
        #expect(range.start == 8.5)
        #expect(range.duration == 3)
        #expect(range.stillOffset == 1.5)
    }

    @Test func truncatedAtStart() {
        let range = LivePhotoRange(stillPosition: 0.5, sourceDuration: 30)
        #expect(range.start == 0)
        #expect(range.duration == 2)
        #expect(range.stillOffset == 0.5)
    }

    @Test func truncatedAtEnd() {
        let range = LivePhotoRange(stillPosition: 29.5, sourceDuration: 30)
        #expect(range.start == 28)
        #expect(range.duration == 2)
        #expect(range.stillOffset == 1.5)
    }
}
