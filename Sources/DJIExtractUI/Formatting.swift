import CoreGraphics
import Foundation
import SwiftUI

enum Formatting {
    /// `1:05.250` style position.
    static func position(_ seconds: TimeInterval) -> String {
        let clamped = max(seconds, 0)
        let minutes = Int(clamped) / 60
        let rest = clamped - Double(minutes * 60)
        return String(format: "%d:%06.3f", minutes, rest)
    }

    /// `1:05` style duration.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func offset(_ seconds: TimeInterval) -> String {
        String(format: "%+.2f s", seconds)
    }
}

extension Image {
    init(frame: CGImage) {
        self.init(decorative: frame, scale: 1)
    }
}
