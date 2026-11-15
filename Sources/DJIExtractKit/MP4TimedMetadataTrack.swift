import Foundation

/// A timed metadata track read straight from an MP4's sample tables.
///
/// AVFoundation hides DJI's `djmd` track (it lists only video, audio and timecode), so the
/// `moov` box is parsed by hand to locate the samples in the file.
struct MP4TimedMetadataTrack {
    let url: URL
    let timescale: UInt32
    /// File offset and size of every sample, in decode order.
    let samples: [(offset: UInt64, size: UInt32)]
    /// Start time of every sample in `timescale` units.
    let startTimes: [UInt64]

    enum ParseError: Error {
        case malformed(String)
    }

    /// Finds the first track whose sample description has the format `format` (e.g. `djmd`).
    init?(url: URL, format: String) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let moov = try Self.topLevelBox("moov", in: file) else { return nil }
        for trak in Box.children(of: moov, type: "trak") {
            guard let mdia = Box.child(of: trak, path: ["mdia"]),
                  let mdhd = Box.child(of: mdia, path: ["mdhd"]),
                  let stbl = Box.child(of: mdia, path: ["minf", "stbl"]),
                  let stsd = Box.child(of: stbl, path: ["stsd"]),
                  stsd.count >= 16, stsd.fourCC(at: 12) == format
            else { continue }
            self.url = url
            timescale = try Self.timescale(mdhd)
            samples = try Self.sampleLocations(stbl)
            startTimes = try Self.startTimes(stbl, count: samples.count)
            return
        }
        return nil
    }

    /// The bytes of the sample covering `seconds`.
    func sample(at seconds: Double) throws -> Data? {
        guard !samples.isEmpty else { return nil }
        let target = UInt64(max(0, seconds) * Double(timescale) + 0.5)
        // Last sample starting at or before `target`.
        var low = 0
        var high = startTimes.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if startTimes[mid] <= target { low = mid } else { high = mid - 1 }
        }
        return try sample(index: low)
    }

    func sample(index: Int) throws -> Data? {
        guard samples.indices.contains(index) else { return nil }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: samples[index].offset)
        return try file.read(upToCount: Int(samples[index].size))
    }

    // MARK: Box parsing

    private static func topLevelBox(_ type: String, in file: FileHandle) throws -> Data? {
        let end = try file.seekToEnd()
        var offset: UInt64 = 0
        while offset + 8 <= end {
            try file.seek(toOffset: offset)
            guard let header = try file.read(upToCount: 16), header.count >= 8 else { return nil }
            var size = UInt64(header.uint32(at: 0))
            var headerSize: UInt64 = 8
            if size == 1 {
                guard header.count >= 16 else { return nil }
                size = header.uint64(at: 8)
                headerSize = 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= headerSize else { throw ParseError.malformed("box size") }
            if header.fourCC(at: 4) == type {
                try file.seek(toOffset: offset + headerSize)
                return try file.read(upToCount: Int(size - headerSize))
            }
            offset += size
        }
        return nil
    }

    private static func timescale(_ mdhd: Data) throws -> UInt32 {
        // version(1) flags(3), then creation/modification times of 4 or 8 bytes each.
        guard mdhd.count >= 4 else { throw ParseError.malformed("mdhd") }
        let offset = mdhd[mdhd.startIndex] == 1 ? 20 : 12
        guard mdhd.count >= offset + 4 else { throw ParseError.malformed("mdhd") }
        return mdhd.uint32(at: offset)
    }

    private static func sampleLocations(_ stbl: Data) throws -> [(offset: UInt64, size: UInt32)] {
        guard let stsz = Box.child(of: stbl, path: ["stsz"]), stsz.count >= 12,
              let stsc = Box.child(of: stbl, path: ["stsc"]), stsc.count >= 8
        else { throw ParseError.malformed("stsz/stsc") }

        let uniformSize = stsz.uint32(at: 4)
        let sampleCount = Int(stsz.uint32(at: 8))
        var sizes = [UInt32](repeating: uniformSize, count: sampleCount)
        if uniformSize == 0 {
            guard stsz.count >= 12 + sampleCount * 4 else { throw ParseError.malformed("stsz") }
            for i in 0..<sampleCount { sizes[i] = stsz.uint32(at: 12 + i * 4) }
        }

        var chunkOffsets: [UInt64] = []
        if let stco = Box.child(of: stbl, path: ["stco"]), stco.count >= 8 {
            let count = Int(stco.uint32(at: 4))
            guard stco.count >= 8 + count * 4 else { throw ParseError.malformed("stco") }
            chunkOffsets = (0..<count).map { UInt64(stco.uint32(at: 8 + $0 * 4)) }
        } else if let co64 = Box.child(of: stbl, path: ["co64"]), co64.count >= 8 {
            let count = Int(co64.uint32(at: 4))
            guard co64.count >= 8 + count * 8 else { throw ParseError.malformed("co64") }
            chunkOffsets = (0..<count).map { co64.uint64(at: 8 + $0 * 8) }
        } else {
            throw ParseError.malformed("chunk offsets")
        }

        // stsc: runs of (firstChunk, samplesPerChunk), 1-based chunk numbers.
        let runCount = Int(stsc.uint32(at: 4))
        guard stsc.count >= 8 + runCount * 12 else { throw ParseError.malformed("stsc") }
        let runs = (0..<runCount).map { (first: Int(stsc.uint32(at: 8 + $0 * 12)), perChunk: Int(stsc.uint32(at: 12 + $0 * 12))) }

        var locations: [(offset: UInt64, size: UInt32)] = []
        locations.reserveCapacity(sampleCount)
        var sample = 0
        for (chunk, chunkOffset) in chunkOffsets.enumerated() where sample < sampleCount {
            let chunkNumber = chunk + 1
            let perChunk = runs.last(where: { $0.first <= chunkNumber })?.perChunk ?? 0
            var offset = chunkOffset
            for _ in 0..<perChunk where sample < sampleCount {
                locations.append((offset, sizes[sample]))
                offset += UInt64(sizes[sample])
                sample += 1
            }
        }
        return locations
    }

    private static func startTimes(_ stbl: Data, count: Int) throws -> [UInt64] {
        guard let stts = Box.child(of: stbl, path: ["stts"]), stts.count >= 8 else { throw ParseError.malformed("stts") }
        let entryCount = Int(stts.uint32(at: 4))
        guard stts.count >= 8 + entryCount * 8 else { throw ParseError.malformed("stts") }
        var times: [UInt64] = []
        times.reserveCapacity(count)
        var time: UInt64 = 0
        for entry in 0..<entryCount {
            let samples = stts.uint32(at: 8 + entry * 8)
            let delta = UInt64(stts.uint32(at: 12 + entry * 8))
            for _ in 0..<samples where times.count < count {
                times.append(time)
                time += delta
            }
        }
        return times
    }
}

/// Helpers for walking boxes already loaded into memory.
private enum Box {
    /// Payloads (after the 8-byte header) of the direct children of `container` with `type`.
    static func children(of container: Data, type: String) -> [Data] {
        var result: [Data] = []
        var offset = 0
        while offset + 8 <= container.count {
            let size = Int(container.uint32(at: offset))
            guard size >= 8, offset + size <= container.count else { break }
            if container.fourCC(at: offset + 4) == type {
                let start = container.startIndex + offset + 8
                result.append(container.subdata(in: start..<(container.startIndex + offset + size)))
            }
            offset += size
        }
        return result
    }

    static func child(of container: Data, path: [String]) -> Data? {
        var current = container
        for type in path {
            guard let next = children(of: current, type: type).first else { return nil }
            current = next
        }
        return current
    }
}

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16 | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3])
    }

    func uint64(at offset: Int) -> UInt64 {
        UInt64(uint32(at: offset)) << 32 | UInt64(uint32(at: offset + 4))
    }

    func fourCC(at offset: Int) -> String {
        let i = startIndex + offset
        return String(bytes: self[i..<(i + 4)], encoding: .ascii) ?? ""
    }
}
