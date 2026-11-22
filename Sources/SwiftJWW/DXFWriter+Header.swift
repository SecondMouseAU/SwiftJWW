import Foundation

extension DXFWriter {
    /// The `$ACADVER` the `HEADER` declares: R12, which is what Jw_cad's own DXF export declares.
    static let versionName = "AC1009"

    /// The `$INSUNITS` code the `HEADER` declares: 4, millimetres.
    static let insertionUnits = 4

    /// The `HEADER` section: the version and the length unit of the coordinates.
    static func header() -> String {
        "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\n\(versionName)\n"
            + "9\n$INSUNITS\n70\n\(insertionUnits)\n0\nENDSEC\n"
    }
}
