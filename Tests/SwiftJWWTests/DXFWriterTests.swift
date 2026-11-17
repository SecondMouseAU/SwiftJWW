import Foundation
import Testing

@testable import SwiftJWW

@Suite("DXF writer: dimension records and full size")
struct DXFWriterTests {
    typealias Point = JWW.Point

    func drawing(
        _ elements: [JWW.Element], blocks: [Int: JWW.BlockDef] = [:], scales: [Int: Double] = [:]
    ) -> JWW.Drawing {
        let groups = (0..<16).map { JWW.LayerGroup(index: $0, scale: scales[$0] ?? 1) }
        return JWW.Drawing(
            version: 700, elements: elements, blocks: blocks, counts: .init(), layerGroups: groups)
    }

    func line(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, layer: Int = 0)
        -> JWW.Entity
    {
        .line(a: Point(x: ax, y: ay), b: Point(x: bx, y: by), layer: layer, color: 1)
    }

    func text(_ s: String, _ x: Double, _ y: Double, height: Double = 2.5, layer: Int = 0)
        -> JWW.Entity
    {
        .text(
            at: Point(x: x, y: y), height: height, width: height, angleRad: 0, string: s,
            layer: layer, color: 1)
    }

    func dot(_ x: Double, _ y: Double, layer: Int = 0) -> JWW.Entity {
        .point(at: Point(x: x, y: y), layer: layer, color: 1)
    }

    /// A horizontal dimension record: the line at `y`, measured points 0.5 above it, from 0 to `length`.
    func record(length: Double, label: String, group: Int = 0, layer: Int = 3) -> JWW.Element {
        let parts: [JWW.Entity] = [
            line(0, 0, length, 0, layer: layer), text(label, length / 2, 1, layer: layer),
            line(0, 0, 0, 2, layer: layer), line(length, 0, length, 2, layer: layer),
            dot(0, 0, layer: layer), dot(length, 0, layer: layer), dot(0, 0.5, layer: layer),
            dot(length, 0.5, layer: layer),
        ]
        return JWW.Element(
            entity: .dimension(parts: parts, layer: layer),
            attributes: .init(layerGroup: group, layer: layer, color: 5))
    }

    func read(_ dxf: String) throws -> ReferenceDXF { try ReferenceDXF(text: dxf) }

    /// The measurement a DXF reader computes from a linear dimension: the distance between groups 13
    /// and 14 along group 50.
    func measurement(_ d: ReferenceDXF.Entity) throws -> Double {
        let ax = try #require(d.number(13))
        let ay = try #require(d.number(23))
        let bx = try #require(d.number(14))
        let by = try #require(d.number(24))
        let angle = (d.number(50) ?? 0) * .pi / 180
        return abs((bx - ax) * cos(angle) + (by - ay) * sin(angle))
    }

    // MARK: dimension records

    @Test("a dimension record is written as one rotated linear DIMENSION")
    func recordBecomesDimension() throws {
        let dxf = try read(DXFWriter.string(drawing([record(length: 38.6, label: "1,930")])))
        #expect(dxf.entities.map(\.type) == ["DIMENSION"])
        let d = try #require(dxf.entities.first)
        #expect(d.number(70) == 0)
        #expect(d.text(1) == "1,930")
        #expect(d.number(13) == 0 && d.number(23) == 0.5)
        #expect(d.number(14) == 38.6 && d.number(24) == 0.5)
        #expect(d.number(50) == 0)
        #expect(d.number(10) == 0 && d.number(20) == 0)
        #expect(d.number(11) == 19.3 && d.number(21) == 1)
        #expect(d.number(62) == 5)
        #expect(d.layer == "0-3")
    }

    @Test("the drawn parts go in the anonymous block the dimension names")
    func anonymousBlock() throws {
        let dxf = try read(DXFWriter.string(drawing([record(length: 10, label: "500")])))
        let name = try #require(dxf.entities.first?.text(2))
        #expect(name.hasPrefix("*D"))
        let members = try #require(dxf.blocks[name])
        // The dimension line, the text, two witness lines and two arrow points; the measured
        // points are groups 13 and 14, not drawn.
        #expect(members.map(\.type) == ["LINE", "TEXT", "LINE", "LINE", "POINT", "POINT"])
        let block = try #require(dxf.blockRecords.first { $0.type == "BLOCK" })
        #expect(block.number(70) == 1)
    }

