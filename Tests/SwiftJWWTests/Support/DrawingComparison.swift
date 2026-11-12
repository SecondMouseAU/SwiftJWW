import Foundation

@testable import SwiftJWW

/// Compares a JWW drawing with the DXF its publisher exported from it.
///
/// The export conventions below were read from real JWW and DXF pairs, not taken from a spec:
/// - Coordinates are full size: the drawn value plus half the sheet, times `$LTSCALE`. The sheet is
///   the DXF header's `$EXTMAX` over `$LTSCALE`. `$LTSCALE` is the scale of the write-target layer
///   group, and it is applied to every layer group, whatever scale the group itself has.
/// - A layer is named `_<group>-<layer>_<name>` with group and layer in hex. A name character whose
///   CP932 bytes the export cannot keep is written as one underscore per byte.
/// - The format is R12, which has no `ELLIPSE`: an elliptical arc is written as `LINE` segments.
/// - A line of line type 9 is written on a layer called `ADD_LINE`.
/// Anything beyond those is reported as unexplained.
enum DrawingComparison {
    /// Full-size millimetres within which two coordinates are the same.
    static let tolerance = 0.01

    struct Report {
        var matched: [String: Int] = [:]
        var explained: [String] = []
        var unexplained: [String] = []

        func summary(_ name: String) -> String {
            let counts = matched.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
            var out = "\(name): matched \(counts.joined(separator: ", "))"
            for line in explained { out += "\n  explained: \(line)" }
            for line in unexplained.prefix(25) { out += "\n  UNEXPLAINED: \(line)" }
            if unexplained.count > 25 { out += "\n  ... \(unexplained.count - 25) more" }
            return out
        }
    }

    private enum Kind: String {
        case line, circle, arc, ellipse, point, text
    }

    private struct Item {
        var kind: Kind
        var layer: String
        var anchor: (x: Double, y: Double)
        var key: [Double]
        var text = ""
        var ellipse: JWW.Entity?
        var note: String { "\(kind.rawValue) \(key.map { String(format: "%.3f", $0) })\(text)" }
    }

    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    static func compare(_ jww: JWW.Drawing, _ dxf: ReferenceDXF) -> Report {
        var report = Report()
        guard let ltscale = dxf.header["$LTSCALE"]?[40].flatMap(Double.init), ltscale > 0,
            let extX = dxf.header["$EXTMAX"]?[10].flatMap(Double.init),
            let extY = dxf.header["$EXTMAX"]?[20].flatMap(Double.init)
        else {
            report.unexplained.append("the DXF header has no usable $LTSCALE and $EXTMAX")
            return report
        }
        let offset = (x: extX / ltscale / 2, y: extY / ltscale / 2)
        let writeGroups = jww.layerGroups.filter { $0.state == 3 }
        if let write = writeGroups.first, writeGroups.count == 1 {
            if abs(write.scale - ltscale) > 1e-9 {
                report.unexplained.append(
                    "$LTSCALE is \(ltscale) but the write layer group is 1:\(write.scale)")
            }
        } else {
            report.unexplained.append("\(writeGroups.count) layer groups are write targets")
        }
        let used = Set(jww.elements.map(\.attributes.layerGroup))
        for group in jww.layerGroups where used.contains(group.index) && group.scale != ltscale {
            report.explained.append(
                "layer group \(group.index) is 1:\(group.scale), the DXF applies 1:\(ltscale) to it"
            )
        }

        let expansion = jww.expandingBlocks()
        for ref in expansion.unresolved {
            report.unexplained.append("block \(ref.definition) could not be expanded")
        }
        var expected: [Item] = []
        for element in expansion.elements {
            collect(element.entity, element.attributes, jww, offset, ltscale, &expected)
        }
        var actual: [Item] = []
        for entity in dxf.entities {
            if let item = dxfItem(entity) {
                actual.append(item)
            } else {
                report.unexplained.append("the DXF has an unsupported \(entity.type)")
            }
        }

        var expectedBy: [String: [Item]] = [:]
        var actualBy: [String: [Item]] = [:]
        for item in expected {
            expectedBy["\(item.layer)|\(item.kind.rawValue)", default: []].append(item)
        }
        for item in actual {
            actualBy["\(item.layer)|\(item.kind.rawValue)", default: []].append(item)
        }
        var ellipsesBy: [String: [Item]] = [:]
        for item in expected where item.kind == .ellipse {
            ellipsesBy[item.layer, default: []].append(item)
        }

        var ellipseSegments = 0
        for key in Set(expectedBy.keys).union(actualBy.keys).sorted() {
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            let layer = String(parts[0])
            guard let kind = Kind(rawValue: String(parts[1])), kind != .ellipse else { continue }
            let want = expectedBy[key] ?? []
            let (missing, extra) = match(want, actualBy[key] ?? [])
            report.matched[kind.rawValue, default: 0] += want.count - missing.count
            for item in missing {
                report.unexplained.append("in the JWW, not in the DXF on \(layer): \(item.note)")
            }
            for item in extra {
                if kind == .line, isEllipseSegment(item, ellipsesBy[layer] ?? []) {
                    ellipseSegments += 1
                } else {
                    report.unexplained.append(
                        "in the DXF, not in the JWW on \(layer): \(item.note)")
                }
            }
        }
        let ellipseCount = expected.filter { $0.kind == .ellipse }.count
        if ellipseCount > 0 {
            report.explained.append(
                "\(ellipseCount) elliptical arcs written as \(ellipseSegments) LINE segments (R12 has no ELLIPSE)"
            )
        }
        let dotted = expected.filter { $0.layer == "ADD_LINE" }.count
        if dotted > 0 {
            report.explained.append("\(dotted) line type 9 lines written on layer ADD_LINE")
        }

        checkLayerNames(jww, dxf, &report)
        checkDimensions(jww, dxf, ltscale, offset, &report)
        return report
    }

