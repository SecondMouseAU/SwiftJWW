import Foundation

/// Sequential little-endian byte cursor + JWW document parser. The header is consumed byte-exactly
/// (most fields discarded); the entity list is dispatched via the MFC `CArchive` class-tag protocol.
extension JWW {
    struct Reader {
        let b: [UInt8]
        var p = 0
        var version = 0

        init(_ data: Data) { b = [UInt8](data) }

        // MARK: primitives (LE)

        mutating func u8() throws -> Int { try ensure(1); defer { p += 1 }; return Int(b[p]) }
        mutating func u16() throws -> Int { try ensure(2); defer { p += 2 }; return Int(b[p]) | (Int(b[p + 1]) << 8) }
        mutating func u32() throws -> Int {
            try ensure(4); defer { p += 4 }
            return Int(b[p]) | (Int(b[p + 1]) << 8) | (Int(b[p + 2]) << 16) | (Int(b[p + 3]) << 24)
        }
        mutating func f64() throws -> Double {
            try ensure(8); defer { p += 8 }
            var bits: UInt64 = 0
            for k in 0..<8 { bits |= UInt64(b[p + k]) << (8 * k) }
            return Double(bitPattern: bits)
        }
        mutating func skip(_ n: Int) throws { try ensure(n); p += n }
        func ensure(_ n: Int) throws { guard n >= 0, p + n <= b.count else { throw JWW.Error.truncated } }
        var eof: Bool { p >= b.count }

        /// A JWW length-prefixed byte string: `u8 len`, or if len==0xFF then `u16 len`; then `len` bytes.
        /// Returns the raw bytes (consumes the full declared length regardless).
        mutating func jwString() throws -> [UInt8] {
            let n0 = try u8()
            let n = n0 == 0xFF ? try u16() : n0
            try ensure(n); defer { p += n }
            return Array(b[p..<p + n])
        }
        mutating func skipString() throws { _ = try jwString() }

        // MARK: header (faithful port of jwwlib JWWDocument::ReadHeader)

        mutating func readHeader() throws {
            try ensure(8)
            guard Array(b[0..<8]) == Array("JwwData.".utf8) else { throw JWW.Error.badMagic }
            p = 8
            version = try u32()
            guard version == 230 || version >= 300 else { throw JWW.Error.unsupportedVersion(version) }

            try skipString()                                   // memo
            try skip(4)                                        // zumen
            try skip(4)                                        // writeGLay
            for _ in 0..<16 {                                  // 16 layer-groups
                try skip(4); try skip(4); try skip(8); try skip(4)   // glay, writeLay, scale(d), glayProtect
                for _ in 0..<16 { try skip(4); try skip(4) }   // 16 layers: lay, layProtect
            }
            try skip(14 * 4)                                   // Dummy[14]
            try skip(5 * 4)                                    // Sunpou1..5
            try skip(4)                                        // Dummy1
            try skip(4)                                        // maxDrawWid
            try skip(8 * 2)                                    // PrtGenten x,y
            try skip(8)                                        // prtBairitsu
            try skip(4)                                        // prt90Kaiten
            try skip(4)                                        // memoriMode
            try skip(8)                                        // memoriHyoujiMin
            try skip(8 * 2)                                    // memoriX, memoriY
            try skip(8 * 2)                                    // memoriKijunTen x,y
            for _ in 0..<(16 * 16) { try skipString() }        // layer names
            for _ in 0..<16 { try skipString() }               // group names
            try skip(8); try skip(8); try skip(4); try skip(8) // kageLevel, kageIdo, kage9_15Flg, kabeKageLevel
            if version >= 300 { try skip(8); try skip(8) }     // tenkuuZuLevel, tenkuuZuEnkoR
            try skip(4)                                        // mmTani3D
            try skip(8); try skip(8 * 2)                       // bairitsu, genten x,y
            try skip(8); try skip(8 * 2)                       // hanniBairitsu, hanniGenten x,y
            if version >= 300 {
                for _ in 0..<8 { try skip(8); try skip(8); try skip(8); try skip(4) }   // zoom 1..8: 3d + dword
            } else {
                for _ in 0..<4 { try skip(8); try skip(8); try skip(8) }                // zoom 1..4: 3d
            }
            if version >= 300 {
                try skip(8 * 3); try skip(4); try skip(8 * 2); try skip(8); try skip(4) // dDm11-13, lnDm1, dDm21-22, mojiBG, nMojiBG
            }
            for _ in 0..<10 { try skip(8) }                    // fukusen[0..9]
            try skip(8)                                        // ryoygawaFukusenTomeDe
            for _ in 0..<10 { try skip(4); try skip(4) }       // Pen[0..9] color, width
            for _ in 0..<10 { try skip(4); try skip(4); try skip(8) }   // PrtPen[0..9] color, width, tenHankei
            for _ in 0..<8 { try skip(4 * 4) }                 // LType1 (i=2..9)
            for _ in 0..<5 { try skip(5 * 4) }                 // LType2 (i=11..15)
            for _ in 0..<4 { try skip(4 * 4) }                 // LType3 (i=16..19)
            try skip(4 * 11)                                   // 11 draw/print flags
            try skip(4); try skip(4)                           // lnDrawTime, nEyeInit
            try skip(4 * 3)                                    // eye_H_Ichi 1,2,3 (DWORD)
            try skip(8 * 5)                                    // eye Z1,Y1,Z2,Y2,V3 (DOUBLE)
            try skip(8 * 4)                                    // senNagasa, boxX, boxY, enHankey
            try skip(4); try skip(4)                           // solidNinniColor, solidColor
            if version >= 420 {
                for _ in 0..<257 { try skip(4); try skip(4) }                          // SXF color display
                for _ in 0..<257 { try skipString(); try skip(4); try skip(4); try skip(8) } // SXF color print
                for _ in 0..<33 { try skip(4 * 4) }                                    // SXF ltype pattern
                for _ in 0..<33 { try skipString(); try skip(4); for _ in 0..<10 { try skip(8) } } // SXF ltype param
            }
            for _ in 0..<10 { try skip(8 * 3); try skip(4) }   // Moji[1..10] x,y,d, col
            try skip(8 * 3)                                    // mojiSizeX,Y,Kankaku
            try skip(4); try skip(4)                           // mojiColor, mojiShu
            try skip(8); try skip(8); try skip(4)              // seiriGyouKan, seiriSuu, kijunZureOn
            try skip(8 * 3); try skip(8 * 3)                   // kijunZureX[3], kijunZureY[3]
        }

