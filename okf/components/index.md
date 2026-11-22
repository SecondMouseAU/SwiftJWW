---
type: component
title: Components index
resource: https://github.com/SecondMouseAU/SwiftJWW
tags: [index]
description: Public modules / API surfaces exposed by SwiftJWW.
timestamp: 2026-11-22
---

# Components

- **`SwiftJWW`** (library): parses a `.jww` file into typed 2D entities (lines, arcs, circles,
  ellipses, points, text, block inserts, dimensions) with their layer group, line type and colour,
  reads the layer groups with their scales, expands blocks, counts the solid fills it skips (at the
  top level and in each block definition), reads or recovers dimensions as one object, and converts
  the drawing to DXF. The DXF has handles, layers named `<group>-<layer>` in hexadecimal with a
  `LAYER` table, dimension records as `DIMENSION` entities, and options to write full-size
  coordinates and to write recovered dimensions as `DIMENSION`s, with a report of them.
- **`JWW.RecoveredDimension`** (in `SwiftJWW`): a dimension rebuilt from loose pieces, with its
  `pieces` (each element it was built from and its role) as the stored source of truth.
  `elementIndices` is computed from `pieces`; it was a settable stored `var` in 1.5.0, so assigning
  it, or constructing a `RecoveredDimension` with it, is a source-breaking change.
- **`jww2dxf`** (executable): CLI wrapper that reads a JWW drawing and writes the DXF equivalent.
- **`DXFWriter.Report`** (in `SwiftJWW`): what the DXF text alone does not say: the handles of the
  recovered `DIMENSION`s with the indices of the elements each was built from and the role of each
  (value text, copy of it, arrow point, dimension line, extension line), the value texts
  nothing explained, and the factor applied to each layer group.
  `DXFWriter.layerName(group:layer:)` gives the layer name the writer uses.
