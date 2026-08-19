#!/usr/bin/env python3
"""Deprecated compatibility entry point.

The old two-texture Copernicus + silhouette pipeline caused coast misalignment.
Use generate_china_surface_texture.py, which builds one packed RGBA map source:
RGB=satellite and Alpha=co-registered numeric elevation.
"""

raise SystemExit(
    "Deprecated: run scripts/tools/generate_china_surface_texture.py instead. "
    "The runtime now uses one packed satellite/elevation texture via "
    "assets/terrain/map_source.json."
)
