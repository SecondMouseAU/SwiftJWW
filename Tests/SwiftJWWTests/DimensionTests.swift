import Foundation
import Testing

@testable import SwiftJWW

@Suite("Dimensions")
struct DimensionTests {
    typealias Builder = SwiftJWWTests.Builder

    // MARK: dimension record

    @Test("a dimension record reads as one dimension with its points, lines and value")
    func recordView() throws {
        var b = Builder()
        b.header(scales: [1: 50])
        b.u16(1)
        b.classTag("CDataSunpou")
        b.base(layer: 3, layerGroup: 1)
        b.senFields(0, 0, 10, 0)  // dimension line
        b.mojiFields("1,930", x: 5, y: 1)
        b.u16(0)  // SXF mode
        b.senFields(0, 0, 0, 2)
        b.senFields(10, 0, 10, 2)  // extension lines
        b.tenFields(0, 0)
        b.tenFields(10, 0)  // arrow points
        b.tenFields(0, 0.5)
        b.tenFields(10, 0.5)  // reference points
        let dwg = try JWW.read(data: b.d)
        let element = try #require(dwg.elements.first)
        let dim = try #require(element.dimension)
        #expect(dim.attributes.layer == 3 && dim.attributes.layerGroup == 1)
        #expect(dim.dimensionLine == .init(a: .init(x: 0, y: 0), b: .init(x: 10, y: 0)))
        #expect(dim.label.string == "1,930" && dim.label.at == .init(x: 5, y: 1))
        #expect(dim.value == 1930)
        #expect(dim.extensionLines.count == 2)
        #expect(dim.arrowPoints == [.init(x: 0, y: 0), .init(x: 10, y: 0)])
        #expect(dim.measuredPoints == [.init(x: 0, y: 0.5), .init(x: 10, y: 0.5)])
        #expect(dim.measuredDistance == 10)
        let scale = try #require(dwg.scale(ofLayerGroup: dim.attributes.layerGroup))
        #expect(scale == 50)
        #expect(dwg.counts.dim == 1)
    }

    @Test("a dimension without the version 4.20 parts has a line and text only")
    func olderRecord() throws {
        let e = JWW.Element(
            entity: .dimension(
                parts: [
                    .line(a: .init(x: 0, y: 0), b: .init(x: 4, y: 0), layer: 0, color: 1),
                    .text(
                        at: .init(x: 2, y: 1), height: 2, width: 2, angleRad: 0, string: "R5",
                        layer: 0, color: 1),
                ], layer: 0))
        let dim = try #require(e.dimension)
        #expect(dim.value == 5)
        #expect(dim.extensionLines.isEmpty && dim.arrowPoints.isEmpty)
        #expect(dim.measuredPoints.isEmpty && dim.measuredDistance == nil)
    }

