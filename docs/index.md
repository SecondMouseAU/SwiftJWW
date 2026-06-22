---
title: SwiftJWW
nav_order: 1
---

# SwiftJWW

A native-Swift reader for **JWW** — the native drawing format of [**Jw_cad**](https://www.jwcad.net/),
the free 2D CAD program widely used in Japan — plus a **`jww2dxf`** command-line converter.

JWW is an MFC `CArchive`-serialized binary file: a `JwwData.` magic, a version, a large (version-gated)
document header, then an MFC object array of drawing entities. SwiftJWW reads the **geometry** — lines,
arcs/circles/ellipses, points, and text — into a neutral ``Drawing`` and converts it to **DXF**.

- Pure Swift, **no third-party dependencies**.
- Clean-room port of the documented JWW byte layout (the published `jwdatafmt` spec + LibreCAD's
  `jwwlib` as the reference reader). **Validated byte-for-byte against the reference reader** on real
  drawings (JWW v7.00): identical entity counts and bounding boxes across thousands of entities.

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/SecondMouseAU/SwiftJWW.git", from: "1.0.0"),
],
```

```swift
.target(name: "YourTarget", dependencies: [.product(name: "SwiftJWW", package: "SwiftJWW")]),
```

---

## Command line

```
swift run jww2dxf drawing.jww            # → drawing.dxf
swift run jww2dxf drawing.jww out.dxf
```

Prints a one-line summary (version, entity counts, bbox) and writes the DXF.

---

## Library

```swift
import SwiftJWW

let dwg = try JWW.read(contentsOf: url)
print(dwg.version, dwg.counts, dwg.bounds as Any)

for e in dwg.entities {
    switch e {
    case let .line(a, b, layer, color): break
    case let .arc(center, radius, start, sweep, tilt, ratio, full, layer, color): break
    case let .point(at, layer, color): break
    case let .text(at, height, width, angleRad, raw, layer, color): break
    }
}

let dxf = DXFWriter.string(dwg)          // or: try DXFWriter.write(dwg, to: url)
```

`JWW.looksLikeJWW(data)` sniffs the `JwwData.` signature.

### Model

```swift
enum Entity {
    case line(a: Point, b: Point, layer: Int, color: Int)
    case arc(center: Point, radius: Double, start: Double, sweep: Double,
             tilt: Double, ratio: Double, full: Bool, layer: Int, color: Int)   // start/sweep radians
    case point(at: Point, layer: Int, color: Int)
    case text(at: Point, height: Double, width: Double, angleRad: Double,
              raw: [UInt8], layer: Int, color: Int)                              // raw = CP932 bytes
}
```

`Drawing.counts` exposes per-class counts (line / arc / point / text / solid / block / dim) for
verification against reference tools; `Drawing.bounds` gives the drawing extent.

---

## DXF mapping

| JWW | DXF |
|---|---|
| line | `LINE` |
| full circle | `CIRCLE` |
| circular arc | `ARC` |
| elliptical arc (ratio ≠ 1) | `ELLIPSE` |
| point | `POINT` |
| text | `TEXT` |

Output is an entities-only, version-agnostic ASCII DXF accepted by AutoCAD, LibreCAD, and most CAD
tools. JWW pen colours pass through as AutoCAD Color Index values; JWW layer numbers become DXF layer
names.

---

## Scope & notes

v1 covers **lines, arcs/circles/ellipses, points, and text** — the core of typical drawings. **Block
inserts and dimensions** are recognised and counted, but not yet expanded into geometry (a planned
addition).

**Text encoding.** JWW stores text as **CP932 (Shift-JIS)** bytes; `Entity.text` exposes the `raw`
bytes, and the DXF writer decodes them to Unicode using the system's CoreFoundation encoding tables.
That's reliable on Apple platforms; on Linux (swift-corelibs-Foundation) CP932 may be unavailable, so
Japanese text may not decode — the geometry still converts. To stay fully portable, decode `raw`
yourself with a vendored Shift-JIS table.

**DWG** is out of scope (proprietary). Produce DXF here and convert to DWG downstream (e.g. the free
ODA File Converter) if you need it.

---

## License & provenance

MIT. This is a **clean-room reimplementation** of the JWW byte layout — no `jwwlib` source is included.
JWW and Jw_cad are the work of their respective authors; LibreCAD's `jwwlib` (GPL) and the published
`jwdatafmt` specification were used as format references.
