---
type: repo
title: SwiftJWW
resource: https://github.com/SecondMouseAU/SwiftJWW
tags: [jww, jw_cad, dxf, 2d, import, swift]
description: Native-Swift reader for JWW (Jw_cad) 2D drawings plus a jww2dxf converter.
timestamp: 2026-06-25
---

# SwiftJWW

A native-Swift reader for **JWW** — the native drawing format of Jw_cad, the free 2D CAD program
widely used in Japan — plus a **`jww2dxf`** command-line converter. JWW is an MFC `CArchive`-serialized
binary file; SwiftJWW reads the geometry (lines, arcs/circles/ellipses, points, text) and converts it
to DXF. Pure Swift, no third-party dependencies; a clean-room port validated byte-for-byte against
LibreCAD's `jwwlib`.

## Role in the ecosystem

- **Cluster:** kernel
- **Depends on:** nothing (leaf — pure Swift)
- **Feeds products:** 2D-drawing import for the OCCTSwift CAD I/O stack (e.g. OCCTSwiftIO's JWW path)

## Components

See [`components/`](components/index.md) for the public surface.

## References

See [`references/`](references/index.md) for the JWW format spec and reference readers.

## Policies

- [Query `context` first for OCCT / OCCTSwift docs](policies/context-first.md)
