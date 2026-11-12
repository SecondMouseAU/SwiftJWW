import Foundation

extension JWW {
    /// A dimension recovered from loose entities, with the elements it was built from.
    public struct RecoveredDimension: Sendable {
        public var dimension: Dimension
        /// Indices into ``Drawing/elements`` of the value text, the two arrow points, the dimension
        /// line pieces and the extension lines the dimension was built from, in ascending order.
        public var elementIndices: [Int]
    }

    /// The outcome of ``Drawing/recoveringDimensions()``.
    public struct DimensionRecovery: Sendable {
        public var dimensions: [RecoveredDimension]
        /// Indices into ``Drawing/elements`` of dimension value texts no measured pair explained:
        /// radius, diameter and angle values, values in another unit, and any text with no pair of
        /// arrow points at the stated distance.
        public var unmatchedValues: [Int]
    }
}

/// Attribute flag bits a dimension leaves on the loose entities it is made of (`jwdatafmt`).
private enum DimensionFlag {
    static let textValue = 0x0010
    static let textDimension = 0x4000
    static let textRadius = 0x0100
    static let textDiameter = 0x0200
    static let textAngle = 0x0400
    static let pointDimension = 0x0040
    static let lineDimension = 0x2000
}

extension JWW.Drawing {
    /// Recovers linear dimensions from files that store them as loose entities.
    ///
    /// Jw_cad stores a dimension as one `CDataSunpou` record only when the drawing was made with its
    /// dimension command, and ``Element/dimension`` reads those. A drawing converted from an older
    /// format, or one whose dimensions were exploded, keeps the pieces as separate lines, points and
    /// text, marked with the dimension attribute flags. This pairs each dimension value text with
    /// the two neighbouring arrow points whose distance times the layer group scale gives the stated
    /// value, picks the pair nearest the text, and adds the extension lines that end on the points.
    ///
    /// It is an inference: the result lists every text it could not explain in
    /// ``DimensionRecovery/unmatchedValues``. The measured points of a recovered dimension are its
    /// arrow points, since a loose file stores no reference points.
    public func recoveringDimensions() -> JWW.DimensionRecovery {
        let tolerance = 1e-3
        var texts: [LooseText] = []
        var points: [LoosePoint] = []
        var lines: [LooseLine] = []
        var unmatched: [Int] = []
        var seen: [String: [Int]] = [:]
        for (index, element) in elements.enumerated() {
            let flags = element.attributes.flags
            let group = element.attributes.layerGroup
            switch element.entity {
            case .text(let at, let height, let width, let angle, let string, _, _)
            where flags & DimensionFlag.textValue != 0
                && flags & DimensionFlag.textDimension != 0:
                let other =
                    DimensionFlag.textRadius | DimensionFlag.textDiameter | DimensionFlag.textAngle
                guard flags & other == 0, let value = JWW.Dimension.parseValue(string),
                    let scale = scale(ofLayerGroup: group), scale > 0
                else {
                    unmatched.append(index)
                    continue
                }
                let key = "\(group)|\(string)"
                if let first = seen[key]?.first(where: {
                    hypot(texts[$0].at.x - at.x, texts[$0].at.y - at.y) <= tolerance
                }) {
                    texts[first].duplicates.append(index)  // the same text stored twice
                    continue
                }
                seen[key, default: []].append(texts.count)
                texts.append(
                    LooseText(
                        index: index, group: group, at: at, value: value, scale: scale,
                        tolerance: JWW.Dimension.roundingTolerance(of: string),
                        label: JWW.Dimension.Label(
                            at: at, height: height, width: width, angleRad: angle, string: string)))
            case .point(let p, _, _) where flags & DimensionFlag.pointDimension != 0:
                points.append(LoosePoint(index: index, group: group, at: p))
            case .line(let a, let b, _, _) where flags & DimensionFlag.lineDimension != 0:
                lines.append(LooseLine(index: index, group: group, a: a, b: b))
            default:
                break
            }
        }

        var candidates: [Candidate] = []
        for (ti, text) in texts.enumerated() {
            let span = text.value / text.scale
            let reach = span / 2 + 25
            let near = points.indices.filter {
                points[$0].group == text.group
                    && hypot(points[$0].at.x - text.at.x, points[$0].at.y - text.at.y) <= reach
            }
            for (k, i) in near.enumerated() {
                for j in near[(k + 1)...] {
                    let p = points[i].at
                    let q = points[j].at
                    let length = hypot(q.x - p.x, q.y - p.y)
                    guard length > tolerance,
                        abs(length * text.scale - text.value) <= text.tolerance,
                        !points.indices.contains(where: {
                            $0 != i && $0 != j && points[$0].group == text.group
                                && Self.lies(points[$0].at, strictlyBetween: p, and: q, tolerance)
                        })
                    else { continue }
                    let mid = JWW.Point(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
                    candidates.append(
                        Candidate(
                            text: ti, p: i, q: j,
                            cost: hypot(mid.x - text.at.x, mid.y - text.at.y)))
                }
            }
        }
        candidates.sort { $0.cost < $1.cost }

        var matchedTexts = Set<Int>()
        var usedPairs = Set<[Int]>()
        var recovered: [JWW.RecoveredDimension] = []
        for candidate in candidates {
            let pair = [candidate.p, candidate.q]
            guard !matchedTexts.contains(candidate.text), !usedPairs.contains(pair) else {
                continue
            }
            matchedTexts.insert(candidate.text)
            usedPairs.insert(pair)
            let text = texts[candidate.text]
            recovered.append(
                build(
                    text: text, p: points[candidate.p], q: points[candidate.q], lines: lines,
                    tolerance: tolerance))
        }
        for (ti, text) in texts.enumerated() where !matchedTexts.contains(ti) {
            unmatched.append(text.index)
        }
        recovered.sort { $0.elementIndices[0] < $1.elementIndices[0] }
        return JWW.DimensionRecovery(dimensions: recovered, unmatchedValues: unmatched.sorted())
    }

    private struct LooseText {
        var index: Int
        var group: Int
        var at: JWW.Point
        var value: Double
        var scale: Double
        var tolerance: Double
        var label: JWW.Dimension.Label
        var duplicates: [Int] = []
    }

    private struct LoosePoint {
        var index: Int
        var group: Int
        var at: JWW.Point
    }

    private struct LooseLine {
        var index: Int
        var group: Int
        var a: JWW.Point
        var b: JWW.Point
    }

    private struct Candidate {
        var text: Int
        var p: Int
        var q: Int
        var cost: Double
    }

    /// True when `r` is on the segment `p`-`q`, away from both ends.
    private static func lies(
        _ r: JWW.Point, strictlyBetween p: JWW.Point, and q: JWW.Point, _ tolerance: Double
    ) -> Bool {
        let dx = q.x - p.x
        let dy = q.y - p.y
        let length2 = dx * dx + dy * dy
        guard length2 > 0 else { return false }
        let t = ((r.x - p.x) * dx + (r.y - p.y) * dy) / length2
        let margin = tolerance / sqrt(length2)
        guard t > margin, t < 1 - margin else { return false }
        let foot = JWW.Point(x: p.x + t * dx, y: p.y + t * dy)
        return hypot(r.x - foot.x, r.y - foot.y) <= tolerance
    }

    private func build(
        text: LooseText, p: LoosePoint, q: LoosePoint, lines: [LooseLine], tolerance: Double
    ) -> JWW.RecoveredDimension {
        let element = elements[text.index]
        let dx = q.at.x - p.at.x
        let dy = q.at.y - p.at.y
        let length = hypot(dx, dy)
        var indices = [text.index, p.index, q.index] + text.duplicates
        var extensionLines: [JWW.Dimension.Segment] = []
        for line in lines where line.group == text.group {
            let direction = JWW.Point(x: line.b.x - line.a.x, y: line.b.y - line.a.y)
            let lineLength = hypot(direction.x, direction.y)
            guard lineLength > tolerance else { continue }
            let cross = abs(direction.x * dy - direction.y * dx) / (lineLength * length)
            if cross < 1e-3 {
                if Self.overlaps(line, p: p.at, q: q.at, tolerance: tolerance) {
                    indices.append(line.index)
                }
            } else if Self.touches(line.a, p.at, q.at, tolerance)
                || Self.touches(line.b, p.at, q.at, tolerance)
            {
                indices.append(line.index)
                extensionLines.append(JWW.Dimension.Segment(a: line.a, b: line.b))
            }
        }
        let dimension = JWW.Dimension(
            attributes: element.attributes,
            dimensionLine: JWW.Dimension.Segment(a: p.at, b: q.at), label: text.label,
            value: text.value, extensionLines: extensionLines, arrowPoints: [p.at, q.at],
            measuredPoints: [p.at, q.at])
        return JWW.RecoveredDimension(
            dimension: dimension, elementIndices: Array(Set(indices)).sorted())
    }

    /// True when `r` coincides with either end `p` or `q`.
    private static func touches(
        _ r: JWW.Point, _ p: JWW.Point, _ q: JWW.Point, _ tolerance: Double
    ) -> Bool {
        hypot(r.x - p.x, r.y - p.y) <= tolerance || hypot(r.x - q.x, r.y - q.y) <= tolerance
    }

    /// True when `line` lies along the segment `p`-`q` and shares more than a point with it.
    private static func overlaps(
        _ line: LooseLine, p: JWW.Point, q: JWW.Point, tolerance: Double
    ) -> Bool {
        let length = hypot(q.x - p.x, q.y - p.y)
        let ux = (q.x - p.x) / length
        let uy = (q.y - p.y) / length
        func along(_ r: JWW.Point) -> Double { (r.x - p.x) * ux + (r.y - p.y) * uy }
        func across(_ r: JWW.Point) -> Double { abs((r.x - p.x) * uy - (r.y - p.y) * ux) }
        guard across(line.a) <= tolerance, across(line.b) <= tolerance else { return false }
        let lo = max(0, min(along(line.a), along(line.b)))
        let hi = min(length, max(along(line.a), along(line.b)))
        return hi - lo > tolerance
    }
}
