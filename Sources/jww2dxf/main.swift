import Foundation
import SwiftJWW

let usage = "usage: jww2dxf [--full-size] [--recover-dimensions] <in.jww> [out.dxf]\n"

/// Says what is wrong with the arguments, then how to use the command, and stops with status 2.
func usageError(_ problem: String) -> Never {
    FileHandle.standardError.write("jww2dxf: \(problem)\n\(usage)".data(using: .utf8)!)
    exit(2)
}

var options = DXFWriter.Options()
var paths: [String] = []
for argument in CommandLine.arguments.dropFirst() {
    switch argument {
    case "--full-size": options.fullSize = true
    case "--recover-dimensions": options.recoversDimensions = true
    case _ where argument.hasPrefix("--"): usageError("unknown option \(argument)")
    default: paths.append(argument)
    }
}
if paths.isEmpty { usageError("no input file") }
if paths.count > 2 { usageError("too many arguments") }
let inURL = URL(fileURLWithPath: paths[0])
let outURL =
    paths.count >= 2
    ? URL(fileURLWithPath: paths[1])
    : inURL.deletingPathExtension().appendingPathExtension("dxf")

do {
    let dwg = try JWW.read(contentsOf: inURL)
    let report = try DXFWriter.write(dwg, to: outURL, options: options)
    let c = dwg.counts
    let solids = dwg.skippedSolidCount
    var line = "\(inURL.lastPathComponent) → \(outURL.lastPathComponent)  (v\(dwg.version); "
    line += "\(c.line) line, \(c.arc) arc, \(c.point) point, \(c.text) text"
    if solids + c.block + c.dim > 0 {
        line += "; skipped \(solids) solid/\(c.block) block/\(c.dim) dim"
    }
    if options.recoversDimensions {
        line += "; \(report.recoveredDimensions.count) dimensions recovered, "
        line += "\(report.unexplainedValues.count) values unexplained"
    }
    line += ")"
    if let b = dwg.bounds {
        line += String(format: "  bbox %.2f×%.2f", b.max.x - b.min.x, b.max.y - b.min.y)
    }
    print(line)
} catch {
    FileHandle.standardError.write("jww2dxf: \(error)\n".data(using: .utf8)!)
    exit(1)
}
