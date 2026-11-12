import Foundation

extension JWW {
    /// A drawing with its block inserts replaced by the entities they stand for.
    public struct BlockExpansion: Sendable {
        /// The drawing's objects in file order, each insert replaced in place by its members.
        ///
        /// Members are mapped to drawing coordinates and list the references they came from in
        /// ``Element/references``.
        public var elements: [Element]
        /// Inserts left out because their definition is missing or they reference their own block,
        /// directly or through other blocks.
        public var unresolved: [BlockReference]
    }
}

extension JWW.Drawing {
    /// Replaces every block insert with the members of its definition.
    ///
    /// An insert scales its block about the block origin by `scaleX` and `scaleY` (a zero scale
    /// reads as 1, as in the DXF writer), rotates by `rotationRad`, and translates to `at`. Inserts
    /// inside a block are expanded in turn, up to `maxDepth` levels. Members keep their own layer,
    /// line type and colour; the insert's are in the matching ``BlockReference``.
    ///
    /// - Parameter maxDepth: The deepest block nesting to follow before an insert is left unresolved.
    /// - Returns: The drawing's objects with inserts expanded, and the inserts that could not be.
    public func expandingBlocks(maxDepth: Int = 32) -> JWW.BlockExpansion {
        var out: [JWW.Element] = []
        var unresolved: [JWW.BlockReference] = []
        expand(
            elements, transform: .identity, chain: [], maxDepth: maxDepth, into: &out,
            unresolved: &unresolved)
        return JWW.BlockExpansion(elements: out, unresolved: unresolved)
    }

    private func expand(
        _ list: [JWW.Element], transform: Affine, chain: [JWW.BlockReference], maxDepth: Int,
        into out: inout [JWW.Element], unresolved: inout [JWW.BlockReference]
    ) {
        for (index, element) in list.enumerated() {
            guard
                case .insert(let def, let at, let scaleX, let scaleY, let rotation, _, _) =
                    element.entity
            else {
                let entity =
                    chain.isEmpty ? element.entity : element.entity.transformed(by: transform)
                out.append(
                    JWW.Element(entity: entity, attributes: element.attributes, references: chain))
                continue
            }
            let reference = JWW.BlockReference(
                definition: def, name: blocks[def]?.name ?? "", index: index, at: at,
                scaleX: scaleX, scaleY: scaleY, rotationRad: rotation,
                attributes: element.attributes)
            guard let block = blocks[def], chain.count < maxDepth,
                !chain.contains(where: { $0.definition == def })
            else {
                unresolved.append(reference)
                continue
            }
            let placement = Affine(
                scaleX: scaleX == 0 ? 1 : scaleX, scaleY: scaleY == 0 ? 1 : scaleY,
                rotation: rotation, translation: at)
            expand(
                block.elements, transform: transform.concatenating(placement),
                chain: chain + [reference], maxDepth: maxDepth, into: &out, unresolved: &unresolved)
        }
    }
}
