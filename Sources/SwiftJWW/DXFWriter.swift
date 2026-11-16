import Foundation

/// Writes a ``JWW/Drawing`` as an ASCII **DXF**.
///
/// An entities-only, version-agnostic DXF that AutoCAD / LibreCAD / most CAD tools accept. Maps
/// JWW entities to DXF: line→`LINE`, full circle→`CIRCLE`, circular arc→`ARC`,
/// elliptical arc→`ELLIPSE`, point→`POINT`, text→`TEXT`, block insert→`INSERT`, and a dimension
/// record with its measured points→`DIMENSION`.
public enum DXFWriter {

    /// What the writer does beyond copying each entity as it is drawn.
    public struct Options: Equatable, Sendable {
        /// Writes full-size coordinates: each element is multiplied by the scale of its layer group.
        ///
        /// A group drawn at 1:80 has its lengths multiplied by 80. Each element uses its own
        /// group's scale, so a drawing whose groups differ in scale is not averaged. A block insert
        /// scales its position and scale factors, and its members follow the insert.
        public var fullSize: Bool

        public init(fullSize: Bool = false) {
            self.fullSize = fullSize
        }
    }

    public static func string(_ dwg: JWW.Drawing, options: Options = Options()) -> String {
        var emitter = DXFEmitter(drawing: dwg, options: options)
        var blocks = ""
        for num in dwg.blocks.keys.sorted() {
            if let def = dwg.blocks[num] { emitter.emitBlock(def, into: &blocks) }
        }
        var entities = ""
        entities.reserveCapacity(dwg.elements.count * 120)
        for element in dwg.elements {
            emitter.emit(element, scale: emitter.scale(of: element), into: &entities)
        }
        var s = "999\nSwiftJWW\n"
        if !blocks.isEmpty || !emitter.anonymousBlocks.isEmpty {
            s += "0\nSECTION\n2\nBLOCKS\n" + blocks + emitter.anonymousBlocks.joined()
            s += "0\nENDSEC\n"
        }
        s += "0\nSECTION\n2\nENTITIES\n" + entities + "0\nENDSEC\n0\nEOF\n"
        return s
    }

    public static func write(
        _ dwg: JWW.Drawing, to url: URL, options: Options = Options()
    ) throws {
        try string(dwg, options: options).write(to: url, atomically: true, encoding: .utf8)
    }

    /// A coordinate or length as DXF text.
    static func number(_ v: Double) -> String {
        v.isFinite ? String(format: "%.6f", v) : "0.0"
    }

    /// JWW pen colour to AutoCAD Color Index.
    ///
    /// JWW colours are small integers; pass through, clamped to a valid ACI (1...255), defaulting
    /// odd values to 7 (white/black).
    static func aci(_ c: Int) -> String {
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