    // MARK: JWW side

    private static func collect(
        _ entity: JWW.Entity, _ attributes: JWW.Attributes, _ jww: JWW.Drawing,
        _ offset: (x: Double, y: Double), _ scale: Double, _ out: inout [Item]
    ) {
        let group = attributes.layerGroup
        func full(_ p: JWW.Point) -> (x: Double, y: Double) {
            ((p.x + offset.x) * scale, (p.y + offset.y) * scale)
        }
        func layerName(_ layer: Int) -> String { layerKey(group: group, layer: layer) }
        switch entity {
        case .line(let a, let b, let layer, _):
            let p = full(a)
            let q = full(b)
            out.append(
                Item(
                    kind: .line, layer: attributes.lineType == 9 ? "ADD_LINE" : layerName(layer),
                    anchor: ((p.x + q.x) / 2, (p.y + q.y) / 2), key: [p.x, p.y, q.x, q.y]))
        case .point(let at, let layer, _):
            let p = full(at)
            out.append(Item(kind: .point, layer: layerName(layer), anchor: p, key: [p.x, p.y]))
        case .text(let at, let height, _, let angle, let string, let layer, _):
            let p = full(at)
            var degrees = (angle * 180 / .pi).truncatingRemainder(dividingBy: 360)
            if degrees < 0 { degrees += 360 }
            out.append(
                Item(
                    kind: .text, layer: layerName(layer), anchor: p,
                    key: [p.x, p.y, height * scale, degrees], text: string))
        case .arc(let c, let r, let start, let sweep, let tilt, let ratio, let isFull, let layer, _):
            let center = full(c)
            if abs(ratio - 1) > 1e-9 {
                let ellipse = JWW.Entity.arc(
                    center: .init(x: center.x, y: center.y), radius: r * scale,
                    start: isFull ? 0 : start, sweep: isFull ? 2 * .pi : sweep, tilt: tilt,
                    ratio: ratio, full: isFull, layer: layer, color: 0)
                out.append(
                    Item(
                        kind: .ellipse, layer: layerName(layer), anchor: center, key: [],
                        ellipse: ellipse))
            } else if isFull || abs(abs(sweep) - 2 * .pi) < 1e-6 {
                out.append(
                    Item(
                        kind: .circle, layer: layerName(layer), anchor: center,
                        key: [center.x, center.y, r * scale]))
            } else {
                let lo = tilt + start + min(0, sweep)
                let hi = lo + abs(sweep)
                func onCircle(_ a: Double) -> [Double] {
                    [center.x + r * scale * cos(a), center.y + r * scale * sin(a)]
                }
                out.append(
                    Item(
                        kind: .arc, layer: layerName(layer), anchor: center,
                        key: [center.x, center.y, r * scale] + onCircle((lo + hi) / 2)
                            + onCircle(lo)
                            + onCircle(hi)))
            }
        case .dimension(let parts, _):
            for part in parts { collect(part, attributes, jww, offset, scale, &out) }
        case .insert:
            break
        }
    }