        // MARK: entity base (CData)

        struct Base { var penStyle = 0, penColor = 0, layer = 0 }
        mutating func readBase() throws -> Base {
            _ = try u32()                                      // group
            let penStyle = try u8()
            let penColor = try u16()
            if version >= 351 { _ = try u16() }                // penWidth
            let layer = try u16()
            _ = try u16()                                      // glayer
            _ = try u16()                                      // flags
            return Base(penStyle: penStyle, penColor: penColor, layer: layer)
        }

        // MARK: parse

        enum Parsed { case entity(JWW.Entity), blockDef(JWW.BlockDef), solid, skip }

        /// MFC `ReadCount` — a WORD, or (if it equals 0xFFFF) a following DWORD. Used for the object-array
        /// length and each block definition's member count.
        mutating func readCount() throws -> Int { let w = try u16(); return w == 0xFFFF ? try u32() : w }

        mutating func parse() throws -> JWW.Drawing {
            try readHeader()
            var entities: [JWW.Entity] = []
            var blocks: [Int: JWW.BlockDef] = [:]
            var counts = JWW.Drawing.Counts()

            // MFC CArchive object map: BOTH class definitions and every object consume an index, so a
            // back-reference index points past all preceding objects to the class's definition slot.
            var classMap: [Int: String] = [:]
            var mapIndex = 1

            _ = try readCount()                                 // main object-array length (drive by EOF below)
            while !eof {
                let parsed: Parsed
                do { parsed = try readObject(&classMap, &mapIndex) } catch JWW.Error.truncated { break }
                switch parsed {
                case .entity(let e):
                    entities.append(e)
                    switch e {
                    case .line: counts.line += 1
                    case .arc: counts.arc += 1
                    case .point: counts.point += 1
                    case .text: counts.text += 1
                    case .insert: counts.block += 1
                    case .dimension: counts.dim += 1
                    }
                case .blockDef(let bd): blocks[bd.number] = bd
                case .solid: counts.solid += 1
                case .skip: break
                }
            }
            return JWW.Drawing(version: version, entities: entities, blocks: blocks, counts: counts)
        }

