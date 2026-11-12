import Foundation

extension JWW.Entity {
    /// This entity mapped through `t`, with an insert returned unchanged.
    ///
    /// Expansion composes an insert's transform with its parent's instead of mapping the insert.
    func transformed(by t: Affine) -> JWW.Entity {
        switch self {
        case .line(let a, let b, let layer, let color):
            return .line(a: t.apply(a), b: t.apply(b), layer: layer, color: color)
        case .point(let at, let layer, let color):
            return .point(at: t.apply(at), layer: layer, color: color)
        case .text(let at, let height, let width, let angle, let string, let layer, let color):
            // A mirrored block keeps its text readable: only position, size and turn follow.
            return .text(
                at: t.apply(at), height: height * t.yScale, width: width * t.xScale,
                angleRad: angle + t.textRotation, string: string, layer: layer, color: color)
        case .arc(
            let center, let radius, let start, let sweep, let tilt, let ratio, let full, let layer,
            let color):
            return Self.transformedArc(
                center: center, radius: radius, start: start, sweep: sweep, tilt: tilt,
                ratio: ratio, full: full, layer: layer, color: color, by: t)
        case .dimension(let parts, let layer):
            return .dimension(parts: parts.map { $0.transformed(by: t) }, layer: layer)
        case .insert:
            return self
        }
    }

    /// An arc mapped through `t`, as the ellipse `c + u*cos(s) + v*sin(s)` with conjugate radii.
    ///
    /// Any affine map sends it to another such ellipse. Its principal axes give the new radius,
    /// ratio and tilt, and a mirror (negative determinant) reverses the parameter direction.
    private static func transformedArc(
        center: JWW.Point, radius: Double, start: Double, sweep: Double, tilt: Double,
        ratio: Double, full: Bool, layer: Int, color: Int, by t: Affine
    ) -> JWW.Entity {
        let u = t.applyLinear(radius * cos(tilt), radius * sin(tilt))
        let v = t.applyLinear(-ratio * radius * sin(tilt), ratio * radius * cos(tilt))
        let uu = u.x * u.x + u.y * u.y
        let vv = v.x * v.x + v.y * v.y
        let uv = u.x * v.x + u.y * v.y
        // A circle has no principal axes to find: keep u and v as they are.
        let isCircle = abs(uu - vv) + 2 * abs(uv) <= 1e-12 * (uu + vv)
        let phi = isCircle ? 0 : 0.5 * atan2(2 * uv, uu - vv)
        let major = (x: u.x * cos(phi) + v.x * sin(phi), y: u.y * cos(phi) + v.y * sin(phi))
        let minor = (x: -u.x * sin(phi) + v.x * cos(phi), y: -u.y * sin(phi) + v.y * cos(phi))
        let majorLength = hypot(major.x, major.y)
        let minorLength = hypot(minor.x, minor.y)
        var newRatio = majorLength > 0 ? minorLength / majorLength : 1
        if abs(newRatio - 1) < 1e-9 { newRatio = 1 }
        let mirrored = major.x * minor.y - major.y * minor.x < 0
        var newStart = start - phi
        var newSweep = sweep
        if mirrored {
            newStart = sweep >= 0 ? phi - start - sweep : phi - start
            newSweep = abs(sweep)
        }
        return .arc(
            center: t.apply(center), radius: majorLength, start: newStart, sweep: newSweep,
            tilt: atan2(major.y, major.x), ratio: newRatio, full: full, layer: layer, color: color)
    }
}
