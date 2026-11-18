import Foundation
import Testing

@testable import SwiftJWW

@Suite("Reference DXF: placing inserts")
struct ReferenceDXFInsertTests {
    /// A DXF with the given block records and entity records, each written as a line of groups.
    func dxf(blocks: [String], entities: [String]) throws -> ReferenceDXF {
        func groups(_ record: String) -> [String] { record.split(separator: " ").map(String.init) }
        var text: [String] = ["0", "SECTION", "2", "BLOCKS"]
        for record in blocks { text += groups(record) }
        text += ["0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"]
        for record in entities { text += groups(record) }
        text += ["0", "ENDSEC", "0", "EOF"]
        return try ReferenceDXF(text: text.joined(separator: "\n"))
    }

    func block(_ name: String, base: String = "10 0 20 0", members: String) -> String {
        "0 BLOCK 2 \(name) 70 0 \(base) 30 0 \(members) 0 ENDBLK"
    }

    @Test("a member is placed by the base point, scale, rotation and position of its insert")
    func placement() throws {
        // The member runs from (1, 1) to (3, 1), so from the base point (1, 1) it runs 2 along x.
        // Scaled by 2 it runs 4, turned a quarter it runs 4 along y, moved to (10, 20) it runs
        // from (10, 20) to (10, 24).
        let file = try dxf(
            blocks: [block("B", base: "10 1 20 1", members: "0 LINE 8 0 10 1 20 1 11 3 21 1")],
            entities: ["0 INSERT 2 B 8 L 10 10 20 20 41 2 42 2 50 90"])
        let placed = file.flattened()
        let line = try #require(placed.entities.first)
        #expect(placed.entities.count == 1 && placed.unsupported.isEmpty)
        #expect(line.type == "LINE")
        #expect(abs((line.number(10) ?? .nan) - 10) < 1e-9)
        #expect(abs((line.number(20) ?? .nan) - 20) < 1e-9)
        #expect(abs((line.number(11) ?? .nan) - 10) < 1e-9)
        #expect(abs((line.number(21) ?? .nan) - 24) < 1e-9)
        // Layer 0 in a block is the layer of the insert.
        #expect(line.layer == "L")
    }

    @Test("an entity outside any insert is kept as it is")
    func untouched() throws {
        let file = try dxf(blocks: [], entities: ["0 POINT 8 A 10 3 20 4"])
        let placed = file.flattened()
        #expect(placed.entities.count == 1 && placed.insertCount == 0)
        #expect(placed.entities.first?.number(10) == 3)
    }

    @Test("an insert inside a block is placed through both inserts")
    func nested() throws {
        // B holds a point at (1, 1). A holds B moved to (5, 0). A is placed at (100, 100) at twice
        // the size: the point is at (6, 1) in A and at (112, 102) in the drawing.
        let file = try dxf(
            blocks: [
                block("B", members: "0 POINT 8 P 10 1 20 1"),
                block("A", members: "0 INSERT 2 B 8 P 10 5 20 0 41 1 42 1 50 0"),
            ], entities: ["0 INSERT 2 A 8 P 10 100 20 100 41 2 42 2 50 0"])
        let placed = file.flattened()
        let point = try #require(placed.entities.first)
        #expect(placed.insertCount == 2 && placed.entities.count == 1)
        #expect(abs((point.number(10) ?? .nan) - 112) < 1e-9)
        #expect(abs((point.number(20) ?? .nan) - 102) < 1e-9)
    }

    @Test("a circle scales its radius and an arc turns its angles")
    func circleAndArc() throws {
        let file = try dxf(
            blocks: [
                block(
                    "C",
                    members: "0 CIRCLE 8 P 10 1 20 0 40 3 0 ARC 8 P 10 0 20 0 40 2 50 350 51 20")
            ], entities: ["0 INSERT 2 C 8 P 10 0 20 0 41 2 42 2 50 30"])
        let placed = file.flattened()
        let circle = try #require(placed.entities.first { $0.type == "CIRCLE" })
        let arc = try #require(placed.entities.first { $0.type == "ARC" })
        #expect(circle.number(40) == 6)
        #expect(abs((circle.number(10) ?? .nan) - 2 * cos(.pi / 6)) < 1e-9)
        #expect(arc.number(40) == 4)
        #expect(abs((arc.number(50) ?? .nan) - 20) < 1e-9)
        #expect(abs((arc.number(51) ?? .nan) - 50) < 1e-9)
    }

    @Test("a member that cannot be placed is listed and left out, not kept in block coordinates")
    func unplaceableMember() throws {
        let file = try dxf(
            blocks: [
                block("T", members: "0 TEXT 8 P 10 1 20 1 11 2 21 2 40 1 1 A 72 1"),
                block("S", members: "0 SOLID 8 P 10 1 20 1 11 2 21 1 12 1 22 2 13 2 23 2"),
                block("L", members: "0 LINE 8 P 10 1 20 1 11 2 21 1"),
            ],
            entities: [
                "0 INSERT 2 T 8 P 10 5 20 5 41 2 42 2", "0 INSERT 2 S 8 P 10 5 20 5 41 2 42 2",
                "0 INSERT 2 L 8 P 10 0 20 0 41 1 42 1",
            ])
        let placed = file.flattened()
        // Only the line, which an insert at the origin at scale 1 leaves in place.
        #expect(placed.entities.map(\.type) == ["LINE"])
        #expect(placed.unsupported.count == 2)
    }

    @Test("a mirror, an uneven scale, an array and a missing block are listed, not placed")
    func unsupported() throws {
        let file = try dxf(
            blocks: [block("B", members: "0 POINT 8 P 10 1 20 1")],
            entities: [
                "0 INSERT 2 B 8 P 10 0 20 0 41 -1 42 1", "0 INSERT 2 B 8 P 10 0 20 0 41 1 42 2",
                "0 INSERT 2 B 8 P 10 0 20 0 70 3 71 1", "0 INSERT 2 MISSING 8 P 10 0 20 0",
            ])
        let placed = file.flattened()
        #expect(placed.entities.isEmpty)
        #expect(placed.unsupported.count == 4)
    }
}
