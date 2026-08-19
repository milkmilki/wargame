#!/usr/bin/env python3
"""Build the complete rectangular satellite texture from NASA Blue Marble.

The playable China alpha mask is intentionally not used here. It remains a
simulation-only city/province constraint; rendering always shows the complete
73E..135.5E / 18N..54N geographic rectangle, including source-image ocean.
"""

from __future__ import annotations

import argparse
import json
import math
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = REPO_ROOT / "assets/terrain/china_natural_earth2_2048.png"
DEFAULT_METADATA = REPO_ROOT / "assets/terrain/china_natural_earth2_2048.json"
DEFAULT_CACHE_DIR = REPO_ROOT / "assets/terrain/source/blue_marble"
SOURCE_URL = (
    "https://eoimages.gsfc.nasa.gov/images/imagerecords/74000/74167/"
    "world.200410.3x5400x2700.jpg"
)
SOURCE_NAME = "world.200410.3x5400x2700.jpg"
ELEVATION_URL = (
    "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/"
    "{zoom}/{x}/{y}.png"
)
ELEVATION_ZOOM = 7
ELEVATION_HIGH_CLIP_M = 6200.0
ELEVATION_LOW_CLIP_M = -8000.0
DEFAULT_BBOX = (73.0, 18.0, 135.5, 54.0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate the complete China rectangle from NASA Blue Marble."
    )
    parser.add_argument("--resolution", type=int, default=2048)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    parser.add_argument("--source-image", type=Path)
    parser.add_argument("--elevation-zoom", type=int, default=ELEVATION_ZOOM)
    parser.add_argument("--high-clip-m", type=float, default=ELEVATION_HIGH_CLIP_M)
    parser.add_argument("--low-clip-m", type=float, default=ELEVATION_LOW_CLIP_M)
    parser.add_argument(
        "--bbox", type=float, nargs=4,
        metavar=("WEST", "SOUTH", "EAST", "NORTH"),
        default=DEFAULT_BBOX,
    )
    return parser.parse_args()


def ensure_source(cache_dir: Path, source_image: Path | None) -> Path:
    if source_image is not None:
        if not source_image.exists():
            raise FileNotFoundError(source_image)
        return source_image
    cache_dir.mkdir(parents=True, exist_ok=True)
    path = cache_dir / SOURCE_NAME
    if not path.exists():
        print(f"downloading {SOURCE_URL}", flush=True)
        urllib.request.urlretrieve(SOURCE_URL, path)
    return path


def longitude_x(longitude: float, width: int) -> float:
    return (longitude + 180.0) / 360.0 * width


def latitude_y(latitude: float, height: int) -> float:
    return (90.0 - latitude) / 180.0 * height


def mercator_position(longitude: float, latitude: float, zoom: int) -> tuple[float, float]:
    scale = float((1 << zoom) * 256)
    x = (longitude + 180.0) / 360.0 * scale
    latitude = max(-85.05112878, min(85.05112878, latitude))
    radians = math.radians(latitude)
    y = (1.0 - math.asinh(math.tan(radians)) / math.pi) * 0.5 * scale
    return x, y


def elevation_tile(cache_dir: Path, zoom: int, x: int, y: int) -> Path:
    path = cache_dir / "terrarium" / str(zoom) / str(x) / f"{y}.png"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(
            ELEVATION_URL.format(zoom=zoom, x=x, y=y), path
        )
    return path


def build_elevation(
    cache_dir: Path,
    bbox: tuple[float, float, float, float],
    resolution: int,
    zoom: int,
) -> tuple[np.ndarray, list[str]]:
    west, south, east, north = bbox
    left, top = mercator_position(west, north, zoom)
    right, bottom = mercator_position(east, south, zoom)
    tile_x0 = int(math.floor(left / 256.0))
    tile_y0 = int(math.floor(top / 256.0))
    tile_x1 = int(math.floor((right - 1e-6) / 256.0))
    tile_y1 = int(math.floor((bottom - 1e-6) / 256.0))
    mosaic = np.zeros(
        ((tile_y1 - tile_y0 + 1) * 256, (tile_x1 - tile_x0 + 1) * 256, 3),
        dtype=np.uint8,
    )
    sources: list[str] = []
    total = (tile_x1 - tile_x0 + 1) * (tile_y1 - tile_y0 + 1)
    done = 0
    for tile_y in range(tile_y0, tile_y1 + 1):
        for tile_x in range(tile_x0, tile_x1 + 1):
            done += 1
            path = elevation_tile(cache_dir, zoom, tile_x, tile_y)
            if done == 1 or done == total or done % 25 == 0:
                print(f"elevation tile {done}/{total}", flush=True)
            tile = np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)
            y0 = (tile_y - tile_y0) * 256
            x0 = (tile_x - tile_x0) * 256
            mosaic[y0:y0 + 256, x0:x0 + 256] = tile
            sources.append(f"{zoom}/{tile_x}/{tile_y}")
    longitudes = np.linspace(west, east, resolution, endpoint=False)
    longitudes += (east - west) / float(resolution) * 0.5
    latitudes = np.linspace(north, south, resolution, endpoint=False)
    latitudes -= (north - south) / float(resolution) * 0.5
    world_scale = float((1 << zoom) * 256)
    sample_x = (longitudes + 180.0) / 360.0 * world_scale - tile_x0 * 256
    latitude_radians = np.radians(np.clip(latitudes, -85.05112878, 85.05112878))
    sample_y = (
        (1.0 - np.arcsinh(np.tan(latitude_radians)) / np.pi)
        * 0.5 * world_scale - tile_y0 * 256
    )
    xi = np.clip(np.rint(sample_x).astype(np.int32), 0, mosaic.shape[1] - 1)
    yi = np.clip(np.rint(sample_y).astype(np.int32), 0, mosaic.shape[0] - 1)
    sampled = mosaic[yi[:, None], xi[None, :]].astype(np.float32)
    elevation = sampled[:, :, 0] * 256.0 + sampled[:, :, 1]
    elevation += sampled[:, :, 2] / 256.0 - 32768.0
    return elevation, sources


