import Foundation

extension JWW {
    /// One of the 16 layer groups of a JWW drawing, with its 16 layers.
    public struct LayerGroup: Sendable {
        /// Group number, 0...15.
        public var index: Int
        /// Group name, decoded from CP932, empty when the group is unnamed.
        public var name: String
        /// The scale denominator of the group: 80 means the group is drawn at 1:80.
        ///
        /// Multiply a drawn length by this to get the full-size length.
        public var scale: Double
        /// Display state: 0 hidden, 1 display only, 2 editable, 3 write target.
        public var state: Int
        /// Protection: 0 none, 1 display state may change, 2 display state fixed.
        public var protection: Int
        /// The layer new objects are written to within this group.
        public var writeLayer: Int
        public var layers: [Layer]

        /// True when the group is not hidden.
        public var isVisible: Bool { state != 0 }

        public init(
            index: Int, name: String = "", scale: Double = 1, state: Int = 2, protection: Int = 0,
            writeLayer: Int = 0, layers: [Layer] = []
        ) {
            self.index = index
            self.name = name
            self.scale = scale
            self.state = state
            self.protection = protection
            self.writeLayer = writeLayer
            self.layers = layers
        }
    }

    /// One layer of a ``LayerGroup``.
    public struct Layer: Sendable {
        /// Layer number within its group, 0...15.
        public var index: Int
        /// Layer name, decoded from CP932, empty when the layer is unnamed.
        public var name: String
        /// Display state: 0 hidden, 1 display only, 2 editable, 3 write target.
        public var state: Int
        /// Protection: 0 none, 1 display state may change, 2 display state fixed.
        public var protection: Int

        /// True when the layer is not hidden.
        public var isVisible: Bool { state != 0 }

        public init(index: Int, name: String = "", state: Int = 2, protection: Int = 0) {
            self.index = index
            self.name = name
            self.state = state
            self.protection = protection
        }
    }
}
