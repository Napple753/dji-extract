import Foundation
import Testing
@testable import DJIExtractCore

private func hex(_ string: String) -> Data {
    var data = Data()
    var index = string.startIndex
    while index < string.endIndex {
        let next = string.index(index, offsetBy: 2)
        data.append(UInt8(string[index..<next], radix: 16)!)
        index = next
    }
    return data
}

@Suite struct DJIMetadataParserTests {
    /// Frame 1 of the Osmo Action 6 sample clip (docs/findings.md).
    let frameSample = hex(
        "1a86010a08080110c8ddd2b301125e1a050d00103f4522050a0301c8012a050d0000803f32030891203a0042004a140df2effc3e"
            + "153bec823e1d33ce18be251547513f520f15529811bf1d671279bc2543b551bf5a0062006a0610820418ee0772050a03a0010a"
            + "7a040a021c0a221a0a14080110012209444a492041433030362d8fc2bf4112021801")

    @Test func readsExposureFromFrameSample() throws {
        let exposure = try #require(DJIMetadataParser.exposure(fromFrame: frameSample))
        #expect(exposure.iso == 3057)
        #expect(exposure.exposureTime == .init(1, 200))
        #expect(exposure.digitalZoom == 1)
    }

    /// `1 { 1 { 10: "DJI OsmoAction6" } }`, the layout of the first sample's header.
    @Test func readsModelFromHeaderWithoutPrefix() {
        let model = Data("DJI OsmoAction6".utf8)
        let inner = Data([0x52, UInt8(model.count)]) + model
        let outer = Data([0x0A, UInt8(inner.count)]) + inner
        let header = Data([0x0A, UInt8(outer.count)]) + outer
        #expect(DJIMetadataParser.model(fromHeader: header) == "OsmoAction6")
    }

    @Test func rejectsGarbage() {
        #expect(DJIMetadataParser.exposure(fromFrame: Data([0xFF, 0xFF, 0xFF])) == nil)
        #expect(DJIMetadataParser.model(fromHeader: Data()) == nil)
        #expect(DJIMetadataParser.exposure(fromFrame: Data([0x08, 0x01])) == nil)
    }
}
