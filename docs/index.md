---
title: SwiftJWW
nav_order: 1
---

# SwiftJWW

A native-Swift reader for **JWW**, the native drawing format of [**Jw_cad**](https://www.jwcad.net/)
(the free 2D CAD program widely used in Japan), plus a **`jww2dxf`** command-line converter.

JWW is an MFC `CArchive`-serialized binary file: a `JwwData.` magic, a version, a large (version-gated)
document header, then an MFC object array of drawing entities. SwiftJWW reads the **geometry** (lines,
arcs/circles/ellipses, points, and text), the layer groups with their scales, dimensions and block
inserts into a neutral ``Drawing``, and converts it to **DXF**.

- Pure Swift, **no third-party dependencies**.
- Clean-room port of the documented JWW byte layout (the published `jwdatafmt` spec + LibreCAD's
  `jwwlib` as the reference reader). **Validated byte-for-byte against the reference reader** on real
  drawings (JWW v7.00): identical entity counts and bounding boxes across thousands of entities.
  Also compared with the DXF published beside 13 real drawings
  ([details](#validation-against-real-drawings)).

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

for element in dwg.elements {
    let attributes = element.attributes
    switch element.entity {
    case let .line(a, b, layer, color): break
    case let .arc(center, radius, start, sweep, tilt, ratio, full, layer, color): break
    case let .point(at, layer, color): break
    case let .text(at, height, width, angleRad, string, layer, color): break
    case let .insert(def, at, scaleX, scaleY, rotationRad, layer, color): break
    case let .dimension(parts, layer): break
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
              string: String, layer: Int, color: Int)                            // decoded from CP932
    case insert(def: Int, at: Point, scaleX: Double, scaleY: Double,
                rotationRad: Double, layer: Int, color: Int)
    case dimension(parts: [Entity], layer: Int)
}

struct Element {                     // Drawing.elements, BlockDef.elements
    var entity: Entity
    var attributes: Attributes       // layerGroup, layer, lineType, color, penWidth, curveAttribute, flags
    var references: [BlockReference] // set on elements produced by block expansion
    var dimension: Dimension? { get }
}
```

`Drawing.counts` exposes per-class counts (line / arc / point / text / solid / block / dim) for
verification against reference tools; `Drawing.bounds` gives the drawing extent. `Drawing.entities`
is the geometry of `Drawing.elements` without the attributes, kept for source compatibility.

`text.angleRad` is in radians. The file stores the angle in degrees; earlier releases passed the stored
number through unconverted, so a text turned 90 degrees read as 90 radians.

### Layers and scale

`Drawing.layerGroups` holds the 16 layer groups. Each `LayerGroup` has `name`, `scale`, `state`,
`protection`, `writeLayer` and its 16 `Layer`s, each with `name`, `state` and `protection`.

`scale` is the denominator of the group's sheet scale: 80 means the group is drawn at 1:80, and a drawn
length times it is the full-size length. `Drawing.scale(ofLayerGroup:)` looks it up by the group number
in `Element.attributes.layerGroup`. A drawing can hold groups at different scales.

`state` is 0 hidden, 1 display only, 2 editable, 3 write target.

### Dimensions

A dimension record (`CDataSunpou`) reads through `Element.dimension` as one `Dimension`:

| Property | Meaning |
|---|---|
| `dimensionLine` | the dimension line |
| `label` | the text: position, height, width, angle and string |
| `value` | the number the text states, without prefix, commas or unit |
| `extensionLines` | the two witness lines (file version 4.20 and later) |
| `arrowPoints` | the two arrow points (4.20 and later) |
| `measuredPoints` | the two reference points the dimension measures between (4.20 and later) |
| `measuredDistance` | the distance between them; times the group scale it should equal `value` |

A file holds a record only when the drawing used Jw_cad's dimension command. A drawing converted from
an older format, or whose dimensions were exploded, keeps the pieces as separate lines, points and
text. Jw_cad marks them in the attribute flags: `0x4010` on a value text, `0x0040` on an arrow point,
`0x2000` on a dimension line or extension line.

`Drawing.recoveringDimensions()` rebuilds a `Dimension` from those pieces. It pairs each value text
with two neighbouring arrow points (none between them) whose distance times the layer group scale is
the stated value within one unit of its last decimal place, picks the pair nearest the text, and adds
the lines that end on the points. An exact duplicate of a text is folded into the dimension it repeats.
It is an inference, so `DimensionRecovery.unmatchedValues` lists every value text it could not explain:
radius, diameter and angle values, values in another unit, and values that differ from the drawn
distance. A recovered dimension has no reference points, so its `measuredPoints` are its arrow points.

### Blocks

`Drawing.expandingBlocks(maxDepth:)` returns a `BlockExpansion`. Each insert is replaced in place by
the members of its definition, scaled about the block origin by `scaleX` and `scaleY` (a zero scale
reads as 1), rotated by `rotationRad`, and moved to `at`. Inserts inside a block expand in turn.
Arcs follow any placement exactly, including non-uniform scale and mirroring, where a circle becomes an
ellipse. Text keeps its place, scales in size and turns with the block; it is not mirrored.

Each expanded `Element.references` lists the inserts it came from, outermost first, each with its
definition number, name, position in its container, placement and attributes. A member keeps its own
layer, line type and colour. `BlockExpansion.unresolved` holds inserts left out because the definition
is missing or the block contains itself. Which layer Jw_cad draws a block member on is not checked
against a real file, because none of the available drawings contains a block.

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
| block definition | `BLOCK` (in the `BLOCKS` section) |
| block insert | `INSERT` (refers to `BLK<number>`) |
| dimension | decomposed into `LINE` / `TEXT` / `POINT` parts |

Output is an entities-only, version-agnostic ASCII DXF accepted by AutoCAD, LibreCAD, and most CAD
tools. JWW pen colours pass through as AutoCAD Color Index values; JWW layer numbers become DXF layer
names.

---

## Scope & notes

Covers **lines, arcs/circles/ellipses, points, text, block definitions + inserts, and dimensions**.
Block definitions are exposed on `Drawing.blocks` (keyed by number) and emitted as DXF `BLOCK`s, with
`.insert` entities becoming `INSERT`s; dimension records are decomposed into their drawn parts in
`Drawing.entities` and in the DXF. The DXF writer does not apply the layer group scale.

**Text encoding.** JWW stores text as **CP932 (Shift-JIS)** bytes; `Entity.text` carries the `string`
decoded at read time with the system's CoreFoundation encoding tables, and the DXF writer emits
non-ASCII as `\U+XXXX` escapes. That is reliable on Apple platforms; on Linux
(swift-corelibs-Foundation) CP932 may be unavailable, so Japanese text may not decode while the
geometry still converts.

**DWG** is out of scope (proprietary). Produce DXF here and convert to DWG downstream (e.g. the free
ODA File Converter) if you need it.

---

## Validation against real drawings

The 13 locomotive drawings on the diesel page of [TECS](https://tecs.g2.xrea.com/cad/dl/dl1.html) are
each published as JWW and as DXF. A test reads each JWW and compares it with its DXF: entity counts per
layer and coordinates must match within 0.01 mm of full size. Across the 13 drawings 58,607 lines,
arcs, circles, points and texts match one for one.

The site allows free use for individual hobby purposes and names no licence, so the files are not in
this repository. Put each `<name>.jww` beside its `<name>.dxf` in a folder and run:

```
SWIFTJWW_FIXTURES=/path/to/folder swift test
```

Without the variable the test is skipped.

The comparison applies the conventions of that DXF export. They were read from these files, not taken
from a specification:

| In the DXF | Convention |
|---|---|
| Coordinates | full size: (drawn value + half the sheet) times `$LTSCALE`, where the sheet is `$EXTMAX / $LTSCALE` |
| `$LTSCALE` | the scale of the write-target layer group, applied to every layer group |
| Layer name | `_<group>-<layer>_<name>`, with group and layer in hex |
| Elliptical arc | written as `LINE` segments, because the R12 format has no `ELLIPSE` |
| Line type 9 | the line is written on a layer called `ADD_LINE` |
| Layer name characters | some are written as underscores, one per byte (`ブレーキ` is `ブレ__キ`) |

What the comparison showed:

- **Text angle** is stored in degrees. The reader treated it as radians until this comparison
  exposed it.
- **Layer group scale** reads as the DXF's `$LTSCALE` for the write-target group in all 13 drawings,
  for example 1:80 for `2120`. Two drawings (`h15tdl1`, `h15tdl2`) also use a second layer group at
  1:10 and 1:5. The DXF export applies 1:50 to it, so converting those objects with their own group
  scale gives a different size from the DXF.
- **No drawing holds a dimension record, a block or a solid.** Their dimensions are loose lines,
  points and text with the dimension attribute flags set. `recoveringDimensions()` rebuilt 214 of
  the 241 dimension values, each with its text at the same place in the DXF. The other 27 are
  diameters such as `860φ` and values with decimals that no pair of arrow points explains; they are
  listed in `unmatchedValues`.
- Block expansion and dimension records are therefore validated on synthetic fixtures only.

---

## License & provenance

MIT. This is a **clean-room reimplementation** of the JWW byte layout, so no `jwwlib` source is
included. JWW and Jw_cad are the work of their respective authors; LibreCAD's `jwwlib` (GPL) and the
published `jwdatafmt` specification were used as format references.