def build_texture(args: argparse.Namespace) -> dict:
    if args.resolution <= 0:
        raise ValueError("--resolution must be positive")
    if args.high_clip_m <= 0.0:
        raise ValueError("--high-clip-m must be positive")
    if args.low_clip_m >= 0.0:
        raise ValueError("--low-clip-m must be negative")
    source_path = ensure_source(args.cache_dir, args.source_image)
    source = Image.open(source_path).convert("RGB")
    west, south, east, north = map(float, args.bbox)
    crop_box = (
        int(round(longitude_x(west, source.width))),
        int(round(latitude_y(north, source.height))),
        int(round(longitude_x(east, source.width))),
        int(round(latitude_y(south, source.height))),
    )
    if crop_box[2] <= crop_box[0] or crop_box[3] <= crop_box[1]:
        raise ValueError("invalid --bbox")
    crop = source.crop(crop_box).resize(
        (args.resolution, args.resolution), Image.Resampling.LANCZOS
    )
    # Keep the image recognizably satellite-based while muting it enough for
    # political overlays, counters and roads to remain legible.
    crop = ImageEnhance.Color(crop).enhance(0.86)
    crop = ImageEnhance.Contrast(crop).enhance(1.04)
    crop = ImageEnhance.Brightness(crop).enhance(0.92)
    elevation, elevation_tiles = build_elevation(
        args.cache_dir, (west, south, east, north),
        args.resolution, args.elevation_zoom
    )
    land = elevation > 0.0
    sea = ~land
    # Alpha is a signed numerical DEM, never a render mask. 0 m is the fixed
    # coastline split: 1..128 encodes -8000..0 m and 129..255 encodes
    # positive land up to high_clip_m. No pixel uses alpha 0.
    elevation_alpha = np.empty(elevation.shape, dtype=np.uint8)
    sea_normalized = np.clip(
        (elevation[sea] - args.low_clip_m) / -args.low_clip_m, 0.0, 1.0
    )
    elevation_alpha[sea] = (
        1 + np.rint(sea_normalized * 127.0).astype(np.uint8)
    )
    land_normalized = np.clip(
        elevation[land] / args.high_clip_m, 0.0, 1.0
    )
    elevation_alpha[land] = (
        129 + np.rint(land_normalized * 126.0).astype(np.uint8)
    )
    rgba = np.asarray(crop.convert("RGBA"), dtype=np.uint8).copy()
    rgba[:, :, 3] = elevation_alpha
    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, mode="RGBA").save(args.output, optimize=True)
    metadata = {
        "source": {
            "dataset": "NASA Blue Marble Next Generation",
            "date": "2004-10",
            "download_url": SOURCE_URL,
            "source_page": (
                "https://visibleearth.nasa.gov/collection/1484/"
                "blue-marble"
            ),
            "credit": "NASA Earth Observatory",
        },
        "elevation_source": {
            "dataset": "AWS Open Terrain Tiles (Terrarium)",
            "url_template": ELEVATION_URL,
            "zoom": args.elevation_zoom,
            "encoding": "elevation_m = R*256 + G + B/256 - 32768",
            "component_sources": "SRTM, GMTED and ETOPO1 as recorded per tile",
            "tiles": elevation_tiles,
        },
        "source_file": SOURCE_NAME,
        "source_raster_size": [source.width, source.height],
        "source_crop_px": list(crop_box),
        "bbox_wgs84": {
            "west": west, "south": south,
            "east": east, "north": north,
        },
        "output": str(args.output.relative_to(REPO_ROOT)),
        "output_size": [args.resolution, args.resolution],
        "processing": {
            "full_rectangle": True,
            "playable_mask_applied": False,
            "packed_texture": "RGB=satellite, A=elevation",
            "elevation_alpha": (
                "1..128=low_clip_m..0m sea, "
                "129..255=positive land..high_clip_m"
            ),
            "low_clip_m": args.low_clip_m,
            "high_clip_m": args.high_clip_m,
            "saturation": 0.86,
            "contrast": 1.04,
            "brightness": 0.92,
            "resampling": "Lanczos",
        },
        "elevation_stats_m": {
            "min": float(np.min(elevation)),
            "max": float(np.max(elevation)),
            "land_min": float(np.min(elevation[land])),
            "land_max": float(np.max(elevation[land])),
            "land_pixels": int(np.count_nonzero(land)),
            "water_pixels": int(np.count_nonzero(~land)),
        },
    }
    args.metadata.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return metadata


def main() -> None:
    metadata = build_texture(parse_args())
    print(
        "wrote {output} from {dataset}".format(
            output=metadata["output"],
            dataset=metadata["source"]["dataset"],
        )
    )


if __name__ == "__main__":
    main()
