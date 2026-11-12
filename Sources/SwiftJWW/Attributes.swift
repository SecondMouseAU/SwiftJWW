import Foundation

extension JWW {
    /// The pen and placement attributes every JWW drawing object carries.
    public struct Attributes: Equatable, Sendable {
        /// Layer group number, 0...15.
        public var layerGroup: Int
        /// Layer number within the group, 0...15.
        public var layer: Int
        /// Line type (JWW pen style) number, which a point sets to 100 for an arrow or marker.
        public var lineType: Int
        /// Pen colour number, as stored in the file.
        public var color: Int
        /// Pen width, zero for files older than version 3.51, which store none.
        public var penWidth: Int
        /// Curve attribute number; lines that form one connected curve share it.
        public var curveAttribute: Int
        /// Raw attribute flag word (hatch, dimension, fitting and similar bits).
        public var flags: Int

        public init(
            layerGroup: Int = 0, layer: Int = 0, lineType: Int = 1, color: Int = 1,
            penWidth: Int = 0, curveAttribute: Int = 0, flags: Int = 0
        ) {
            self.layerGroup = layerGroup
            self.layer = layer
            self.lineType = lineType
            self.color = color
            self.penWidth = penWidth
            self.curveAttribute = curveAttribute
            self.flags = flags
        }
    }
}
