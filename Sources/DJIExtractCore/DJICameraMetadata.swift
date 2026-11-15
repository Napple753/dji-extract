import Foundation

/// Exposure settings of one frame, from the DJI `djmd` timed metadata track.
public struct FrameExposure: Hashable, Sendable {
    public var iso: Double?
    /// Exposure time as a fraction, e.g. 1/200 s.
    public var exposureTime: Fraction?
    public var digitalZoom: Double?

    public struct Fraction: Hashable, Sendable {
        public var numerator: Int
        public var denominator: Int

        public init(_ numerator: Int, _ denominator: Int) {
            self.numerator = numerator
            self.denominator = denominator
        }

        public var seconds: Double { Double(numerator) / Double(denominator) }
    }

    public init(iso: Double? = nil, exposureTime: Fraction? = nil, digitalZoom: Double? = nil) {
        self.iso = iso
        self.exposureTime = exposureTime
        self.digitalZoom = digitalZoom
    }
}

/// Camera information written into exported files.
public struct CameraInfo: Hashable, Sendable {
    public var make: String
    /// Model as the camera reports it (e.g. `OsmoAction6`). `nil` if the file does not say.
    public var model: String?
    /// Exposure of the exported frame. Photos only.
    public var exposure: FrameExposure?

    public init(make: String = "DJI", model: String? = nil, exposure: FrameExposure? = nil) {
        self.make = make
        self.model = model
        self.exposure = exposure
    }

    /// Used when the source has no readable DJI metadata.
    public static let unknown = CameraInfo()
}

/// Decodes the protobuf samples of the DJI `djmd` track.
///
/// Field numbers follow ExifTool's `dvtm_ac203` table (Osmo Action 4), which ExifTool also
/// applies to Action 5 (`ac204`) and Action 6 (`ac206`). See `docs/findings.md`.
public enum DJIMetadataParser {
    /// The model name from the first sample of the track (`1.1.10`, e.g. `DJI OsmoAction6`),
    /// without the leading `DJI `.
    public static func model(fromHeader data: Data) -> String? {
        guard let message = Protobuf.Message(data),
              let raw = message.string(at: [1, 1, 10])?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty
        else { return nil }
        let prefix = "DJI "
        return raw.hasPrefix(prefix) ? String(raw.dropFirst(prefix.count)) : raw
    }

    /// The exposure settings in a frame sample (`3.2.*`).
    public static func exposure(fromFrame data: Data) -> FrameExposure? {
        guard let message = Protobuf.Message(data) else { return nil }
        var exposure = FrameExposure()
        exposure.iso = message.float(at: [3, 2, 3, 1]).map(Double.init)
        if let values = message.packedVarints(at: [3, 2, 4, 1]), values.count == 2, values[0] > 0, values[1] > 0 {
            exposure.exposureTime = .init(Int(values[0]), Int(values[1]))
        }
        exposure.digitalZoom = message.float(at: [3, 2, 5, 1]).map(Double.init)
        return exposure == FrameExposure() ? nil : exposure
    }
}

/// Just enough protobuf wire-format decoding to read DJI metadata without a schema.
enum Protobuf {
    enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
    }

    struct Message {
        var fields: [(number: Int, value: Value)] = []

        init?(_ data: Data) {
            var reader = Reader(data: data)
            while !reader.isAtEnd {
                guard let key = reader.varint() else { return nil }
                let number = Int(key >> 3)
                switch key & 7 {
                case 0:
                    guard let value = reader.varint() else { return nil }
                    fields.append((number, .varint(value)))
                case 1:
                    guard let value = reader.fixed(8) else { return nil }
                    fields.append((number, .fixed64(value)))
                case 2:
                    guard let length = reader.varint(), let value = reader.bytes(Int(length)) else { return nil }
                    fields.append((number, .bytes(value)))
                case 5:
                    guard let value = reader.fixed(4) else { return nil }
                    fields.append((number, .fixed32(UInt32(value))))
                default:
                    return nil
                }
            }
        }

        /// The first value at a field path, descending through nested messages.
        func value(at path: [Int]) -> Value? {
            guard let first = path.first, let value = fields.first(where: { $0.number == first })?.value else { return nil }
            if path.count == 1 { return value }
            guard case .bytes(let data) = value, let nested = Message(data) else { return nil }
            return nested.value(at: Array(path.dropFirst()))
        }

        func string(at path: [Int]) -> String? {
            guard case .bytes(let data) = value(at: path) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        func float(at path: [Int]) -> Float? {
            guard case .fixed32(let bits) = value(at: path) else { return nil }
            return Float(bitPattern: bits)
        }

        func packedVarints(at path: [Int]) -> [UInt64]? {
            guard case .bytes(let data) = value(at: path) else { return nil }
            var reader = Reader(data: data)
            var values: [UInt64] = []
            while !reader.isAtEnd {
                guard let value = reader.varint() else { return nil }
                values.append(value)
            }
            return values
        }
    }

    struct Reader {
        let data: Data
        var index: Data.Index

        init(data: Data) {
            self.data = data
            index = data.startIndex
        }

        var isAtEnd: Bool { index >= data.endIndex }

        mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < data.endIndex, shift < 64 {
                let byte = data[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        mutating func fixed(_ size: Int) -> UInt64? {
            guard data.endIndex - index >= size else { return nil }
            var result: UInt64 = 0
            for offset in 0..<size {
                result |= UInt64(data[index + offset]) << (8 * UInt64(offset))
            }
            index += size
            return result
        }

        mutating func bytes(_ count: Int) -> Data? {
            guard count >= 0, data.endIndex - index >= count else { return nil }
            defer { index += count }
            return data.subdata(in: index..<(index + count))
        }
    }
}
