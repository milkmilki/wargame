#!/usr/bin/env python3
"""Build the offline China terrain-color texture from Natural Earth II.

Natural Earth raster and vector data are public domain:
https://www.naturalearthdata.com/about/terms-of-use/
"""

from __future__ import annotations

import argparse
import json
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageEnhance
from rasterio.enums import Resampling
from rasterio.windows import from_bounds
from scipy.ndimage import distance_transform_edt


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MASK = REPO_ROOT / "assets/terrain/china_mask.png"
DEFAULT_OUTPUT = REPO_ROOT / "assets/terrain/china_natural_earth2_2048.png"
DEFAULT_METADATA = REPO_ROOT / "assets/terrain/china_natural_earth2_2048.json"
DEFAULT_CACHE_DIR = REPO_ROOT / "assets/terrain/source/natural_earth"
SOURCE_URL = (
    "https://naciscdn.org/naturalearth/50m/raster/NE2_50M_SR.zip"
)
SOURCE_NAME = "NE2_50M_SR"
DEFAULT_BBOX = (73.0, 18.0, 135.5, 54.0)  # west, south, east, north


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a masked 2048 China texture from Natural Earth II."
    )
    parser.add_argument("--resolution", type=int, default=2048)
    parser.add_argument("--mask", type=Path, default=DEFAULT_MASK)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    parser.add_argument("--source-tif", type=Path)
    parser.add_argument(
        "--bbox",
        type=float,
        nargs=4,
        metavar=("WEST", "SOUTH", "EAST", "NORTH"),
        default=DEFAULT_BBOX,
    )
    return parser.parse_args()


def ensure_source(cache_dir: Path, source_tif: Path | None) -> Path:
    if source_tif is not None:
        if not source_tif.exists():
            raise FileNotFoundError(source_tif)
        return source_tif
    tif_path = cache_dir / SOURCE_NAME / f"{SOURCE_NAME}.tif"
    if tif_path.exists():
        return tif_path
    cache_dir.mkdir(parents=True, exist_ok=True)
    zip_path = cache_dir / f"{SOURCE_NAME}.zip"
    if not zip_path.exists():
        print(f"downloading {SOURCE_URL}", flush=True)
        urllib.request.urlretrieve(SOURCE_URL, zip_path)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(cache_dir)
    if not tif_path.exists():
        matches = list(cache_dir.rglob(f"{SOURCE_NAME}.tif"))
        if not matches:
            raise RuntimeError(f"{SOURCE_NAME}.tif missing after extraction")
        tif_path = matches[0]
    return tif_path


def threshold_bbox(alpha: np.ndarray, threshold: int = 51) -> tuple[int, int, int, int]:
    ys, xs = np.where(alpha > threshold)
    if xs.size == 0:
        raise RuntimeError("mask has no playable pixels")
    return (
        int(xs.min()),
        int(ys.min()),
        int(xs.max()) + 1,
        int(ys.max()) + 1,
    )


def build_texture(args: argparse.Namespace) -> dict:
    if args.resolution <= 0:
        raise ValueError("--resolution must be positive")
    source_tif = ensure_source(args.cache_dir, args.source_tif)
    mask = Image.open(args.mask).convert("RGBA").resize(
        (args.resolution, args.resolution),
        Image.Resampling.LANCZOS,
    )
    alpha = np.asarray(mask.getchannel("A"), dtype=np.uint8)
    alpha_bbox = threshold_bbox(alpha)
    target_width = alpha_bbox[2] - alpha_bbox[0]
    target_height = alpha_bbox[3] - alpha_bbox[1]
    west, south, east, north = map(float, args.bbox)

    with rasterio.open(source_tif) as source:
        window = from_bounds(west, south, east, north, source.transform)
        rgb = source.read(
            [1, 2, 3],
            window=window,
            out_shape=(3, target_height, target_width),
            resampling=Resampling.lanczos,
        )
        source_crs = str(source.crs)
        source_size = [source.width, source.height]
    source_rgb = np.moveaxis(rgb, 0, 2)
    flat_water = (
        (source_rgb.max(axis=2) - source_rgb.min(axis=2) <= 1)
        & (source_rgb.mean(axis=2) >= 245.0)
    )
    nearest_land = distance_transform_edt(
        flat_water,
        return_distances=False,
        return_indices=True,
    )
    source_rgb[flat_water] = source_rgb[
        nearest_land[0][flat_water],
        nearest_land[1][flat_water],
    ]
    crop = Image.fromarray(source_rgb)
    # EU4-style thematic maps need muted land cover beneath political colors.
    crop = ImageEnhance.Color(crop).enhance(0.72)
    crop = ImageEnhance.Contrast(crop).enhance(1.08)
    crop = ImageEnhance.Brightness(crop).enhance(0.94)

    canvas = Image.new("RGBA", (args.resolution, args.resolution), (0, 0, 0, 0))
    canvas.paste(crop.convert("RGBA"), alpha_bbox[:2])
    rgba = np.asarray(canvas, dtype=np.uint8).copy()
    rgba[:, :, 3] = alpha
    output = Image.fromarray(rgba)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output, optimize=True)

    metadata = {
        "source": {
            "dataset": "Natural Earth II with Shaded Relief",
            "scale": "1:50m",
            "version": "3.2.0",
            "download_url": SOURCE_URL,
            "terms_url": (
                "https://www.naturalearthdata.com/about/terms-of-use/"
            ),
            "license": "Public domain",
        },
        "source_file": f"{SOURCE_NAME}.tif",
        "source_crs": source_crs,
        "source_raster_size": source_size,
        "bbox_wgs84": {
            "west": west,
            "south": south,
            "east": east,
            "north": north,
        },
        "output": str(args.output.relative_to(REPO_ROOT)),
        "output_size": [args.resolution, args.resolution],
        "alpha_bbox_px": list(alpha_bbox),
        "processing": {
            "saturation": 0.72,
            "contrast": 1.08,
            "brightness": 0.94,
            "resampling": "Lanczos",
            "flat_water_pixels_filled": int(flat_water.sum()),
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
