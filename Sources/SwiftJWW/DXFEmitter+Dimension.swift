import Foundation

extension DXFEmitter {
    /// Writes a `DIMENSION` and the anonymous block it names, which holds the drawn `members`.
    ///
    /// A rotated linear dimension: the measured points are groups 13 and 14, a point on the
    /// dimension line group 10, the angle of the line group 50, and the text position and text
    /// groups 11 and 1.
    ///
    /// - Returns: The handle of the `DIMENSION`.
    @discardableResult
    mutating func emitDimension(
        _ d: DXFDimension, members: [JWW.Entity], group: Int, layer: Int, color: Int,
        into s: inout String
    ) -> String {
        func p(_ code: Int, _ v: String) { s += "\(code)\n\(v)\n" }
        func num(_ v: Double) -> String { DXFWriter.number(v) }
        let name = "*D\(anonymousBlocks.count + 1)"
        var angle = (d.angleRad * 180 / .pi).truncatingRemainder(dividingBy: 360)
        if angle < 0 { angle += 360 }

        let dimensionHandle = handle()
        p(0, "DIMENSION")
        p(5, dimensionHandle)
        p(8, layerName(group: group, layer: layer))
        p(62, DXFWriter.aci(color))
        p(2, name)
        p(10, num(d.onLine.x))
        p(20, num(d.onLine.y))
        p(30, "0.0")
        p(11, num(d.labelAt.x))
        p(21, num(d.labelAt.y))
        p(31, "0.0")
        p(70, "0")
        p(1, DXFWriter.dxfText(d.label))
        p(13, num(d.first.x))
        p(23, num(d.first.y))
        p(33, "0.0")
        p(14, num(d.second.x))
        p(24, num(d.second.y))
        p(34, "0.0")
        p(50, num(angle))

        var block = "0\nBLOCK\n5\n\(handle())\n8\n0\n2\n\(name)\n70\n1\n"
        block += "10\n0.0\n20\n0.0\n30\n0.0\n3\n\(name)\n"
        for member in members { emit(member, group: group, into: &block) }
        block += "0\nENDBLK\n5\n\(handle())\n8\n0\n"
        anonymousBlocks.append(block)
        return dimensionHandle
    }

    /// Writes a dimension rebuilt from loose pieces as a `DIMENSION`, with the pieces in its block.
    ///
    /// The pieces are the elements the recovery used, written at the scale of the dimension's layer
    /// group, and the handle of the `DIMENSION` is kept in ``recoveredHandles``.
    mutating func emitRecovered(
        _ recovered: JWW.RecoveredDimension, as dimension: DXFDimension, into s: inout String
    ) {
        let attributes = recovered.dimension.attributes
        let scale = scale(ofGroup: attributes.layerGroup)
        let members = recovered.elementIndices.map { drawing.elements[$0].entity.scaled(by: scale) }
        recoveredHandles.append(
            emitDimension(
                dimension.scaled(by: scale), members: members, group: attributes.layerGroup,
                layer: attributes.layer, color: attributes.color, into: &s))
    }
}
