import Foundation

/// Writes a ``JWW/Drawing`` as an ASCII **DXF** (an entities-only, version-agnostic DXF that AutoCAD /
/// LibreCAD / most CAD tools accept). Maps JWW entities to DXF: line→`LINE`, full circle→`CIRCLE`,
/// circular arc→`ARC`, elliptical arc→`ELLIPSE`, point→`POINT`, text→`TEXT`.
public enum DXFWriter {

    public static func string(_ dwg: JWW.Drawing) -> String {
        var s = "999\nSwiftJWW\n0\nSECTION\n2\nENTITIES\n"
        s.reserveCapacity(dwg.entities.count * 120)
        for e in dwg.entities { emit(e, into: &s) }
        s += "0\nENDSEC\n0\nEOF\n"
        return s
    }

    public static func write(_ dwg: JWW.Drawing, to url: URL) throws {
        try string(dwg).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: entity emit

    private static func emit(_ e: JWW.Entity, into s: inout String) {
        func p(_ code: Int, _ v: String) { s += "\(code)\n\(v)\n" }
        func num(_ v: Double) -> String { v.isFinite ? String(format: "%.6f", v) : "0.0" }
        let deg = 180.0 / Double.pi

        switch e {
        case let .line(a, b, layer, color):
            p(0, "LINE"); p(8, "\(layer)"); p(62, aci(color))
            p(10, num(a.x)); p(20, num(a.y)); p(30, "0.0")
            p(11, num(b.x)); p(21, num(b.y)); p(31, "0.0")

        case let .arc(c, r, start, sweep, tilt, ratio, full, layer, color):
            if abs(ratio - 1) < 1e-9 {                          // circle / circular arc
                if full || abs(abs(sweep) - 2 * .pi) < 1e-6 {
                    p(0, "CIRCLE"); p(8, "\(layer)"); p(62, aci(color))
                    p(10, num(c.x)); p(20, num(c.y)); p(30, "0.0"); p(40, num(r))
                } else {
                    p(0, "ARC"); p(8, "\(layer)"); p(62, aci(color))
                    p(10, num(c.x)); p(20, num(c.y)); p(30, "0.0"); p(40, num(r))
                    p(50, num(start * deg)); p(51, num((start + sweep) * deg))
                }
            } else {                                            // ellipse / elliptical arc
                p(0, "ELLIPSE"); p(8, "\(layer)"); p(62, aci(color))
                p(10, num(c.x)); p(20, num(c.y)); p(30, "0.0")
                p(11, num(cos(tilt) * r)); p(21, num(sin(tilt) * r)); p(31, "0.0")   // major axis endpoint, rel. to center
                p(40, num(ratio))
                p(41, num(full ? 0 : start)); p(42, num(full ? 2 * .pi : start + sweep))
            }

        case let .point(at, layer, color):
            p(0, "POINT"); p(8, "\(layer)"); p(62, aci(color))
            p(10, num(at.x)); p(20, num(at.y)); p(30, "0.0")

        case let .text(at, height, _, angleRad, raw, layer, color):
            p(0, "TEXT"); p(8, "\(layer)"); p(62, aci(color))
            p(10, num(at.x)); p(20, num(at.y)); p(30, "0.0")
            p(40, num(height > 0 ? height : 2.5))
            p(1, decodeText(raw))
            if abs(angleRad) > 1e-9 { p(50, num(angleRad * deg)) }
        }
    }

    /// JWW pen colour → AutoCAD Color Index. JWW colours are small integers; pass through, clamped to a
    /// valid ACI (1…255), defaulting odd values to 7 (white/black).
    private static func aci(_ c: Int) -> String {
        (1...255).contains(c) ? "\(c)" : "7"
    }

    /// JWW text is CP932 (Shift-JIS). Decode to a Swift String for the (UTF-8) DXF. DXF group-code 1
    /// can't contain a newline, so any are stripped.
    private static func decodeText(_ raw: [UInt8]) -> String {
        let data = Data(raw)
        let cp932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        let str = String(data: data, encoding: cp932) ?? String(data: data, encoding: .shiftJIS) ?? String(decoding: raw, as: UTF8.self)
        return str.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }
}
