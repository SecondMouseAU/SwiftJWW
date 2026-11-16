import Foundation

extension DXFEmitter {
    /// The `TABLES` section: the linetype and the layers the entities use.
    ///
    /// A layer with a JWW name carries it as its description, in the extended data AutoCAD keeps
    /// layer descriptions in.
    mutating func tables() -> String {
        var s = "0\nSECTION\n2\nTABLES\n"
        s += "0\nTABLE\n2\nLTYPE\n70\n1\n"
        s +=
            "0\nLTYPE\n5\n\(handle())\n2\nCONTINUOUS\n70\n0\n3\nSolid line\n72\n65\n73\n0\n40\n0.0\n"
        s += "0\nENDTAB\n"

        let names = Set(layers.keys).union(["0"]).sorted()
        s += "0\nTABLE\n2\nLAYER\n70\n\(names.count)\n"
        for name in names {
            s += "0\nLAYER\n5\n\(handle())\n2\n\(name)\n70\n0\n62\n7\n6\nCONTINUOUS\n"
            if let description = layers[name], !description.isEmpty {
                s += "1001\nAcAecLayerStandard\n1000\n\n1000\n\(DXFWriter.dxfText(description))\n"
            }
        }
        s += "0\nENDTAB\n"

        if layers.values.contains(where: { !$0.isEmpty }) {
            s += "0\nTABLE\n2\nAPPID\n70\n1\n"
            s += "0\nAPPID\n5\n\(handle())\n2\nAcAecLayerStandard\n70\n0\n"
            s += "0\nENDTAB\n"
        }
        return s + "0\nENDSEC\n"
    }
}
