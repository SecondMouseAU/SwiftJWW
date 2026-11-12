import Foundation
import Testing

@testable import SwiftJWW

@Suite("Drawing comparison")
struct DrawingComparisonTests {
    /// A 1:80 drawing whose only dimension sits inside block 1, which is inserted at (10, 10).
    func drawingWithDimensionInBlock() -> JWW.Drawing {
        func piece(_ entity: JWW.Entity, flags: Int) -> JWW.Element {
            JWW.Element(entity: entity, attributes: .init(layer: 14, color: 1, flags: flags))
        }
        let members = [
            piece(.point(at: .init(x: 0, y: 0), layer: 14, color: 1), flags: 0x3D40),
            piece(.point(at: .init(x: 5, y: 0), layer: 14, color: 1), flags: 0x3D40),
            piece(
                .text(
                    at: .init(x: 2, y: 1), height: 2.5, width: 2.5, angleRad: 0, string: "400",
                    layer: 14, color: 1), flags: 0x4010),
        ]
        let insert = JWW.Element(
            entity: .insert(
                def: 1, at: .init(x: 10, y: 10), scaleX: 1, scaleY: 1, rotationRad: 0, layer: 14,
                color: 1), attributes: .init(layerGroup: 0, layer: 14))
        let groups = (0..<16).map { index in
            JWW.LayerGroup(
                index: index, scale: 80, state: index == 0 ? 3 : 2,
                layers: (0..<16).map { JWW.Layer(index: $0) })
        }
        return JWW.Drawing(
            version: 700, elements: [insert],
            blocks: [1: JWW.BlockDef(number: 1, name: "plan", elements: members)],
            counts: .init(), layerGroups: groups)
    }

    /// The DXF of that drawing: full-size coordinates on a sheet of 100 drawn units at 1:80.
    func dxf(withText: Bool) throws -> ReferenceDXF {
        var text = """
              9
            $LTSCALE
             40
            80
              9
            $EXTMAX
             10
            8000
             20
            8000
              0
            ENDSEC
              0
            SECTION
              2
            ENTITIES
              0
            POINT
              8
            _0-e_
             10
            4800
             20
            4800
              0
            POINT
              8
            _0-e_
             10
            5200
             20
            4800

            """
        if withText {
            text += """
                  0
                TEXT
                  8
                _0-e_
                 10
                4960
                 20
                4880
                 40
                200
                  1
                400
                 50
                0

                """
        }
        text += "  0\nENDSEC\n  0\nEOF\n"
        return try ReferenceDXF(text: "  0\nSECTION\n  2\nHEADER\n" + text)
    }

    @Test("a dimension inside a block is recovered from the expanded drawing and checked")
    func checksDimensionInBlock() throws {
        let report = DrawingComparison.compare(
            drawingWithDimensionInBlock(), try dxf(withText: true))
        #expect(report.unexplained.isEmpty)
        #expect(report.explained.contains("1 dimensions recovered from 1 value texts"))
    }

    @Test("a dimension inside a block whose text is missing from the DXF is reported")
    func reportsMissingText() throws {
        let report = DrawingComparison.compare(
            drawingWithDimensionInBlock(), try dxf(withText: false))
        #expect(
            report.unexplained.contains("dimension 400 has no TEXT at its position in the DXF"))
    }
}
