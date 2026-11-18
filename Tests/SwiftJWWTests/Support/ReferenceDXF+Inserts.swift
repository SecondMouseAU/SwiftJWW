import Foundation

extension ReferenceDXF {
    /// The entities of the drawing with every `INSERT` replaced by the members of its block.
    struct Flattened {
        var entities: [Entity] = []
        /// How many inserts were replaced, those inside blocks included.
        var insertCount = 0
        /// One line for each insert or member that could not be placed, and why.
        var unsupported: [String] = []
    }

    /// A map from block coordinates to drawing coordinates: scale, then turn, then move.
    private struct Placement {
        var scale = 1.0
        var cosine = 1.0
        var sine = 0.0
        var dx = 0.0
        var dy = 0.0

        var isIdentity: Bool { scale == 1 && cosine == 1 && sine == 0 && dx == 0 && dy == 0 }
        var degrees: Double { atan2(sine, cosine) * 180 / .pi }

        func apply(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
            (scale * (cosine * x - sine * y) + dx, scale * (sine * x + cosine * y) + dy)
        }

        /// The map that sends a point through `inner` first and then through this one.
        func after(_ inner: Placement) -> Placement {
            let moved = apply(inner.dx, inner.dy)
            return Placement(
                scale: scale * inner.scale, cosine: cosine * inner.cosine - sine * inner.sine,
                sine: sine * inner.cosine + cosine * inner.sine, dx: moved.x, dy: moved.y)
        }
    }

    /// Replaces each `INSERT` by the entities of its block, placed as the insert places them.
    ///
    /// An insert is placed by its position (groups 10 and 20), one scale for both axes (groups 41
    /// and 42), its rotation in degrees (group 50) and the base point of its block. A member on
    /// layer `0` takes the layer of the insert. A mirror, a scale that differs between the axes, an
    /// array of inserts or a member of a type the comparison does not read is listed in
    /// ``Flattened/unsupported`` instead of being placed wrongly.
    ///
    /// - Parameter maxDepth: The deepest nesting of inserts followed.
    /// - Returns: The entities with the inserts placed, and what could not be placed.
    func flattened(maxDepth: Int = 32) -> Flattened {
        let members = blocks
        var bases: [String: (x: Double, y: Double)] = [:]
        for record in blockRecords where record.type == "BLOCK" {
            if let name = record.text(2) {
                bases[name] = (record.number(10) ?? 0, record.number(20) ?? 0)
            }
        }
        var result = Flattened()

        func number(_ value: Double) -> String { "\(value)" }

        func place(_ e: Entity, _ p: Placement, layer: String?, depth: Int) {
            guard e.type == "INSERT" else {
                let placed = moved(e, by: p, layer: layer)
                result.entities.append(placed)
                return
            }
            let name = e.text(2) ?? ""
            let sx = e.number(41) ?? 1
            let sy = e.number(42) ?? 1
            guard let inside = members[name] else {
                result.unsupported.append("an INSERT of block \(name), which has no definition")
                return
            }
            guard sx > 0, abs(sx - sy) <= 1e-9 * sx else {
                result.unsupported.append("an INSERT of \(name) with scale \(sx), \(sy)")
                return
            }
            guard (e.number(70) ?? 1) <= 1, (e.number(71) ?? 1) <= 1 else {
                result.unsupported.append("an INSERT of \(name) that is an array")
                return
            }
            guard depth < maxDepth else {
                result.unsupported.append("an INSERT of \(name) nested more than \(maxDepth) deep")
                return
            }
            result.insertCount += 1
            let turn = (e.number(50) ?? 0) * .pi / 180
            let base = bases[name] ?? (0, 0)
            var local = Placement(scale: sx, cosine: cos(turn), sine: sin(turn))
            // position + scale * turn * (point - base), as one scale-turn-move.
            let atBase = local.apply(base.x, base.y)
            local.dx = (e.number(10) ?? 0) - atBase.x
            local.dy = (e.number(20) ?? 0) - atBase.y
            let own = e.layer == "0" ? layer : e.layer
            for member in inside { place(member, p.after(local), layer: own, depth: depth + 1) }
        }

        func moved(_ e: Entity, by p: Placement, layer: String?) -> Entity {
            var out = e
            if let layer, e.layer == "0" { out.groups[8] = [layer] }
            guard !p.isIdentity else { return out }
            func point(_ x: Int, _ y: Int) {
                guard let u = e.number(x), let v = e.number(y) else { return }
                let q = p.apply(u, v)
                out.groups[x] = [number(q.x)]
                out.groups[y] = [number(q.y)]
            }
            func turned(_ code: Int) {
                guard let a = e.number(code) else { return }
                var d = (a + p.degrees).truncatingRemainder(dividingBy: 360)
                if d < 0 { d += 360 }
                out.groups[code] = [number(d)]
            }
            func scaled(_ code: Int) {
                if let v = e.number(code) { out.groups[code] = [number(v * p.scale)] }
            }
            switch e.type {
            case "LINE":
                point(10, 20)
                point(11, 21)
            case "POINT":
                point(10, 20)
            case "CIRCLE":
                point(10, 20)
                scaled(40)
            case "ARC":
                point(10, 20)
                scaled(40)
                turned(50)
                turned(51)
            case "ELLIPSE":
                point(10, 20)
                // The major axis is a vector from the center: it turns and scales but does not move.
                if let u = e.number(11), let v = e.number(21) {
                    let q = Placement(scale: p.scale, cosine: p.cosine, sine: p.sine).apply(u, v)
                    out.groups[11] = [number(q.x)]
                    out.groups[21] = [number(q.y)]
                }
            case "TEXT":
                point(10, 20)
                scaled(40)
                turned(50)
                if e.groups[11] != nil {
                    result.unsupported.append("a TEXT with an alignment point in a block")
                }
            default:
                result.unsupported.append("a \(e.type) in a block placed by an insert")
            }
            return out
        }

        for e in entities { place(e, Placement(), layer: nil, depth: 0) }
        return result
    }
}
