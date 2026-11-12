import Foundation

extension JWW {
    /// A drawing object with its attributes: the entity-level result of reading a JWW file.
    ///
    /// ``entity`` is the same geometry ``Drawing/entities`` lists; the element adds the layer group,
    /// line type, colour and pen width, and, for an object produced by block expansion, the chain of
    /// block references it came from.
    public struct Element: Sendable {
        public var entity: Entity
        public var attributes: Attributes
        /// The block references this element was expanded from, outermost first, or none.
        public var references: [BlockReference]

        /// The structured form of a dimension; nil for any other entity.
        public var dimension: Dimension? { Dimension(self) }

        public init(entity: Entity, attributes: Attributes, references: [BlockReference] = []) {
            self.entity = entity
            self.attributes = attributes
            self.references = references
        }

        /// Wraps a bare entity, taking its layer and colour and defaulting the rest.
        public init(entity: Entity) {
            self.init(entity: entity, attributes: Element.legacyAttributes(of: entity))
        }

        private static func legacyAttributes(of entity: Entity) -> Attributes {
            switch entity {
            case .line(_, _, let layer, let color),
                .arc(_, _, _, _, _, _, _, let layer, let color),
                .point(_, let layer, let color),
                .text(_, _, _, _, _, let layer, let color),
                .insert(_, _, _, _, _, let layer, let color):
                return Attributes(layer: layer, color: color)
            case .dimension(_, let layer):
                return Attributes(layer: layer)
            }
        }
    }

    /// One block insertion an expanded ``Element`` came from.
    public struct BlockReference: Sendable {
        /// The block definition number, a key of ``Drawing/blocks``.
        public var definition: Int
        /// The block's name, empty when the definition is missing.
        public var name: String
        /// The position of the insert in the list that holds it: the drawing's elements for a
        /// top-level reference, the parent block's elements for a nested one.
        public var index: Int
        public var at: Point
        public var scaleX: Double
        public var scaleY: Double
        public var rotationRad: Double
        /// The insert's own layer, line type and colour.
        public var attributes: Attributes
    }
}