    @Test("only a dimension entity has a dimension view")
    func notADimension() {
        #expect(
            JWW.Element(entity: .point(at: .init(x: 0, y: 0), layer: 0, color: 1)).dimension == nil)
    }

    // MARK: value text

    @Test("the number in dimension text is read through prefixes, commas and units")
    func parseValue() {
        #expect(JWW.Dimension.parseValue("1,930") == 1930)
        #expect(JWW.Dimension.parseValue("φ12.5") == 12.5)
        #expect(JWW.Dimension.parseValue("R5mm") == 5)
        #expect(JWW.Dimension.parseValue("\u{FF12}\u{FF10}\u{FF10}") == 200)
        #expect(JWW.Dimension.parseValue("-3") == -3)
        #expect(JWW.Dimension.parseValue("838.2φ") == 838.2)
        #expect(JWW.Dimension.parseValue("abc") == nil)
        #expect(JWW.Dimension.parseValue("") == nil)
    }

    @Test("the rounding tolerance is one unit of the last decimal place")
    func roundingTolerance() {
        #expect(abs(JWW.Dimension.roundingTolerance(of: "1,930") - 1) < 1e-6)
        #expect(abs(JWW.Dimension.roundingTolerance(of: "12.5") - 0.1) < 1e-6)
        #expect(abs(JWW.Dimension.roundingTolerance(of: "838.25φ") - 0.01) < 1e-6)
    }

    // MARK: recovery from loose entities

    func drawing(_ elements: [JWW.Element], scale: Double = 80) -> JWW.Drawing {
        let groups = (0..<16).map { JWW.LayerGroup(index: $0, scale: scale) }
        return JWW.Drawing(
            version: 700, elements: elements, blocks: [:], counts: .init(), layerGroups: groups)
    }

    func valueText(_ s: String, _ x: Double, _ y: Double, flags: Int = 0x4010) -> JWW.Element {
        JWW.Element(
            entity: .text(
                at: .init(x: x, y: y), height: 2.5, width: 2.5, angleRad: 0, string: s, layer: 14,
                color: 1), attributes: .init(layer: 14, flags: flags))
    }

    func arrow(_ x: Double, _ y: Double) -> JWW.Element {
        JWW.Element(
            entity: .point(at: .init(x: x, y: y), layer: 14, color: 1),
            attributes: .init(layer: 14, flags: 0x3D40))
    }

    func dimLine(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> JWW.Element {
        JWW.Element(
            entity: .line(a: .init(x: ax, y: ay), b: .init(x: bx, y: by), layer: 14, color: 1),
            attributes: .init(layer: 14, flags: 0x2000))
    }

    @Test("a value text is paired with the arrow points at its stated distance")
    func recoversLinear() throws {
        // 10 drawn units at 1:80 is 800.
        let dwg = drawing([
            dimLine(0, 0, 10, 0), dimLine(0, 0, 0, 3), dimLine(10, 0, 10, 3), arrow(0, 0),
            arrow(10, 0), valueText("800", 4, 1),
        ])
        let result = dwg.recoveringDimensions()
        #expect(result.unmatchedValues.isEmpty)
        let found = try #require(result.dimensions.first)
        #expect(result.dimensions.count == 1)
        #expect(found.dimension.value == 800)
        #expect(found.dimension.measuredPoints == [.init(x: 0, y: 0), .init(x: 10, y: 0)])
        #expect(found.dimension.measuredDistance == 10)
        #expect(found.dimension.extensionLines.count == 2)
        #expect(found.elementIndices == [0, 1, 2, 3, 4, 5])
    }

    @Test("the pair nearest the text wins when two pairs share a distance")
    func nearestPair() throws {
        let dwg = drawing([
            arrow(0, 0), arrow(10, 0), arrow(0, 20), arrow(10, 20), valueText("800", 4, 21),
        ])
        let found = try #require(dwg.recoveringDimensions().dimensions.first)
        #expect(found.dimension.arrowPoints.map(\.y) == [20, 20])
    }

    @Test("a chain does not pair a total with points that have another between")
    func chainAdjacency() {
        let dwg = drawing([
            arrow(0, 0), arrow(5, 0), arrow(10, 0), valueText("400", 2, 1), valueText("400", 7, 1),
            valueText("800", 4, 3),
        ])
        let result = dwg.recoveringDimensions()
        #expect(result.dimensions.count == 2)
        #expect(result.unmatchedValues == [5])
    }

    @Test("a rounded up or truncated value still matches within a unit")
    func roundedValue() {
        // 558.499 drawn at 1:80 is stated as 559.
        let dwg = drawing([arrow(0, 0), arrow(558.499 / 80, 0), valueText("559", 3, 1)])
        #expect(dwg.recoveringDimensions().dimensions.count == 1)
    }

    @Test("decimal places narrow the tolerance")
    func decimalTolerance() {
        let dwg = drawing([arrow(0, 0), arrow(838.0 / 80, 0), valueText("838.2", 3, 1)])
        let result = dwg.recoveringDimensions()
        #expect(result.dimensions.isEmpty && result.unmatchedValues == [2])
    }

    @Test("an exact duplicate text is folded into the dimension it repeats")
    func duplicateText() throws {
        let dwg = drawing([
            arrow(0, 0), arrow(10, 0), valueText("800", 4, 1), valueText("800", 4, 1),
        ])
        let result = dwg.recoveringDimensions()
        #expect(result.dimensions.count == 1 && result.unmatchedValues.isEmpty)
        #expect(try #require(result.dimensions.first).elementIndices == [0, 1, 2, 3])
    }

    typealias Piece = JWW.RecoveredDimension.Piece

    @Test("each piece of a recovered dimension has its role, in the order of the indices")
    func pieceRoles() throws {
        let dwg = drawing([
            dimLine(0, 0, 10, 0), dimLine(0, 0, 0, 3), dimLine(10, 0, 10, 3), arrow(0, 0),
            arrow(10, 0), valueText("800", 4, 1), valueText("800", 4, 1),
        ])
        let found = try #require(dwg.recoveringDimensions().dimensions.first)
        #expect(
            found.pieces == [
                Piece(index: 0, role: .dimensionLine), Piece(index: 1, role: .extensionLine),
                Piece(index: 2, role: .extensionLine), Piece(index: 3, role: .arrowPoint),
                Piece(index: 4, role: .arrowPoint), Piece(index: 5, role: .valueText),
                Piece(index: 6, role: .valueTextCopy),
            ])
        #expect(found.pieces.map(\.index) == found.elementIndices)
        let witness = found.pieces.filter { $0.role == .extensionLine }
        #expect(witness.count == found.dimension.extensionLines.count)
    }

    @Test("a piece two chained dimensions share has its role in each")
    func sharedPieceRoles() throws {
        // Arrow points 0 to 2, values 3 and 4, then a witness line at each of x = 5 (shared), 0
        // and 10, and the dimension line of each half.
        let dwg = drawing([
            arrow(0, 0), arrow(5, 0), arrow(10, 0), valueText("400", 2, 1), valueText("400", 7, 1),
            dimLine(5, 0, 5, 3), dimLine(0, 0, 0, 3), dimLine(10, 0, 10, 3), dimLine(0, 0, 5, 0),
            dimLine(5, 0, 10, 0),
        ])
        let found = dwg.recoveringDimensions().dimensions
        #expect(found.count == 2)
        #expect(
            found[0].pieces == [
                Piece(index: 0, role: .arrowPoint), Piece(index: 1, role: .arrowPoint),
                Piece(index: 3, role: .valueText), Piece(index: 5, role: .extensionLine),
                Piece(index: 6, role: .extensionLine), Piece(index: 8, role: .dimensionLine),
            ])
        #expect(
            found[1].pieces == [
                Piece(index: 1, role: .arrowPoint), Piece(index: 2, role: .arrowPoint),
                Piece(index: 4, role: .valueText), Piece(index: 5, role: .extensionLine),
                Piece(index: 7, role: .extensionLine), Piece(index: 9, role: .dimensionLine),
            ])
    }

    /// Two 800 dimensions from the same corner, one along x and one along y, and the line between
    /// the corner and the end of the second: an extension line of the first, the dimension line of
    /// the second.
    var corner: JWW.Drawing {
        drawing([
            arrow(0, 0), arrow(10, 0), arrow(0, 10), valueText("800", 4, 1),
            valueText("800", -1, 5), dimLine(0, 0, 0, 10),
        ])
    }

    @Test("the element indices are those of the pieces, in ascending order, whatever the drawing")
    func indicesAreThoseOfThePieces() throws {
        let drawings = [
            corner,
            drawing([
                arrow(0, 0), arrow(5, 0), arrow(10, 0), valueText("400", 2, 1),
                valueText("400", 7, 1), dimLine(5, 0, 5, 3), dimLine(0, 0, 5, 0),
            ]),
            drawing([
                arrow(0, 0), arrow(10, 0), valueText("800", 4, 1), valueText("800", 4, 1),
                dimLine(0, 0, 10, 0), dimLine(0, 0, 0, 3),
            ]),
        ]
        var seen = 0
        for dwg in drawings {
            for found in dwg.recoveringDimensions().dimensions {
                seen += 1
                #expect(found.elementIndices == found.pieces.map(\.index))
                #expect(found.elementIndices == found.elementIndices.sorted())
                #expect(Set(found.elementIndices).count == found.elementIndices.count)
            }
        }
        #expect(seen == 5)
    }

    @Test("a piece two dimensions share can be a different thing to each")
    func differentRoleInEach() throws {
        let found = corner.recoveringDimensions().dimensions
        #expect(found.count == 2)
        let along = try #require(found.first { $0.elementIndices.contains(3) })
        let up = try #require(found.first { $0.elementIndices.contains(4) })
        #expect(along.pieces.contains(Piece(index: 5, role: .extensionLine)))
        #expect(up.pieces.contains(Piece(index: 5, role: .dimensionLine)))
        #expect(along.pieces.contains(Piece(index: 0, role: .arrowPoint)))
        #expect(up.pieces.contains(Piece(index: 0, role: .arrowPoint)))
    }

    @Test("every repeat of a value text at the same place is a copy")
    func manyCopies() throws {
        let dwg = drawing([
            arrow(0, 0), arrow(10, 0), valueText("800", 4, 1), valueText("800", 4, 1),
            valueText("800", 4, 1),
        ])
        let found = try #require(dwg.recoveringDimensions().dimensions.first)
        #expect(
            found.pieces.suffix(3) == [
                Piece(index: 2, role: .valueText), Piece(index: 3, role: .valueTextCopy),
                Piece(index: 4, role: .valueTextCopy),
            ])
    }

    @Test("a line is a dimension line or an extension line by the recovery's parallel threshold")
    func roleAtTheParallelThreshold() throws {
        // Two lines of length 0.5 from the first arrow point, which is 10 from the second. The
        // first rises 0.00045, a sine of 0.0009 to the dimension line, which is under the 0.001
        // the recovery takes as parallel. The second rises 0.00055, a sine of 0.0011.
        let dwg = drawing([
            arrow(0, 0), arrow(10, 0), valueText("800", 4, 1), dimLine(0, 0, 0.5, 0.00045),
            dimLine(0, 0, 0.5, 0.00055),
        ])
        let found = try #require(dwg.recoveringDimensions().dimensions.first)
        #expect(
            found.pieces.suffix(2) == [
                Piece(index: 3, role: .dimensionLine), Piece(index: 4, role: .extensionLine),
            ])
    }

    /// How many times each value text of `dwg` is in a recovered dimension or in the unexplained
    /// values, which is once for each text when nothing drops out and nothing is counted twice.
    func placements(_ dwg: JWW.Drawing, _ result: JWW.DimensionRecovery) -> [Int: Int] {
        var count: [Int: Int] = [:]
        for found in result.dimensions {
            for i in found.elementIndices { count[i, default: 0] += 1 }
        }
        for i in result.unmatchedValues { count[i, default: 0] += 1 }
        var texts: [Int: Int] = [:]
        for (i, element) in dwg.elements.enumerated() {
            if case .text = element.entity, element.attributes.flags & 0x4010 == 0x4010 {
                texts[i] = count[i] ?? 0
            }
        }
        return texts
    }

    @Test("a duplicate of an unexplained value text is listed as unexplained too")
    func duplicateOfUnexplained() {
        // 999 has no pair of arrow points at that distance, and is stored twice at one place.
        let dwg = drawing([
            arrow(0, 0), arrow(10, 0), valueText("800", 4, 1), valueText("999", 4, 3),
            valueText("999", 4, 3),
        ])
        let result = dwg.recoveringDimensions()
        #expect(result.dimensions.count == 1)
        #expect(result.dimensions.first?.elementIndices == [0, 1, 2])
        #expect(result.unmatchedValues == [3, 4])
        #expect(placements(dwg, result).values.allSatisfy { $0 == 1 })
    }

    @Test("every value text is in exactly one place, whatever copies of it there are")
    func everyValueTextInOnePlace() {
        let dwg = drawing([
            arrow(0, 0), arrow(10, 0),
            valueText("800", 4, 1), valueText("800", 4, 1),  // explained, twice
            valueText("999", 4, 3), valueText("999", 4, 3), valueText("999", 4, 3),  // three times
            valueText("R5", 4, 5, flags: 0x4110), valueText("R5", 4, 5, flags: 0x4110),
            valueText("999", 9, 3),  // the same text somewhere else is not a copy
        ])
        let result = dwg.recoveringDimensions()
        #expect(result.unmatchedValues == [4, 5, 6, 7, 8, 9])
        let counts = placements(dwg, result)
        #expect(counts.count == 8)
        #expect(counts.values.allSatisfy { $0 == 1 })
    }

    @Test("radius, diameter and angle values and unexplained values are listed, not guessed")
    func unmatched() {
        let dwg = drawing([
            arrow(0, 0), arrow(10, 0), valueText("R5", 4, 1, flags: 0x4110),
            valueText("18", 4, 2, flags: 0x4410), valueText("999", 4, 3), valueText("text", 4, 4),
        ])
        let result = dwg.recoveringDimensions()
        #expect(result.dimensions.isEmpty)
        #expect(result.unmatchedValues == [2, 3, 4, 5])
    }

    @Test("pieces that are not marked as dimensions are left alone")
    func unflagged() {
        let plain = JWW.Element(
            entity: .point(at: .init(x: 0, y: 0), layer: 0, color: 1), attributes: .init())
        let plain2 = JWW.Element(
            entity: .point(at: .init(x: 10, y: 0), layer: 0, color: 1), attributes: .init())
        let dwg = drawing([plain, plain2, valueText("800", 4, 1, flags: 0)])
        let result = dwg.recoveringDimensions()
        #expect(result.dimensions.isEmpty && result.unmatchedValues.isEmpty)
    }

    @Test("the scale of the text's layer group decides the distance")
    func usesLayerGroupScale() {
        var groups = (0..<16).map { JWW.LayerGroup(index: $0, scale: 80) }
        groups[2].scale = 50
        var text = valueText("500", 4, 1)
        text.attributes.layerGroup = 2
        var a = arrow(0, 0)
        var b = arrow(10, 0)
        a.attributes.layerGroup = 2
        b.attributes.layerGroup = 2
        let dwg = JWW.Drawing(
            version: 700, elements: [a, b, text], blocks: [:], counts: .init(), layerGroups: groups)
        #expect(dwg.recoveringDimensions().dimensions.count == 1)
    }
}
