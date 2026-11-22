import Foundation
import Testing

@testable import SwiftJWW

@Suite("Real JWW files written with recovered dimensions")
struct RealFileDXFWriterTests {
    /// The dimensions the writer recovers and the values it cannot explain, as checked by hand
    /// against the TECS drawings (SecondMouseAU/SwiftJWW#19).
    static let expected: [String: (recovered: Int, unexplained: Int)] = [
        "2120": (29, 0), "eitakyouta_3": (13, 1), "dd12": (14, 2),
    ]

    /// DXF text with its `\U+XXXX` escapes turned back into characters.
    static func unescaped(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let marker = rest.range(of: "\\U+") {
            out += rest[..<marker.lowerBound]
            let digits = rest[marker.upperBound...].prefix(4)
            if let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) {
                out.unicodeScalars.append(scalar)
                rest = rest[marker.upperBound...].dropFirst(4)
            } else {
                out += "\\U+"
                rest = rest[marker.upperBound...]
            }
        }
        return out + rest
    }

    @Test(
        "each recovered dimension is a DIMENSION whose measurement is its stated value",
        .enabled(if: !Fixtures.drawings.isEmpty), arguments: Fixtures.drawings)
    func writesRecovered(_ url: URL) throws {
        let name = url.deletingPathExtension().lastPathComponent
        let dwg = try JWW.read(contentsOf: url)
        let output = DXFWriter.output(
            dwg, options: .init(fullSize: true, recoversDimensions: true))
        let dxf = try ReferenceDXF(text: output.text)
        let dimensions = dxf.entities.filter { $0.type == "DIMENSION" }

        #expect(dimensions.count == output.report.recoveredDimensions.count)
        #expect(Set(dimensions.compactMap { $0.text(5) }) == Set(output.report.recoveredDimensions))
        let measure = DXFWriterTests()
        for dimension in dimensions {
            let label = Self.unescaped(try #require(dimension.text(1)))
            let stated = try #require(JWW.Dimension.parseValue(label))
            let measured = try measure.measurement(dimension)
            let allowed = JWW.Dimension.roundingTolerance(of: label) + 1e-3
            #expect(abs(measured - stated) <= allowed, "\(name): \(label) measures \(measured)")
        }
        if let want = Self.expected[name] {
            #expect(output.report.recoveredDimensions.count == want.recovered, "\(name)")
            #expect(output.report.unexplainedValues.count == want.unexplained, "\(name)")
        }

        let lists = output.report.recoveredDimensions.map {
            output.report.recoveredDimensionElements[$0] ?? []
        }
        #expect(lists == dwg.recoveringDimensions().dimensions.map(\.elementIndices), "\(name)")
        let pieces = output.report.recoveredDimensions.map {
            output.report.recoveredDimensionPieces[$0] ?? []
        }
        #expect(pieces == dwg.recoveringDimensions().dimensions.map(\.pieces), "\(name)")
        #expect(pieces.map { $0.map(\.index) } == lists, "\(name)")
        for found in dwg.recoveringDimensions().dimensions {
            #expect(found.elementIndices == found.pieces.map(\.index), "\(name)")
            #expect(found.elementIndices == found.elementIndices.sorted(), "\(name)")
        }
        let groups = Set(dwg.elements.map(\.attributes.layerGroup))
        #expect(Set(output.report.appliedScales.keys) == groups, "\(name)")
        for group in groups {
            // The writer's rule: the stated scale when it is finite and positive, otherwise 1.
            let stated = dwg.scale(ofLayerGroup: group) ?? 1
            let factor = stated.isFinite && stated > 0 ? stated : 1
            #expect(output.report.appliedScales[group] == factor, "\(name)")
        }
    }

    @Test(
        "each piece's role fits what the element is: text, points, and lines by where they lie",
        .enabled(if: !Fixtures.drawings.isEmpty), arguments: Fixtures.drawings)
    func rolesFitTheElements(_ url: URL) throws {
        let name = url.deletingPathExtension().lastPathComponent
        let dwg = try JWW.read(contentsOf: url)
        let report = DXFWriter.output(dwg, options: .init(recoversDimensions: true)).report
        let tolerance = 1e-3
        for handle in report.recoveredDimensions {
            let pieces = try #require(report.recoveredDimensionPieces[handle], "\(name)")
            let arrows: [JWW.Point] = pieces.filter { $0.role == .arrowPoint }.compactMap {
                if case .point(let at, _, _) = dwg.elements[$0.index].entity { at } else { nil }
            }
            #expect(arrows.count == 2, "\(name) \(handle)")
            guard arrows.count == 2 else { continue }
            let span = hypot(arrows[1].x - arrows[0].x, arrows[1].y - arrows[0].y)
            func distance(_ a: JWW.Point, _ b: JWW.Point) -> Double { hypot(a.x - b.x, a.y - b.y) }
            func offLine(_ r: JWW.Point) -> Double {
                abs(
                    (r.x - arrows[0].x) * (arrows[1].y - arrows[0].y)
                        - (r.y - arrows[0].y) * (arrows[1].x - arrows[0].x)) / span
            }
            for piece in pieces {
                let entity = dwg.elements[piece.index].entity
                switch (piece.role, entity) {
                case (.arrowPoint, .point), (.valueText, .text), (.valueTextCopy, .text):
                    break
                case (.dimensionLine, .line(let a, let b, _, _)):
                    #expect(offLine(a) <= tolerance && offLine(b) <= tolerance, "\(name) \(handle)")
                case (.extensionLine, .line(let a, let b, _, _)):
                    let ends =
                        arrows.contains { distance($0, a) <= tolerance }
                        || arrows.contains { distance($0, b) <= tolerance }
                    #expect(ends, "\(name) \(handle): an extension line ends on an arrow point")
                    // A line along the arrow line is the dimension line, not an extension line.
                    let along = offLine(a) <= tolerance && offLine(b) <= tolerance
                    #expect(!along, "\(name) \(handle): an extension line crosses the arrow line")
                default:
                    Issue.record("\(name) \(handle): \(piece.role) is not a \(entity)")
                }
            }
        }
    }

    @Test(
        "the 2120's rebuilt dimensions name their pieces, which are the 125 elements on 0-E",
        .enabled(if: Fixtures.drawings.contains { $0.lastPathComponent == "2120.jww" }))
    func piecesOf2120() throws {
        let url = try #require(Fixtures.drawings.first { $0.lastPathComponent == "2120.jww" })
        let dwg = try JWW.read(contentsOf: url)
        let report = DXFWriter.output(dwg, options: .init(fullSize: true, recoversDimensions: true))
            .report
        // The count and the match with recoveringDimensions() are checked in writesRecovered.
        #expect(Set(report.recoveredDimensionElements.keys) == Set(report.recoveredDimensions))
        let onLayer = dwg.elements.indices.filter {
            let attributes = dwg.elements[$0].attributes
            return DXFWriter.layerName(group: attributes.layerGroup, layer: attributes.layer)
                == "0-E"
        }
        #expect(onLayer.count == 125)
        #expect(Set(report.recoveredDimensionElements.values.joined()) == Set(onLayer))
    }

    @Test(
        "the 2120's report gives each piece the role recoveringDimensions() found for it",
        .enabled(if: Fixtures.drawings.contains { $0.lastPathComponent == "2120.jww" }))
    func rolesOf2120() throws {
        let url = try #require(Fixtures.drawings.first { $0.lastPathComponent == "2120.jww" })
        let dwg = try JWW.read(contentsOf: url)
        let report = DXFWriter.output(dwg, options: .init(fullSize: true, recoversDimensions: true))
            .report
        let found = dwg.recoveringDimensions().dimensions
        #expect(found.count == 29 && report.recoveredDimensions.count == 29)
        let reported = report.recoveredDimensions.flatMap {
            report.recoveredDimensionPieces[$0] ?? []
        }
        #expect(reported == found.flatMap(\.pieces))
        var counts: [JWW.RecoveredDimension.Role: Int] = [:]
        for piece in reported { counts[piece.role, default: 0] += 1 }
        #expect(counts[.valueText] == 29)
        #expect(counts[.valueTextCopy] == 1)
        #expect(counts[.arrowPoint] == 58)
        #expect(counts[.dimensionLine] == 30)
        #expect(counts[.extensionLine] == 56)
        #expect(Set(counts.keys) == Set(JWW.RecoveredDimension.Role.allCases))
    }

    @Test(
        "the 2120 has no loose text, point or line left on its dimension layer",
        .enabled(if: Fixtures.drawings.contains { $0.lastPathComponent == "2120.jww" }))
    func nothingLooseOn2120() throws {
        let url = try #require(Fixtures.drawings.first { $0.lastPathComponent == "2120.jww" })
        let dwg = try JWW.read(contentsOf: url)
        let output = DXFWriter.output(dwg, options: .init(recoversDimensions: true))
        let dxf = try ReferenceDXF(text: output.text)
        let onLayer = dxf.entities.filter { $0.layer == "0-E" }
        #expect(onLayer.count == 29 && onLayer.allSatisfy { $0.type == "DIMENSION" })
    }

    @Test(
        "no ELLIPSE written from a real drawing has a ratio above 1",
        .enabled(if: !Fixtures.drawings.isEmpty), arguments: Fixtures.drawings)
    func ellipseRatios(_ url: URL) throws {
        let name = url.deletingPathExtension().lastPathComponent
        let dwg = try JWW.read(contentsOf: url)
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg))
        let ellipses = (dxf.entities + dxf.blockRecords).filter { $0.type == "ELLIPSE" }
        print("\(name): \(ellipses.count) ellipses")
        for d in ellipses {
            let ratio = try #require(d.number(40), "\(name)")
            #expect(ratio > 0 && ratio <= 1, "\(name): ratio \(ratio)")
        }
    }
}
