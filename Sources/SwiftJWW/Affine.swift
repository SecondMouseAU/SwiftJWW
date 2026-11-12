import Foundation

/// A 2D affine map: `x' = a*x + c*y + tx`, `y' = b*x + d*y + ty`.
struct Affine {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0

    static let identity = Affine()

    /// Scale about the origin, then rotate, then translate: how a block insert places its members.
    init(scaleX: Double, scaleY: Double, rotation: Double, translation: JWW.Point) {
        a = cos(rotation) * scaleX
        b = sin(rotation) * scaleX
        c = -sin(rotation) * scaleY
        d = cos(rotation) * scaleY
        tx = translation.x
        ty = translation.y
    }

    init() {}

    /// The map that applies `inner` first, then this one.
    func concatenating(_ inner: Affine) -> Affine {
        var out = Affine()
        out.a = a * inner.a + c * inner.b
        out.b = b * inner.a + d * inner.b
        out.c = a * inner.c + c * inner.d
        out.d = b * inner.c + d * inner.d
        out.tx = a * inner.tx + c * inner.ty + tx
        out.ty = b * inner.tx + d * inner.ty + ty
        return out
    }

    func apply(_ p: JWW.Point) -> JWW.Point {
        JWW.Point(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }

    /// The linear part only: a direction or offset, not a position.
    func applyLinear(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (a * x + c * y, b * x + d * y)
    }

    var determinant: Double { a * d - b * c }

    /// The angle the x axis is turned to.
    var rotation: Double { atan2(b, a) }

    /// The turn a text follows: `rotation`, but a mirror never leaves text upside down.
    ///
    /// A mirror can be read as a flip of either axis, which differ by a half turn, so the turn is
    /// kept within a quarter turn of upright.
    var textRotation: Double {
        let turn = rotation
        guard determinant < 0, cos(turn) < 0 else { return turn }
        return turn > 0 ? turn - .pi : turn + .pi
    }

    var xScale: Double { hypot(a, b) }
    var yScale: Double { hypot(c, d) }
}
