import Foundation
import Testing

@testable import SwiftJWW

@Suite("Block expansion")
struct BlockExpansionTests {
    func line(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> JWW.Element {
        JWW.Element(
            entity: .line(a: .init(x: ax, y: ay), b: .init(x: bx, y: by), layer: 1, color: 2))
    }

    func insert(
        _ def: Int, at: (Double, Double), sx: Double = 1, sy: Double = 1, rotation: Double = 0
    ) -> JWW.Element {
        JWW.Element(
            entity: .insert(
                def: def, at: .init(x: at.0, y: at.1), scaleX: sx, scaleY: sy,
                rotationRad: rotation, layer: 4, color: 3),
            attributes: .init(layerGroup: 2, layer: 4, lineType: 1, color: 3))
    }

    func drawing(_ top: [JWW.Element], blocks: [Int: [JWW.Element]]) -> JWW.Drawing {
        var defs: [Int: JWW.BlockDef] = [:]
        for (number, members) in blocks {
            defs[number] = JWW.BlockDef(number: number, name: "block\(number)", elements: members)
        }
        return JWW.Drawing(
            version: 700, elements: top, blocks: defs, counts: .init(), layerGroups: [])
    }

    func segment(_ e: JWW.Element) -> (a: JWW.Point, b: JWW.Point)? {
        guard case .line(let a, let b, _, _) = e.entity else { return nil }
        return (a, b)
    }

    func near(_ p: JWW.Point, _ x: Double, _ y: Double) -> Bool {
        abs(p.x - x) < 1e-9 && abs(p.y - y) < 1e-9
    }

    @Test("an insert is replaced by its members at the insertion point")
    func translation() throws {
        let dwg = drawing([insert(1, at: (10, 20))], blocks: [1: [line(0, 0, 1, 0)]])
        let result = dwg.expandingBlocks()
        #expect(result.unresolved.isEmpty && result.elements.count == 1)
        let element = try #require(result.elements.first)
        let seg = try #require(segment(element))
        #expect(near(seg.a, 10, 20) && near(seg.b, 11, 20))
        let ref = try #require(element.references.first)
        #expect(element.references.count == 1)
        #expect(ref.definition == 1 && ref.name == "block1" && ref.index == 0)
        #expect(ref.at == .init(x: 10, y: 20) && ref.attributes.layerGroup == 2)
    }

    @Test("scale applies before rotation, then the insertion point")
    func scaleAndRotation() throws {
        let dwg = drawing(
            [insert(1, at: (5, 5), sx: 2, sy: 2, rotation: .pi / 2)],
            blocks: [1: [line(1, 0, 2, 0)]])
        let element = try #require(dwg.expandingBlocks().elements.first)
        let seg = try #require(segment(element))
        #expect(near(seg.a, 5, 7) && near(seg.b, 5, 9))
    }

    @Test("X and Y scale are independent and a zero scale reads as 1")
    func independentScale() throws {
        let dwg = drawing(
            [insert(1, at: (0, 0), sx: 2, sy: 3), insert(1, at: (0, 0), sx: 0, sy: 0)],
            blocks: [1: [line(1, 1, 2, 2)]])
        let out = dwg.expandingBlocks().elements.compactMap(segment)
        #expect(near(out[0].a, 2, 3) && near(out[0].b, 4, 6))
        #expect(near(out[1].a, 1, 1) && near(out[1].b, 2, 2))
    }

    @Test("members replace the insert in place, keeping file order around them")
    func order() {
        let dwg = drawing(
            [line(0, 0, 1, 1), insert(1, at: (0, 0)), line(5, 5, 6, 6)],
            blocks: [1: [line(7, 7, 8, 8), line(9, 9, 10, 10)]])
        let out = dwg.expandingBlocks().elements
        #expect(out.map { $0.references.count } == [0, 1, 1, 0])
        #expect(out.compactMap(segment).map { $0.a.x } == [0, 7, 9, 5])
        #expect(out.map { $0.references.first?.index } == [nil, 1, 1, nil])
    }

    @Test("top-level objects pass through unchanged")
    func passThrough() throws {
        let arc = JWW.Element(
            entity: .arc(
                center: .init(x: 1, y: 2), radius: 3, start: 0.1, sweep: 1, tilt: 0.7, ratio: 0.5,
                full: false, layer: 0, color: 1))
        let out = try #require(drawing([arc], blocks: [:]).expandingBlocks().elements.first)
        guard case .arc(_, let r, let start, _, let tilt, let ratio, _, _, _) = out.entity else {
            Issue.record("not an arc")
            return
        }
        #expect(r == 3 && start == 0.1 && tilt == 0.7 && ratio == 0.5)
    }

    @Test("nested blocks compose, and each member lists its references outermost first")
    func nested() throws {
        // Block 1: a unit line. Block 2: block 1 at (10,0) doubled. Drawing: block 2 turned 90 degrees.
        let dwg = drawing(
            [insert(2, at: (0, 100), rotation: .pi / 2)],
            blocks: [1: [line(0, 0, 1, 0)], 2: [insert(1, at: (10, 0), sx: 2, sy: 2)]])
        let result = dwg.expandingBlocks()
        let element = try #require(result.elements.first)
        let seg = try #require(segment(element))
        #expect(near(seg.a, 0, 110) && near(seg.b, 0, 112))
        #expect(element.references.map(\.definition) == [2, 1])
        #expect(element.references.map(\.index) == [0, 0])
        #expect(element.references[1].at == .init(x: 10, y: 0))
    }

    @Test("a block that contains itself is left unresolved, not followed forever")
    func cycle() {
        let dwg = drawing(
            [insert(1, at: (0, 0))], blocks: [1: [line(0, 0, 1, 0), insert(1, at: (5, 0))]])
        let result = dwg.expandingBlocks()
        #expect(result.elements.count == 1)
        #expect(result.unresolved.map(\.definition) == [1])
    }

    @Test("blocks that reference each other are caught")
    func mutualCycle() {
        let dwg = drawing(
            [insert(1, at: (0, 0))],
            blocks: [1: [line(0, 0, 1, 0), insert(2, at: (0, 0))], 2: [insert(1, at: (0, 0))]])
        let result = dwg.expandingBlocks()
        #expect(result.elements.count == 1)
        #expect(result.unresolved.map(\.definition) == [1])
    }

    @Test("an insert of an undefined block is reported")
    func missingDefinition() {
        let result = drawing([insert(9, at: (0, 0))], blocks: [:]).expandingBlocks()
        #expect(result.elements.isEmpty)
        #expect(result.unresolved.map(\.definition) == [9] && result.unresolved[0].name.isEmpty)
    }

    @Test("maxDepth limits how far nested blocks are followed")
    func depthLimit() {
        let dwg = drawing(
            [insert(2, at: (0, 0))],
            blocks: [1: [line(0, 0, 1, 0)], 2: [insert(1, at: (0, 0))]])
        #expect(dwg.expandingBlocks().elements.count == 1)
        let shallow = dwg.expandingBlocks(maxDepth: 1)
        #expect(shallow.elements.isEmpty && shallow.unresolved.map(\.definition) == [1])
    }

    @Test("text turns with the block and scales with it; a dimension's parts move together")
    func textAndDimension() throws {
        let text = JWW.Element(
            entity: .text(
                at: .init(x: 1, y: 0), height: 2, width: 3, angleRad: 0.25, string: "A", layer: 0,
                color: 1))
        let dim = JWW.Element(
            entity: .dimension(
                parts: [
                    .line(a: .init(x: 0, y: 0), b: .init(x: 1, y: 0), layer: 0, color: 1),
                    .text(
                        at: .init(x: 0.5, y: 0), height: 1, width: 1, angleRad: 0, string: "1",
                        layer: 0, color: 1),
                ], layer: 0))
        let dwg = drawing(
            [insert(1, at: (10, 0), sx: 2, sy: 2, rotation: .pi / 2)], blocks: [1: [text, dim]])
        let out = dwg.expandingBlocks().elements
        guard case .text(let at, let height, let width, let angle, _, _, _) = out[0].entity else {
            Issue.record("not text")
            return
        }
        #expect(near(at, 10, 2) && abs(height - 4) < 1e-9 && abs(width - 6) < 1e-9)
        #expect(abs(angle - (0.25 + .pi / 2)) < 1e-9)
        let moved = try #require(out[1].dimension)
        #expect(near(moved.dimensionLine.a, 10, 0) && near(moved.dimensionLine.b, 10, 2))
        #expect(near(moved.label.at, 10, 1))
    }

    struct TextTurn {
        var sx: Double
        var sy: Double
        var rotation: Double
        /// The turn added to the text's own angle.
        var turn: Double
    }

    @Test(
        "a mirror never leaves text upside down, and a placement without one turns it in full",
        arguments: [
            TextTurn(sx: -1, sy: 1, rotation: 0, turn: 0),
            TextTurn(sx: 1, sy: -1, rotation: 0, turn: 0),
            TextTurn(sx: -2, sy: 2, rotation: 0.5, turn: 0.5),
            TextTurn(sx: 2, sy: -2, rotation: 0.5, turn: 0.5),
            TextTurn(sx: -1, sy: 1, rotation: 2, turn: 2 - .pi),
            TextTurn(sx: 1, sy: -1, rotation: -2, turn: .pi - 2),
            TextTurn(sx: 1, sy: 1, rotation: 2, turn: 2),
            TextTurn(sx: -1, sy: -1, rotation: 0, turn: .pi),
        ])
    func textUnderMirror(_ p: TextTurn) throws {
        let text = JWW.Element(
            entity: .text(
                at: .init(x: 1, y: 0), height: 2, width: 3, angleRad: 0.25, string: "A", layer: 0,
                color: 1))
        let dwg = drawing(
            [insert(1, at: (0, 0), sx: p.sx, sy: p.sy, rotation: p.rotation)],
            blocks: [1: [text]])
        let placed = try #require(dwg.expandingBlocks().elements.first)
        guard case .text(_, _, _, let angle, _, _, _) = placed.entity else {
            Issue.record("not text")
            return
        }
        #expect(abs((angle - (0.25 + p.turn)).remainder(dividingBy: 2 * .pi)) < 1e-9)
    }

    // MARK: arcs

    struct Placement {
        var sx: Double
        var sy: Double
        var rotation: Double
        var at: (Double, Double)
    }

    @Test(
        "an arc stays the same curve under rotation, scale, non-uniform scale and mirroring",
        arguments: [
            Placement(sx: 1, sy: 1, rotation: 0, at: (3, 4)),
            Placement(sx: 1, sy: 1, rotation: 0.9, at: (-2, 5)),
            Placement(sx: 2.5, sy: 2.5, rotation: -0.4, at: (0, 0)),
            Placement(sx: 2, sy: 0.5, rotation: 0.6, at: (1, 1)),
            Placement(sx: -1, sy: 1, rotation: 0, at: (0, 0)),
            Placement(sx: 1, sy: -2, rotation: 1.1, at: (7, -3)),
            Placement(sx: -3, sy: -3, rotation: 0.2, at: (2, 2)),
        ])
    func arcsFollowThePlacement(_ p: Placement) throws {
        let c = JWW.Point(x: 1.5, y: -0.5)
        // circle and ellipse, with a counter-clockwise and a clockwise sweep
        let shapes: [(r: Double, tilt: Double, ratio: Double, start: Double, sweep: Double)] = [
            (2, 0.3, 1, 0.4, 1.9), (2, 0.3, 1, 2.0, -1.2), (3, 0.8, 0.4, 0.2, 2.5),
            (3, -0.5, 0.4, 1.0, -2.2),
        ]
        for s in shapes {
            let arc = JWW.Element(
                entity: .arc(
                    center: c, radius: s.r, start: s.start, sweep: s.sweep, tilt: s.tilt,
                    ratio: s.ratio, full: false, layer: 0, color: 1))
            let dwg = drawing(
                [insert(1, at: p.at, sx: p.sx, sy: p.sy, rotation: p.rotation)], blocks: [1: [arc]])
            let out = try #require(dwg.expandingBlocks().elements.first).entity
            func place(_ q: JWW.Point) -> JWW.Point {
                let sx = p.sx * q.x
                let sy = p.sy * q.y
                return .init(
                    x: cos(p.rotation) * sx - sin(p.rotation) * sy + p.at.0,
                    y: sin(p.rotation) * sx + cos(p.rotation) * sy + p.at.1)
            }
            for i in 0...10 {
                let t = s.start + s.sweep * Double(i) / 10
                let q = place(
                    ArcGeometry.point(center: c, radius: s.r, tilt: s.tilt, ratio: s.ratio, at: t))
                #expect(ArcGeometry.contains(out, q), "sample \(i) of \(s) under \(p)")
            }
            // a point on the same ellipse but outside the sweep must not be on the new arc
            let outside = s.sweep >= 0 ? s.start + s.sweep + 0.4 : s.start + 0.4
            let q = place(
                ArcGeometry.point(center: c, radius: s.r, tilt: s.tilt, ratio: s.ratio, at: outside)
            )
            #expect(!ArcGeometry.contains(out, q), "outside point of \(s) under \(p)")
        }
    }

    @Test("a circle under uniform scale stays a circle")
    func circleStaysCircle() throws {
        let circle = JWW.Element(
            entity: .arc(
                center: .init(x: 0, y: 0), radius: 2, start: 0, sweep: 2 * .pi, tilt: 0, ratio: 1,
                full: true, layer: 0, color: 1))
        let dwg = drawing(
            [insert(1, at: (1, 1), sx: 3, sy: 3, rotation: 0.7)], blocks: [1: [circle]])
        let out = try #require(dwg.expandingBlocks().elements.first).entity
        guard case .arc(let center, let r, _, _, _, let ratio, let full, _, _) = out else {
            Issue.record("not an arc")
            return
        }
        #expect(near(center, 1, 1) && abs(r - 6) < 1e-9 && ratio == 1 && full)
    }
}
