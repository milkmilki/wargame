#!/usr/bin/env python3
"""Rasterize the default China city-generation mask to the map-source bbox."""

from __future__ import annotations

import json
import urllib.request
from pathlib import Path

import rasterio
from PIL import Image
from rasterio.features import rasterize
from rasterio.transform import from_bounds

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_10m_admin_0_map_units.geojson"
)
CACHE = REPO_ROOT / "assets/terrain/source/natural_earth_admin"
OUTPUT = REPO_ROOT / "assets/terrain/default_china_city_mask.png"
METADATA = REPO_ROOT / "assets/terrain/default_china_city_mask.json"
MAP_SOURCE_METADATA = REPO_ROOT / "assets/terrain/china_natural_earth2_2048.json"
RESOLUTION = 2048


def ensure_source() -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    geojson = CACHE / "ne_10m_admin_0_map_units.geojson"
    if not geojson.exists():
        print(f"downloading {SOURCE_URL}", flush=True)
        urllib.request.urlretrieve(SOURCE_URL, geojson)
    return geojson


def main() -> None:
    metadata = json.loads(MAP_SOURCE_METADATA.read_text(encoding="utf-8"))
    bbox = metadata["bbox_wgs84"]
    west, south, east, north = (
        float(bbox["west"]), float(bbox["south"]),
        float(bbox["east"]), float(bbox["north"]),
    )
    geojson_path = ensure_source()
    shapes = []
    geojson = json.loads(geojson_path.read_text(encoding="utf-8"))
    selected = 0
    for feature in geojson["features"]:
        if feature.get("properties", {}).get("ADM0_A3") != "CHN":
            continue
        shapes.append((feature["geometry"], 255))
        selected += 1
    if not shapes:
        raise RuntimeError("Natural Earth map units contain no ADM0_A3=CHN geometry")
    transform = from_bounds(west, south, east, north, RESOLUTION, RESOLUTION)
    mask = rasterize(
        shapes, out_shape=(RESOLUTION, RESOLUTION), transform=transform,
        fill=0, dtype="uint8", all_touched=False,
    )
    Image.fromarray(mask, mode="L").save(OUTPUT, optimize=True)
    out_metadata = {
        "source": SOURCE_URL,
        "dataset": "Natural Earth 1:10m Admin 0 Map Units",
        "filter": "ADM0_A3 == CHN",
        "bbox_wgs84": [west, south, east, north],
        "resolution": [RESOLUTION, RESOLUTION],
        "selected_features": selected,
        "semantics": "white=city generation allowed, black=forbidden",
        "rendering_effect": "none",
    }
    METADATA.write_text(
        json.dumps(out_metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {OUTPUT.relative_to(REPO_ROOT)} from {selected} CHN features")


if __name__ == "__main__":
    main()
