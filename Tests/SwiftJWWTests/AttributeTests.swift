import Foundation
import Testing

@testable import SwiftJWW

@Suite("Attributes and layer groups")
struct AttributeTests {
    typealias Builder = SwiftJWWTests.Builder

    @Test("each element carries layer group, layer, line type, colour, pen width, curve and flags")
    func elementAttributes() throws {
        var b = Builder()
        b.header()
        b.u16(1)
        b.classTag("CDataSen")
        b.base(
            penStyle: 6, color: 4, layer: 0xE, layerGroup: 3, curve: 9, penWidth: 7, flags: 0x2000)
        for v in [0.0, 0, 1, 1] { b.f64(v) }
        let dwg = try JWW.read(data: b.d)
        let element = try #require(dwg.elements.first)
        #expect(
            element.attributes
                == JWW.Attributes(
                    layerGroup: 3, layer: 14, lineType: 6, color: 4, penWidth: 7,
                    curveAttribute: 9, flags: 0x2000))
        guard case .line(_, _, let layer, let color) = element.entity else {
            Issue.record("not a line")
            return
        }
        #expect(layer == 14 && color == 4)
        #expect(dwg.entities.count == dwg.elements.count)
    }

    @Test("a bare entity wrapped as an element takes its layer and colour")
    func wrappedEntity() {
        let e = JWW.Element(entity: .point(at: .init(x: 1, y: 2), layer: 5, color: 3))
        #expect(e.attributes.layer == 5 && e.attributes.color == 3 && e.attributes.layerGroup == 0)
    }

    @Test("layer groups carry scale, state and CP932 names")
    func layerGroups() throws {
        let sunpou: [UInt8] = [144, 161, 150, 64]
        let yuka: [UInt8] = [143, 176, 137, 186]
        var b = Builder()
        b.header(
            scales: [0: 80, 1: 50], layerNames: [0: [14: sunpou, 3: Array("walls".utf8)]],
            groupNames: [1: yuka])
        b.u16(0)
        let dwg = try JWW.read(data: b.d)
        #expect(dwg.layerGroups.count == 16)
        #expect(dwg.scale(ofLayerGroup: 0) == 80)
        #expect(dwg.scale(ofLayerGroup: 1) == 50)
        #expect(dwg.scale(ofLayerGroup: 2) == 1)
        #expect(dwg.scale(ofLayerGroup: 16) == nil)
        #expect(dwg.scale(ofLayerGroup: -1) == nil)
        #expect(dwg.layerGroups[0].state == 3 && dwg.layerGroups[0].isVisible)
        #expect(dwg.layerGroups[0].layers.count == 16)
        #expect(dwg.layerGroups[0].layers[3].name == "walls")
        #expect(dwg.layerGroups[0].layers[14].name == JWW.decodeCP932(sunpou))
        #expect(dwg.layerGroups[1].name == JWW.decodeCP932(yuka))
        #expect(dwg.layerGroups[2].name.isEmpty)
    }

    @Test("a drawing built without layer groups has no scale")
    func noLayerGroups() {
        let dwg = JWW.Drawing(version: 700, entities: [], counts: .init())
        #expect(dwg.scale(ofLayerGroup: 0) == nil)
    }

    @Test("text angle is stored in degrees and read in radians")
    func textAngle() throws {
        var b = Builder()
        b.header()
        b.u16(1)
        b.classTag("CDataMoji")
        b.mojiFields("A", angleDegrees: 90)
        let dwg = try JWW.read(data: b.d)
        guard case .text(_, _, _, let angle, _, _, _) = dwg.entities[0] else {
            Issue.record("not text")
            return
        }
        #expect(abs(angle - .pi / 2) < 1e-12)
        let lines = DXFWriter.string(dwg).components(separatedBy: "\n")
        let i = try #require(lines.firstIndex(of: "50"))
        #expect(abs((Double(lines[i + 1]) ?? 0) - 90) < 1e-3)
    }
}
