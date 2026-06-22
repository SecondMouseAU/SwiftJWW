import Foundation
import SwiftJWW

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: jww2dxf <in.jww> [out.dxf]\n".data(using: .utf8)!)
    exit(2)
}
let inURL = URL(fileURLWithPath: args[1])
let outURL = args.count >= 3 ? URL(fileURLWithPath: args[2])
    : inURL.deletingPathExtension().appendingPathExtension("dxf")

do {
    let dwg = try JWW.read(contentsOf: inURL)
    try DXFWriter.write(dwg, to: outURL)
    let c = dwg.counts
    var line = "\(inURL.lastPathComponent) → \(outURL.lastPathComponent)  (v\(dwg.version); "
    line += "\(c.line) line, \(c.arc) arc, \(c.point) point, \(c.text) text"
    if c.solid + c.block + c.dim > 0 { line += "; skipped \(c.solid) solid/\(c.block) block/\(c.dim) dim" }
    line += ")"
    if let b = dwg.bounds {
        line += String(format: "  bbox %.2f×%.2f", b.max.x - b.min.x, b.max.y - b.min.y)
    }
    print(line)
} catch {
    FileHandle.standardError.write("jww2dxf: \(error)\n".data(using: .utf8)!)
    exit(1)
}
