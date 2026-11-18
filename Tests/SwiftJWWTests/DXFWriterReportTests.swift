import Foundation
import Testing

@testable import SwiftJWW

@Suite("DXF writer: the report")
struct DXFWriterReportTests {
    let dimensions = DimensionTests()
    let writer = DXFWriterTests()
    let recovery = DXFWriterRecoveryTests()
    let recover = DXFWriter.Options(recoversDimensions: true)

    /// A loose line, then the 800 dimension of six pieces, then a 400 dimension of two arrow
    /// points and its text.
    var twoDimensions: JWW.Drawing {
        dimensions.drawing(
            [JWW.Element(entity: writer.line(50, 50, 60, 60))] + recovery.sample + [
                dimensions.arrow(0, 20), dimensions.arrow(5, 20),
                dimensions.valueText("400", 2, 21),
            ])
    }

    /// The DXF entity type an element's entity is written as, and its points by group code.
    func drawnAs(_ element: JWW.Element) -> (type: String, points: [Int: Double])? {
        switch element.entity {
        case .line(let a, let b, _, _): ("LINE", [10: a.x, 20: a.y, 11: b.x, 21: b.y])
        case .point(let at, _, _): ("POINT", [10: at.x, 20: at.y])
        case .text(let at, _, _, _, _, _, _): ("TEXT", [10: at.x, 20: at.y])
        default: nil
        }
    }

    @Test("each handle's indices are the elements written in the block its DIMENSION names")
    func elementsInBlock() throws {
        let dwg = twoDimensions
        let output = DXFWriter.output(dwg, options: recover)
        let dxf = try ReferenceDXF(text: output.text)
        let written = dxf.entities.filter { $0.type == "DIMENSION" }
        #expect(written.count == 2)
        #expect(
            Set(output.report.recoveredDimensionElements.keys)
                == Set(output.report.recoveredDimensions))
        for dimension in written {
            let handle = try #require(dimension.text(5))
            let indices = try #require(output.report.recoveredDimensionElements[handle])
            let name = try #require(dimension.text(2))
            let members = try #require(dxf.blocks[name])
            #expect(indices.count == members.count)
            for (index, member) in zip(indices, members) {
                let piece = try #require(drawnAs(dwg.elements[index]))
                #expect(member.type == piece.type)
                for (code, value) in piece.points { #expect(member.number(code) == value) }
            }
        }
        let lists = output.report.recoveredDimensions.map {
            output.report.recoveredDimensionElements[$0]
        }
        #expect(lists == [[1, 2, 3, 4, 5, 6], [7, 8, 9]])
    }

    @Test("each handle's indices are the ones recoveringDimensions() gives for that dimension")
    func sameAsRecovery() throws {
        // Two dimensions that share an arrow point each list it.
        let dwg = dimensions.drawing([
            dimensions.arrow(0, 0), dimensions.arrow(5, 0), dimensions.arrow(10, 0),
            dimensions.valueText("400", 2, 1), dimensions.valueText("400", 7, 1),
        ])
        let report = DXFWriter.output(dwg, options: recover).report
        let lists = report.recoveredDimensions.map { report.recoveredDimensionElements[$0] ?? [] }
        #expect(lists == dwg.recoveringDimensions().dimensions.map(\.elementIndices))
        #expect(lists == [[0, 1, 3], [1, 2, 4]])
    }

    @Test("the report gives the factor each layer group was multiplied by")
    func appliedScales() throws {
        let elements = [0, 1, 2].map { group in
            JWW.Element(entity: writer.line(0, 0, 10, 5), attributes: .init(layerGroup: group))
        }
        let dwg = writer.drawing(elements, scales: [0: 80, 1: 10, 2: 0])
        let output = DXFWriter.output(dwg, options: .init(fullSize: true))
        // A group with no usable scale is written as drawn.
        #expect(output.report.appliedScales == [0: 80, 1: 10, 2: 1])
        let lines = try ReferenceDXF(text: output.text).entities
        for (group, line) in zip([0, 1, 2], lines) {
            #expect(line.number(11) == 10 * (output.report.appliedScales[group] ?? 0))
        }
        let drawn = DXFWriter.output(dwg).report
        #expect(drawn.appliedScales == [0: 1, 1: 1, 2: 1])
    }

    @Test("a layer group only block members use is not listed, since the insert carries the scale")
    func blockMembersNotListed() {
        let member = JWW.Element(entity: writer.line(0, 0, 5, 5), attributes: .init(layerGroup: 3))
        let def = JWW.BlockDef(number: 7, name: "box", elements: [member])
        let insert = JWW.Element(
            entity: .insert(
                def: 7, at: .init(x: 2, y: 3), scaleX: 1, scaleY: 1, rotationRad: 0, layer: 0,
                color: 1))
        let dwg = writer.drawing([insert], blocks: [7: def], scales: [0: 10, 3: 50])
        let report = DXFWriter.output(dwg, options: .init(fullSize: true)).report
        #expect(report.appliedScales == [0: 10])
    }
}
