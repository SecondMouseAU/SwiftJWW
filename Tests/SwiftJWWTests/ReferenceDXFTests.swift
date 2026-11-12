import Foundation
import Testing

@testable import SwiftJWW

@Suite("Reference DXF reader")
struct ReferenceDXFTests {
    let wellFormed = """
          0
        SECTION
          2
        HEADER
          9
        $LTSCALE
         40
        80
          0
        ENDSEC
          0
        SECTION
          2
        ENTITIES
          0
        POINT
          8
        _0-e_
         10
        1.5
         20
        2.5
          0
        ENDSEC
          0
        EOF

        """

    @Test("header values and entities are read, and trailing blank lines are ignored")
    func readsWellFormed() throws {
        let dxf = try ReferenceDXF(text: wellFormed + "\n\n")
        #expect(dxf.header["$LTSCALE"]?[40] == "80")
        let point = try #require(dxf.entities.first)
        #expect(dxf.entities.count == 1 && point.type == "POINT" && point.layer == "_0-e_")
        #expect(point.number(10) == 1.5 && point.number(20) == 2.5)
    }

    @Test("a line that is not a group code throws instead of being skipped")
    func rejectsBadCode() {
        let broken = wellFormed.replacingOccurrences(of: "  8\n", with: "  eight\n")
        #expect(throws: ReferenceDXF.MalformedError.self) { try ReferenceDXF(text: broken) }
    }

    @Test("a code with no value at the end of the file throws")
    func rejectsDanglingCode() {
        #expect(throws: ReferenceDXF.MalformedError.self) {
            try ReferenceDXF(text: wellFormed + "  999\n")
        }
    }
}
