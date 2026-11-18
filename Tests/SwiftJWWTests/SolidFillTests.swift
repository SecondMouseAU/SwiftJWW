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

    @Test("block expansion counts the solid fills each insert places, through nested blocks")
    func expanded() {
        func insert(_ def: Int) -> JWW.Element {
            JWW.Element(
                entity: .insert(
                    def: def, at: .init(x: 0, y: 0), scaleX: 1, scaleY: 1, rotationRad: 0,
                    layer: 0, color: 1))
        }
        // Block 1 holds no fill but inserts block 2, which holds one. Two inserts of block 1 and
        // one top-level fill make three.
        let blocks = [
            1: JWW.BlockDef(number: 1, name: "outer", elements: [insert(2)]),
            2: JWW.BlockDef(number: 2, name: "inner", elements: [], solidCount: 1),
        ]
        var counts = JWW.Drawing.Counts()
        counts.solid = 1
        let dwg = JWW.Drawing(
            version: 700, elements: [insert(1), insert(1)], blocks: blocks, counts: counts,
            layerGroups: [])
        #expect(dwg.expandingBlocks().solidCount == 3)
    }
}
