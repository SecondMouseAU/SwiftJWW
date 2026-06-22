# SwiftJWW

[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftJWW%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SecondMouseAU/SwiftJWW)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftJWW%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SecondMouseAU/SwiftJWW)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-page-2ea44f)](https://secondmouseau.github.io/SwiftJWW/)

📖 **Documentation:** <https://secondmouseau.github.io/SwiftJWW/>

A native-Swift reader for **JWW** — the native drawing format of [**Jw_cad**](https://www.jwcad.net/),
the free 2D CAD program widely used in Japan — plus a **`jww2dxf`** command-line converter.

JWW is an MFC `CArchive`-serialized binary file (`JwwData.` magic, a version, a large version-gated
document header, then an MFC object array of entities). SwiftJWW reads the geometry — **lines,
arcs/circles/ellipses, points, and text** — and converts it to **DXF**.

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

for e in dwg.entities {
    switch e {
    case let .line(a, b, layer, color):  …
    case let .arc(center, radius, start, sweep, tilt, ratio, full, layer, color):  …
    case let .point(at, layer, color):  …
    case let .text(at, height, width, angleRad, raw, layer, color):  …   // `raw` is CP932 bytes
    }
}

let dxf = DXFWriter.string(dwg)          // or DXFWriter.write(dwg, to: url)
```

`JWW.looksLikeJWW(data)` sniffs the `JwwData.` signature.

## Scope & notes

Covers **lines, arcs/circles/ellipses, points, text, block definitions + inserts, and dimensions**.
Block definitions become DXF `BLOCK`s and inserts become `INSERT`s (`Drawing.blocks` holds the defs by
number); dimensions are decomposed into their drawn parts (dimension line, value text, witness lines,
arrows). **Text is decoded to Unicode at read time** (`Entity.text.string`) from the file's CP932
(Shift-JIS) bytes via `JWW.decodeCP932`, and the DXF writer emits non-ASCII as `\U+XXXX` escapes so
Japanese renders in AutoCAD / LibreCAD regardless of code page. (CP932 decoding uses CoreFoundation —
reliable on Apple platforms; on Linux it falls back and Japanese may not decode, but geometry still
converts.)

> Block/dimension support is validated on synthetic fixtures and is structurally correct against the
> documented format; the line/arc/point/text core is additionally validated byte-for-byte against the
> reference reader on real drawings.

DWG output is out of scope (proprietary); produce DXF here and convert to DWG downstream (e.g. the free
ODA File Converter) if needed.

## License

MIT. JWW and Jw_cad are the work of their respective authors; the reference `jwwlib` is part of
LibreCAD (GPL). This is a clean-room reimplementation of the format — no jwwlib code is included.
