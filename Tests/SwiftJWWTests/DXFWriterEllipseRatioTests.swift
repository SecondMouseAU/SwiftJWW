import Foundation
import Testing

@testable import SwiftJWW

@Suite("DXF writer: ellipses with a ratio above 1")
struct DXFWriterEllipseRatioTests {
    typealias Point = JWW.Point

    let center = Point(x: 2, y: 1)
    let radius = 4.0
    let tilt = 30 * Double.pi / 180

    func degrees(_ d: Double) -> Double { d * .pi / 180 }

    func ellipse(
        ratio: Double, start: Double = 0, sweep: Double = 2 * .pi, full: Bool = false
    ) -> JWW.Entity {
        .arc(
            center: center, radius: radius, start: start, sweep: sweep, tilt: tilt, ratio: ratio,
            full: full, layer: 0, color: 1)
    }

    func written(_ e: JWW.Entity) throws -> ReferenceDXF.Entity {
        let dwg = JWW.Drawing(version: 700, entities: [e], counts: .init())
        let entity = try #require(try ReferenceDXF(text: DXFWriter.string(dwg)).entities.first)
        #expect(entity.type == "ELLIPSE")
        return entity
    }

    /// The ellipse a DXF reader draws from an `ELLIPSE`: the major axis in groups 11 and 21, the
    /// ratio in group 40 and the counter-clockwise run from group 41 to group 42.
    func drawn(_ d: ReferenceDXF.Entity) throws -> JWW.Entity {
        let mx = try #require(d.number(11))
        let my = try #require(d.number(21))
        let start = try #require(d.number(41))
        var sweep = (try #require(d.number(42)) - start).truncatingRemainder(dividingBy: 2 * .pi)
        if sweep <= 0 { sweep += 2 * .pi }
        return .arc(
            center: Point(x: try #require(d.number(10)), y: try #require(d.number(20))),
            radius: hypot(mx, my), start: start, sweep: sweep, tilt: atan2(my, mx),
            ratio: try #require(d.number(40)), full: false, layer: 0, color: 1)
    }

    /// The points of `e`, evenly spaced in parameter from its start through its sweep.
    func samples(of e: JWW.Entity, count: Int = 24) -> [Point] {
        guard case .arc(let c, let r, let start, let sweep, let tilt, let ratio, _, _, _) = e else {
            return []
        }
        return (0...count).map {
            ArcGeometry.point(
                center: c, radius: r, tilt: tilt, ratio: ratio,
                at: start + sweep * Double($0) / Double(count))
        }
    }

    /// True when every point of each curve lies on the other, so they are the same curve.
    func sameCurve(_ a: JWW.Entity, _ b: JWW.Entity) -> Bool {
        // The DXF keeps six decimal places.
        samples(of: a).allSatisfy { ArcGeometry.contains(b, $0, tolerance: 1e-4) }
            && samples(of: b).allSatisfy { ArcGeometry.contains(a, $0, tolerance: 1e-4) }
    }

    @Test("the longer axis is the major axis, and the ratio is at most 1")
    func majorAxisIsTheLongerOne() throws {
        let d = try written(ellipse(ratio: 1.6, full: true))
        let mx = try #require(d.number(11))
        let my = try #require(d.number(21))
        #expect(abs(hypot(mx, my) - radius * 1.6) < 1e-5)
        // Perpendicular to the tilt axis.
        #expect(abs(mx * cos(tilt) + my * sin(tilt)) < 1e-5)
        #expect(abs((d.number(40) ?? 0) - 1 / 1.6) < 1e-6)
        #expect(d.number(41) == 0)
        #expect(abs((d.number(42) ?? 0) - 2 * .pi) < 1e-6)
    }

    @Test("a full ellipse is written over the points of the original")
    func fullEllipse() throws {
        let original = ellipse(ratio: 1.6, full: true)
        #expect(try sameCurve(original, drawn(written(original))))
    }

    @Test(
        "a partial ellipse covers the same part, with the same ends",
        arguments: [
            (100.0, 60.0), (80.0, 40.0), (300.0, 100.0), (0.0, 359.0), (100.0, -60.0),
            (20.0, -60.0), (10.0, -300.0),
        ])
    func partialEllipse(start: Double, sweep: Double) throws {
        let original = ellipse(ratio: 1.6, start: degrees(start), sweep: degrees(sweep))
        let d = try written(original)
        let after = try drawn(d)
        #expect(sameCurve(original, after))
        // The ends are the same two points, whichever way the arc is run.
        let ends = [original, after].map { e -> Set<String> in
            let points = samples(of: e, count: 1)
            return Set(points.map { String(format: "%.3f,%.3f", $0.x, $0.y) })
        }
        #expect(ends[0] == ends[1])
        for code in [41, 42] {
            let t = try #require(d.number(code))
            #expect(t >= 0 && t <= 2 * .pi + 1e-9)
        }
    }

    @Test("an ellipse whose ratio is at most 1 keeps its axes")
    func ratioAtMostOne() throws {
        let d = try written(ellipse(ratio: 0.5, full: true))
        #expect(abs((d.number(11) ?? 0) - radius * cos(tilt)) < 1e-5)
        #expect(abs((d.number(21) ?? 0) - radius * sin(tilt)) < 1e-5)
        #expect(d.number(40) == 0.5)
    }

    @Test("the ratio of every written ellipse is at most 1, at full size too")
    func ratioNeverAboveOne() throws {
        let dwg = JWW.Drawing(
            version: 700,
            entities: [
                ellipse(ratio: 2, full: true), ellipse(ratio: 1.0001), ellipse(ratio: 0.3),
                ellipse(ratio: 1.6, start: 1, sweep: -2),
            ], counts: .init())
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg, options: .init(fullSize: true)))
        let ellipses = dxf.entities.filter { $0.type == "ELLIPSE" }
        #expect(ellipses.count == 4)
        for d in ellipses {
            let ratio = try #require(d.number(40))
            #expect(ratio > 0 && ratio <= 1)
        }
    }
}
