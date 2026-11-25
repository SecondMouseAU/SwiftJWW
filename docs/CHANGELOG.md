# Changelog

Most recent first, one entry per tagged version. The date is the tag's date in the git history: the
tagging date for the annotated tags 1.0.0 to 1.2.2, the commit date for the lightweight tags after
them. Both are in the local time they were recorded in (UTC+10 or UTC+11); for 1.5.0 and 2.0.0 the UTC
date is the day before. Changes that can stop existing code compiling are called out.

## Unreleased

Documentation only, with no change to the API or to the DXF written: `docs/index.md` now says which
readers were run on the three things in the output that R12 does not have (`ELLIPSE`, `$INSUNITS` and
`\U+XXXX` text escapes) and what each did, including that LibreOffice Draw does not draw `ELLIPSE`
under any of the nine versions tried ([#46](https://github.com/SecondMouseAU/SwiftJWW/issues/46),
[#47](https://github.com/SecondMouseAU/SwiftJWW/issues/47)).

## 2.0.0 (2026-11-23)

**Major version: two source-breaking changes, a `HEADER` in every DXF, and a role for each piece of a
rebuilt dimension.** The reader, the source of `jww2dxf` and `Package.swift` are unchanged; every DXF
`jww2dxf` writes gains the `HEADER` below. A dependency declared `from: "1.0.0"` stays on the 1.x line
and does not pick this version up; move it to `from: "2.0.0"`.

**Breaking: `JWW.RecoveredDimension.elementIndices` is now get-only** ([#35](https://github.com/SecondMouseAU/SwiftJWW/issues/35), PR [#37](https://github.com/SecondMouseAU/SwiftJWW/pull/37)).
In 1.5.0 it was a stored `public var`. It is now computed from the new stored `pieces`
(`pieces.map(\.index)`), with the same values in the same ascending order, so the two cannot differ.

- Reading `elementIndices` compiles and behaves as before.
- Assigning to `elementIndices` no longer compiles.
- Constructing a `RecoveredDimension` with `elementIndices:` no longer compiles. That memberwise
  initializer was internal, so only code in the package or under `@testable import` could call it; the
  initializer is now the internal `init(dimension:pieces:)`.
- Migration: stop assigning (work on a copy, `var indices = dimension.elementIndices`), and where you
  built one under `@testable import`, pass `pieces: [.init(index: 3, role: .valueText), ...]`, each
  element with its role, in place of `elementIndices: [3, ...]`.

**Breaking: `DXFWriter.Report.init` no longer takes `recoveredDimensionElements:`** ([#39](https://github.com/SecondMouseAU/SwiftJWW/issues/39), PR [#40](https://github.com/SecondMouseAU/SwiftJWW/pull/40)).
In 1.5.0 `recoveredDimensionElements` was a stored `public var` and an `init` parameter. The stored
value is now `recoveredDimensionPieces`, and `recoveredDimensionElements` is get-only, computed from it
(each list's `map(\.index)`, under the same handles, in the same order). The initializer is now
`init(recoveredDimensions:unexplainedValues:recoveredDimensionPieces:appliedScales:)`.

- Reading `recoveredDimensionElements` or `recoveredDimensionPieces` compiles and behaves as before.
  So does every `Report.init` call that leaves `recoveredDimensionElements:` out, `DXFWriter.Report()`
  included.
- Passing `recoveredDimensionElements:` to `Report.init` no longer compiles.
- Assigning to `recoveredDimensionElements` (for example `report.recoveredDimensionElements[h] = ...`)
  no longer compiles.
- Migration: pass `recoveredDimensionPieces: [handle: [.init(index: 3, role: .valueText), ...]]` in place
  of `recoveredDimensionElements: [handle: [3, ...]]`, and assign to `recoveredDimensionPieces[handle]`
  rather than to `recoveredDimensionElements`.
- `recoveredDimensionElements` is rebuilt on each access, so a loop over many handles should read it
  once into a local, or use `recoveredDimensionPieces`.
- `Report` is still `Equatable`. Its equality now compares `recoveredDimensionPieces`, so the roles
  count as well as the indices.

**Every DXF now opens with a `HEADER` section** ([#34](https://github.com/SecondMouseAU/SwiftJWW/issues/34), PR [#36](https://github.com/SecondMouseAU/SwiftJWW/pull/36); [#38](https://github.com/SecondMouseAU/SwiftJWW/issues/38), PR [#41](https://github.com/SecondMouseAU/SwiftJWW/pull/41)).
Before this `DXFWriter` wrote none, so a reader had no version and no length unit to go on. It declares:

- `$ACADVER` `AC1009` (R12), the version Jw_cad's own DXF export declares.
- `$INSUNITS` `4` (millimetres), with or without `Options.fullSize`. With it the coordinates are real
  millimetres (a layer group with no usable scale stays as drawn). Without it they are millimetres of
  paper at the drawn scale, and a length times the scale of its layer group is the real one.
- `$HANDLING` `1`, the R12 variable that makes the group 5 handles valid.
- `$HANDSEED`, the next handle no record has, in hexadecimal. It comes from the writer's own handle
  counter, so it is above every handle in the file, the tables' and the blocks' included.

`AC1009` says how the file is built (R12 has no subclass markers, and neither does the writer), not
what it holds. The writer still emits `ELLIPSE` (R13 and later), `$INSUNITS` (R2000 and later) and
`\U+XXXX` text escapes, and a reader that holds the file to R12 strictly may skip or reject them.
SwiftDXF and ezdxf 1.4.5 read the same entities as before and report the version and unit, and with the
seed ezdxf no longer warns of non-unique entity handles on drawings with blocks. The `TABLE` header
records carry no handle, as before. AutoCAD was not run.

**Each piece of a rebuilt dimension now has a role** ([#35](https://github.com/SecondMouseAU/SwiftJWW/issues/35), PR [#37](https://github.com/SecondMouseAU/SwiftJWW/pull/37)).
A consumer no longer needs its own copy of the recovery's parallel test (a sine under 0.001) to tell a
dimension line from an extension line ([OCCTSwiftIO#82](https://github.com/SecondMouseAU/OCCTSwiftIO/pull/82)).

- `JWW.RecoveredDimension.pieces: [Piece]`: what each element the dimension was built from is to it, in
  ascending order of index. A `Piece` is an `index` into `Drawing.elements` and a `Role`.
- `JWW.RecoveredDimension.Role`: `valueText`, `valueTextCopy`, `arrowPoint`, `dimensionLine`,
  `extensionLine`. It is `Sendable`, `Hashable` and `CaseIterable` with `String` raw values. Adding a role
  later would break an exhaustive `switch` over it. `Piece` is `Sendable` and `Hashable`.
- `DXFWriter.Report.recoveredDimensionPieces: [String: [JWW.RecoveredDimension.Piece]]`, keyed by the
  handle of the `DIMENSION` like `recoveredDimensionElements`. A piece that two chained dimensions
  share has its role in each, and the role can differ between them.
- A line parallel to the one through the arrow points (its sine to it under 0.001) is a dimension line
  only if both its ends are within 0.001 of that line and it shares more than 0.001 of length with the
  span between the arrow points. Otherwise it is not a piece, and neither is any line of length 0.001 or
  less. The recovery never put such a line in `elementIndices` either. (0.001 is in drawn coordinates.)
- On the `2120` drawing the report's roles equal what `recoveringDimensions()` finds: 29 value texts,
  1 copy, 58 arrow points, 30 dimension lines and 56 extension lines (a piece two dimensions share
  counts once for each). That test runs when `SWIFTJWW_FIXTURES` points at the real drawings.

## 1.5.0 (2026-11-19)

**Rebuilt dimensions name their pieces, solid fills inside blocks are counted, three fixes, and block
expansion is checked against the DXF exports of 271 real drawings with blocks.**
Additive API, apart from one change to the writer's report noted below.

**Added**

- `DXFWriter.Report.recoveredDimensionElements`: for each rebuilt dimension's handle, the indices into
  `Drawing.elements` of the pieces it was built from, the same lists `recoveringDimensions()` gives
  ([#22](https://github.com/SecondMouseAU/SwiftJWW/issues/22)).
- `DXFWriter.Report.appliedScales`: the factor the writer multiplied each layer group's top-level
  elements by, keyed by group ([#22](https://github.com/SecondMouseAU/SwiftJWW/issues/22)).
- `DXFWriter.layerName(group:layer:)` is public: the `<group>-<layer>` hexadecimal name the writer gives
  a layer, such as `0-E` ([#22](https://github.com/SecondMouseAU/SwiftJWW/issues/22)).
- Solid fills inside blocks are counted: `BlockDef.solidCount`, `BlockExpansion.solidCount` (what the
  expanded drawing holds, nested blocks included) and `Drawing.skippedSolidCount` (what the file
  stores, each block definition once), which `jww2dxf` prints among the skipped solids
  ([#24](https://github.com/SecondMouseAU/SwiftJWW/issues/24)).
- Block expansion is checked against the publisher's DXF export of 271 TECS drawings with blocks:
  1,323,803 entities agree within 0.01 mm at full size. The comparison now places a DXF's inserts
  itself, so it can read a DXF that holds blocks ([#29](https://github.com/SecondMouseAU/SwiftJWW/issues/29)).

**Fixed**

- An elliptical arc with a negative sweep was written as the rest of its ellipse. It is now written
  from its counter-clockwise start, as circular arcs already were ([#23](https://github.com/SecondMouseAU/SwiftJWW/issues/23)).
- An ellipse whose minor-to-major ratio is above 1 is written with its axes swapped, the reciprocal
  ratio and its parameters turned back a quarter turn, since DXF allows a ratio of at most 1. The
  written ellipse is the same curve with the same ends ([#27](https://github.com/SecondMouseAU/SwiftJWW/issues/27)).
- A dimension value text that no dimension explains and that is stored twice at the same place: its
  copy is now listed with it among the unexplained values, so every value text is in exactly one list
  ([#28](https://github.com/SecondMouseAU/SwiftJWW/issues/28)).

**Changed**

- `DXFWriter.Report.appliedScales` is filled on every write, so a report no longer equals
  `DXFWriter.Report()` when `recoversDimensions` is off: it holds each group's factor, 1 without
  `fullSize` ([#22](https://github.com/SecondMouseAU/SwiftJWW/issues/22)).
- `Drawing.counts` still counts top-level objects only, and its documentation now says so
  ([#24](https://github.com/SecondMouseAU/SwiftJWW/issues/24)).

## 1.4.0 (2026-11-17)

**DXF dimensions and layer groups.** Additive API; the DXF text changes for every write.

**Added**

- A dimension record with its measured points is written as one rotated linear `DIMENSION`, with the
  dimension line, text, witness lines and arrow points in the anonymous `*D<n>` block it names
  ([#18](https://github.com/SecondMouseAU/SwiftJWW/issues/18)).
- `DXFWriter.Options(fullSize:)`: multiplies each element by the scale of its own layer group, so a
  drawing whose groups differ in scale is not averaged. A block insert scales its position and scale
  factors, and its members follow the insert ([#18](https://github.com/SecondMouseAU/SwiftJWW/issues/18)).
- `DXFWriter.Options(recoversDimensions:)`: writes the dimensions `Drawing.recoveringDimensions()`
  rebuilds as `DIMENSION`s, and keeps the loose pieces they were built from in the block instead of the
  entities ([#19](https://github.com/SecondMouseAU/SwiftJWW/issues/19)).
- `DXFWriter.output(_:options:)` returns the text with a `Report` of the handles of the recovered
  dimensions and the indices of the value texts no dimension explains. `DXFWriter.write(_:to:options:)`
  now returns that report, and ignoring it still compiles ([#19](https://github.com/SecondMouseAU/SwiftJWW/issues/19)).
- `jww2dxf --full-size` and `--recover-dimensions`. The summary line adds the number of dimensions
  recovered and values unexplained ([#19](https://github.com/SecondMouseAU/SwiftJWW/issues/19)).

**Changed**

- Every DXF now has layers named `<group>-<layer>` in hexadecimal, as Jw_cad names them in its own
  export: layer 14 of group 0 is `0-E`. Before, the layer was its bare number and the layer group was
  dropped. A consumer that matches on the old names needs to move ([#19](https://github.com/SecondMouseAU/SwiftJWW/issues/19)).
- Every entity has a handle (group 5), and the file has a `TABLES` section with the `LTYPE` and `LAYER`
  tables. A layer with a JWW name carries it as its description, in the extended data AutoCAD keeps
  layer descriptions in ([#19](https://github.com/SecondMouseAU/SwiftJWW/issues/19)).
- The writer now walks `Drawing.elements`, so each entity keeps its layer group ([#18](https://github.com/SecondMouseAU/SwiftJWW/issues/18)).

**Checked**

- The three drawings with a JWW file were written with both options and read back with SwiftDXF 0.4.0.
  `2120` gives 29 `DIMENSION`s on `0-E` with no value left unexplained and nothing loose on that layer.
  `eitakyouta_3` gives 13 with 1 unexplained, and `dd12` 14 with 2. Every measurement is within one unit
  of its label's last decimal place. That check is not part of the test suite, which has no SwiftDXF
  dependency.
- The layer descriptions are not checked in AutoCAD.
- No real file holds a dimension record or a block, so those paths are covered by synthetic tests. The
  new real-file tests run when `SWIFTJWW_FIXTURES` points at a folder with the `.jww` files and are
  skipped otherwise.

## 1.3.1 (2026-11-12)

**Fixes from the review of 1.3.0.** No API change ([#17](https://github.com/SecondMouseAU/SwiftJWW/pull/17)).

**Fixed**

- Text in a mirrored block was turned by half a turn when the block had a negative X scale. A mirror
  now never leaves text upside down: the turn it takes stays within a quarter turn of upright.

**Tests**

- The real-file comparison now checks dimensions inside blocks, since it recovers them from the
  block-expanded drawing.
- The DXF reader used by the comparison throws on a line that is not a group code, instead of skipping
  it and leaving the parsed drawing short.

## 1.3.0 (2026-11-12)

**Layer groups with scale, per-object attributes, dimensions, and block expansion.** Additive API, one
behavior fix.

**Added**

- `Drawing.layerGroups` and `Drawing.scale(ofLayerGroup:)`: the 16 layer groups with scale
  denominator, state, protection and CP932 names ([#13](https://github.com/SecondMouseAU/SwiftJWW/issues/13)).
- `Drawing.elements`: every object with its `Attributes` (layer group, layer, line type, colour, pen
  width, curve attribute, flags) ([#13](https://github.com/SecondMouseAU/SwiftJWW/issues/13)).
- `Dimension` for dimension records, and `Drawing.recoveringDimensions()` to rebuild dimensions from the
  loose text, arrow and line pieces that files without dimension records carry
  ([#13](https://github.com/SecondMouseAU/SwiftJWW/issues/13)).
- `Drawing.expandingBlocks()`: resolves block inserts to positioned elements with their reference
  chain, handles nesting, mirrors and non-uniform scale, and reports unresolved inserts and cycles
  ([#14](https://github.com/SecondMouseAU/SwiftJWW/issues/14)).
- A real-file comparison suite that checks the reader against 13 TECS JWW and DXF pairs (58,607
  entities). It runs when `SWIFTJWW_FIXTURES` points at a folder of pairs and is skipped otherwise
  ([#14](https://github.com/SecondMouseAU/SwiftJWW/issues/14)).

**Fixed**

- Text angle is stored in degrees in JWW files; it is now read as radians, so rotated text no longer
  comes out wrong in `Entity.text` and in the DXF output.

None of the 13 TECS drawings holds a dimension record or a block, so those two paths are covered by
synthetic tests. Existing `Drawing.entities` and `BlockDef.entities` are unchanged.

Also in this tag, with no effect on the library's API: CI builds and tests on pushes and pull
requests that touch sources, tests or the manifest ([#11](https://github.com/SecondMouseAU/SwiftJWW/pull/11)),
on `macos-latest` ([#12](https://github.com/SecondMouseAU/SwiftJWW/pull/12)); the ecosystem code-style rollout is
applied ([#9](https://github.com/SecondMouseAU/SwiftJWW/issues/9)); and further OKF policies (writing
style, search before building, code structure, issue tracking) and the pull request template are added.

## 1.2.2 (2026-07-20)

**Catch-up release for repository changes since 1.2.1.** SPI hygiene (`.spi.yml`,
[#4](https://github.com/SecondMouseAU/SwiftJWW/issues/4)) and OKF onboarding (policies and the
ecosystem catalog). No API change. Tagged 2026-07-20; its last commit is dated 2026-07-17.

## 1.2.1 (2026-06-22)

**Fixes circular-arc angles in the DXF.** The JWW tilt axis is now applied, and start and end are
normalized and ordered counter-clockwise, so tilted arcs are no longer rotated and negative-sweep arcs
are not truncated. Validated against a reference Jw_cad DXF export: 419 of 420 unique arcs match
exactly.

## 1.2.0 (2026-06-22)

**Text is decoded to Unicode at read time, and the DXF writer emits non-ASCII as `\U+XXXX` escapes**, so
Japanese text renders in AutoCAD and LibreCAD whatever the code page.

- `Entity.text` carries `string: String` where 1.1.0 carried `raw: [UInt8]` (the CP932 bytes). Code that
  matched or built the `raw:` payload does not compile against 1.2.0.
- New public `JWW.decodeCP932(_:)`, the decoder the reader uses for CP932 (Shift-JIS) bytes.

## 1.1.0 (2026-06-22)

**Adds block definitions and inserts, and dimensions.**

- Block definitions are exposed on `Drawing.blocks` and written as DXF `BLOCK`s, and inserts are written
  as `INSERT`s.
- A dimension is decomposed into its drawn parts.
- `Entity` gains the cases `.insert` and `.dimension`, so a `switch` over `Entity` with no `default`
  needs the two new cases.
- The reader parses the MFC block-definition list with the correct per-definition member counts.
- The core line, arc, point and text path is unchanged and still byte-exact against the reference
  reader on real drawings. Block and dimension support is validated on synthetic fixtures.

## 1.0.0 (2026-06-22)

**First release.** A native-Swift, dependency-free reader for the JWW (Jw_cad) binary format, and a
`jww2dxf` converter. Core entities: line, arc/circle/ellipse, point and text. A clean-room port of the
documented byte layout, validated byte-for-byte against the reference reader on real v7.00 drawings
(identical entity counts and bounding boxes).
