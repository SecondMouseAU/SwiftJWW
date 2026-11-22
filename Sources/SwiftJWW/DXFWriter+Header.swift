import Foundation

extension DXFWriter {
    /// The `$ACADVER` the `HEADER` declares: R12, which is what Jw_cad's own DXF export declares.
    static let versionName = "AC1009"

    /// The `$INSUNITS` code the `HEADER` declares: 4, millimetres.
    static let insertionUnits = 4

    /// The `HEADER` section: the version, the length unit of the coordinates, and that entities
    /// have handles, with `handseed` (hexadecimal) as the next one free.
    static func header(handseed: String) -> String {
        "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\n\(versionName)\n"
            + "9\n$INSUNITS\n70\n\(insertionUnits)\n9\n$HANDLING\n70\n1\n"
            + "9\n$HANDSEED\n5\n\(handseed)\n0\nENDSEC\n"
    }
}
