import Foundation

/// Writes a ``JWW/Drawing`` as an ASCII **DXF**.
///
/// A version-agnostic DXF that AutoCAD / LibreCAD / most CAD tools accept. Maps
/// JWW entities to DXF: line→`LINE`, full circle→`CIRCLE`, circular arc→`ARC`,
/// elliptical arc→`ELLIPSE`, point→`POINT`, text→`TEXT`, block insert→`INSERT`, and a dimension
/// record with its measured points→`DIMENSION`. Each entity has a handle (group 5), and its layer is
/// named `<group>-<layer>` in hexadecimal, as Jw_cad names it in its own DXF and DWG export: layer
/// 14 of group 0 is `0-E`.
///
/// The `HEADER` declares `$INSUNITS` 4, millimetres; ``Options/fullSize`` says which millimetres.
public enum DXFWriter {

    /// What the writer does beyond copying each entity as it is drawn.
    public struct Options: Equatable, Sendable {
        /// Writes full-size coordinates: each element is multiplied by the scale of its layer group.
        ///
        /// A group drawn at 1:80 has its lengths multiplied by 80. Each element uses its own
        /// group's scale, so a drawing whose groups differ in scale is not averaged. A block insert
        /// scales its position and scale factors, and its members follow the insert.
        ///
        /// The `HEADER` says millimetres either way. With this set the coordinates are real
        /// millimetres (a group with no usable scale stays as drawn), and without it they are
        /// millimetres of paper at the drawn scale.
        public var fullSize: Bool

        /// Writes the dimensions ``JWW/Drawing/recoveringDimensions()`` rebuilds as `DIMENSION`s.
        ///
        /// Each rebuilt dimension is one rotated linear `DIMENSION`, and the loose lines, points
        /// and text it was built from go in the anonymous block it names instead of the entities.
        /// A value text no dimension explains stays a loose `TEXT`.
        public var recoversDimensions: Bool

        public init(fullSize: Bool = false, recoversDimensions: Bool = false) {
            self.fullSize = fullSize
            self.recoversDimensions = recoversDimensions
        }
    }

    /// What the DXF text alone does not say: the dimensions the writer inferred and the scales it
    /// applied.
    public struct Report: Equatable, Sendable {
        /// The handles (group 5) of the `DIMENSION`s rebuilt from loose pieces, not read from a
        /// stored record.
        public var recoveredDimensions: [String]
        /// Indices into ``JWW/Drawing/elements`` of the dimension value texts no dimension explains.
        public var unexplainedValues: [Int]
        /// For each handle in ``recoveredDimensions``, the indices into ``JWW/Drawing/elements`` of
        /// the pieces the `DIMENSION` was built from and holds in its block.
        ///
        /// Each list is the ``JWW/RecoveredDimension/elementIndices`` of that dimension.
        public var recoveredDimensionElements: [String: [Int]]
        /// The factor the top-level elements of each layer group were multiplied by, keyed by group.
        ///
        /// Every layer group of a top-level element is listed. The factor is the group's scale with
        /// ``Options/fullSize`` when that scale is finite and positive, and 1 otherwise. A block
        /// member is written as drawn and takes the factor of the insert that places it.
        public var appliedScales: [Int: Double]

        public init(
            recoveredDimensions: [String] = [], unexplainedValues: [Int] = [],
            recoveredDimensionElements: [String: [Int]] = [:], appliedScales: [Int: Double] = [:]
        ) {
            self.recoveredDimensions = recoveredDimensions
            self.unexplainedValues = unexplainedValues
            self.recoveredDimensionElements = recoveredDimensionElements
            self.appliedScales = appliedScales
        }
    }

    /// The DXF text with its ``Report``.
    public struct Output: Sendable {
        public var text: String
        public var report: Report
    }

    public static func string(_ dwg: JWW.Drawing, options: Options = Options()) -> String {
        output(dwg, options: options).text
    }

    /// Writes the DXF to `url` and returns its ``Report``.
    @discardableResult
    public static func write(
        _ dwg: JWW.Drawing, to url: URL, options: Options = Options()
    ) throws -> Report {
        let result = output(dwg, options: options)
        try result.text.write(to: url, atomically: true, encoding: .utf8)
        return result.report
    }

    /// The DXF text and a report of the dimensions it recovered, the values it could not explain and
    /// the scale it applied to each layer group.
    ///
    /// The dimension fields of the report are empty unless ``Options/recoversDimensions`` is set.
    public static func output(_ dwg: JWW.Drawing, options: Options = Options()) -> Output {
        var emitter = DXFEmitter(drawing: dwg, options: options)
        var blocks = ""
        for num in dwg.blocks.keys.sorted() {
            if let def = dwg.blocks[num] { emitter.emitBlock(def, into: &blocks) }
        }

        var report = Report()
        for group in Set(dwg.elements.map(\.attributes.layerGroup)) {
            report.appliedScales[group] = emitter.scale(ofGroup: group)
        }

        // A recovered dimension is written where its first piece was, and its pieces are not
        // written again as loose entities.
        var starting: [Int: [(JWW.RecoveredDimension, DXFDimension)]] = [:]
        var consumed = Set<Int>()
        if options.recoversDimensions {
            let recovery = dwg.recoveringDimensions()
            report.unexplainedValues = recovery.unmatchedValues
            for found in recovery.dimensions {
                guard let first = found.elementIndices.first,
                    let dimension = DXFDimension(recovered: found.dimension)
                else { continue }
                starting[first, default: []].append((found, dimension))
                consumed.formUnion(found.elementIndices)
            }
        }

        var entities = ""
        entities.reserveCapacity(dwg.elements.count * 120)
        for (index, element) in dwg.elements.enumerated() {
            for (found, dimension) in starting[index] ?? [] {
                let handle = emitter.emitRecovered(found, as: dimension, into: &entities)
                report.recoveredDimensions.append(handle)
                report.recoveredDimensionElements[handle] = found.elementIndices
            }
            if consumed.contains(index) { continue }
            emitter.emit(element, scale: emitter.scale(of: element), into: &entities)
        }

        var s = "999\nSwiftJWW\n"
        s += header()
        s += emitter.tables()
        if !blocks.isEmpty || !emitter.anonymousBlocks.isEmpty {
            s += "0\nSECTION\n2\nBLOCKS\n" + blocks + emitter.anonymousBlocks.joined()
            s += "0\nENDSEC\n"
        }
        s += "0\nSECTION\n2\nENTITIES\n" + entities + "0\nENDSEC\n0\nEOF\n"
        return Output(text: s, report: report)
    }

    /// The name the writer gives a JWW layer: the layer group and layer in hexadecimal, such as `0-E`.
    public static func layerName(group: Int, layer: Int) -> String {
        "\(String(group, radix: 16, uppercase: true))-\(String(layer, radix: 16, uppercase: true))"
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
    /// code page (the `HEADER` carries no `$DWGCODEPAGE`).
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
