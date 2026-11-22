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

    /// A drawing with a layer that has a JWW name, so the tables also hold an application record.
    var named: JWW.Drawing {
        var groups: [JWW.LayerGroup] = (0..<16).map { JWW.LayerGroup(index: $0, scale: 1) }
        groups[0].layers = [JWW.Layer(index: 14, name: "寸法")]
        let attributes = JWW.Attributes(layerGroup: 0, layer: 14)
        let element = JWW.Element(
            entity: helper.line(0, 0, 1, 1, layer: 14), attributes: attributes)
        return JWW.Drawing(
            version: 700, elements: [element], blocks: [:], counts: .init(), layerGroups: groups)
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

    /// The handle (group 5) of a record, or `nil` when it has none.
    func handle(of record: ReferenceDXF.Entity) -> Int? {
        guard let text = record.text(5) else { return nil }
        return Int(text.trimmingCharacters(in: .whitespaces), radix: 16)
    }

    /// The highest handle of the table, block and entity records, or `nil` for none.
    func highestHandle(_ dxf: ReferenceDXF) -> Int? {
        let records: [ReferenceDXF.Entity] = dxf.entities + dxf.blockRecords + dxf.tableRecords
        let handles: [Int] = records.compactMap { handle(of: $0) }
        return handles.max()
    }

    // MARK: the unit and the version

    @Test("the header declares millimetres")
    func declaresMillimetres() throws {
        let dxf = try ReferenceDXF(text: DXFWriter.string(helper.drawing([])))
        #expect(dxf.header["$INSUNITS"]?[70] == "4")
    }

    @Test("the header declares R12, the version Jw_cad's own export declares")
    func declaresVersion() throws {
        let dxf = try ReferenceDXF(text: DXFWriter.string(helper.drawing([])))
        #expect(dxf.header["$ACADVER"]?[1] == "AC1009")
    }

    @Test("no record carries a subclass marker, which R12 does not have")
    func noSubclassMarkers() throws {
        let dxf = try ReferenceDXF(text: DXFWriter.string(mixed))
        let records: [ReferenceDXF.Entity] = dxf.entities + dxf.blockRecords + dxf.tableRecords
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0.groups[100] == nil })
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

    @Test("every drawing and every option declares the version, the unit and the handles")
    func anyDrawingAnyOptions() throws {
        let options: [DXFWriter.Options] = [
            .init(), .init(fullSize: true), .init(recoversDimensions: true),
            .init(fullSize: true, recoversDimensions: true),
        ]
        let bare = JWW.Drawing(version: 700, entities: [helper.line(0, 0, 1, 1)], counts: .init())
        let sample: [JWW.Element] = DXFWriterRecoveryTests().sample
        let recovered: JWW.Drawing = DimensionTests().drawing(sample)
        var drawings: [(name: String, drawing: JWW.Drawing)] = []
        drawings.append((name: "empty", drawing: helper.drawing([])))
        drawings.append((name: "bare entities", drawing: bare))
        drawings.append((name: "mixed", drawing: mixed))
        drawings.append((name: "loose dimension", drawing: recovered))
        drawings.append((name: "named layer", drawing: named))
        for (name, dwg) in drawings {
            for option in options {
                let dxf = try ReferenceDXF(text: DXFWriter.string(dwg, options: option))
                let label = "\(name) drawing with \(option)"
                #expect(dxf.header["$INSUNITS"]?[70] == "4", "\(label)")
                #expect(dxf.header["$ACADVER"]?[1] == "AC1009", "\(label)")
                #expect(dxf.header["$HANDLING"]?[70] == "1", "\(label)")
                let seed = Int(dxf.header["$HANDSEED"]?[5] ?? "", radix: 16)
                let highest = highestHandle(dxf)
                #expect(seed != nil, "\(label)")
                #expect((seed ?? 0) > (highest ?? 0), "\(label)")
            }
        }
    }

    @Test("the handle seed is above the handles of a recovered dimension and of its block")
    func seedAboveRecoveredDimension() throws {
        let sample: [JWW.Element] = DXFWriterRecoveryTests().sample
        let dwg: JWW.Drawing = DimensionTests().drawing(sample)
        let output = DXFWriter.output(dwg, options: .init(recoversDimensions: true))
        #expect(output.report.recoveredDimensions.count == 1)
        let dxf = try ReferenceDXF(text: output.text)
        let seed = Int(dxf.header["$HANDSEED"]?[5] ?? "", radix: 16) ?? 0
        let dimension = try #require(dxf.entities.first)
        let name = try #require(dimension.text(2))
        let blockHandles: [Int] = (dxf.blocks[name] ?? []).compactMap { handle(of: $0) }
        #expect(blockHandles.count == 6)
        #expect(blockHandles.allSatisfy { $0 < seed })
        #expect((handle(of: dimension) ?? seed) < seed)
        // The tables take the last handles, and the seed is the one after them.
        #expect(seed == (highestHandle(dxf) ?? 0) + 1)
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
        #expect(sections(DXFWriter.string(mixed)) == ["HEADER", "TABLES", "BLOCKS", "ENTITIES"])
    }

    @Test("the header is these bytes, with the handle after the linetype and layer 0 as the seed")
    func headerBytes() {
        // The linetype has handle 1 and layer 0 handle 2, so 3 is the next free handle.
        let text = DXFWriter.string(helper.drawing([]))
        #expect(
            text.hasPrefix(
                "999\nSwiftJWW\n0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n"
                    + "9\n$INSUNITS\n70\n4\n9\n$HANDLING\n70\n1\n9\n$HANDSEED\n5\n3\n"
                    + "0\nENDSEC\n0\nSECTION\n2\nTABLES\n"))
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
