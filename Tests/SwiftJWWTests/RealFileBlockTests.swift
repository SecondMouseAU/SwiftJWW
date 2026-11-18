import Foundation
import Testing

@testable import SwiftJWW

@Suite("Real JWW files with blocks, written as DXF")
struct RealFileBlockTests {
    @Test(
        "the blocks the writer writes place the entities of the expanded drawing written without them",
        .enabled(if: !Fixtures.blockDrawings.isEmpty), arguments: Fixtures.blockDrawings)
    func blocksPlaceToTheExpansion(_ url: URL) throws {
        let name = url.deletingPathExtension().lastPathComponent
        let dwg = try JWW.read(contentsOf: url)
        let expansion = dwg.expandingBlocks()
        #expect(expansion.unresolved.isEmpty, "\(name)")
        let options = DXFWriter.Options(fullSize: true)
        let written = try ReferenceDXF(text: DXFWriter.string(dwg, options: options))
        let flat = JWW.Drawing(
            version: dwg.version, elements: expansion.elements, blocks: [:], counts: dwg.counts,
            layerGroups: dwg.layerGroups)
        let expected = try ReferenceDXF(text: DXFWriter.string(flat, options: options))
        let report = DrawingComparison.compare(expected, with: written)
        print(report.summary(name))
        #expect(report.unexplained.isEmpty, "\(report.summary(name))")
    }
}
