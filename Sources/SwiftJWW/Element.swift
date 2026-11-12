import Foundation

extension JWW {
    /// A drawing object with its attributes: the entity-level result of reading a JWW file.
    ///
    /// ``entity`` is the same geometry ``Drawing/entities`` lists; the element adds the layer group,
    /// line type, colour, pen width and attribute flags.
    public struct Element: Sendable {
        public var entity: Entity
        public var attributes: Attributes

        /// The structured form of a dimension; nil for any other entity.
        public var dimension: Dimension? { Dimension(self) }

        public init(entity: Entity, attributes: Attributes) {
            self.entity = entity
            self.attributes = attributes
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
}
