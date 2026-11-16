import Foundation

/// The groups of a rotated linear DXF `DIMENSION`, taken from a JWW dimension.
struct DXFDimension {
    /// The parts of a record that are drawn.
    ///
    /// They are the dimension line, the text, two witness lines and two arrow points. The two
    /// measured points that follow are not drawn.
    static let drawnPartCount = 6

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

    /// The same dimension with every coordinate multiplied by `factor`.
    func scaled(by factor: Double) -> DXFDimension {
        guard factor != 1 else { return self }
        func f(_ p: JWW.Point) -> JWW.Point { JWW.Point(x: p.x * factor, y: p.y * factor) }
        return DXFDimension(
            onLine: f(onLine), labelAt: f(labelAt), label: label, first: f(first),
            second: f(second), angleRad: angleRad)
    }
}
