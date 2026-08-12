import Foundation

/// Writes a ``JWW/Drawing`` as an ASCII **DXF**.
///
/// An entities-only, version-agnostic DXF that AutoCAD / LibreCAD / most CAD tools accept. Maps
/// JWW entities to DXF: line→`LINE`, full circle→`CIRCLE`, circular arc→`ARC`,
/// elliptical arc→`ELLIPSE`, point→`POINT`, text→`TEXT`.
public enum DXFWriter {

    public static func string(_ dwg: JWW.Drawing) -> String {
        var s = "999\nSwiftJWW\n"
        s.reserveCapacity(dwg.entities.count * 120)
        // BLOCKS section: one BLOCK per definition, named BLK<number>.
        if !dwg.blocks.isEmpty {
            s += "0\nSECTION\n2\nBLOCKS\n"
            for num in dwg.blocks.keys.sorted() {
                let def = dwg.blocks[num]!
                let name = "BLK\(num)"
                s += "0\nBLOCK\n8\n0\n2\n\(name)\n70\n0\n10\n0.0\n20\n0.0\n30\n0.0\n3\n\(name)\n"
                for e in def.entities { emit(e, into: &s) }
                s += "0\nENDBLK\n8\n0\n"
            }
            s += "0\nENDSEC\n"
        }
        s += "0\nSECTION\n2\nENTITIES\n"
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
        func normDeg(_ x: Double) -> Double {
            let a = x.truncatingRemainder(dividingBy: 360)
            return a < 0 ? a + 360 : a
        }
        let deg = 180.0 / Double.pi

        switch e {
        case .line(let a, let b, let layer, let color):
            p(0, "LINE")
            p(8, "\(layer)")
            p(62, aci(color))
            p(10, num(a.x))
            p(20, num(a.y))
            p(30, "0.0")
            p(11, num(b.x))
            p(21, num(b.y))
            p(31, "0.0")

        case .arc(
            let c, let r, let start, let sweep, let tilt, let ratio, let full, let layer, let color):
            if abs(ratio - 1) < 1e-9 {  // circle / circular arc
                if full || abs(abs(sweep) - 2 * .pi) < 1e-6 {
                    p(0, "CIRCLE")
                    p(8, "\(layer)")
                    p(62, aci(color))
                    p(10, num(c.x))
                    p(20, num(c.y))
                    p(30, "0.0")
                    p(40, num(r))
                } else {
                    p(0, "ARC")
                    p(8, "\(layer)")
                    p(62, aci(color))
                    p(10, num(c.x))
                    p(20, num(c.y))
                    p(30, "0.0")
                    p(40, num(r))
                    // JWW start/sweep are measured from the tilt axis; DXF wants absolute CCW angles in
                    // [0,360). Add tilt, and order start→end CCW (so a negative sweep isn't drawn inverted).
                    let a0 = tilt + start
                    let a1 = tilt + start + sweep
                    let lo = sweep >= 0 ? a0 : a1
                    let hi = sweep >= 0 ? a1 : a0
                    p(50, num(normDeg(lo * deg)))
                    p(51, num(normDeg(hi * deg)))
                }
            } else {  // ellipse / elliptical arc
                p(0, "ELLIPSE")
                p(8, "\(layer)")
                p(62, aci(color))
                p(10, num(c.x))
                p(20, num(c.y))
                p(30, "0.0")
                p(11, num(cos(tilt) * r))
                p(21, num(sin(tilt) * r))
                p(31, "0.0")  // major axis endpoint, rel. to center
                p(40, num(ratio))
                p(41, num(full ? 0 : start))
                p(42, num(full ? 2 * .pi : start + sweep))
            }

        case .point(let at, let layer, let color):
            p(0, "POINT")
            p(8, "\(layer)")
            p(62, aci(color))
            p(10, num(at.x))
            p(20, num(at.y))
            p(30, "0.0")

        case .text(let at, let height, _, let angleRad, let string, let layer, let color):
            p(0, "TEXT")
            p(8, "\(layer)")
            p(62, aci(color))
            p(10, num(at.x))
            p(20, num(at.y))
            p(30, "0.0")
            p(40, num(height > 0 ? height : 2.5))
            p(1, dxfText(string))
            if abs(angleRad) > 1e-9 { p(50, num(angleRad * deg)) }

        case .insert(let def, let at, let scaleX, let scaleY, let rotationRad, let layer, let color):
            p(0, "INSERT")
            p(8, "\(layer)")
            p(62, aci(color))
            p(2, "BLK\(def)")
            p(10, num(at.x))
            p(20, num(at.y))
            p(30, "0.0")
            p(41, num(scaleX == 0 ? 1 : scaleX))
            p(42, num(scaleY == 0 ? 1 : scaleY))
            p(43, "1.0")
            if abs(rotationRad) > 1e-9 { p(50, num(rotationRad * deg)) }

        case .dimension(let parts, _):
            // Decomposed: dimension line, text, witness lines, arrows.
            for part in parts { emit(part, into: &s) }
        }
    }

    /// JWW pen colour to AutoCAD Color Index.
    ///
    /// JWW colours are small integers; pass through, clamped to a valid ACI (1...255), defaulting
    /// odd values to 7 (white/black).
    private static func aci(_ c: Int) -> String {
        (1...255).contains(c) ? "\(c)" : "7"
    }

    /// Prepare a (Unicode) string for a DXF group-1 value.
    ///
    /// Strips newlines, and escapes every non-ASCII character as the DXF `\U+XXXX` unicode
    /// escape. This renders correctly in AutoCAD / LibreCAD regardless of the reader's assumed
    /// code page (an entities-only DXF carries no `$DWGCODEPAGE`).
    static func dxfText(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            if u == "\n" || u == "\r" {
                out += " "
            } else if u.value < 0x80 {
                out.unicodeScalars.append(u)
            } else {
                out += String(format: "\\U+%04X", u.value)
            }
        }
        return out
    }
}
