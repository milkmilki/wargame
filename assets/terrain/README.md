# Terrain assets

Runtime textures:

- `china_natural_earth2_2048.png`: the single packed runtime map source. RGB is
  NASA Blue Marble satellite color; Alpha is co-registered numeric elevation
  from AWS Open Terrain Tiles (SRTM/GMTED/ETOPO1). Alpha 0 means water and
  Alpha 1..255 means positive land elevation. No administrative/playable mask
  is applied. The historical filename is retained for runtime compatibility.
- `default_china_city_mask.png`: optional default city-generation constraint,
  rasterized from Natural Earth map units to the exact map-source bbox. White
  permits city generation; black forbids it. It never affects rendering.

At runtime, Godot reads both visible color and geography from this one RGBA
texture, so cities, coastlines and the displayed satellite image cannot drift.
No procedural terrain plugin or network map service is required at runtime.

Regenerate:

```bash
python3 -m pip install -r scripts/tools/requirements-terrain.txt
python3 scripts/tools/generate_china_surface_texture.py
python3 scripts/tools/generate_default_city_mask.py
```

The source archives and intermediate metric DEM cache are ignored by Git.
Output metadata records source URL, geographic bounds and processing values.

## Licensing

Satellite surface imagery is NASA Blue Marble Next Generation:
<https://visibleearth.nasa.gov/collection/1484/blue-marble>.

Elevation tile source and packed-channel metadata are recorded in
`china_natural_earth2_2048.json`.
