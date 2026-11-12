# SwiftJWW

[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftJWW%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SecondMouseAU/SwiftJWW)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftJWW%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SecondMouseAU/SwiftJWW)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-page-2ea44f)](https://secondmouseau.github.io/SwiftJWW/)

📖 **Documentation:** <https://secondmouseau.github.io/SwiftJWW/>

A native-Swift reader for **JWW**, the native drawing format of [**Jw_cad**](https://www.jwcad.net/)
(the free 2D CAD program widely used in Japan), plus a **`jww2dxf`** command-line converter.

JWW is an MFC `CArchive`-serialized binary file (`JwwData.` magic, a version, a large version-gated
document header, then an MFC object array of entities). SwiftJWW reads the geometry (**lines,
arcs/circles/ellipses, points, and text**), the layer groups with their scales and dimensions, and
converts it to **DXF**.

- Pure Swift, no third-party dependencies.
- Clean-room port of the documented JWW byte layout (the published `jwdatafmt` spec + LibreCAD's
  `jwwlib` as the reference reader). **Validated byte-for-byte** against the reference reader on real
  drawings: identical entity counts and bounding boxes.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/SecondMouseAU/SwiftJWW.git", from: "1.0.0"),
],
// target:
.target(name: "YourTarget", dependencies: [.product(name: "SwiftJWW", package: "SwiftJWW")]),
```

## CLI

```
swift run jww2dxf drawing.jww            # → drawing.dxf
swift run jww2dxf drawing.jww out.dxf
```

## Library

```swift
import SwiftJWW

let dwg = try JWW.read(contentsOf: url)
print(dwg.version, dwg.counts.line, dwg.counts.arc, dwg.bounds as Any)

for element in dwg.elements {
    let attributes = element.attributes   // layerGroup, layer, lineType, color, penWidth, flags
    switch element.entity {
    case let .line(a, b, layer, color):  …
    case let .arc(center, radius, start, sweep, tilt, ratio, full, layer, color):  …
    case let .point(at, layer, color):  …
    case let .text(at, height, width, angleRad, string, layer, color):  …   // Unicode, angle in radians
    case let .insert(def, at, scaleX, scaleY, rotationRad, layer, color):  …
    case let .dimension(parts, layer):  …
    }
}

let dxf = DXFWriter.string(dwg)          // or DXFWriter.write(dwg, to: url)
```

`JWW.looksLikeJWW(data)` sniffs the `JwwData.` signature. `Drawing.entities` is the same geometry
without the attributes, kept for source compatibility.

**Layers and scale.** `Drawing.layerGroups` holds the 16 layer groups, each with its name, its 16
named layers and its `scale`, the denominator of the sheet scale (80 means 1:80). A drawn length
times `dwg.scale(ofLayerGroup:)` is the full-size length.

**Dimensions.** `element.dimension` reads a dimension record as one object: dimension line, text and
its numeric `value`, extension lines, arrow points and measured points. A file stores a record only
when the drawing used Jw_cad's dimension command; a converted or exploded drawing keeps the pieces as
loose lines, points and text with the dimension attribute flags set. `dwg.recoveringDimensions()`
pairs each dimension value text with the two arrow points at its stated distance and lists every
value it could not explain.

## Scope & notes

Covers **lines, arcs/circles/ellipses, points, text, block definitions + inserts, and dimensions**.
Block definitions become DXF `BLOCK`s and inserts become `INSERT`s (`Drawing.blocks` holds the defs by
number); dimension records are decomposed into their drawn parts in `Drawing.entities` and in the DXF.
**Text is decoded to Unicode at read time** (`Entity.text.string`) from the file's CP932 (Shift-JIS)
bytes via `JWW.decodeCP932`, and the DXF writer emits non-ASCII as `\U+XXXX` escapes so Japanese
renders in AutoCAD / LibreCAD regardless of code page. (CP932 decoding uses CoreFoundation, which is
reliable on Apple platforms; on Linux it falls back and Japanese may not decode, but geometry still
converts.) The DXF writer does not apply the layer group scale.

DWG output is out of scope (proprietary); produce DXF here and convert to DWG downstream (e.g. the free
ODA File Converter) if needed.

## License

MIT. JWW and Jw_cad are the work of their respective authors; the reference `jwwlib` is part of
LibreCAD (GPL). This is a clean-room reimplementation of the format, so no jwwlib code is included.
