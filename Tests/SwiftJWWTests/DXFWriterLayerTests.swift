import Foundation
import Testing

@testable import SwiftJWW

@Suite("DXF writer: layer names, layer table and handles")
struct DXFWriterLayerTests {
    let helper = DXFWriterTests()

    func entity(group: Int, layer: Int) -> JWW.Element {
        JWW.Element(
            entity: helper.line(0, 0, 1, 1, layer: layer),
            attributes: .init(layerGroup: group, layer: layer))
    }

    /// The `5` handles in a DXF text, in order.
    func handles(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        return stride(from: 0, to: lines.count - 1, by: 2).compactMap {
            lines[$0] == "5" ? lines[$0 + 1] : nil
        }
    }

    // MARK: layer names

    @Test("a layer is named for its group and layer in hexadecimal, as Jw_cad names it")
    func layerNames() throws {
        let dwg = helper.drawing([entity(group: 0, layer: 14), entity(group: 10, layer: 3)])
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg))
        #expect(dxf.entities.map(\.layer) == ["0-E", "A-3"])
    }

    @Test("layer 14 of every group lands on its own layer")
    func groupsDoNotShareLayers() throws {
        let dwg = helper.drawing((0..<16).map { entity(group: $0, layer: 14) })
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg))
        #expect(Set(dxf.entities.map(\.layer)).count == 16)
    }

    @Test("a drawing built from bare entities puts them in group 0")
    func bareEntities() throws {
        let dwg = JWW.Drawing(
            version: 700, entities: [helper.line(0, 0, 1, 1, layer: 5)], counts: .init())
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg))
        #expect(dxf.entities.first?.layer == "0-5")
    }

    @Test("the group of a block member and of a dimension's parts is used too")
    func blockAndDimensionLayers() throws {
        let member = JWW.Element(
            entity: helper.line(0, 0, 5, 5, layer: 2), attributes: .init(layerGroup: 3, layer: 2))
        let def = JWW.BlockDef(number: 1, name: "box", elements: [member])
        let old = JWW.Element(
            entity: .dimension(
                parts: [helper.line(0, 0, 4, 0, layer: 9), helper.text("R5", 2, 1, layer: 9)],
                layer: 9),
            attributes: .init(layerGroup: 4, layer: 9))
        let dxf = try ReferenceDXF(text: DXFWriter.string(helper.drawing([old], blocks: [1: def])))
        #expect(dxf.blocks["BLK1"]?.first?.layer == "3-2")
        #expect(dxf.entities.map(\.layer) == ["4-9", "4-9"])
    }

    // MARK: layer table

    @Test("the layer table lists layer 0 and each layer the entities use, once")
    func layerTable() throws {
        let dwg = helper.drawing([
            entity(group: 0, layer: 14), entity(group: 0, layer: 14), entity(group: 1, layer: 0),
        ])
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg))
        #expect(dxf.layers.compactMap { $0.text(2) } == ["0", "0-E", "1-0"])
        let table = try #require(dxf.tableRecords.first { $0.text(2) == "LAYER" })
        #expect(table.number(70) == 3)
    }

    @Test("a layer's JWW name is its description")
    func layerDescription() throws {
        var groups = (0..<16).map { JWW.LayerGroup(index: $0, scale: 1) }
        groups[0].layers = [JWW.Layer(index: 14, name: "寸法"), JWW.Layer(index: 1, name: "")]
        let dwg = JWW.Drawing(
            version: 700, elements: [entity(group: 0, layer: 14), entity(group: 0, layer: 1)],
            blocks: [:], counts: .init(), layerGroups: groups)
        let dxf = try ReferenceDXF(text: DXFWriter.string(dwg))
        let named = try #require(dxf.layers.first { $0.text(2) == "0-E" })
        #expect(named.text(1001) == "AcAecLayerStandard")
        #expect(named.groups[1000] == ["", DXFWriter.dxfText("寸法")])
        let unnamed = try #require(dxf.layers.first { $0.text(2) == "0-1" })
        #expect(unnamed.groups[1000] == nil)
        // The application the description is stored under is registered.
        #expect(
            dxf.tableRecords.contains { $0.type == "APPID" && $0.text(2) == "AcAecLayerStandard" })
    }

    @Test("with no layer named there is no application to register")
    func noDescriptions() throws {
        let dxf = try ReferenceDXF(
            text: DXFWriter.string(helper.drawing([entity(group: 0, layer: 2)])))
        #expect(!dxf.tableRecords.contains { $0.type == "APPID" })
    }

    // MARK: handles

    @Test("every entity, block and table record has a handle, and no handle repeats")
    func handlesAreUnique() throws {
        let def = JWW.BlockDef(number: 1, name: "box", elements: [entity(group: 0, layer: 1)])
        let dwg = helper.drawing(
            [
                entity(group: 0, layer: 14), entity(group: 2, layer: 3),
                helper.record(length: 10, label: "500"),
            ],
            blocks: [1: def])
        let text = DXFWriter.string(dwg)
        let dxf = try ReferenceDXF(text: text)
        let written = dxf.entities + dxf.blockRecords + dxf.layers
        #expect(written.allSatisfy { $0.text(5) != nil })
        let all = handles(text)
        #expect(Set(all).count == all.count)
        #expect(all.allSatisfy { Int($0, radix: 16) != nil })
    }

    @Test("handles are the same for the same drawing")
    func handlesAreStable() {
        let dwg = helper.drawing([
            entity(group: 0, layer: 14), helper.record(length: 10, label: "500"),
        ])
        #expect(DXFWriter.string(dwg) == DXFWriter.string(dwg))
    }
}
