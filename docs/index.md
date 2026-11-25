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

What each version changed, with the source-breaking changes called out, is in the
[changelog](https://github.com/SecondMouseAU/SwiftJWW/blob/main/docs/CHANGELOG.md).

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
swift run jww2dxf --full-size --recover-dimensions drawing.jww
```

Prints a one-line summary (version, entity counts, what was skipped, bbox) and writes the DXF. The
skipped solid fills are `Drawing.skippedSolidCount`: those at the top level and those in block
definitions, each counted once. `--full-size` and `--recover-dimensions` set the
[writer options](#scale) of the same names, and with the second the summary adds how many
dimensions were recovered and how many values stayed unexplained.

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
let full = DXFWriter.string(dwg, options: .init(fullSize: true))   // full-size coordinates
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

`Drawing.counts` exposes per-class counts (line / arc / point / text / solid / block / dim) of the
top-level objects for verification against reference tools; `Drawing.bounds` gives the drawing
extent. `Drawing.entities` is the geometry of `Drawing.elements` without the attributes, kept for
source compatibility.

The reader skips solid fills (`CDataSolid`) without reading their shape, so a count is all that is
left of them. `counts.solid` counts the top-level ones. A solid fill inside a block definition is
counted in that block's `BlockDef.solidCount` instead, and each insert of the block places it again,
including an insert inside another block. `Drawing.skippedSolidCount` is the number the file
stores: the top-level fills plus each block definition's, counted once. `BlockExpansion.solidCount`
is the total the expanded drawing holds: the top-level fills, plus each expanded insert's block
count.

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
distance. A duplicate of such a text is listed too, so each value text is either among the
`elementIndices` of one recovered dimension or in `unmatchedValues`, and never in both. A recovered
dimension has no reference points, so its `measuredPoints` are its arrow points.

Each `RecoveredDimension` gives its `pieces`: the elements it was built from, in ascending order of
index, each with the `Role` the recovery gave it. Its `elementIndices` are the indices of those pieces,
computed from them, so the two cannot differ:

| `Role` | The piece |
|---|---|
| `valueText` | the value text |
| `valueTextCopy` | a copy of the value text, stored at the same place |
| `arrowPoint` | one of the two arrow points |
| `dimensionLine` | a line parallel to the line through the arrow points (its sine to that line is under 0.001), with both ends within 0.001 of it, that shares more than a point with the span between them |
| `extensionLine` | a line that is not parallel to that line (its sine is 0.001 or more) and has an end on an arrow point |

The role is the recovery's own decision, taken where it collects the lines of a dimension, so a
consumer does not need to apply the 0.001 sine test again to tell the two apart. A line parallel to
the arrow points' line that does not lie along it, or meets it only at a point, is neither and is not
a piece. An element that two chained dimensions share has its role in the `pieces` of each.

**Source-breaking change.** In 1.5.0 `RecoveredDimension.elementIndices` was a stored `var`. It is now
read-only and computed from `pieces`, which are the stored values, so code that assigns
`elementIndices`, or that constructs a `RecoveredDimension` with it, no longer compiles. Reading
`elementIndices` is unchanged, with the same values in the same order. The memberwise initialiser was
internal, so only code using `@testable import` could construct a `RecoveredDimension`.

### Blocks

`Drawing.expandingBlocks(maxDepth:)` returns a `BlockExpansion`. Each insert is replaced in place by
the members of its definition, scaled about the block origin by `scaleX` and `scaleY` (a zero scale
reads as 1), rotated by `rotationRad`, and moved to `at`. Inserts inside a block expand in turn.
Arcs follow any placement exactly, including non-uniform scale and mirroring, where a circle becomes an
ellipse. Text keeps its place, scales in size and turns with the block; it is not mirrored, and a
mirrored block never leaves it upside down (the turn it takes stays within a quarter turn of upright).

Each expanded `Element.references` lists the inserts it came from, outermost first, each with its
definition number, name, position in its container, placement and attributes. A member keeps its own
layer, line type and colour. `BlockExpansion.unresolved` holds inserts left out because the definition
is missing or the block contains itself, and `BlockExpansion.solidCount` the number of solid fills the
expanded drawing holds ([see Model](#model)). Which layer Jw_cad draws a block member on is not checked
against a real file, because none of the drawings that have a DXF export beside them contains a block.

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
| dimension record | `DIMENSION` (rotated linear), with its parts in an anonymous `*D<n>` block |
| dimension record from a file older than 4.20 | decomposed into `LINE` / `TEXT` / `POINT` parts |

A DXF `ARC` or `ELLIPSE` runs counter-clockwise from its start to its end, so a circular or
elliptical arc with a negative sweep is written from its far end. The DXF then covers the same part
of the curve as the JWW.

A DXF `ELLIPSE` has its major axis along the longer axis and a ratio of at most 1. JWW takes the
axis along its tilt as the radius and scales the other by the ratio, so an ellipse with a ratio
above 1 is longer across the tilt. It is written with the perpendicular axis as the major axis, the
reciprocal ratio, and its start and end parameters turned back a quarter turn. The DXF draws the
same curve.

Output is an ASCII DXF. JWW pen colours pass through as AutoCAD Color Index values.
[Readers run on the DXF](#readers-run-on-the-dxf) lists the readers it was run through; AutoCAD was
not one of them.

### Header and unit

The file opens with a `HEADER` section that declares `$ACADVER` `AC1009` (R12), `$INSUNITS` `4`
(millimetres), `$HANDLING` `1` and `$HANDSEED`. Jw_cad draws in millimetres, so a reader gets the
unit from the file instead of assuming it, and `SwiftDXF` reports a version instead of an empty one.

`$HANDLING` `1` is what makes the group 5 handles valid in R12, which has them only when it is set.
`$HANDSEED` is the next handle no record has, in hexadecimal, so it is above every handle in the
file, the tables' and the blocks' included. It is worked out after the rest of the file is built and
written before it. `libdxfrw` writes the same pair, and `ezdxf` starts its own handles at the seed:
without one it warned of non-unique entity handles on drawings with blocks.

**What the version does and does not say.** `AC1009` is what Jw_cad's own DXF export declares, and
it is the version whose structure the file has: R12 has no subclass markers (group 100), and
neither does the writer, where R13 and later expect them on every record. It does not say the
content is R12. The writer also emits `ELLIPSE` (R13 and later, and real drawings have them), the
`$INSUNITS` variable (R2000 and later; an R12 file has none) and `\U+XXXX` text escapes. A reader
that holds the file to R12 strictly may skip or reject those. None of the readers that were run
does that: each reader in the table that was run reads the same entities under `AC1009` as under each
later version it was given ([Readers run on the DXF](#readers-run-on-the-dxf) gives each result).
One of them, LibreOffice Draw, does not draw `ELLIPSE` under any of the nine versions tried, so
declaring another version would not help it. AutoCAD was not run. Declaring a later version would
first need the subclass markers and owner handles on every record, and on each `TABLE` header a
handle, an owner and a subclass marker.

The unit is millimetres whatever the options, and what a coordinate measures differs:

| `fullSize` | A coordinate is | A line drawn 10 long in a layer group at 1:80 |
|---|---|---|
| set | real millimetres | written as 800 |
| not set | millimetres of paper, at the drawn scale | written as 10, which is 800 at full size |

Without `fullSize`, the scale of the layer group ([Scale](#scale), `Drawing.layerGroups`) turns a
length into a real one. With it, a layer group with no usable scale is still written as drawn.

### Readers run on the DXF

These readers were run on the three things in the output that Autodesk's R12 reference does not
list: `ELLIPSE`, `$INSUNITS` and `\U+XXXX` text escapes (see [Header and unit](#header-and-unit)). The
test files were a five-entity file in the writer's format, with `$ACADVER` set to each of `AC1009`,
`AC1012`, `AC1014`, `AC1015`, `AC1018`, `AC1021`, `AC1024`, `AC1027` and `AC1032`, and the writer's
output for `ec01`, a TECS drawing with blocks and 25 `ELLIPSE`s. The five-entity file has:

- a `HEADER` of `$ACADVER`, `$INSUNITS` 4, `$HANDLING` 1 and `$HANDSEED`, a `LTYPE` table with
  `CONTINUOUS` and a `LAYER` table with `0` and `0-0`, and every entity on `0-0`;
- a `LINE` from (0, 0) to (100, 50) and a `CIRCLE` of radius 10 at (50, 25);
- an `ELLIPSE` at (200, 25) with major axis (30, 0), ratio 0.5 and parameters 0 to 6.283185 (a full
  ellipse), and an `ELLIPSE` at (300, 25) with the same axis and ratio and parameters 0 to 1.570796
  (a quarter);
- a `TEXT` of `\U+5BF8\U+6CD5 A\U+00B0` at (10, 60).

Each reader in the table that was run was run on the five-entity file under all nine versions.
`ec01` was read by `SwiftDXF`, `ezdxf` and `libdxfrw` under the same nine, and drawn by LibreOffice
Draw as written. *Ran* means the program was run on those files, and *read only* means only its
source was read. The table gives what each reader did under `AC1009`, and each reader that was run
gave the same result under the other eight, apart from the version it reports and two differences in
`ezdxf`. It upgrades `AC1012` and `AC1014` to `AC1015` on load, which adds 20 arrow-head blocks of its
own to `ec01` and leaves the modelspace entities as they are, and from `AC1012` on its audit reports
each `TABLE` header that has no handle (see [Layers and handles](#layers-and-handles)).

| Reader | `ELLIPSE` | `$INSUNITS` | `\U+XXXX` |
|---|---|---|---|
| `SwiftDXF` 0.6.1 (ran) | read exactly (centre, major axis, ratio, parameters) | `insUnits` is 4 (nil when the variable is absent) | decoded to `寸法 A°` |
| `ezdxf` 1.4.5 (ran) | read exactly; the audit finds nothing | `doc.units` is 4 (0 when absent) | `ezdxf.read` keeps it as written, in `dxf.text` and in `plain_text()`; `ezdxf.recover.readfile` and `ezdxf.decode_dxf_unicode` decode it |
| `libdxfrw`: LibreCAD's bundled copy (LibreCAD commit `b91fbdc`) and the standalone one (libdxfrw commit `d68fb1e`) (ran: built from source and run through a small program that prints each `ELLIPSE` and counts the other entities) | both read exactly | held as a header variable, 4 | decoded |
| GDAL OGR 3.13.3, the copy in QGIS 4.2.3 (ran, `ogrinfo`) | read as a line string (91 vertices for the full ellipse, 24 for the quarter arc) | listed as `$INSUNITS=4` in the dataset's `DXF_HEADER_VARIABLES` metadata, and applied to nothing (the layer has no spatial reference, and the coordinates are the file's) | kept as written, in the `Text` field and in the label style |
| OpenSCAD 2026.10.11 (ran, `import()` to SVG) | read: 3 contours (the `CIRCLE` and the two `ELLIPSE`s; the `LINE` is not one), and 1 without the `ELLIPSE`s | ignored: the SVG is the same without the variable | `TEXT` is not imported ("Unsupported DXF Entity 'TEXT'") |
| LibreOffice Draw 26.8.3.1 (ran, headless import to SVG and PNG) | **not drawn** (below) | no effect seen in the output | decoded (the SVG text reads `寸法 A°`) |
| Inkscape 1.4.4, `dxf_input.py` (read only: `inkscape` would not open a DXF here) | `export_ellipse`, with no version test (the script's docstring says it takes a DXF of AutoCAD Release 13, `AC1012`, or later, but it never reads `$ACADVER`) | not read by the script | decoded, with no version test |

assimp 6.0 (ran, `assimp info`) gave one mesh of one line from the five-entity file, with the three
present or absent, so it says nothing about them. LibreCAD itself was not run. Its source (read
only) copies every header variable that `libdxfrw` reads into the drawing, with no version test, and
takes the length unit of the drawing from `$INSUNITS`, so by its source it takes the unit under any
version.

**LibreOffice Draw does not draw `ELLIPSE`, under any of the nine versions.** From the five-entity
file it draws the `LINE` and the `CIRCLE` and neither `ELLIPSE`. The nine SVG renders, one per declared
version, are byte-identical to each other and to the render of the same file with the `ELLIPSE`s
removed, and it draws both curves when they are written as `LINE` segments. For `ec01` as written,
the SVG is byte-identical to the one for the same file with its 25 `ELLIPSE` records removed. Nor does
it draw an `ELLIPSE` in a file that is R2000 in structure as well as in name: for files written by
`ezdxf` as R2000 and R2010 and by `libdxfrw` as R2000, the SVG is byte-identical to the one for the
same file without its `ELLIPSE`s. It is the one reader in the table that drops `ELLIPSE`, and
declaring another version does not help it.

**The escape is ordinary in R12-era output, and the unit and `ELLIPSE` are not.** Other writers were
run at R12 and R2000 on `寸法 A°`. LibreCAD's bundled `libdxfrw` writes `\U+5BF8\U+6CD5 A` and the
degree sign as one byte of `$DWGCODEPAGE` `ANSI_1252` at both, with the hex digits in upper case as this
writer has them (this writer also escapes the degree sign). `ezdxf` 1.4.5 writes the same in lower case at
both, and UTF-8 at R2010. The standalone `libdxfrw` wrote the UTF-8 bytes unchanged at R12 and at R2000,
so not every writer uses the escape. `libdxfrw` writes `$INSUNITS` only for a version after `AC1014`
(its source, and its output at `AC1009` and `AC1015`), and `ezdxf` at R12 leaves it out and logs that
drawing units are not exported for R12. At R12 `libdxfrw` writes an ellipse as a `POLYLINE` of
`VERTEX` records and a `SEQEND` (128 vertices for a full ellipse, the default part count), and at
`AC1015` as an `ELLIPSE`.

**Not run.** AutoCAD, ODA, BricsCAD, eDrawings and Shapr3D were not run on the output, so what any of
them does with a file that declares R12 and holds the three is not known. Inkscape's DXF import was
read, not run, and LibreCAD itself was not run (only the `libdxfrw` it bundles, and its source).

### Layers and handles

A layer is named `<group>-<layer>` with both numbers in hexadecimal, the convention of Jw_cad's own
DXF and DWG export: layer 14 of group 0 is `0-E`, and layer 14 of group 1 is `1-E`, so the groups no
longer share layers. A `TABLES` section holds a `LTYPE` table with `CONTINUOUS` and a `LAYER` table of
layer `0` and every layer the entities use. A layer that has a JWW name carries it as its
description, in the `AcAecLayerStandard` extended data AutoCAD keeps layer descriptions in (so
`0-E` is described as 寸法, "dimensions").

`DXFWriter.layerName(group:layer:)` gives the name the writer uses for a JWW layer, so a consumer can
name the layer of a JWW element the way the DXF does.

Every entity, `BLOCK`, `ENDBLK` and table record has a handle (group 5), in hexadecimal and unique in
the file. They are counted in the order the file is built (blocks, then entities, then tables), not
the order it is written in, so the same drawing and options give the same handles.

A `TABLE` header has no handle: it is `0 TABLE`, `2 <name>` and `70 <count>`. That is the whole
header in Autodesk's R12 reference, in the R12 output of `libdxfrw` and in the R12 files with
`$HANDLING` 1 that were checked, and none of the readers tried needs more: `SwiftDXF` 0.6.1, `ezdxf`
1.4.5 (which gives the header of an R12 file a handle itself when it audits, and does not report
that as a fix) and `libdxfrw` (LibreCAD's source of November 2026, built and run). A handle before
the `2` group would hide the tables from readers that expect the name right after `TABLE`:
`SwiftDXF` read no layers or line types, and `libdxfrw` failed the read. A handle after the name or
the count did no harm to those readers, but R12 does not call for one. From R13 on, `ezdxf` and
`libdxfrw` write one there, after the name, and `ezdxf`'s audit reports a header without one.

### Dimension records

A record with measured points (file version 4.20 and later) becomes one `DIMENSION` of type 0, a
rotated linear dimension:

| Group | Value |
|---|---|
| 13, 14 | the two measured points |
| 10 | the start of the dimension line, which is on it |
| 50 | the angle of the dimension line from the x axis, in degrees |
| 11 | the text position |
| 1 | the text as written, such as `1,930` |
| 2 | the anonymous block, `*D1`, `*D2` and so on |

The block holds the drawn parts: the dimension line, the text, the two witness lines and the two
arrow points. The measured points are not drawn, so they are only in groups 13 and 14. A reader
measures a rotated linear dimension as the distance between groups 13 and 14 along group 50, so the
dimension line sets what is measured. A record whose dimension line has no length takes the
direction of its measured points.

### Recovered dimensions

`DXFWriter.Options(recoversDimensions: true)` runs `recoveringDimensions()` and writes each
dimension it rebuilds as one rotated linear `DIMENSION`, at the place its first piece had among the
other elements. The loose lines, points and text it was built from go in the anonymous block it names,
and are not written again as entities. A value text no dimension explains stays a loose `TEXT`. A
piece that two chained dimensions share is in both blocks.

| Group | Value |
|---|---|
| 13, 14 | the ends of the two witness lines away from the dimension line; the arrow point on a side with no witness line |
| 10 | the midpoint of the arrow points, which is on the dimension line |
| 50 | the angle of the dimension line from the first arrow point to the second |
| 11 | the text position |
| 1 | the text as written, such as `10,439` |
| 8 | the layer, such as `0-E` |

If the witness line ends would not measure the arrow distance along the dimension line, which a
slanted witness line causes, both sides take the arrow points.

`DXFWriter.output(_:options:)` returns the text with a `Report`, and `DXFWriter.write(_:to:options:)`
returns the report too:

| Field | Value |
|---|---|
| `recoveredDimensions` | the handles of the `DIMENSION`s rebuilt from loose pieces rather than read from a stored record, in the order written, so a consumer can mark them as inferred |
| `recoveredDimensionPieces` | for each of those handles, the pieces the `DIMENSION` was built from, in the order its block holds them, each as a `RecoveredDimension.Piece` of its `index` and its `role` ([Role](#dimensions)): the `pieces` `recoveringDimensions()` gives for it |
| `recoveredDimensionElements` | for each of those handles, the `index` of each of its `recoveredDimensionPieces`, in the same order, computed from them: the `elementIndices` `recoveringDimensions()` gives for it |
| `unexplainedValues` | the indices into `Drawing.elements` of the dimension value texts no dimension explains |
| `appliedScales` | the factor the top-level elements of each layer group were multiplied by ([Scale](#scale)) |

The four dimension fields are empty without the option. Once the DXF is parsed, a dimension's
handle links it to its pieces in the JWW: the value text, the arrow points, the dimension line and
the extension lines, with each one's text, position and layer, and `recoveredDimensionPieces` says
which of those each is. A piece that two chained dimensions share is listed for both, with its role
in each, and a dimension's value text stored twice at the same place is listed with its copy as a
`valueTextCopy`. A JWW element's position is in drawn coordinates: times `appliedScales` for its
layer group, it is where the DXF draws the piece.

**Source-breaking change.** In 1.5.0 `Report.recoveredDimensionElements` was a stored `var` and a
parameter of `Report.init`. `recoveredDimensionPieces` is now the stored value and
`recoveredDimensionElements` is read-only and computed from it, so the two cannot disagree. Code that
assigns `recoveredDimensionElements`, or that passes `recoveredDimensionElements:` to `Report.init`,
no longer compiles; give the pieces instead. Reading either property is unchanged, with the same
values in the same order, and so is every `Report.init` call that leaves `recoveredDimensionElements`
out.

On the TECS drawings (checked against SwiftDXF 0.4.0, which reads each as a linear `DIMENSION`):

| Drawing | Dimensions | Values unexplained |
|---|---|---|
| `2120` | 29, all on `0-E`, with nothing else left on that layer | 0 |
| `eitakyouta_3` | 13 | 1 |
| `dd12` | 14 | 2 |

With full size, each measures its stated value to within one unit of the last decimal place of its
text, the same tolerance the recovery matches with.

The 29 dimensions of the `2120` hold 29 value texts, 1 copy of a value text, 58 arrow points, 30
dimension lines and 56 extension lines, which is what `recoveredDimensionPieces` reports (a piece two
dimensions share counts once for each).

### Scale

The writer keeps drawn coordinates by default. `DXFWriter.Options(fullSize: true)` multiplies each
element by the scale of its own layer group, so a group at 1:80 is written 80 times larger and a
drawing whose groups differ in scale is not averaged. Lengths, radii, text height and the position
and scale factors of an insert all follow. The layer group is the one in `Element.attributes`; a
drawing with no layer groups, or a group with no usable scale, is written as drawn.

Block members are written as drawn, in the block's own coordinates, and the insert carries the
scale of its own layer group. A member in a layer group of a different scale does not use it.
No drawing that has a DXF export beside it contains a block, so this is not checked against a real
file.

With full size, a `DIMENSION` measures its stated value as it is. Without it, the measured length
times the layer group scale is the stated value.

`Report.appliedScales` gives the factor the writer multiplied the top-level elements of each layer
group by, keyed by group number, for every layer group that holds a top-level element: the group's
scale with full size when that scale is finite and positive, and 1 otherwise. A block member is
written as drawn and takes the factor of the insert that places it, whatever its own group, so a
group only block members use is not listed.

---

## Scope & notes

Covers **lines, arcs/circles/ellipses, points, text, block definitions + inserts, and dimensions**.
Block definitions are exposed on `Drawing.blocks` (keyed by number) and emitted as DXF `BLOCK`s, with
`.insert` entities becoming `INSERT`s; dimension records are decomposed into their drawn parts in
`Drawing.entities`, and the DXF writer writes them as `DIMENSION`s. The DXF writer applies the layer
group scale only when `Options.fullSize` is set.

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

Block expansion is checked on 271 more TECS drawings, the ones whose published DXF holds block
inserts. Each of the 271 JWW files holds a block definition for every insert in its DXF: 29,332
inserts, 22 of them nested. After the inserts of the DXF are placed, 1,323,803 lines, arcs, circles,
points and texts match the block-expanded JWW within 0.01 mm of full size. A second test writes each
drawing with `DXFWriter` at full size, with its blocks, and checks that placing the written inserts
gives the entities of the same drawing written with its blocks already expanded.

The site allows free use for individual hobby purposes and names no licence, so the files are not in
this repository. Put each `<name>.jww` beside its `<name>.dxf` in a folder, at any depth, and run:

```
SWIFTJWW_FIXTURES=/path/to/folder swift test
```

Without the variable the tests are skipped. All 271 block drawings take about two minutes.

The comparison applies the conventions of that DXF export. They were read from these files, not taken
from a specification:

| In the DXF | Convention |
|---|---|
| Coordinates | full size: (drawn value + half the sheet) times `$LTSCALE`, where the sheet is `$EXTMAX / $LTSCALE` |
| `$LTSCALE` | the scale of the write-target layer group, applied to every layer group |
| Layer name | `_<group>-<layer>_<name>`, with group and layer in hex |
| Elliptical arc | written as `LINE` segments, because the R12 format has no `ELLIPSE` |
| Ratio not exactly 1 | an arc or circle whose ratio differs from 1 by only `7.6e-10` is an elliptical arc too (`el15`) |
| Block | a `BLOCK` of the members at full size about the block origin, and an `INSERT` at (position + half the sheet) times `$LTSCALE` with the scale of the JWW insert |
| Line type 9 | the line is written on a layer called `ADD_LINE` |
| Layer name characters | some are written as underscores, one per byte (`ブレーキ` is `ブレ__キ`) |

What the comparison showed:

- **Text angle** is stored in degrees. The reader treated it as radians until this comparison
  exposed it.
- **Layer group scale** reads as the DXF's `$LTSCALE` for the write-target group in all 13 drawings,
  for example 1:80 for `2120`. Two drawings (`h15tdl1`, `h15tdl2`) also use a second layer group at
  1:10 and 1:5. The DXF export applies 1:50 to it, so converting those objects with their own group
  scale gives a different size from the DXF.
- **None of the 13 drawings holds a dimension record, a block or a solid.** Their dimensions are
  loose lines, points and text with the dimension attribute flags set. `recoveringDimensions()`
  rebuilt 214 of the 241 dimension values, each with its text at the same place in the DXF. The other
  27 are diameters such as `860φ` and values with decimals that no pair of arrow points explains;
  they are listed in `unmatchedValues`.
- **Block expansion agrees with the export in all 271 block drawings.** The coordinates, layers and
  counts of every expanded member match, with the two differences below. The inserts in these files
  are never rotated or mirrored and never scaled unevenly: 15,462 have scale 0.8 and 13,848 scale 1.
  Rotation, mirroring and uneven scale of block expansion are therefore validated on synthetic
  fixtures only. So are dimension records, since none of the 271 drawings holds one, and solids.
- **Elliptical arcs** are written as `LINE` segments in 194 of the 271 drawings: 2,943 arcs, 44,329
  segments. The 16 circles of `el15` that are written this way have a ratio of `1 - 7.6e-10`, so the
  export reads any ratio other than exactly 1 as an ellipse.
- **28 zero-length lines** in the DXF of two drawings (16 in `hk0805`, 12 in `hk9000`) have no object in the
  JWW. Each is at the end of a JWW line. They are counted as explained, but what writes them is not
  known.

---

## License & provenance

MIT. This is a **clean-room reimplementation** of the JWW byte layout, so no `jwwlib` source is
included. JWW and Jw_cad are the work of their respective authors; LibreCAD's `jwwlib` (GPL) and the
published `jwdatafmt` specification were used as format references.
