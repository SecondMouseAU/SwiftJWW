import Foundation

/// The state of one DXF while it is written: handles, the layers used and the dimension blocks.
struct DXFEmitter {
    let drawing: JWW.Drawing
    let options: DXFWriter.Options
    /// The anonymous blocks of the dimensions written so far, as DXF text.
    var anonymousBlocks: [String] = []
    /// The handles of the `DIMENSION`s rebuilt from loose pieces, in the order written.
    var recoveredHandles: [String] = []
    /// The layers written so far, by name, each with the JWW layer name it stands for.
    var layers: [String: String] = [:]
    private var nextHandle = 1

    init(drawing: JWW.Drawing, options: DXFWriter.Options) {
        self.drawing = drawing
        self.options = options
    }

    /// The factor an element's coordinates are multiplied by: its layer group's scale when writing
    /// full size and the group is known, otherwise 1.
    func scale(of element: JWW.Element) -> Double {
        scale(ofGroup: element.attributes.layerGroup)
    }

    /// The factor for a layer group: its scale when writing full size and it is known, otherwise 1.
    func scale(ofGroup group: Int) -> Double {
        guard options.fullSize, let scale = drawing.scale(ofLayerGroup: group),
            scale.isFinite, scale > 0
        else { return 1 }
        return scale
    }

    /// The next handle (group 5), in hexadecimal.
    mutating func handle() -> String {
        defer { nextHandle += 1 }
        return String(nextHandle, radix: 16, uppercase: true)
    }

    /// The name of the DXF layer for a JWW layer group and layer, which it records as used.
    mutating func layerName(group: Int, layer: Int) -> String {
        let name = DXFWriter.layerName(group: group, layer: layer)
        if layers[name] == nil {
            let groups = drawing.layerGroups
            layers[name] =
                groups.indices.contains(group)
                ? groups[group].layers.first { $0.index == layer }?.name ?? "" : ""
        }
        return name
    }

    // MARK: blocks and elements

    /// Writes a block definition as a `BLOCK` named `BLK<number>`, its members as they are drawn.
    ///
    /// The scale of a full-size drawing is carried by the insert, not by the members.
    mutating func emitBlock(_ def: JWW.BlockDef, into s: inout String) {
        let name = "BLK\(def.number)"
        s += "0\nBLOCK\n5\n\(handle())\n8\n0\n2\n\(name)\n70\n0\n10\n0.0\n20\n0.0\n30\n0.0\n"
        s += "3\n\(name)\n"
        for member in def.elements { emit(member, scale: 1, into: &s) }
        s += "0\nENDBLK\n5\n\(handle())\n8\n0\n"
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
                members: parts.prefix(JWW.Dimension.PartLayout.drawn.upperBound).map {
                    $0.scaled(by: scale)
                },
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
        /// The first groups every entity has: its type, handle, layer and colour.
        func head(_ type: String, _ layer: Int, _ color: Int) {
            p(0, type)
            p(5, handle())
            p(8, layerName(group: group, layer: layer))
            p(62, aci(color))
        }

        switch e {
        case .line(let a, let b, let layer, let color):
            head("LINE", layer, color)
            p(10, num(a.x))
            p(20, num(a.y))
            p(30, "0.0")
            p(11, num(b.x))
            p(21, num(b.y))
            p(31, "0.0")

        case .arc(
            let c, let r, let start, let sweep, let tilt, let ratio, let full, let layer, let color):
            if abs(ratio - 1) < 1e-9 {  // circle / circular arc
                if full || abs(abs(sweep) - 2 * .pi) < 1e-6 {
                    head("CIRCLE", layer, color)
                    p(10, num(c.x))
                    p(20, num(c.y))
                    p(30, "0.0")
                    p(40, num(r))
                } else {
                    head("ARC", layer, color)
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
                head("ELLIPSE", layer, color)
                p(10, num(c.x))
                p(20, num(c.y))
                p(30, "0.0")
                p(11, num(cos(tilt) * r))
                p(21, num(sin(tilt) * r))
                p(31, "0.0")  // major axis endpoint, rel. to center
                p(40, num(ratio))
                // An ELLIPSE runs counter-clockwise from group 41 to group 42, so a negative sweep
                // is written from its far end, as an ARC is.
                p(41, num(full ? 0 : min(start, start + sweep)))
                p(42, num(full ? 2 * .pi : max(start, start + sweep)))
            }

        case .point(let at, let layer, let color):
            head("POINT", layer, color)
            p(10, num(at.x))
            p(20, num(at.y))
            p(30, "0.0")

        case .text(let at, let height, _, let angleRad, let string, let layer, let color):
            head("TEXT", layer, color)
            p(10, num(at.x))
            p(20, num(at.y))
            p(30, "0.0")
            p(40, num(height > 0 ? height : 2.5))
            p(1, DXFWriter.dxfText(string))
            if abs(angleRad) > 1e-9 { p(50, num(angleRad * deg)) }

        case .insert(let def, let at, let scaleX, let scaleY, let rotationRad, let layer, let color):
            head("INSERT", layer, color)
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
