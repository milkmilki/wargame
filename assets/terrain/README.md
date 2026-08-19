# Terrain assets

Runtime textures:

- `china_copernicus_glo90_2048.png`: authoritative grayscale elevation and
  playable-land alpha, generated from Copernicus DEM GLO-90.
- `china_natural_earth2_2048.png`: muted historical land-cover color generated
  from Natural Earth II 1:50m with shaded relief.
- `china_mask.png`: stable playable-land silhouette shared by both pipelines.

At runtime, Godot directly samples the Copernicus texture into a deterministic
`ArrayMesh` and layers the Natural Earth texture in the terrain shader. No
procedural terrain plugin or third-party map service is required.

Regenerate:

```bash
python3 -m pip install -r scripts/tools/requirements-terrain.txt
python3 scripts/tools/generate_china_copernicus_heightmap.py
python3 scripts/tools/generate_china_surface_texture.py
```

The source archives and intermediate metric DEM cache are ignored by Git.
Output metadata records source URL, geographic bounds and processing values.

## Licensing

Natural Earth raster and vector map data are public domain:
<https://www.naturalearthdata.com/about/terms-of-use/>.

Copernicus DEM source and processing metadata are recorded in
`china_copernicus_glo90_2048.json`.
