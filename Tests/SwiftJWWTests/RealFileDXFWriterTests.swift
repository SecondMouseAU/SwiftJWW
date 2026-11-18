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