        /// Read one MFC object: resolve its class tag, then deserialize the entity. `CDataList` (a block
        /// definition) recursively reads its member objects; `CDataBlock` is a block insert; `CDataSunpou`
        /// is decomposed into its drawn parts.
        mutating func readObject(_ classMap: inout [Int: String], _ mapIndex: inout Int) throws -> Parsed {
            let tag = try u16()
            var j = 0
            switch tag {
            case 0x0000: return .skip                           // null object — no index consumed
            case 0xFFFF:
                _ = try u16()                                   // schema
                let len = try u16()                             // class-name length (WORD)
                try ensure(len); let name = Array(b[p..<p + len]); p += len
                classMap[mapIndex] = String(decoding: name, as: UTF8.self)
                j = mapIndex; mapIndex += 1
            case 0xFF7F, 0x7FFF:
                j = try u32() & 0x7FFFFFFF
            default:
                j = (tag & 0x8000) != 0 ? (tag & 0x7FFF) : 0
            }
            guard let cls = classMap[j] else { return .skip }
            mapIndex += 1                                        // the object about to be read takes an index

            switch cls {
            case "CDataSen":   return .entity(try readSen())
            case "CDataEnko":  return .entity(try readEnko())
            case "CDataTen":   return .entity(try readTen())
            case "CDataMoji":  return .entity(try readMoji())
            case "CDataSolid":
                let base = try readBase(); try skip(8 * 8)
                if base.penColor == 10 { _ = try u32() }
                return .solid
            case "CDataBlock":
                let base = try readBase()
                let at = JWW.Point(x: try f64(), y: try f64())
                let sx = try f64(), sy = try f64(), rot = try f64()
                let num = try u32()
                return .entity(.insert(def: num, at: at, scaleX: sx, scaleY: sy, rotationRad: rot, layer: base.layer, color: base.penColor))
            case "CDataList":
                _ = try readBase()
                let num = try u32(); _ = try u32(); _ = try u32()      // number, reffered, time
                let nameRaw = try jwString()
                let memberCount = try readCount()                       // CObList of member entities
                var members: [JWW.Entity] = []
                var n = 0
                while n < memberCount {
                    n += 1
                    if case .entity(let e) = try readObject(&classMap, &mapIndex) { members.append(e) }
                }
                let name = String(decoding: nameRaw, as: UTF8.self).components(separatedBy: "@@").first ?? ""
                return .blockDef(.init(number: num, name: name, entities: members))
            case "CDataSunpou":
                return .entity(try readSunpou())
            default:
                throw JWW.Error.unknownClass(cls)
            }
        }

        // MARK: entity field reads

        mutating func readSen() throws -> JWW.Entity {
            let base = try readBase()
            let a = JWW.Point(x: try f64(), y: try f64())
            let b = JWW.Point(x: try f64(), y: try f64())
            return .line(a: a, b: b, layer: base.layer, color: base.penColor)
        }
        mutating func readEnko() throws -> JWW.Entity {
            let base = try readBase()
            let c = JWW.Point(x: try f64(), y: try f64())
            let r = try f64(), sa = try f64(), aa = try f64(), tilt = try f64(), ratio = try f64()
            let full = try u32() != 0
            return .arc(center: c, radius: r, start: sa, sweep: aa, tilt: tilt, ratio: ratio, full: full, layer: base.layer, color: base.penColor)
        }
        mutating func readTen() throws -> JWW.Entity {
            let base = try readBase()
            let pt = JWW.Point(x: try f64(), y: try f64())
            _ = try u32()                                       // kariten
            if base.penStyle == 100 { _ = try u32(); _ = try f64(); _ = try f64() }
            return .point(at: pt, layer: base.layer, color: base.penColor)
        }
        mutating func readMoji() throws -> JWW.Entity {
            let base = try readBase()
            let at = JWW.Point(x: try f64(), y: try f64())
            _ = try f64(); _ = try f64()                        // end x,y
            _ = try u32()                                       // mojiShu
            let sx = try f64(), sy = try f64(); _ = try f64()
            let ang = try f64()
            _ = try jwString()                                  // font name
            let raw = try jwString()                            // text
            return .text(at: at, height: sy, width: sx, angleRad: ang, raw: raw, layer: base.layer, color: base.penColor)
        }
        /// Dimension = base + dimension line + value text, plus (v4.20+) a mode word, two witness lines,
        /// and four arrow/reference points. Decomposed into its drawn parts.
        mutating func readSunpou() throws -> JWW.Entity {
            let base = try readBase()
            var parts: [JWW.Entity] = []
            parts.append(try readSen())                         // dimension line
            parts.append(try readMoji())                        // value text
            if version >= 420 {
                _ = try u16()                                   // SXF mode
                parts.append(try readSen()); parts.append(try readSen())   // witness lines
                for _ in 0..<4 { parts.append(try readTen()) }  // arrows / reference points
            }
            return .dimension(parts: parts, layer: base.layer)
        }
    }
}
