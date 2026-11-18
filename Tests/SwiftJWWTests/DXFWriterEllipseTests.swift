import Foundation
import Testing

@testable import SwiftJWW

@Suite("DXF writer: elliptical arcs")
struct DXFWriterEllipseTests {
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

    func written(_ e: JWW.Entity) throws -> ReferenceDXF.Entity {
        let dwg = JWW.Drawing(version: 700, entities: [e], counts: .init())
        let entity = try #require(try ReferenceDXF(text: DXFWriter.string(dwg)).entities.first)
        #expect(entity.type == "ELLIPSE")
        return entity
    }

    /// The point of the JWW ellipse at parameter `t`, measured from its tilt axis.
    func point(at t: Double) -> Point {
        ArcGeometry.point(center: center, radius: radius, tilt: tilt, ratio: ratio, at: t)
    }

    /// True when a DXF reader draws `q` as part of the `ELLIPSE`: on the curve, and inside the
    /// counter-clockwise run from group 41 to group 42.
    func covers(_ d: ReferenceDXF.Entity, _ q: Point) throws -> Bool {
        let cx = try #require(d.number(10))
        let cy = try #require(d.number(20))
        let mx = try #require(d.number(11))
        let my = try #require(d.number(21))
        let r = try #require(d.number(40))
        let start = try #require(d.number(41))
        let end = try #require(d.number(42))
        let major = hypot(mx, my)
        let ux = mx / major
        let uy = my / major
        let x = ((q.x - cx) * ux + (q.y - cy) * uy) / major
        let y = (-(q.x - cx) * uy + (q.y - cy) * ux) / (major * r)
        guard abs(hypot(x, y) - 1) < 1e-6 else { return false }
        func ccw(_ a: Double) -> Double {
            let m = a.truncatingRemainder(dividingBy: 2 * .pi)
            return m < 0 ? m + 2 * .pi : m
        }
        return ccw(atan2(y, x) - start) <= ccw(end - start) + 1e-9
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
}
