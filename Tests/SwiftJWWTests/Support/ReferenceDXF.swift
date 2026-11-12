import Foundation

@testable import SwiftJWW

/// A minimal reader for the ASCII DXF that the JWW publisher exports.
///
/// It keeps header values and entities by group code, and only what the JWW comparison needs.
struct ReferenceDXF {
    struct Entity {
        var type: String
        var groups: [Int: [String]] = [:]

        var layer: String { groups[8]?.first ?? "" }
        var lineType: String { groups[6]?.first ?? "" }
        func number(_ code: Int, _ index: Int = 0) -> Double? {
            guard let values = groups[code], values.indices.contains(index) else { return nil }
            return Double(values[index].trimmingCharacters(in: .whitespaces))
        }
        func text(_ code: Int) -> String? { groups[code]?.first }
    }

    /// Header variable to group code to first value, such as `$EXTMAX` to `10` to `23760`.
    var header: [String: [Int: String]] = [:]
    var entities: [Entity] = []

    /// A line that should hold a group code but does not: the file is not a well-formed DXF.
    struct MalformedError: Error, CustomStringConvertible {
        var line: Int
        var content: String
        var description: String { "DXF line \(line) is not a group code: \(content)" }
    }

    init(contentsOf url: URL) throws {
        try self.init(text: JWW.decodeCP932([UInt8](try Data(contentsOf: url))))
    }

    /// Reads DXF text, and throws on a line that is not a group code rather than skipping it.
    init(text: String) throws {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        var section = ""
        var variable: String?
        var current: Entity?
        var previous: (code: Int, value: String)?
        var i = 0
        while i + 1 < lines.count {
            defer { i += 2 }
            guard let code = Int(lines[i].trimmingCharacters(in: .whitespaces)) else {
                throw MalformedError(line: i + 1, content: String(lines[i]))
            }
            let value = String(lines[i + 1])
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if code == 0 {
                if let finished = current { entities.append(finished) }
                current = nil
                variable = nil
                if trimmed == "ENDSEC" {
                    section = ""
                } else if section == "ENTITIES", trimmed != "SECTION", trimmed != "EOF" {
                    current = Entity(type: trimmed)
                }
            } else if code == 2, previous?.code == 0, previous?.value == "SECTION" {
                section = trimmed
            } else if section == "HEADER" {
                if code == 9 {
                    variable = trimmed
                } else if let name = variable, header[name]?[code] == nil {
                    header[name, default: [:]][code] = trimmed
                }
            } else if section == "ENTITIES" {
                current?.groups[code, default: []].append(value)
            }
            previous = (code, trimmed)
        }
        if i < lines.count {
            throw MalformedError(line: i + 1, content: String(lines[i]))
        }
        if let finished = current { entities.append(finished) }
    }
}