    // MARK: layers

    /// The layer an item is matched on: `_<group>-<layer>_` for a JWW layer, the whole name otherwise.
    private static func layerKey(group: Int, layer: Int) -> String {
        "_\(String(group, radix: 16))-\(String(layer, radix: 16))_"
    }

    private static func layerKey(_ dxfLayer: String) -> String {
        guard let name = splitLayer(dxfLayer) else { return dxfLayer }
        return layerKey(group: name.group, layer: name.layer)
    }

    private static func splitLayer(_ name: String) -> (group: Int, layer: Int, rest: String)? {
        let c = Array(name)
        guard c.count >= 5, c[0] == "_", c[2] == "-", c[4] == "_",
            let g = Int(String(c[1]), radix: 16), let l = Int(String(c[3]), radix: 16)
        else { return nil }
        return (g, l, String(c[5...]))
    }

    private static func cp932(_ s: String) -> [UInt8] {
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        return [UInt8](s.data(using: encoding) ?? Data())
    }

    /// Every DXF layer's name must be the JWW layer's name, or the same bytes with some written as `_`.
    private static func checkLayerNames(
        _ jww: JWW.Drawing, _ dxf: ReferenceDXF, _ report: inout Report
    ) {
        for layer in Set(dxf.entities.map(\.layer)).sorted() {
            guard let parts = splitLayer(layer) else { continue }
            var name: String?
            if jww.layerGroups.indices.contains(parts.group),
                jww.layerGroups[parts.group].layers.indices.contains(parts.layer)
            {
                name = jww.layerGroups[parts.group].layers[parts.layer].name
            }
            guard let name else {
                report.unexplained.append("the DXF has layer \(layer), the JWW has no such layer")
                continue
            }
            if name == parts.rest { continue }
            let want = cp932(name)
            let got = cp932(parts.rest)
            if want.count == got.count && zip(want, got).allSatisfy({ $0 == $1 || $1 == 0x5F }) {
                report.explained.append("layer name \(name) is written \(parts.rest) in the DXF")
            } else {
                report.unexplained.append("layer \(layer) is named \(name) in the JWW")
            }
        }
    }

    // MARK: DXF side

    private static func dxfItem(_ e: ReferenceDXF.Entity) -> Item? {
        guard let x = e.number(10), let y = e.number(20) else { return nil }
        switch e.type {
        case "LINE":
            guard let x2 = e.number(11), let y2 = e.number(21) else { return nil }
            return Item(
                kind: .line, layer: layerKey(e.layer), anchor: ((x + x2) / 2, (y + y2) / 2),
                key: [x, y, x2, y2])
        case "POINT":
            return Item(kind: .point, layer: layerKey(e.layer), anchor: (x, y), key: [x, y])
        case "CIRCLE":
            guard let r = e.number(40) else { return nil }
            return Item(kind: .circle, layer: layerKey(e.layer), anchor: (x, y), key: [x, y, r])
        case "ARC":
            guard let r = e.number(40), let a0 = e.number(50), let a1 = e.number(51) else {
                return nil
            }
            var span = (a1 - a0).truncatingRemainder(dividingBy: 360)
            if span <= 0 { span += 360 }
            func onCircle(_ degrees: Double) -> [Double] {
                [x + r * cos(degrees * .pi / 180), y + r * sin(degrees * .pi / 180)]
            }
            return Item(
                kind: .arc, layer: layerKey(e.layer), anchor: (x, y),
                key: [x, y, r] + onCircle(a0 + span / 2) + onCircle(a0) + onCircle(a0 + span))
        case "TEXT":
            guard let h = e.number(40), let string = e.text(1) else { return nil }
            var degrees = (e.number(50) ?? 0).truncatingRemainder(dividingBy: 360)
            if degrees < 0 { degrees += 360 }
            return Item(
                kind: .text, layer: layerKey(e.layer), anchor: (x, y), key: [x, y, h, degrees],
                text: string)
        default:
            return nil
        }
    }

