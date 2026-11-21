import Foundation

extension DXFWriter {
    /// The `$INSUNITS` code the `HEADER` declares: 4, millimetres.
    static let insertionUnits = 4

    /// The `HEADER` section: the length unit of the coordinates, and no `$ACADVER` (see the docs).
    static func header() -> String {
        "0\nSECTION\n2\nHEADER\n9\n$INSUNITS\n70\n\(insertionUnits)\n0\nENDSEC\n"
    }
}
