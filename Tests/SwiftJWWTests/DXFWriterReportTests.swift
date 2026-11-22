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
                // The recovery builds a dimension from lines, points and text only.
                let piece = try #require(
                    drawnAs(dwg.elements[index]), "piece \(index) is not a line, point or text")
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

    @Test(
        "the element indices of a report are those of its pieces, and follow them when they change")
    func elementsFollowThePieces() {
        typealias Piece = JWW.RecoveredDimension.Piece
        var report = DXFWriter.Report(
            recoveredDimensions: ["2A", "2B"],
            recoveredDimensionPieces: [
                "2A": [
                    Piece(index: 2, role: .arrowPoint), Piece(index: 5, role: .valueText),
                    Piece(index: 7, role: .arrowPoint),
                ],
                "2B": [],
            ])
        #expect(report.recoveredDimensionElements == ["2A": [2, 5, 7], "2B": []])
        report.recoveredDimensionPieces["2B"] = [Piece(index: 9, role: .valueText)]
        report.recoveredDimensionPieces["2A"] = nil
        #expect(report.recoveredDimensionElements == ["2B": [9]])
        #expect(DXFWriter.Report().recoveredDimensionElements.isEmpty)
    }

    @Test("chained dimensions are keyed by the handles in the DXF, with their indices ascending")
    func elementsOfEveryHandle() throws {
        let dwg = dimensions.drawing([
            dimensions.arrow(0, 0), dimensions.arrow(5, 0), dimensions.arrow(10, 0),
            dimensions.valueText("400", 2, 1), dimensions.valueText("400", 7, 1),
            dimensions.valueText("400", 7, 1),
        ])
        let output = DXFWriter.output(dwg, options: recover)
        let dxf = try ReferenceDXF(text: output.text)
        let written = dxf.entities.filter { $0.type == "DIMENSION" }.compactMap { $0.text(5) }
        #expect(written.count == 2)
        #expect(Set(output.report.recoveredDimensionElements.keys) == Set(written))
        #expect(
            output.report.recoveredDimensionElements.values.sorted { $0[0] < $1[0] } == [
                [0, 1, 3], [1, 2, 4, 5],
            ])
        for list in output.report.recoveredDimensionElements.values {
            #expect(list == list.sorted() && Set(list).count == list.count)
        }
    }

    @Test("each handle's pieces are the ones recoveringDimensions() gives, with their roles")
    func piecesWithRoles() throws {
        typealias Piece = JWW.RecoveredDimension.Piece
        let dwg = twoDimensions
        let report = DXFWriter.output(dwg, options: recover).report
        let lists = report.recoveredDimensions.map { report.recoveredDimensionPieces[$0] ?? [] }
        #expect(lists == dwg.recoveringDimensions().dimensions.map(\.pieces))
        #expect(
            lists == [
                [
                    Piece(index: 1, role: .dimensionLine), Piece(index: 2, role: .extensionLine),
                    Piece(index: 3, role: .extensionLine), Piece(index: 4, role: .arrowPoint),
                    Piece(index: 5, role: .arrowPoint), Piece(index: 6, role: .valueText),
                ],
                [
                    Piece(index: 7, role: .arrowPoint), Piece(index: 8, role: .arrowPoint),
                    Piece(index: 9, role: .valueText),
                ],
            ])
    }

    @Test("a piece two dimensions share has its own role in the pieces of each handle")
    func sharedPieceInEach() throws {
        typealias Piece = JWW.RecoveredDimension.Piece
        let report = DXFWriter.output(dimensions.corner, options: recover).report
        #expect(report.recoveredDimensions.count == 2)
        let lists = report.recoveredDimensions.compactMap { report.recoveredDimensionPieces[$0] }
        let along = try #require(lists.first { $0.contains(Piece(index: 3, role: .valueText)) })
        let up = try #require(lists.first { $0.contains(Piece(index: 4, role: .valueText)) })
        // The corner arrow point and the line between the corner and the far end are in both.
        #expect(
            along == [
                Piece(index: 0, role: .arrowPoint), Piece(index: 1, role: .arrowPoint),
                Piece(index: 3, role: .valueText), Piece(index: 5, role: .extensionLine),
            ])
        #expect(
            up == [
                Piece(index: 0, role: .arrowPoint), Piece(index: 2, role: .arrowPoint),
                Piece(index: 4, role: .valueText), Piece(index: 5, role: .dimensionLine),
            ])
    }

    @Test("a copy of the value text is reported as a copy, not as a second value text")
    func copyOfTheValueText() throws {
        let dwg = dimensions.drawing([
            dimensions.arrow(0, 0), dimensions.arrow(10, 0), dimensions.valueText("800", 4, 1),
            dimensions.valueText("800", 4, 1),
        ])
        let report = DXFWriter.output(dwg, options: recover).report
        let handle = try #require(report.recoveredDimensions.first)
        #expect(
            report.recoveredDimensionPieces[handle] == [
                .init(index: 0, role: .arrowPoint), .init(index: 1, role: .arrowPoint),
                .init(index: 2, role: .valueText), .init(index: 3, role: .valueTextCopy),
            ])
        #expect(report.recoveredDimensionElements[handle] == [0, 1, 2, 3])
    }

    @Test("without the option no pieces are reported")
    func noPiecesWithoutOption() {
        let report = DXFWriter.output(twoDimensions).report
        #expect(report.recoveredDimensionPieces.isEmpty)
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

    @Test("each piece, times its own layer group's applied scale, is where the DXF draws it")
    func piecesAtTheirGroupScale() throws {
        // The 800 dimension in group 0 at 1:80, with a line along its dimension line and a witness
        // line in group 1 at 1:10. The recovery uses pieces of the text's group only, so the
        // factor of each piece's own group is the one its DIMENSION was written at.
        func inGroup1(_ element: JWW.Element) -> JWW.Element {
            var element = element
            element.attributes.layerGroup = 1
            return element
        }
        var groups = (0..<16).map { JWW.LayerGroup(index: $0, scale: 80) }
        groups[1].scale = 10
        let elements =
            recovery.sample + [
                inGroup1(dimensions.dimLine(2, 0, 8, 0)), inGroup1(dimensions.dimLine(0, 0, 0, -3)),
            ]
        let dwg = JWW.Drawing(
            version: 700, elements: elements, blocks: [:], counts: .init(), layerGroups: groups)
        let output = DXFWriter.output(dwg, options: .init(fullSize: true, recoversDimensions: true))
        #expect(output.report.appliedScales == [0: 80, 1: 10])
        let dxf = try ReferenceDXF(text: output.text)
        let dimension = try #require(dxf.entities.first { $0.type == "DIMENSION" })
        let handle = try #require(dimension.text(5))
        let name = try #require(dimension.text(2))
        let indices = try #require(output.report.recoveredDimensionElements[handle])
        let members = try #require(dxf.blocks[name])
        #expect(indices == [0, 1, 2, 3, 4, 5])
        for (index, member) in zip(indices, members) {
            let element = dwg.elements[index]
            let factor = try #require(output.report.appliedScales[element.attributes.layerGroup])
            let piece = try #require(drawnAs(element))
            for (code, value) in piece.points {
                #expect(abs((member.number(code) ?? .nan) - value * factor) < 1e-6)
            }
        }
    }
}
