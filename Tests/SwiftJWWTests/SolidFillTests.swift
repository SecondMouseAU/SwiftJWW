import Foundation
import Testing

@testable import SwiftJWW

@Suite("Solid fills")
struct SolidFillTests {
    /// The fields of a `CDataSolid`: its attributes and four corners, with no colour value after them.
    func solidFields(_ b: inout SwiftJWWTests.Builder) {
        b.base(color: 2, layer: 4)
        for v in [0.0, 0, 5, 0, 5, 5, 0, 5] { b.f64(v) }
    }

    /// A JWW with a top-level solid fill and an insert of block 7, whose members are a line and two
    /// solid fills.
    func sample() -> Data {
        var b = SwiftJWWTests.Builder()
        b.header()
        b.u16(2)  // main array preamble
        b.classTag("CDataSolid")
        solidFields(&b)
        b.classTag("CDataBlock")
        b.base()
        for v in [5.0, 6, 1, 1, 0] { b.f64(v) }
        b.u32(7)
        b.u16(1)  // block-definition list
        b.classTag("CDataList")
        b.base()
        b.u32(7)
        b.u32(0)
        b.u32(0)
        b.str("plate")
        b.u16(3)  // 3 members
        b.classTag("CDataSolid")
        solidFields(&b)
        b.classTag("CDataSen")
        b.senFields(0, 0, 5, 5)
        b.classTag("CDataSolid")
        solidFields(&b)
        return b.d
    }

    @Test("the solid fills of a block definition are counted on the block, not in the drawing")
    func inBlock() throws {
        let dwg = try JWW.read(data: sample())
        let block = try #require(dwg.blocks[7])
        #expect(block.solidCount == 2)
        #expect(block.elements.count == 1)
        #expect(dwg.counts.solid == 1)
        #expect(dwg.counts.block == 1)
    }
}
