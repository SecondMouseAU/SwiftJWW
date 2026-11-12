import Foundation
import Testing

@testable import SwiftJWW

/// JWW files and the DXF their publisher exported from each, from a private folder.
///
/// Set `SWIFTJWW_FIXTURES` to a folder holding `<name>.jww` beside `<name>.dxf`, at any depth. The
/// TECS drawings are not licensed for redistribution, so none are kept in this repository; without
/// the variable these tests are skipped.
enum Fixtures {
    struct Pair: Sendable, CustomTestStringConvertible {
        var name: String
        var jww: URL
        var dxf: URL
        var testDescription: String { name }
    }

    static let pairs: [Pair] = {
        guard let path = ProcessInfo.processInfo.environment["SWIFTJWW_FIXTURES"],
            let walker = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
        else { return [] }
        var found: [Pair] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "jww" {
            let base = url.deletingPathExtension()
            for ext in ["dxf", "DXF", "Dxf"] {
                let dxf = base.appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: dxf.path) {
                    found.append(Pair(name: base.lastPathComponent, jww: url, dxf: dxf))
                    break
                }
            }
        }
        return found.sorted { $0.name < $1.name }
    }()
}

@Suite("Real JWW files against their DXF exports")
struct RealFileComparisonTests {
    @Test(
        "the JWW reads as the DXF exported from it does",
        .enabled(if: !Fixtures.pairs.isEmpty), arguments: Fixtures.pairs)
    func matchesDXF(_ pair: Fixtures.Pair) throws {
        let jww = try JWW.read(contentsOf: pair.jww)
        let dxf = try ReferenceDXF(contentsOf: pair.dxf)
        let report = DrawingComparison.compare(jww, dxf)
        print(report.summary(pair.name))
        #expect(report.unexplained.isEmpty, "\(report.summary(pair.name))")
    }
}