    @Test("the block holds none of the points the reader takes as measured points")
    func blockExcludesMeasuredPoints() throws {
        let element = record(length: 10, label: "500")
        let parsed = try #require(JWW.Dimension(element))
        #expect(parsed.measuredPoints.map(\.y) == [0.5, 0.5])
        #expect(parsed.arrowPoints.map(\.y) == [0, 0])
        let dxf = try read(DXFWriter.string(drawing([element])))
        let name = try #require(dxf.entities.first?.text(2))
        let members = try #require(dxf.blocks[name])
        #expect(members.count == JWW.Dimension.PartLayout.drawn.count)
        #expect(!members.contains { $0.type == "POINT" && $0.number(20) == 0.5 })
    }

    @Test("a vertical dimension line gives a 90 degree rotation, measured along it")
    func verticalRotation() throws {
        let parts: [JWW.Entity] = [
            line(0, 0, 0, 20), text("1,000", 1, 10), line(0, 0, 2, 0), line(0, 20, 2, 20),
            dot(0, 0),
            dot(0, 20), dot(0.5, 0), dot(0.5, 20),
        ]
        let element = JWW.Element(
            entity: .dimension(parts: parts, layer: 0), attributes: .init())
        let d = try #require(read(DXFWriter.string(drawing([element]))).entities.first)
        #expect(d.number(50) == 90)
        #expect(try measurement(d) == 20)
    }

    @Test("the measurement times the layer group scale is the stated value")
    func measurementTimesScale() throws {
        // 38.6 drawn at 1:50 is 1,930.
        let dwg = drawing([record(length: 38.6, label: "1,930")], scales: [0: 50])
        let d = try #require(read(DXFWriter.string(dwg)).entities.first)
        #expect(abs(try measurement(d) * 50 - 1930) < 1e-4)
    }

    @Test("a record older than 4.20 keeps its decomposed output")
    func olderRecordDecomposed() throws {
        let element = JWW.Element(
            entity: .dimension(parts: [line(0, 0, 4, 0), text("R5", 2, 1)], layer: 0))
        let dxf = try read(DXFWriter.string(drawing([element])))
        #expect(dxf.entities.map(\.type) == ["LINE", "TEXT"])
        #expect(dxf.blockRecords.isEmpty)
    }

    @Test("a dimension inside a block definition names an anonymous block too")
    func recordInBlock() throws {
        let def = JWW.BlockDef(
            number: 4, name: "frame", elements: [record(length: 10, label: "500")])
        let dxf = try read(DXFWriter.string(drawing([], blocks: [4: def])))
        let inside = try #require(dxf.blocks["BLK4"])
        #expect(inside.map(\.type) == ["DIMENSION"])
        let name = try #require(inside.first?.text(2))
        #expect(dxf.blocks[name]?.count == 6)
    }

    @Test("each dimension gets its own block name")
    func uniqueBlockNames() throws {
        let dwg = drawing([record(length: 10, label: "500"), record(length: 20, label: "1,000")])
        let dxf = try read(DXFWriter.string(dwg))
        let names = dxf.entities.compactMap { $0.text(2) }
        #expect(names.count == 2 && Set(names).count == 2)
        #expect(names.allSatisfy { dxf.blocks[$0] != nil })
    }

    // MARK: full size

    @Test("drawn coordinates are kept unless full size is asked for")
    func drawnByDefault() throws {
        let dwg = drawing([.init(entity: line(0, 0, 10, 5))], scales: [0: 80])
        let l = try #require(read(DXFWriter.string(dwg)).entities.first)
        #expect(l.number(11) == 10 && l.number(21) == 5)
    }

    @Test("full size multiplies each element by the scale of its own layer group")
    func fullSizePerGroup() throws {
        let dwg = drawing(
            [
                JWW.Element(entity: line(0, 0, 10, 5), attributes: .init(layerGroup: 0)),
                JWW.Element(entity: line(0, 0, 10, 5), attributes: .init(layerGroup: 1)),
            ], scales: [0: 80, 1: 10])
        let lines = try read(DXFWriter.string(dwg, options: .init(fullSize: true))).entities
        #expect(lines[0].number(11) == 800 && lines[0].number(21) == 400)
        #expect(lines[1].number(11) == 100 && lines[1].number(21) == 50)
    }