    // MARK: matching

    private static func close(_ a: Item, _ b: Item) -> Bool {
        let near = { (u: Double, v: Double) in abs(u - v) <= tolerance }
        switch a.kind {
        case .line:
            let same = zip(a.key, b.key).allSatisfy(near)
            let swapped =
                near(a.key[0], b.key[2]) && near(a.key[1], b.key[3])
                && near(a.key[2], b.key[0]) && near(a.key[3], b.key[1])
            return same || swapped
        case .text:
            let turn = abs(a.key[3] - b.key[3])
            return a.text == b.text && zip(a.key.prefix(3), b.key.prefix(3)).allSatisfy(near)
                && min(turn, 360 - turn) <= 0.01
        default:
            return a.key.count == b.key.count && zip(a.key, b.key).allSatisfy(near)
        }
    }

    private static func match(_ expected: [Item], _ actual: [Item]) -> (
        missing: [Item], extra: [Item]
    ) {
        let size = 100.0
        func cell(_ p: (x: Double, y: Double)) -> Cell {
            Cell(x: Int((p.x / size).rounded(.down)), y: Int((p.y / size).rounded(.down)))
        }
        var grid: [Cell: [Int]] = [:]
        for (i, item) in actual.enumerated() { grid[cell(item.anchor), default: []].append(i) }
        var used = Set<Int>()
        var missing: [Item] = []
        for item in expected {
            let home = cell(item.anchor)
            var found = false
            search: for dx in -1...1 {
                for dy in -1...1 {
                    for i in grid[Cell(x: home.x + dx, y: home.y + dy)] ?? []
                    where !used.contains(i) && close(item, actual[i]) {
                        used.insert(i)
                        found = true
                        break search
                    }
                }
            }
            if !found { missing.append(item) }
        }
        let extra = actual.enumerated().filter { !used.contains($0.offset) }.map(\.element)
        return (missing, extra)
    }

    /// True when both ends of a line lie on one of the layer's elliptical arcs.
    private static func isEllipseSegment(_ line: Item, _ ellipses: [Item]) -> Bool {
        let ends = [
            JWW.Point(x: line.key[0], y: line.key[1]), JWW.Point(x: line.key[2], y: line.key[3]),
        ]
        return ellipses.contains { item in
            guard let e = item.ellipse else { return false }
            return ends.allSatisfy { ArcGeometry.contains(e, $0, tolerance: tolerance) }
        }
    }

    // MARK: dimensions

    /// Every recovered dimension must have its value text in the DXF, at the same place.
    private static func checkDimensions(
        _ jww: JWW.Drawing, _ dxf: ReferenceDXF, _ scale: Double, _ offset: (x: Double, y: Double),
        _ report: inout Report
    ) {
        let recovery = jww.recoveringDimensions()
        let texts = dxf.entities.filter { $0.type == "TEXT" }
        for found in recovery.dimensions {
            let label = found.dimension.label
            let x = (label.at.x + offset.x) * scale
            let y = (label.at.y + offset.y) * scale
            let present = texts.contains {
                $0.text(1) == label.string && abs(($0.number(10) ?? .nan) - x) <= tolerance
                    && abs(($0.number(20) ?? .nan) - y) <= tolerance
            }
            if !present {
                report.unexplained.append(
                    "dimension \(label.string) has no TEXT at its position in the DXF")
            }
        }
        var valueTexts = 0
        for element in jww.elements {
            if case .text = element.entity, element.attributes.flags & 0x4010 == 0x4010 {
                valueTexts += 1
            }
        }
        var line =
            "\(recovery.dimensions.count) dimensions recovered from \(valueTexts) value texts"
        if !recovery.unmatchedValues.isEmpty {
            let strings = recovery.unmatchedValues.compactMap { i -> String? in
                if case .text(_, _, _, _, let s, _, _) = jww.elements[i].entity { return s }
                return nil
            }
            line += ", unrecovered: \(strings)"
        }
        report.explained.append(line)
    }
}
