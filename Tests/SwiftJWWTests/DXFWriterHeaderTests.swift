import Foundation
import Testing

@testable import SwiftJWW

@Suite("DXF writer: the header and its length unit")
struct DXFWriterHeaderTests {
    let helper = DXFWriterTests()

    /// One of each kind of entity, a block with an insert of it, and a dimension record.
    var mixed: JWW.Drawing {
        let line = helper.line(0, 0, 10, 5)
        let arc = JWW.Entity.arc(
            center: .init(x: 1, y: 2), radius: 3, start: 0, sweep: .pi, tilt: 0, ratio: 1,
            full: false, layer: 0, color: 1)
        let circle = JWW.Entity.arc(
            center: .init(x: 1, y: 2), radius: 3, start: 0, sweep: 2 * .pi, tilt: 0, ratio: 1,
            full: true, layer: 0, color: 1)
        let ellipse = JWW.Entity.arc(
            center: .init(x: 1, y: 2), radius: 4, start: 0, sweep: 2 * .pi, tilt: 0, ratio: 0.5,
            full: true, layer: 0, color: 1)
        let insert = JWW.Entity.insert(
            def: 7, at: .init(x: 2, y: 3), scaleX: 1, scaleY: 1, rotationRad: 0, layer: 0, color: 1)
        let def = JWW.BlockDef(number: 7, name: "box", elements: [.init(entity: line)])
        let entities: [JWW.Entity] = [
            line, arc, circle, ellipse, helper.dot(1, 2), helper.text("A", 1, 2), insert,
        ]
        var elements: [JWW.Element] = entities.map { JWW.Element(entity: $0) }
        elements.append(helper.record(length: 10, label: "500"))
        return helper.drawing(elements, blocks: [7: def], scales: [0: 80])
    }

    /// The names of the sections in the order the text has them.
    func sections(_ text: String) -> [String] {
        let lines: [String] = text.components(separatedBy: "\n")
        var names: [String] = []
        var index = 2
        while index + 1 < lines.count {
            let isRecord: Bool = lines[index - 2] == "0" && lines[index - 1] == "SECTION"
            let isName: Bool = lines[index] == "2"
            if isRecord && isName { names.append(lines[index + 1]) }
            index += 2
        }
        return names
    }

    // MARK: the unit

    @Test("the header declares millimetres")
    func declaresMillimetres() throws {
        let dxf = try ReferenceDXF(text: DXFWriter.string(helper.drawing([])))
        #expect(dxf.header["$INSUNITS"]?[70] == "4")
    }

    @Test("full size and drawn coordinates are both declared in millimetres")
    func sameUnitWithAndWithoutFullSize() throws {
        let dwg = helper.drawing([.init(entity: helper.line(0, 0, 10, 5))], scales: [0: 80])
        let drawn = try ReferenceDXF(text: DXFWriter.string(dwg))
        let full = try ReferenceDXF(text: DXFWriter.string(dwg, options: .init(fullSize: true)))
        #expect(drawn.header["$INSUNITS"]?[70] == "4")
        #expect(full.header["$INSUNITS"]?[70] == "4")
        // The unit is the same and the numbers differ: paper millimetres at 1:80, then real ones.
        #expect(drawn.entities.first?.number(11) == 10)
        #expect(full.entities.first?.number(11) == 800)
    }

    @Test("every drawing and every option declares the unit")
    func anyDrawingAnyOptions() throws {
        let options: [DXFWriter.Options] = [
            .init(), .init(fullSize: true), .init(recoversDimensions: true),
            .init(fullSize: true, recoversDimensions: true),
        ]
        let bare = JWW.Drawing(version: 700, entities: [helper.line(0, 0, 1, 1)], counts: .init())
        let drawings: [(name: String, drawing: JWW.Drawing)] = [
            ("empty", helper.drawing([])), ("bare entities", bare), ("mixed", mixed),
        ]
        for (name, dwg) in drawings {
            for option in options {
                let dxf = try ReferenceDXF(text: DXFWriter.string(dwg, options: option))
                let unit = dxf.header["$INSUNITS"]?[70]
                #expect(unit == "4", "\(name) drawing with \(option)")
            }
        }
    }

    @Test("the file written by write(_:to:) declares it too")
    func writtenFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DXFWriterHeaderTests-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        try DXFWriter.write(mixed, to: url)
        let dxf = try ReferenceDXF(contentsOf: url)
        #expect(dxf.header["$INSUNITS"]?[70] == "4")
    }

    // MARK: the rest of the output

    @Test("the header is the first section, after the comment and before the tables")
    func headerFirst() {
        let text = DXFWriter.string(mixed)
        #expect(sections(text) == ["HEADER", "TABLES", "BLOCKS", "ENTITIES"])
        #expect(
            text.hasPrefix(
                "999\nSwiftJWW\n0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n4\n0\nENDSEC\n"
                    + "0\nSECTION\n2\nTABLES\n"))
    }

    @Test("the sections after the header hold the entities, blocks and layers of the drawing")
    func restOfTheFile() throws {
        let dxf = try ReferenceDXF(text: DXFWriter.string(mixed))
        #expect(
            dxf.entities.map(\.type)
                == ["LINE", "ARC", "CIRCLE", "ELLIPSE", "POINT", "TEXT", "INSERT", "DIMENSION"])
        #expect(Set(dxf.entities.map(\.layer)) == ["0-0", "0-3"])
        #expect(dxf.layers.map { $0.text(2) } == ["0", "0-0", "0-3"])
        #expect(dxf.blocks["BLK7"]?.map(\.type) == ["LINE"])
        let name = try #require(dxf.entities.last?.text(2))
        #expect(dxf.blocks[name]?.count == 6)
    }
}
