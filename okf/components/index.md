---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftJWW
tags: [index]
description: Public modules / API surfaces exposed by SwiftJWW.
timestamp: 2026-11-25
---

# Components

- **`SwiftJWW`** (library): parses a `.jww` file into typed 2D entities (lines, arcs, circles,
  ellipses, points, text, block inserts, dimensions) with their layer group, line type and colour,
  reads the layer groups with their scales, expands blocks, counts the solid fills it skips (at the
  top level and in each block definition), reads or recovers dimensions as one object, and converts
  the drawing to DXF. The DXF has a `HEADER` declaring `$ACADVER` `AC1009`, `$INSUNITS` 4
  (millimetres: real ones with full-size coordinates, paper ones at the drawn scale without) and
  `$HANDLING` 1 with a `$HANDSEED`, handles, layers named `<group>-<layer>` in hexadecimal with a
  `LAYER` table, dimension records as `DIMENSION` entities, and options to write full-size
  coordinates and to write recovered dimensions as `DIMENSION`s, with a report of them. The version
  names how the file is built, not its content: `ELLIPSE` and `$INSUNITS` are not R12. Six readers
  were run on such a file, none treats it differently because it says R12, and LibreOffice Draw does
  not draw `ELLIPSE` under any of the nine versions tried; AutoCAD was not run (`docs/index.md`, "Readers run on the DXF").
- **`JWW.RecoveredDimension`** (in `SwiftJWW`): a dimension rebuilt from loose pieces, with its
  `pieces` (each element it was built from and its role) as the stored source of truth.
  `elementIndices` is computed from `pieces`; it was a settable stored `var` in 1.5.0, so assigning
  it, or constructing a `RecoveredDimension` with it, is a source-breaking change.
- **`jww2dxf`** (executable): CLI wrapper that reads a JWW drawing and writes the DXF equivalent.
- **`DXFWriter.Report`** (in `SwiftJWW`): what the DXF text alone does not say: the handles of the
  recovered `DIMENSION`s with the indices of the elements each was built from and the role of each
  (value text, copy of it, arrow point, dimension line, extension line), the value texts
  nothing explained, and the factor applied to each layer group. `recoveredDimensionPieces` is the
  stored value and `recoveredDimensionElements` is computed from it; it was a settable stored `var`
  and an `init` parameter in 1.5.0, so assigning it, or passing it to `Report.init`, is a
  source-breaking change.
  `DXFWriter.layerName(group:layer:)` gives the layer name the writer uses.