    @Test("a part drawn at 1:10 has the bounds of the same part drawn at 1:1 once full size")
    func sameBoundsAsOneToOne() throws {
        func extent(_ dxf: ReferenceDXF) -> [Double] {
            var xs: [Double] = []
            var ys: [Double] = []
            for e in dxf.entities {
                for code in [10, 11] { if let v = e.number(code) { xs.append(v) } }
                for code in [20, 21] { if let v = e.number(code) { ys.append(v) } }
            }
            return [xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0]
        }
        let full = drawing([.init(entity: line(0, 0, 120, 80)), .init(entity: dot(30, 40))])
        let tenth = drawing(
            [.init(entity: line(0, 0, 12, 8)), .init(entity: dot(3, 4))], scales: [0: 10])
        let a = extent(try read(DXFWriter.string(full)))
        let b = extent(try read(DXFWriter.string(tenth, options: .init(fullSize: true))))
        #expect(a == b)
    }

    @Test("full size scales circles, arcs, ellipses, text and points")
    func fullSizeEntities() throws {
        let arc = JWW.Entity.arc(
            center: Point(x: 1, y: 2), radius: 3, start: 0, sweep: .pi, tilt: 0, ratio: 1,
            full: false, layer: 0, color: 1)
        let circle = JWW.Entity.arc(
            center: Point(x: 1, y: 2), radius: 3, start: 0, sweep: 2 * .pi, tilt: 0, ratio: 1,
            full: true, layer: 0, color: 1)
        let ellipse = JWW.Entity.arc(
            center: Point(x: 1, y: 2), radius: 4, start: 0, sweep: 2 * .pi, tilt: 0, ratio: 0.5,
            full: true, layer: 0, color: 1)
        let dwg = drawing(
            [arc, circle, ellipse, text("A", 1, 2, height: 2.5), dot(1, 2)].map {
                .init(entity: $0)
            },
            scales: [0: 20])
        let e = try read(DXFWriter.string(dwg, options: .init(fullSize: true))).entities
        #expect(e.map(\.type) == ["ARC", "CIRCLE", "ELLIPSE", "TEXT", "POINT"])
        #expect(e[0].number(10) == 20 && e[0].number(20) == 40 && e[0].number(40) == 60)
        #expect(e[0].number(50) == 0 && e[0].number(51) == 180)
        #expect(e[1].number(40) == 60)
        #expect(e[2].number(11) == 80 && e[2].number(40) == 0.5)
        #expect(e[3].number(10) == 20 && e[3].number(40) == 50)
        #expect(e[4].number(10) == 20 && e[4].number(20) == 40)
    }

    @Test("full size scales an insert's position and scale factors, not the block's members")
    func fullSizeInsert() throws {
        let def = JWW.BlockDef(number: 7, name: "box", elements: [.init(entity: line(0, 0, 5, 5))])
        let insert = JWW.Element(
            entity: .insert(
                def: 7, at: Point(x: 2, y: 3), scaleX: 1, scaleY: 0, rotationRad: 0, layer: 0,
                color: 1))
        let dxf = try read(
            DXFWriter.string(
                drawing([insert], blocks: [7: def], scales: [0: 10]), options: .init(fullSize: true)
            ))
        let i = try #require(dxf.entities.first)
        #expect(i.number(10) == 20 && i.number(20) == 30)
        #expect(i.number(41) == 10 && i.number(42) == 10)
        #expect(dxf.blocks["BLK7"]?.first?.number(11) == 5)
    }

    @Test("a dimension record at full size states its value with no scale applied")
    func fullSizeRecord() throws {
        let dwg = drawing([record(length: 38.6, label: "1,930")], scales: [0: 50])
        let dxf = try read(DXFWriter.string(dwg, options: .init(fullSize: true)))
        let d = try #require(dxf.entities.first)
        #expect(abs(try measurement(d) - 1930) < 1e-4)
        #expect(d.number(11) == 965 && d.number(21) == 50)
        let name = try #require(d.text(2))
        let members = try #require(dxf.blocks[name])
        #expect(members[0].number(11) == 1930)
        #expect(members[1].number(40) == 125)  // the text, 2.5 high, at 1:50
    }

    @Test("full size leaves a drawing with no layer groups as it is")
    func fullSizeWithoutGroups() throws {
        let dwg = JWW.Drawing(version: 700, entities: [line(0, 0, 10, 5)], counts: .init())
        let l = try #require(
            read(DXFWriter.string(dwg, options: .init(fullSize: true))).entities.first)
        #expect(l.number(11) == 10)
    }

    @Test("a layer group with a scale of zero is not used to multiply")
    func zeroScale() throws {
        let dwg = drawing([.init(entity: line(0, 0, 10, 5))], scales: [0: 0])
        let l = try #require(
            read(DXFWriter.string(dwg, options: .init(fullSize: true))).entities.first)
        #expect(l.number(11) == 10)
    }
}
