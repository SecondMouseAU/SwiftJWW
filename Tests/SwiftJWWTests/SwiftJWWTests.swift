import Testing
import Foundation
@testable import SwiftJWW

@Suite("JWW reading + DXF")
struct SwiftJWWTests {

    // MARK: synthetic JWW builder (minimal v700 header + entities), mirroring Reader.readHeader

    struct Builder {
        var d = Data()
        mutating func u8(_ v: Int) { d.append(UInt8(v & 0xFF)) }
        mutating func u16(_ v: Int) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        mutating func u32(_ v: Int) { for k in 0..<4 { d.append(UInt8((v >> (8 * k)) & 0xFF)) } }
        mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { d.append(contentsOf: $0) } }
        mutating func emptyStr() { u8(0) }
        mutating func zeros(_ n: Int) { d.append(Data(count: n)) }

        /// Emit a minimal but byte-exact v700 header (all fields zero / empty strings).
        mutating func header() {
            d.append(contentsOf: Array("JwwData.".utf8))
            u32(700)
            emptyStr()                                  // memo
            u32(0); u32(0)                              // zumen, writeGLay
            for _ in 0..<16 { zeros(4 + 4 + 8 + 4); for _ in 0..<16 { zeros(8) } }   // layer-groups
            zeros(14 * 4); zeros(5 * 4); zeros(4); zeros(4)        // dummy, sunpou, dummy1, maxDrawWid
            zeros(8 * 2); zeros(8); zeros(4); zeros(4); zeros(8); zeros(8 * 2); zeros(8 * 2)
            for _ in 0..<(16 * 16) { emptyStr() }; for _ in 0..<16 { emptyStr() }    // names
            zeros(8); zeros(8); zeros(4); zeros(8)                 // kage...
            zeros(8); zeros(8)                                     // tenkuu (v>=300)
            zeros(4); zeros(8); zeros(8 * 2); zeros(8); zeros(8 * 2)
            for _ in 0..<8 { zeros(8 + 8 + 8 + 4) }                // zoom (v>=300)
            zeros(8 * 3); zeros(4); zeros(8 * 2); zeros(8); zeros(4)   // dDm (v>=300)
            zeros(8 * 10); zeros(8)                                // fukusen, ryo
            for _ in 0..<10 { zeros(8) }; for _ in 0..<10 { zeros(16) }   // Pen, PrtPen
            for _ in 0..<8 { zeros(16) }; for _ in 0..<5 { zeros(20) }; for _ in 0..<4 { zeros(16) }  // LType
            zeros(4 * 11); zeros(8); zeros(4 * 3); zeros(8 * 5); zeros(8 * 4); zeros(8)   // flags..solid
            for _ in 0..<257 { zeros(8) }                          // SXF color display (v>=420)
            for _ in 0..<257 { emptyStr(); zeros(16) }             // SXF color print
            for _ in 0..<33 { zeros(16) }                          // SXF ltype pattern
            for _ in 0..<33 { emptyStr(); zeros(4 + 80) }          // SXF ltype param
            for _ in 0..<10 { zeros(8 * 3 + 4) }                   // Moji[1..10]
            zeros(8 * 3); zeros(8); zeros(8); zeros(8); zeros(4); zeros(8 * 6)   // moji write settings
        }
        mutating func base(penStyle: Int = 1, color: Int = 2, layer: Int = 0) {
            u32(0); u8(penStyle); u16(color); u16(0); u16(layer); u16(0); u16(0)   // v>=351 → penWidth present
        }
        mutating func str(_ s: String) { let a = Array(s.utf8); u8(a.count); d.append(contentsOf: a) }
        mutating func classTag(_ name: String) { u16(0xFFFF); u16(0x2bc); u16(name.utf8.count); d.append(contentsOf: Array(name.utf8)) }
        // inline entity field groups (no object tag — used inside CDataSunpou)
        mutating func senFields(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, layer: Int = 0) { base(layer: layer); f64(x1); f64(y1); f64(x2); f64(y2) }
        mutating func mojiFields(_ text: String, layer: Int = 0) { base(layer: layer); f64(0); f64(0); f64(0); f64(0); u32(0); f64(2); f64(2); f64(0); f64(0); emptyStr(); str(text) }
        mutating func tenFields(_ x: Double, _ y: Double, layer: Int = 0) { base(layer: layer); f64(x); f64(y); u32(0) }
    }

    /// Build a JWW with 2 lines (one class def + one back-ref) and 1 arc.
    static func sample() -> Data {
        var b = Builder()
        b.header()
        b.u16(3)                                        // array preamble (non-0xFFFF)
        // line 1 — new class CDataSen
        b.u16(0xFFFF); b.u16(0x2bc); b.u16(8); b.d.append(contentsOf: Array("CDataSen".utf8))
        b.base(layer: 5); b.f64(0); b.f64(0); b.f64(10); b.f64(0)
        // line 2 — back-ref (CDataSen class is map index 1)
        b.u16(0x8001); b.base(layer: 5); b.f64(10); b.f64(0); b.f64(10); b.f64(5)
        // arc — new class CDataEnko
        b.u16(0xFFFF); b.u16(0x2bc); b.u16(9); b.d.append(contentsOf: Array("CDataEnko".utf8))
        b.base(layer: 7); b.f64(3); b.f64(4); b.f64(2); b.f64(0); b.f64(.pi); b.f64(0); b.f64(1); b.u32(0)
        return b.d
    }

    @Test("reads synthetic JWW: counts, coordinates, bounds")
    func reads() throws {
        let dwg = try JWW.read(data: Self.sample())
        #expect(dwg.version == 700)
        #expect(dwg.counts.line == 2)
        #expect(dwg.counts.arc == 1)
        guard case let .line(a, bb, layer, _) = dwg.entities[0] else { Issue.record("not a line"); return }
        #expect(a.x == 0 && bb.x == 10 && layer == 5)
        guard case let .arc(c, r, _, sweep, _, ratio, _, _, _) = dwg.entities[2] else { Issue.record("not an arc"); return }
        #expect(c.x == 3 && c.y == 4 && r == 2 && ratio == 1 && abs(sweep - .pi) < 1e-9)
        let bounds = try #require(dwg.bounds)
        #expect(bounds.max.x == 10)                     // line endpoints reach x=10
    }

    @Test("DXF writer maps entities to LINE / CIRCLE / ARC / POINT / TEXT")
    func dxf() throws {
        let dwg = JWW.Drawing(version: 700, entities: [
            .line(a: .init(x: 0, y: 0), b: .init(x: 1, y: 1), layer: 0, color: 2),
            .arc(center: .init(x: 0, y: 0), radius: 5, start: 0, sweep: 2 * .pi, tilt: 0, ratio: 1, full: true, layer: 0, color: 1),
            .arc(center: .init(x: 0, y: 0), radius: 5, start: 0, sweep: .pi, tilt: 0, ratio: 1, full: false, layer: 0, color: 1),
            .point(at: .init(x: 2, y: 3), layer: 0, color: 1),
            .text(at: .init(x: 0, y: 0), height: 2.5, width: 2.5, angleRad: 0, string: "AB", layer: 0, color: 7),
        ], counts: .init())
        let s = DXFWriter.string(dwg)
        #expect(s.contains("\nLINE\n") && s.contains("\nCIRCLE\n") && s.contains("\nARC\n") && s.contains("\nPOINT\n") && s.contains("\nTEXT\n"))
        #expect(s.hasSuffix("EOF\n"))
        #expect(s.contains("\nAB\n"))                   // text payload
    }

    @Test("arc start/end include the tilt axis, normalized to [0,360)")
    func arcTilt() throws {
        // start=10°, sweep=40°, tilt=90° → DXF start=100°, end=140°.
        let dwg = JWW.Drawing(version: 700, entities: [
            .arc(center: .init(x: 0, y: 0), radius: 1, start: 10 * .pi / 180, sweep: 40 * .pi / 180,
                 tilt: .pi / 2, ratio: 1, full: false, layer: 0, color: 1),
        ], counts: .init())
        let s = DXFWriter.string(dwg)
        let lines = s.components(separatedBy: "\n")
        func after(_ code: String) -> Double? {
            guard let i = lines.firstIndex(of: code) else { return nil }; return Double(lines[i + 1])
        }
        #expect(abs((after("50") ?? 0) - 100) < 1e-3)
        #expect(abs((after("51") ?? 0) - 140) < 1e-3)
    }

    /// A JWW with a top-level line, a dimension, a block insert (→ def 7), then a block-definition list
    /// holding one CDataList (number 7) with a single member line.
    static func sampleWithBlocksAndDims() -> Data {
        var b = Builder()
        b.header()
        b.u16(3)                                        // main array preamble
        b.classTag("CDataSen"); b.senFields(0, 0, 10, 0)                 // top-level line
        b.classTag("CDataSunpou"); b.base(layer: 3)                     // dimension
        b.senFields(0, 0, 10, 0); b.mojiFields("100")                  // dim line + value text
        b.u16(0); b.senFields(0, 0, 0, 1); b.senFields(10, 0, 10, 1)   // sxf mode + 2 witness lines
        for _ in 0..<4 { b.tenFields(0, 0) }                           // 4 arrow/ref points
        b.classTag("CDataBlock"); b.base(layer: 2)                     // block insert → def 7
        b.f64(5); b.f64(6); b.f64(1); b.f64(1); b.f64(0); b.u32(7)
        // block-definition list: count (skipped as a null tag), then one CDataList
        b.u16(1)
        b.classTag("CDataList"); b.base(); b.u32(7); b.u32(0); b.u32(0); b.str("widget")
        b.u16(1)                                                       // 1 member
        b.classTag("CDataSen"); b.senFields(0, 0, 5, 5)                // member line
        return b.d
    }

    @Test("captures block definitions, inserts, and dimensions")
    func blocksAndDims() throws {
        let dwg = try JWW.read(data: Self.sampleWithBlocksAndDims())
        #expect(dwg.counts.line == 1)                   // only the top-level line (dim parts + block members excluded)
        #expect(dwg.counts.dim == 1)
        #expect(dwg.counts.block == 1)                  // the insert
        // block definition 7 captured with its single member line
        let def = try #require(dwg.blocks[7])
        #expect(def.name == "widget" && def.entities.count == 1)
        // the insert references def 7
        guard let ins = dwg.entities.first(where: { if case .insert = $0 { return true } else { return false } }),
              case let .insert(num, at, _, _, _, _, _) = ins else { Issue.record("no insert"); return }
        #expect(num == 7 && at.x == 5 && at.y == 6)
        // the dimension decomposes into parts (line + text + witnesses + arrows)
        guard let dim = dwg.entities.first(where: { if case .dimension = $0 { return true } else { return false } }),
              case let .dimension(parts, _) = dim else { Issue.record("no dimension"); return }
        #expect(parts.count >= 3)
        // DXF carries a BLOCKS section + INSERT
        let dxf = DXFWriter.string(dwg)
        #expect(dxf.contains("\nBLOCKS\n") && dxf.contains("\nBLOCK\n") && dxf.contains("\nINSERT\n") && dxf.contains("\nBLK7\n"))
    }

    @Test("looksLikeJWW + error on bad magic and empty")
    func sniffAndErrors() {
        #expect(JWW.looksLikeJWW(Data("JwwData.".utf8)))
        #expect(!JWW.looksLikeJWW(Data("xof ".utf8)))
        #expect(throws: JWW.Error.self) { try JWW.read(data: Data("NotAJwwFile______".utf8)) }
        #expect(throws: JWW.Error.empty) { try JWW.read(data: Data()) }
    }
}
