import Foundation
import Testing

@testable import SwiftJWW

@Suite("DXF writer: recovered dimensions")
struct DXFWriterRecoveryTests {
    let dimensions = DimensionTests()
    let writer = DXFWriterTests()
    let recover = DXFWriter.Options(recoversDimensions: true)

    /// A recovered dimension of 10 drawn units at 1:80 (800): the dimension line, both witness
    /// lines, both arrow points and the value text.
    var sample: [JWW.Element] {
        [
            dimensions.dimLine(0, 0, 10, 0), dimensions.dimLine(0, 0, 0, 3),
            dimensions.dimLine(10, 0, 10, 3), dimensions.arrow(0, 0), dimensions.arrow(10, 0),
            dimensions.valueText("800", 4, 1),
        ]
    }

    func measurement(_ d: ReferenceDXF.Entity) throws -> Double {
        try writer.measurement(d)
    }

    @Test("recovered dimensions are written as DIMENSION entities when asked")
    func writesDimension() throws {
        let output = DXFWriter.output(dimensions.drawing(sample), options: recover)
        let dxf = try ReferenceDXF(text: output.text)
        #expect(dxf.entities.map(\.type) == ["DIMENSION"])
        let d = try #require(dxf.entities.first)
        #expect(d.layer == "0-E")
        #expect(d.text(1) == "800")
        #expect(d.number(70) == 0)
        // The witness lines run up from the dimension line, so the measured points are their far ends.
        #expect(d.number(13) == 0 && d.number(23) == 3)
        #expect(d.number(14) == 10 && d.number(24) == 3)
        #expect(d.number(10) == 5 && d.number(20) == 0)
        #expect(d.number(50) == 0)
        #expect(d.number(11) == 4 && d.number(21) == 1)
    }

    @Test("the pieces are in the anonymous block, not loose")
    func piecesInBlock() throws {
        let dxf = try ReferenceDXF(
            text: DXFWriter.string(dimensions.drawing(sample), options: recover))
        let name = try #require(dxf.entities.first?.text(2))
        let members = try #require(dxf.blocks[name])
        #expect(members.map(\.type).sorted() == ["LINE", "LINE", "LINE", "POINT", "POINT", "TEXT"])
        #expect(members.allSatisfy { $0.layer == "0-E" })
    }

    @Test("without the option the pieces are written as they were, and the report is empty")
    func offByDefault() throws {
        let output = DXFWriter.output(dimensions.drawing(sample))
        let dxf = try ReferenceDXF(text: output.text)
        #expect(dxf.entities.map(\.type) == ["LINE", "LINE", "LINE", "POINT", "POINT", "TEXT"])
        #expect(dxf.blockRecords.isEmpty)
        #expect(output.report == DXFWriter.Report())
    }

    @Test("the report lists the DIMENSION handles it recovered")
    func reportHandles() throws {
        let dwg = dimensions.drawing(
            sample + [
                dimensions.arrow(0, 20), dimensions.arrow(5, 20),
                dimensions.valueText("400", 2, 21),
            ])
        let output = DXFWriter.output(dwg, options: recover)
        let dxf = try ReferenceDXF(text: output.text)
        let written = dxf.entities.filter { $0.type == "DIMENSION" }.compactMap { $0.text(5) }
        #expect(written.count == 2)
        #expect(output.report.recoveredDimensions == written)
        #expect(output.report.unexplainedValues.isEmpty)
    }

    @Test("a value no dimension explains stays a loose text and is reported with its index")
    func unexplained() throws {
        let dwg = dimensions.drawing(
            sample + [
                dimensions.valueText("999", 4, 5), dimensions.valueText("R5", 4, 7, flags: 0x4110),
            ])
        let output = DXFWriter.output(dwg, options: recover)
        let dxf = try ReferenceDXF(text: output.text)
        #expect(output.report.unexplainedValues == [6, 7])
        #expect(output.report.recoveredDimensions.count == 1)
        #expect(dxf.entities.map(\.type) == ["DIMENSION", "TEXT", "TEXT"])
        #expect(dxf.entities.dropFirst().map { $0.text(1) } == ["999", "R5"])
    }

    @Test("a dimension is written where its first piece was, among the other entities")
    func keepsOrder() throws {
        let before = JWW.Element(entity: writer.line(0, 0, 1, 1))
        let after = JWW.Element(entity: writer.line(2, 2, 3, 3))
        let dxf = try ReferenceDXF(
            text: DXFWriter.string(
                dimensions.drawing([before] + sample + [after]), options: recover))
        #expect(dxf.entities.map(\.type) == ["LINE", "DIMENSION", "LINE"])
    }

