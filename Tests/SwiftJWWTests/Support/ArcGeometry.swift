import Foundation

@testable import SwiftJWW

/// Geometry on JWW arcs, shared by the tests: a point on an arc, and whether a point lies on one.
enum ArcGeometry {
    /// The point of the ellipse `center`, `radius`, `tilt`, `ratio` at parameter `t`.
    static func point(
        center c: JWW.Point, radius r: Double, tilt: Double, ratio: Double, at t: Double
    ) -> JWW.Point {
        let x = r * cos(t)
        let y = ratio * r * sin(t)
        return .init(x: c.x + x * cos(tilt) - y * sin(tilt), y: c.y + x * sin(tilt) + y * cos(tilt))
    }

    /// True when `q` lies on the arc `e` within `tolerance` and inside its start and sweep.
    static func contains(_ e: JWW.Entity, _ q: JWW.Point, tolerance: Double = 1e-9) -> Bool {
        guard case .arc(let c, let r, let start, let sweep, let tilt, let ratio, _, _, _) = e else {
            return false
        }
        let dx = q.x - c.x
        let dy = q.y - c.y
        let x = dx * cos(tilt) + dy * sin(tilt)
        let y = -dx * sin(tilt) + dy * cos(tilt)
        let nx = x / r
        let ny = y / (ratio * r)
        guard abs(hypot(nx, ny) - 1) * ratio * r <= tolerance else { return false }
        let base = sweep >= 0 ? start : start + sweep
        var rel = (atan2(ny, nx) - base).truncatingRemainder(dividingBy: 2 * .pi)
        if rel < 0 { rel += 2 * .pi }
        let slack = tolerance / (ratio * r)
        return rel <= abs(sweep) + slack || rel > 2 * .pi - slack
    }
}
