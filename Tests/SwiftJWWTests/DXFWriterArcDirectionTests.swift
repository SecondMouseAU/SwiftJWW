import Foundation
import Testing

@testable import SwiftJWW

@Suite("DXF writer: arcs with a negative sweep")
struct DXFWriterArcDirectionTests {
    typealias Point = JWW.Point

    let center = Point(x: 2, y: 1)
    let radius = 4.0
    let ratio = 0.5
    let tilt = 30 * Double.pi / 180

    func degrees(_ d: Double) -> Double { d * .pi / 180 }

    func ellipse(start: Double, sweep: Double) -> JWW.Entity {
        .arc(
            center: center, radius: radius, start: start, sweep: sweep, tilt: tilt, ratio: ratio,
            full: false, layer: 0, color: 1)
    }

    func written(_ e: JWW.Entity, as type: String = "ELLIPSE") throws -> ReferenceDXF.Entity {
        let dwg = JWW.Drawing(version: 700, entities: [e], counts: .init())
        let entity = try #require(try ReferenceDXF(text: DXFWriter.string(dwg)).entities.first)
        #expect(entity.type == type)
        return entity
    }

    /// The point of the JWW ellipse at parameter `t`, measured from its tilt axis.
    func point(at t: Double) -> Point {
        ArcGeometry.point(center: center, radius: radius, tilt: tilt, ratio: ratio, at: t)
    }

    /// True when a DXF reader draws `q` as part of the `ELLIPSE`, which runs counter-clockwise from
    /// group 41 to group 42.
    func covers(_ d: ReferenceDXF.Entity, _ q: Point) throws -> Bool {
        let mx = try #require(d.number(11))
        let my = try #require(d.number(21))
        let start = try #require(d.number(41))
        var sweep = (try #require(d.number(42)) - start).truncatingRemainder(dividingBy: 2 * .pi)
        if sweep <= 0 { sweep += 2 * .pi }
        let drawn = JWW.Entity.arc(
            center: Point(x: try #require(d.number(10)), y: try #require(d.number(20))),
            radius: hypot(mx, my), start: start, sweep: sweep, tilt: atan2(my, mx),
            ratio: try #require(d.number(40)), full: false, layer: 0, color: 1)
        // The DXF keeps six decimal places.
        return ArcGeometry.contains(drawn, q, tolerance: 1e-4)
    }

    @Test("a negative sweep is written as the part of the ellipse the JWW arc covers")
    func negativeSweep() throws {
        // From 100 degrees back to 40: 70 is on the arc, 160 is on the rest of the ellipse.
        let arc = ellipse(start: degrees(100), sweep: degrees(-60))
        let inside = point(at: degrees(70))
        let outside = point(at: degrees(160))
        #expect(ArcGeometry.contains(arc, inside, tolerance: 1e-6))
        #expect(!ArcGeometry.contains(arc, outside, tolerance: 1e-6))

        let d = try written(arc)
        #expect(try covers(d, inside))
        #expect(try !covers(d, outside))
    }

    @Test("a negative sweep writes the same ends as the positive sweep over the same span")
    func sameAsPositive() throws {
        let backward = try written(ellipse(start: degrees(100), sweep: degrees(-60)))
        let forward = try written(ellipse(start: degrees(40), sweep: degrees(60)))
        #expect(backward.text(41) == forward.text(41))
        #expect(backward.text(42) == forward.text(42))
    }

    @Test("a negative sweep across the major axis covers the same part of the ellipse")
    func acrossMajorAxis() throws {
        // From 20 degrees back to -40: 0 is on the arc, 90 is not.
        let d = try written(ellipse(start: degrees(20), sweep: degrees(-60)))
        #expect(try covers(d, point(at: 0)))
        #expect(try !covers(d, point(at: degrees(90))))
    }

    @Test("a circular arc with a negative sweep runs counter-clockwise over the same span")
    func circularArc() throws {
        // From 100 degrees back to 40, measured from a tilt of 30: 70 to 130 from the x axis.
        let arc = JWW.Entity.arc(
            center: center, radius: radius, start: degrees(100), sweep: degrees(-60), tilt: tilt,
            ratio: 1, full: false, layer: 0, color: 1)
        let d = try written(arc, as: "ARC")
        #expect(abs((d.number(50) ?? 0) - 70) < 1e-6)
        #expect(abs((d.number(51) ?? 0) - 130) < 1e-6)
    }
}