    @Test("with no witness line the arrow points are the measured points")
    func noWitnessLines() throws {
        let dwg = dimensions.drawing([
            dimensions.dimLine(0, 0, 10, 0), dimensions.arrow(0, 0), dimensions.arrow(10, 0),
            dimensions.valueText("800", 4, 1),
        ])
        let d = try #require(
            try ReferenceDXF(text: DXFWriter.string(dwg, options: recover)).entities.first)
        #expect(d.number(13) == 0 && d.number(23) == 0 && d.number(14) == 10 && d.number(24) == 0)
    }

    @Test("a slanted witness line that would change the measured length is not used")
    func slantedWitnessLine() throws {
        // The far end of the left line is 2 to the left of the arrow point, so the points it
        // would give measure 12 along the dimension line, not the 10 the arrows are apart.
        let dwg = dimensions.drawing([
            dimensions.dimLine(0, 0, 10, 0), dimensions.dimLine(0, 0, -2, 3),
            dimensions.dimLine(10, 0, 10, 3), dimensions.arrow(0, 0), dimensions.arrow(10, 0),
            dimensions.valueText("800", 4, 1),
        ])
        let d = try #require(
            try ReferenceDXF(text: DXFWriter.string(dwg, options: recover)).entities.first)
        #expect(try measurement(d) == 10)
    }

    @Test("a vertical dimension is rotated 90 degrees and measures along it")
    func verticalRecovered() throws {
        let dwg = dimensions.drawing([
            dimensions.dimLine(0, 0, 0, 10), dimensions.dimLine(0, 0, 3, 0),
            dimensions.dimLine(0, 10, 3, 10), dimensions.arrow(0, 0), dimensions.arrow(0, 10),
            dimensions.valueText("800", 1, 4),
        ])
        let d = try #require(
            try ReferenceDXF(text: DXFWriter.string(dwg, options: recover)).entities.first)
        #expect(d.number(50) == 90)
        #expect(try measurement(d) == 10)
    }

    @Test("at full size the measurement is the stated value, with no scale applied")
    func fullSizeMeasurement() throws {
        let dwg = dimensions.drawing(sample)
        let options = DXFWriter.Options(fullSize: true, recoversDimensions: true)
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg, options: options))
        let d = try #require(dxf.entities.first)
        #expect(abs(try measurement(d) - 800) < 1e-6)
        #expect(d.number(11) == 320 && d.number(21) == 80)
        let name = try #require(d.text(2))
        let members = try #require(dxf.blocks[name])
        #expect(members.first { $0.type == "TEXT" }?.number(40) == 200)
    }

    @Test("without full size the measurement times the scale is the stated value")
    func drawnMeasurement() throws {
        let d = try #require(
            try ReferenceDXF(text: DXFWriter.string(dimensions.drawing(sample), options: recover))
                .entities.first)
        #expect(abs(try measurement(d) * 80 - 800) < 1e-6)
    }

    @Test("two dimensions that share an arrow point each keep it in their own block")
    func sharedPiece() throws {
        let dwg = dimensions.drawing([
            dimensions.arrow(0, 0), dimensions.arrow(5, 0), dimensions.arrow(10, 0),
            dimensions.valueText("400", 2, 1), dimensions.valueText("400", 7, 1),
        ])
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg, options: recover))
        #expect(dxf.entities.map(\.type) == ["DIMENSION", "DIMENSION"])
        let sizes = dxf.entities.compactMap { $0.text(2) }.map { dxf.blocks[$0]?.count }
        #expect(sizes == [3, 3])
        #expect(dxf.entities.contains { $0.type == "POINT" } == false)
    }

    @Test("the report and the DIMENSIONs are those of the 2120's kind of drawing: all explained")
    func nothingLeftLoose() throws {
        let dxf = try ReferenceDXF(
            text: DXFWriter.string(dimensions.drawing(sample), options: recover))
        #expect(dxf.entities.allSatisfy { $0.type == "DIMENSION" })
    }

    @Test("write returns the report")
    func writeReturnsReport() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swiftjww-\(UUID().uuidString).dxf")
        defer { try? FileManager.default.removeItem(at: url) }
        let report = try DXFWriter.write(dimensions.drawing(sample), to: url, options: recover)
        #expect(report.recoveredDimensions.count == 1)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\nDIMENSION\n"))
    }
}
