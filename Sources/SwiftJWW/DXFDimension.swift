import Foundation

/// The groups of a rotated linear DXF `DIMENSION`, taken from a JWW dimension.
struct DXFDimension {
    /// A point on the dimension line (group 10).
    var onLine: JWW.Point
    /// The text position (group 11).
    var labelAt: JWW.Point
    /// The text as written (group 1).
    var label: String
    /// The first and second measured points (groups 13 and 14).
    var first: JWW.Point
    var second: JWW.Point
    /// The angle of the dimension line from the x axis (group 50).
    var angleRad: Double

    init(
        onLine: JWW.Point, labelAt: JWW.Point, label: String, first: JWW.Point, second: JWW.Point,
        angleRad: Double
    ) {
        self.onLine = onLine
        self.labelAt = labelAt
        self.label = label
        self.first = first
        self.second = second
        self.angleRad = angleRad
    }

    /// A stored dimension record, nil when it has no measured points (a file older than 4.20).
    ///
    /// The dimension line gives the angle. A record whose line has no length takes the direction
    /// of its measured points.
    init?(record: JWW.Dimension) {
        guard record.measuredPoints.count == 2 else { return nil }
        let a = record.dimensionLine.a
        let b = record.dimensionLine.b
        let m = record.measuredPoints
        var dx = b.x - a.x
        var dy = b.y - a.y
        if hypot(dx, dy) < 1e-9 {
            dx = m[1].x - m[0].x
            dy = m[1].y - m[0].y
        }
        self.init(
            onLine: a, labelAt: record.label.at, label: record.label.string, first: m[0],
            second: m[1], angleRad: atan2(dy, dx))
    }

    /// A dimension rebuilt from loose pieces, nil when it has no two arrow points a length apart.
    ///
    /// The dimension line runs between the arrow points. The measured points are the far ends of
    /// the witness lines, the ends away from the dimension line, and the arrow point itself on a
    /// side that has no witness line. If the far ends do not measure the arrow distance along the
    /// dimension line, both sides take the arrow points.
    init?(recovered: JWW.Dimension) {
        guard recovered.arrowPoints.count == 2 else { return nil }
        let p = recovered.arrowPoints[0]
        let q = recovered.arrowPoints[1]
        let length = hypot(q.x - p.x, q.y - p.y)
        guard length > DXFDimension.tolerance else { return nil }
        let ux = (q.x - p.x) / length
        let uy = (q.y - p.y) / length
        /// The end of a witness line away from the dimension line, for the line that starts at `end`.
        func farEnd(from end: JWW.Point) -> JWW.Point? {
            for line in recovered.extensionLines {
                let da = abs((line.a.x - p.x) * uy - (line.a.y - p.y) * ux)
                let db = abs((line.b.x - p.x) * uy - (line.b.y - p.y) * ux)
                let (near, far) = da <= db ? (line.a, line.b) : (line.b, line.a)
                if hypot(near.x - end.x, near.y - end.y) <= DXFDimension.tolerance { return far }
            }
            return nil
        }
        var first = farEnd(from: p) ?? p
        var second = farEnd(from: q) ?? q
        let along = abs((second.x - first.x) * ux + (second.y - first.y) * uy)
        if abs(along - length) > DXFDimension.tolerance {
            first = p
            second = q
        }
        self.init(
            onLine: JWW.Point(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2),
            labelAt: recovered.label.at, label: recovered.label.string, first: first,
            second: second, angleRad: atan2(q.y - p.y, q.x - p.x))
    }

    /// How far apart two drawn points may be and still be the same point, as in the dimension
    /// recovery.
    private static let tolerance = 1e-3

    /// The same dimension with every coordinate multiplied by `factor`.
    func scaled(by factor: Double) -> DXFDimension {
        guard factor != 1 else { return self }
        func f(_ p: JWW.Point) -> JWW.Point { JWW.Point(x: p.x * factor, y: p.y * factor) }
        return DXFDimension(
            onLine: f(onLine), labelAt: f(labelAt), label: label, first: f(first),
            second: f(second), angleRad: angleRad)
    }
}
