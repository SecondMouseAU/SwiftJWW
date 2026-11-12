import Foundation

extension JWW {
    /// A dimension read as one object: the measured points, the dimension line, the text and its value.
    ///
    /// Built from an ``Element`` whose entity is ``Entity/dimension(parts:layer:)``. A file stores a
    /// dimension only when the drawing used Jw_cad's dimension command; a value typed as loose text
    /// and lines has no dimension record and reads as separate entities.
    public struct Dimension: Sendable {
        public struct Segment: Equatable, Sendable {
            public var a: Point
            public var b: Point
        }

        /// The text of a dimension.
        public struct Label: Sendable {
            public var at: Point
            public var height: Double
            public var width: Double
            public var angleRad: Double
            public var string: String
        }

        public var attributes: Attributes
        public var dimensionLine: Segment
        public var label: Label
        /// The number the text states, nil when it holds none.
        ///
        /// A radius or diameter prefix, thousands commas and a trailing unit are dropped.
        public var value: Double?
        /// The two witness (auxiliary) lines, empty in a file older than version 4.20.
        public var extensionLines: [Segment]
        /// The two arrow points, empty in a file older than version 4.20.
        public var arrowPoints: [Point]
        /// The two reference points the dimension measures between, empty before version 4.20.
        public var measuredPoints: [Point]

        /// The distance between the two measured points in drawn units, nil without them.
        ///
        /// Multiply by the layer group's ``LayerGroup/scale`` to compare with ``value``.
        public var measuredDistance: Double? {
            guard measuredPoints.count == 2 else { return nil }
            return hypot(
                measuredPoints[1].x - measuredPoints[0].x, measuredPoints[1].y - measuredPoints[0].y
            )
        }

        /// Reads the number out of dimension text such as `1,930`, `φ12.5` or `R5mm`.
        static func parseValue(_ text: String) -> Double? {
            var digits = ""
            var started = false
            for scalar in text.unicodeScalars {
                let c = halfWidth(scalar)
                if "0123456789".unicodeScalars.contains(c) || (started && c == ".") {
                    digits.unicodeScalars.append(c)
                    started = true
                } else if c == "," && started {
                    continue
                } else if (c == "-" || c == "+") && !started && digits.isEmpty {
                    digits.unicodeScalars.append(c)
                } else if started {
                    break
                } else {
                    digits = ""
                }
            }
            return Double(digits)
        }

        /// One unit in the last decimal place the text states: how far a measured distance may
        /// differ from the stated value when Jw_cad rounded it, rounded it up or truncated it.
        static func roundingTolerance(of text: String) -> Double {
            var decimals = 0
            var started = false
            var afterPoint = false
            for scalar in text.unicodeScalars {
                let c = halfWidth(scalar)
                if "0123456789".unicodeScalars.contains(c) {
                    if afterPoint { decimals += 1 }
                    started = true
                } else if c == "." && started && !afterPoint {
                    afterPoint = true
                } else if c == "," && started {
                    continue
                } else if started {
                    break
                }
            }
            return pow(10, -Double(decimals)) + 1e-9
        }

        fileprivate static func halfWidth(_ s: Unicode.Scalar) -> Unicode.Scalar {
            switch s.value {
            case 0xFF10...0xFF19: return Unicode.Scalar(s.value - 0xFF10 + 0x30) ?? s
            case 0xFF0E: return "."
            case 0xFF0C: return ","
            case 0xFF0D: return "-"
            default: return s
            }
        }
    }
}

extension JWW.Dimension {
    /// Reads a dimension record, whose parts are in the order ``JWW/Entity/dimension(parts:layer:)``
    /// lists them.
    init?(_ element: JWW.Element) {
        guard case .dimension(let parts, _) = element.entity, parts.count >= 2,
            case .line(let a, let b, _, _) = parts[0],
            case .text(let at, let height, let width, let angle, let string, _, _) = parts[1]
        else { return nil }
        var extensionLines: [Segment] = []
        var arrowPoints: [JWW.Point] = []
        var measuredPoints: [JWW.Point] = []
        if parts.count >= 8 {
            for part in parts[2...3] {
                if case .line(let a, let b, _, _) = part {
                    extensionLines.append(Segment(a: a, b: b))
                }
            }
            for part in parts[4...5] {
                if case .point(let p, _, _) = part { arrowPoints.append(p) }
            }
            for part in parts[6...7] {
                if case .point(let p, _, _) = part { measuredPoints.append(p) }
            }
        }
        self.init(
            attributes: element.attributes, dimensionLine: Segment(a: a, b: b),
            label: Label(at: at, height: height, width: width, angleRad: angle, string: string),
            value: JWW.Dimension.parseValue(string), extensionLines: extensionLines,
            arrowPoints: arrowPoints, measuredPoints: measuredPoints)
    }
}
