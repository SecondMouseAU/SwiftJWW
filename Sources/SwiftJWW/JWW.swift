import Foundation

/// A native-Swift reader for **JWW** — the native drawing format of **Jw_cad**, the free 2D CAD program
/// widely used in Japan. JWW is an MFC `CArchive`-serialized binary file: an 8-byte `JwwData.` magic, a
/// version, a large fixed (version-gated) document header, then an MFC object array of drawing entities.
///
/// `SwiftJWW` reads the geometry — lines, arcs/circles/ellipses, points, and text — into a neutral
/// ``Drawing``. It is a clean-room port of the documented JWW byte layout (LibreCAD's `jwwlib`
/// reverse-engineering + the published `jwdatafmt` spec). Block inserts and dimensions are recognised
/// but not yet expanded (see ``Entity``).
///
/// ```swift
/// let dwg = try JWW.read(contentsOf: url)
/// print(dwg.entities.count, dwg.bounds as Any)
/// ```
public enum JWW {

    // MARK: Model

    public struct Point: Equatable, Sendable { public var x: Double; public var y: Double }

    /// A drawing entity. Coordinates are in the drawing's own units (mm in real-world scale).
    public indirect enum Entity: Sendable {
        case line(a: Point, b: Point, layer: Int, color: Int)
        /// `start`/`sweep` in radians (CCW). `tilt` rotates the axis; `ratio` is the minor/major axis
        /// ratio (1 = circle). `full` marks a closed circle/ellipse.
        case arc(center: Point, radius: Double, start: Double, sweep: Double, tilt: Double, ratio: Double, full: Bool, layer: Int, color: Int)
        case point(at: Point, layer: Int, color: Int)
        case text(at: Point, height: Double, width: Double, angleRad: Double, raw: [UInt8], layer: Int, color: Int)
        /// A block insertion: places block definition `def` (by number — see ``Drawing/blocks``) at
        /// `at`, scaled and rotated.
        case insert(def: Int, at: Point, scaleX: Double, scaleY: Double, rotationRad: Double, layer: Int, color: Int)
        /// A dimension, decomposed into its drawn parts (dimension line, value text, witness lines).
        case dimension(parts: [Entity], layer: Int)
    }

    /// A block definition: a named group of entities, referenced by ``Entity/insert(def:...)``.
    public struct BlockDef: Sendable { public var number: Int; public var name: String; public var entities: [Entity] }

    public struct Drawing: Sendable {
        public var version: Int
        public var entities: [Entity]
        /// Block definitions keyed by number, referenced by `.insert` entities.
        public var blocks: [Int: BlockDef] = [:]
        /// Counts by JWW class, for verification against reference tools.
        public var counts: Counts
        public struct Counts: Sendable, Equatable {
            public var line = 0, arc = 0, point = 0, text = 0, solid = 0, block = 0, dim = 0
        }

        public var bounds: (min: Point, max: Point)? {
            var lo = Point(x: .greatestFiniteMagnitude, y: .greatestFiniteMagnitude)
            var hi = Point(x: -.greatestFiniteMagnitude, y: -.greatestFiniteMagnitude)
            var any = false
            func acc(_ p: Point) { any = true; lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y) }
            func visit(_ e: Entity) {
                switch e {
                case let .line(a, b, _, _): acc(a); acc(b)
                case let .arc(c, r, _, _, _, _, _, _, _): acc(Point(x: c.x - r, y: c.y - r)); acc(Point(x: c.x + r, y: c.y + r))
                case let .point(p, _, _): acc(p)
                case let .text(p, _, _, _, _, _, _): acc(p)
                case let .insert(_, p, _, _, _, _, _): acc(p)
                case let .dimension(parts, _): parts.forEach(visit)
                }
            }
            entities.forEach(visit)
            return any ? (lo, hi) : nil
        }
    }

    public enum Error: Swift.Error, Equatable, Sendable {
        case empty
        case truncated
        case badMagic
        case unsupportedVersion(Int)
        case unknownClass(String)
    }

    // MARK: Entry points

    public static func read(contentsOf url: URL) throws -> Drawing {
        try read(data: try Data(contentsOf: url))
    }

    public static func read(data: Data) throws -> Drawing {
        guard !data.isEmpty else { throw Error.empty }
        var r = Reader(data)
        return try r.parse()
    }

    /// Sniff: a JWW file begins with the ASCII bytes `"JwwData."`.
    public static func looksLikeJWW(_ data: Data) -> Bool {
        let magic: [UInt8] = Array("JwwData.".utf8)
        guard data.count >= magic.count else { return false }
        return Array(data.prefix(magic.count)) == magic
    }
}
