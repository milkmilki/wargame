"""Package numeric SRTM15+ relief and Natural Earth land/lakes for native Godot.

Development only: pip install numpy netCDF4 rasterio. No image artwork is used.
Inputs: GMT earth_relief_06m_p.grd and Natural Earth v5.1.2 GeoJSON files.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

import numpy as np
from netCDF4 import Dataset
from rasterio.features import rasterize, shapes
from rasterio.transform import from_bounds


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    source_grid = args.source / "earth_relief_06m_p.grd"
    with Dataset(source_grid) as dataset:
        z = dataset.variables["z"]
        elevation = np.asarray(z[:], dtype=np.float64)
        lon = np.asarray(dataset.variables["lon"][:])
        lat = np.asarray(dataset.variables["lat"][:])
        assert np.all(np.isfinite(elevation)) and lon[0] < lon[-1]
        if lat[0] < lat[-1]:
            elevation = elevation[::-1, :]
        height, width = elevation.shape
        title = dataset.title
    assert (width, height) == (3600, 1800)
    transform = from_bounds(-180, -90, 180, 90, width, height)
    land_path = args.source / "ne_50m_land.geojson"
    lakes_path = args.source / "ne_50m_lakes.geojson"
    land = json.loads(land_path.read_text(encoding="utf-8"))
    lakes = json.loads(lakes_path.read_text(encoding="utf-8"))
    # Ocean=1, land=0, lakes=2. Below-sea-level land stays land (e.g. Netherlands).
    water = rasterize([(f["geometry"], 0) for f in land["features"]],
                      out_shape=(height, width), transform=transform, fill=1, dtype="uint8")
    # Natural Earth land represents the Caspian as a hole and omits it from
    # ne_50m_lakes. Reclassify that geographic component explicitly. Other
    # closed raster components cannot be assumed to be lakes: a narrow strait
    # may disappear at 6 arcminutes (e.g. Bosporus / Black Sea).
    enclosed = []
    for geometry, value in shapes(water, mask=(water == 1), transform=transform):
        ring = geometry["coordinates"][0]
        xs, ys = zip(*ring)
        caspian = min(xs) > 44 and max(xs) < 56 and min(ys) > 35 and max(ys) < 48
        if value == 1 and caspian:
            enclosed.append((geometry, 2))
    if enclosed:
        rasterize(enclosed, out=water, transform=transform)
    rasterize([(f["geometry"], 2) for f in lakes["features"]],
              out=water, transform=transform)
    packed = np.rint(elevation * 2).astype("<i2")
    relief_path = args.output / "earth_relief_06m.i16.gz"
    water_path = args.output / "earth_water_06m.u8.gz"
    relief_path.write_bytes(gzip.compress(packed.tobytes(), mtime=0))
    water_path.write_bytes(gzip.compress(water.tobytes(), mtime=0))
    metadata = {
        "format": "atlas-earth-surface-v1", "width": width, "height": height,
        "projection": "EPSG:4326 equirectangular", "registration": "pixel-center",
        "bounds": [-180, -90, 180, 90], "row_order": "north-to-south",
        "elevation_scale_m": 0.5, "elevation_encoding": "signed-i16-little-endian-gzip",
        "relief_file": relief_path.name, "water_file": water_path.name,
        "relief_sha256": sha(relief_path), "water_sha256": sha(water_path),
        "relief_title": title,
        "water_classes": {"land": 0, "ocean": 1, "lake": 2},
        "water_processing": "Natural Earth land/lakes; Caspian land-hole component is a lake. Closed raster seas retain ocean class; subpixel straits are not assumed absent.",
        "sources": [
            {"url": "https://oceania.generic-mapping-tools.org/server/earth/earth_relief/earth_relief_06m_p.grd",
             "sha256": sha(source_grid), "reference": "Tozer et al. 2019, DOI 10.1029/2019EA000658",
             "description": "GMT SRTM15+ v2.7, 6 arcminutes; 31.5 km full-width Gaussian filter"},
            {"url": "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_50m_land.geojson",
             "sha256": sha(land_path), "license": "public domain"},
            {"url": "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_50m_lakes.geojson",
             "sha256": sha(lakes_path), "license": "public domain"}],
        "date": "2026-10-09", "runtime": "native Godot; no Python dependency"
    }
    (args.output / "earth_source.json").write_text(json.dumps(metadata, indent=2)+"\n", encoding="utf-8")
    print("EARTH_SOURCE", width, height, "elevation", float(elevation.min()), float(elevation.max()),
          "water", dict(zip(*np.unique(water, return_counts=True))), "bytes", relief_path.stat().st_size+water_path.stat().st_size)


if __name__ == "__main__":
    main()
