import Foundation

/// The state of one DXF while it is written: the dimension blocks made so far.
struct DXFEmitter {
    let drawing: JWW.Drawing
    let options: DXFWriter.Options
    /// The anonymous blocks of the dimensions written so far, as DXF text.
    var anonymousBlocks: [String] = []

    init(drawing: JWW.Drawing, options: DXFWriter.Options) {
        self.drawing = drawing
        self.options = options
    }

    /// The factor an element's coordinates are multiplied by: its layer group's scale when writing
    /// full size and the group is known, otherwise 1.
    func scale(of element: JWW.Element) -> Double {
        guard options.fullSize,
            let scale = drawing.scale(ofLayerGroup: element.attributes.layerGroup),
            scale.isFinite, scale > 0
        else { return 1 }
        return scale
    }

    /// The name of the DXF layer for a JWW layer group and layer.
    func layerName(group: Int, layer: Int) -> String {
        "\(layer)"
    }

    // MARK: blocks and elements

    /// Writes a block definition as a `BLOCK` named `BLK<number>`, its members as they are drawn.
    ///
    /// The scale of a full-size drawing is carried by the insert, not by the members.
    mutating func emitBlock(_ def: JWW.BlockDef, into s: inout String) {
        let name = "BLK\(def.number)"
        s += "0\nBLOCK\n8\n0\n2\n\(name)\n70\n0\n10\n0.0\n20\n0.0\n30\n0.0\n3\n\(name)\n"
        for member in def.elements { emit(member, scale: 1, into: &s) }
        s += "0\nENDBLK\n8\n0\n"
    }

    /// Writes an element with its coordinates multiplied by `scale`.
    ///
    /// A dimension record with its measured points becomes one `DIMENSION`; an older record is
    /// written as its drawn parts.
    mutating func emit(_ element: JWW.Element, scale: Double, into s: inout String) {
        let attributes = element.attributes
        if case .dimension(let parts, let layer) = element.entity,
            let record = JWW.Dimension(element), let dimension = DXFDimension(record: record)
        {
            emitDimension(
                dimension.scaled(by: scale),
                members: parts.prefix(DXFDimension.drawnPartCount).map { $0.scaled(by: scale) },
                group: attributes.layerGroup, layer: layer, color: attributes.color, into: &s)
            return
        }
        emit(element.entity.scaled(by: scale), group: attributes.layerGroup, into: &s)
    }

    // MARK: entity emit

    /// Writes an entity whose coordinates are final.
    mutating func emit(_ e: JWW.Entity, group: Int, into s: inout String) {
        func p(_ code: Int, _ v: String) { s += "\(code)\n\(v)\n" }
        func num(_ v: Double) -> String { DXFWriter.number(v) }
        func normDeg(_ x: Double) -> Double {
            let a = x.truncatingRemainder(dividingBy: 360)
            return a < 0 ? a + 360 : a
        }
        let deg = 180.0 / Double.pi
        func aci(_ c: Int) -> String { DXFWriter.aci(c) }

        switch e {
        case .line(let a, let b, let layer, let color):
            p(0, "LINE")
            p(8, layerName(group: group, layer: layer))
            p(62, aci(color))
            p(10, num(a.x))
            p(20, num(a.y))
            p(30, "0.0")
            p(11, num(b.x))
            p(21, num(b.y))
            p(31, "0.0")

        case .arc(
            let c, let r, let start, let sweep, let tilt, let ratio, let full, let layer, let color):
            let name = layerName(group: group, layer: layer)
            if abs(ratio - 1) < 1e-9 {  // circle / circular arc
                if full || abs(abs(sweep) - 2 * .pi) < 1e-6 {
                    p(0, "CIRCLE")
                    p(8, name)
                    p(62, aci(color))
                    p(10, num(c.x))
                    p(20, num(c.y))
                    p(30, "0.0")
                    p(40, num(r))
                } else {
                    p(0, "ARC")
                    p(8, name)
                    p(62, aci(color))
                    p(10, num(c.x))
                    p(20, num(c.y))
                    p(30, "0.0")
                    p(40, num(r))
                    // JWW start/sweep are measured from the tilt axis; DXF wants absolute CCW angles in
                    // [0,360). Add tilt, and order start→end CCW (so a negative sweep isn't drawn inverted).
                    let a0 = tilt + start
                    let a1 = tilt + start + sweep
                    let lo = sweep >= 0 ? a0 : a1
                    let hi = sweep >= 0 ? a1 : a0
                    p(50, num(normDeg(lo * deg)))
                    p(51, num(normDeg(hi * deg)))
                }
            } else {  // ellipse / elliptical arc
                p(0, "ELLIPSE")
                p(8, name)
                p(62, aci(color))
                p(10, num(c.x))
                p(20, num(c.y))
                p(30, "0.0")
                p(11, num(cos(tilt) * r))
                p(21, num(sin(tilt) * r))
                p(31, "0.0")  // major axis endpoint, rel. to center
                p(40, num(ratio))
                p(41, num(full ? 0 : start))
                p(42, num(full ? 2 * .pi : start + sweep))
            }

        case .point(let at, let layer, let color):
            p(0, "POINT")
            p(8, layerName(group: group, layer: layer))
            p(62, aci(color))
            p(10, num(at.x))
            p(20, num(at.y))
            p(30, "0.0")

        case .text(let at, let height, _, let angleRad, let string, let layer, let color):
            p(0, "TEXT")
            p(8, layerName(group: group, layer: layer))
            p(62, aci(color))
            p(10, num(at.x))
            p(20, num(at.y))
            p(30, "0.0")
            p(40, num(height > 0 ? height : 2.5))
            p(1, DXFWriter.dxfText(string))
            if abs(angleRad) > 1e-9 { p(50, num(angleRad * deg)) }

        case .insert(let def, let at, let scaleX, let scaleY, let rotationRad, let layer, let color):
            p(0, "INSERT")
            p(8, layerName(group: group, layer: layer))
            p(62, aci(color))
            p(2, "BLK\(def)")
            p(10, num(at.x))
            p(20, num(at.y))
            p(30, "0.0")
            p(41, num(scaleX == 0 ? 1 : scaleX))
            p(42, num(scaleY == 0 ? 1 : scaleY))
            p(43, "1.0")
            if abs(rotationRad) > 1e-9 { p(50, num(rotationRad * deg)) }

        case .dimension(let parts, _):
            // Decomposed: dimension line, text, witness lines, arrows.
            for part in parts { emit(part, group: group, into: &s) }
        }
    }
}

extension JWW.Entity {
    /// This entity with its coordinates and lengths multiplied by `factor` about the origin.
    ///
    /// An insert scales its position and its scale factors, a zero factor reading as 1 as the
    /// writer does, and keeps its rotation.
    func scaled(by factor: Double) -> JWW.Entity {
        guard factor != 1 else { return self }
        if case .insert(
            let def, let at, let scaleX, let scaleY, let rotation, let layer, let color) =
            self
        {
            return .insert(
                def: def, at: JWW.Point(x: at.x * factor, y: at.y * factor),
                scaleX: (scaleX == 0 ? 1 : scaleX) * factor,
                scaleY: (scaleY == 0 ? 1 : scaleY) * factor, rotationRad: rotation, layer: layer,
                color: color)
        }
        return transformed(
            by: Affine(
                scaleX: factor, scaleY: factor, rotation: 0, translation: JWW.Point(x: 0, y: 0)))
    }
}
