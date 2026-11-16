import Foundation
import SwiftJWW

let usage = "usage: jww2dxf [--full-size] [--recover-dimensions] <in.jww> [out.dxf]\n"
var options = DXFWriter.Options()
var paths: [String] = []
for argument in CommandLine.arguments.dropFirst() {
    switch argument {
    case "--full-size": options.fullSize = true
    case "--recover-dimensions": options.recoversDimensions = true
    case _ where argument.hasPrefix("--"):
        FileHandle.standardError.write(
            "jww2dxf: unknown option \(argument)\n\(usage)".data(using: .utf8)!)
        exit(2)
    default: paths.append(argument)
    }
}
guard !paths.isEmpty, paths.count <= 2 else {
    FileHandle.standardError.write(usage.data(using: .utf8)!)
    exit(2)
}
let inURL = URL(fileURLWithPath: paths[0])
let outURL =
    paths.count >= 2
    ? URL(fileURLWithPath: paths[1])
    : inURL.deletingPathExtension().appendingPathExtension("dxf")

do {
    let dwg = try JWW.read(contentsOf: inURL)
    let report = try DXFWriter.write(dwg, to: outURL, options: options)
    let c = dwg.counts
    var line = "\(inURL.lastPathComponent) → \(outURL.lastPathComponent)  (v\(dwg.version); "
    line += "\(c.line) line, \(c.arc) arc, \(c.point) point, \(c.text) text"
    if c.solid + c.block + c.dim > 0 {
        line += "; skipped \(c.solid) solid/\(c.block) block/\(c.dim) dim"
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
