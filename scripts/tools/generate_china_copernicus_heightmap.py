#!/usr/bin/env python3
"""Generate the authoritative China heightmap from Copernicus DEM COG tiles.

The game expects a grayscale image with alpha:
- alpha marks playable land, taken from assets/terrain/china_mask.png;
- white means low altitude and dark means high altitude, matching
  TerrainMapGenerator.altitude_from_luminance().
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Iterable

import numpy as np
import rasterio
from PIL import Image
from rasterio.enums import Resampling
from rasterio.windows import from_bounds


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MASK = REPO_ROOT / "assets/terrain/china_mask.png"
DEFAULT_OUTPUT = REPO_ROOT / "assets/terrain/china_copernicus_glo90_2048.png"
DEFAULT_METERS = REPO_ROOT / "assets/terrain/china_copernicus_glo90_2048_dem_meters.npz"
DEFAULT_METADATA = REPO_ROOT / "assets/terrain/china_copernicus_glo90_2048.json"
DEFAULT_TILE_LIST = REPO_ROOT / "assets/terrain/source/copernicus_glo90_tileList.txt"

COPERNICUS_GLO90_BASE_URL = "https://copernicus-dem-90m.s3.amazonaws.com"
COPERNICUS_GLO90_TILE_LIST_URL = f"{COPERNICUS_GLO90_BASE_URL}/tileList.txt"
COPERNICUS_GLO90_PREFIX = "Copernicus_DSM_COG_30"

# Mainland China plus Hainan/Taiwan and border highlands. The silhouette alpha
# remains the real playable mask; this bbox only gives the DEM sampling frame.
DEFAULT_BBOX = (73.0, 18.0, 135.5, 54.0)  # west, south, east, north


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a 2048 China heightmap from Copernicus GLO-90 DEM."
    )
    parser.add_argument("--resolution", type=int, default=2048)
    parser.add_argument("--mask", type=Path, default=DEFAULT_MASK)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--meters-output", type=Path, default=DEFAULT_METERS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--tile-list", type=Path, default=DEFAULT_TILE_LIST)
    parser.add_argument(
        "--bbox",
        type=float,
        nargs=4,
        metavar=("WEST", "SOUTH", "EAST", "NORTH"),
        default=DEFAULT_BBOX,
    )
    parser.add_argument("--sea-level-m", type=float, default=0.0)
    parser.add_argument("--high-clip-m", type=float, default=6200.0)
    parser.add_argument("--alpha-threshold", type=int, default=51)
    parser.add_argument(
        "--reuse-meters",
        action="store_true",
        help="Regenerate PNG/metadata from --meters-output without remote COG reads.",
    )
    return parser.parse_args()


def ensure_tile_list(path: Path) -> list[str]:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        import requests

        response = requests.get(COPERNICUS_GLO90_TILE_LIST_URL, timeout=60)
        response.raise_for_status()
        path.write_text(response.text, encoding="utf-8")
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def tile_name(lat: int, lon: int) -> str:
    ns = "N" if lat >= 0 else "S"
    ew = "E" if lon >= 0 else "W"
    return f"{COPERNICUS_GLO90_PREFIX}_{ns}{abs(lat):02d}_00_{ew}{abs(lon):03d}_00_DEM"


def tile_url(name: str) -> str:
    return f"{COPERNICUS_GLO90_BASE_URL}/{name}/{name}.tif"


def make_alpha_canvas(mask_path: Path, resolution: int) -> Image.Image:
    source = Image.open(mask_path).convert("RGBA")
    fit_w = resolution
    fit_h = max(1, round(float(source.height) * float(resolution) / float(source.width)))
    resized = source.getchannel("A").resize((fit_w, fit_h), Image.Resampling.LANCZOS)
    canvas = Image.new("L", (resolution, resolution), 0)
    canvas.paste(resized, (0, (resolution - fit_h) // 2))
    return canvas


def alpha_threshold_bbox(
    alpha_array: np.ndarray,
    alpha_threshold: int,
) -> tuple[int, int, int, int] | None:
    ys, xs = np.where(alpha_array > alpha_threshold)
    if xs.size == 0 or ys.size == 0:
        return None
    return (
        int(np.min(xs)),
        int(np.min(ys)),
        int(np.max(xs)) + 1,
        int(np.max(ys)) + 1,
    )


def iter_candidate_tiles(
    bbox: tuple[float, float, float, float],
    alpha_bbox: tuple[int, int, int, int],
    alpha_array: np.ndarray,
    alpha_threshold: int,
    available: set[str],
) -> Iterable[tuple[int, int, str, tuple[int, int, int, int]]]:
    west, south, east, north = bbox
    left_px, top_px, right_px, bottom_px = alpha_bbox
    width = max(1, right_px - left_px)
    height = max(1, bottom_px - top_px)

    for lat in range(math.floor(south), math.ceil(north)):
        tile_top = min(float(lat + 1), north)
        tile_bottom = max(float(lat), south)
        y0 = top_px + math.floor((north - tile_top) / (north - south) * height)
        y1 = top_px + math.ceil((north - tile_bottom) / (north - south) * height)
        y0 = max(top_px, min(bottom_px, y0))
        y1 = max(top_px, min(bottom_px, y1))
        if y1 <= y0:
            continue
        for lon in range(math.floor(west), math.ceil(east)):
            name = tile_name(lat, lon)
            if name not in available:
                continue
            tile_left = max(float(lon), west)
            tile_right = min(float(lon + 1), east)
            x0 = left_px + math.floor((tile_left - west) / (east - west) * width)
            x1 = left_px + math.ceil((tile_right - west) / (east - west) * width)
            x0 = max(left_px, min(right_px, x0))
            x1 = max(left_px, min(right_px, x1))
            if x1 <= x0:
                continue
            if np.max(alpha_array[y0:y1, x0:x1]) <= alpha_threshold:
                continue
            yield lat, lon, name, (x0, y0, x1, y1)


def pixel_window_to_bounds(
    pixel_window: tuple[int, int, int, int],
    alpha_bbox: tuple[int, int, int, int],
    bbox: tuple[float, float, float, float],
) -> tuple[float, float, float, float]:
    x0, y0, x1, y1 = pixel_window
    left_px, top_px, right_px, bottom_px = alpha_bbox
    west, south, east, north = bbox
    width = max(1, right_px - left_px)
    height = max(1, bottom_px - top_px)
    left = west + (float(x0 - left_px) / float(width)) * (east - west)
    right = west + (float(x1 - left_px) / float(width)) * (east - west)
    top = north - (float(y0 - top_px) / float(height)) * (north - south)
    bottom = north - (float(y1 - top_px) / float(height)) * (north - south)
    return left, bottom, right, top


def read_tile_into_canvas(
    name: str,
    pixel_window: tuple[int, int, int, int],
    alpha_bbox: tuple[int, int, int, int],
    bbox: tuple[float, float, float, float],
    elevation: np.ndarray,
    coverage: np.ndarray,
) -> bool:
    x0, y0, x1, y1 = pixel_window
    left, bottom, right, top = pixel_window_to_bounds(pixel_window, alpha_bbox, bbox)
    url = tile_url(name)
    with rasterio.open(url) as src:
        window = from_bounds(left, bottom, right, top, src.transform)
        data = src.read(
            1,
            window=window,
            out_shape=(y1 - y0, x1 - x0),
            boundless=True,
            fill_value=np.nan,
            masked=True,
            resampling=Resampling.bilinear,
        )
    values = np.asarray(data.filled(np.nan), dtype=np.float32)
    valid = np.isfinite(values)
    if not np.any(valid):
        return False
    target = elevation[y0:y1, x0:x1]
    target[valid] = values[valid]
    coverage[y0:y1, x0:x1] |= valid
    return True


def fill_missing_land_elevation(
    elevation: np.ndarray,
    coverage: np.ndarray,
    land: np.ndarray,
    sea_level_m: float,
) -> tuple[np.ndarray, np.ndarray, int]:
    filled = elevation.copy()
    known = coverage.copy()
    missing = land & ~known
    initial_missing = int(np.count_nonzero(missing))
    if initial_missing == 0:
        return filled, known, 0

    for _step in range(max(elevation.shape)):
        sums = np.zeros_like(filled, dtype=np.float32)
        counts = np.zeros(filled.shape, dtype=np.uint8)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                src_y0 = max(0, -dy)
                src_y1 = filled.shape[0] - max(0, dy)
                src_x0 = max(0, -dx)
                src_x1 = filled.shape[1] - max(0, dx)
                dst_y0 = max(0, dy)
                dst_y1 = filled.shape[0] - max(0, -dy)
                dst_x0 = max(0, dx)
                dst_x1 = filled.shape[1] - max(0, -dx)
                source_known = known[src_y0:src_y1, src_x0:src_x1]
                sums[dst_y0:dst_y1, dst_x0:dst_x1] += np.where(
                    source_known,
                    filled[src_y0:src_y1, src_x0:src_x1],
                    0.0,
                )
                counts[dst_y0:dst_y1, dst_x0:dst_x1] += source_known.astype(np.uint8)
        can_fill = missing & (counts > 0)
        if not np.any(can_fill):
            break
        filled[can_fill] = sums[can_fill] / counts[can_fill].astype(np.float32)
        known[can_fill] = True
        missing = land & ~known
        if not np.any(missing):
            break

    if np.any(missing):
        filled[missing] = sea_level_m
        known[missing] = True
    return filled, known, initial_missing


def build_heightmap(args: argparse.Namespace) -> dict:
    if args.resolution <= 0:
        raise ValueError("--resolution must be positive")
    west, south, east, north = map(float, args.bbox)
    if not (west < east and south < north):
        raise ValueError("--bbox must be WEST SOUTH EAST NORTH")
    if args.high_clip_m <= args.sea_level_m:
        raise ValueError("--high-clip-m must be greater than --sea-level-m")

    alpha = make_alpha_canvas(args.mask, args.resolution)
    alpha_array = np.asarray(alpha, dtype=np.uint8)
    alpha_bbox = alpha_threshold_bbox(alpha_array, args.alpha_threshold)
    if alpha_bbox is None:
        raise RuntimeError(f"mask has no pixels above alpha threshold: {args.mask}")

    tile_names = ensure_tile_list(args.tile_list)
    available = set(tile_names)
    candidates = list(
        iter_candidate_tiles(
            (west, south, east, north),
            alpha_bbox,
            alpha_array,
            args.alpha_threshold,
            available,
        )
    )
    if not candidates:
        raise RuntimeError("no Copernicus tiles intersect the configured mask/bbox")

    used_tiles: list[str] = []
    failed_tiles: list[str] = []
    if args.reuse_meters:
        cached = np.load(args.meters_output)
        elevation = np.asarray(cached["elevation_m"], dtype=np.float32)
        coverage = np.asarray(cached["coverage"], dtype=bool)
        if elevation.shape != (args.resolution, args.resolution):
            raise RuntimeError("--meters-output resolution does not match --resolution")
    else:
        elevation = np.full((args.resolution, args.resolution), np.nan, dtype=np.float32)
        coverage = np.zeros((args.resolution, args.resolution), dtype=bool)

        rasterio_env = {
            "AWS_NO_SIGN_REQUEST": "YES",
            "GDAL_DISABLE_READDIR_ON_OPEN": "EMPTY_DIR",
            "CPL_VSIL_CURL_ALLOWED_EXTENSIONS": ".tif",
            "VSI_CACHE": "TRUE",
            "VSI_CACHE_SIZE": str(64 * 1024 * 1024),
        }
        with rasterio.Env(**rasterio_env):
            for index, (_lat, _lon, name, pixel_window) in enumerate(candidates, start=1):
                print(f"[{index}/{len(candidates)}] {name}", flush=True)
                try:
                    if read_tile_into_canvas(
                        name,
                        pixel_window,
                        alpha_bbox,
                        (west, south, east, north),
                        elevation,
                        coverage,
                    ):
                        used_tiles.append(name)
                except Exception as exc:  # keep going; missing sea/offshore COGs are expected.
                    failed_tiles.append(f"{name}: {exc}")
        np.savez_compressed(
            args.meters_output,
            elevation_m=elevation,
            coverage=coverage,
            alpha=alpha_array,
        )

    land = alpha_array > args.alpha_threshold
    if not np.any(land):
        raise RuntimeError("DEM read completed but no land pixels were covered")
    elevation, coverage, filled_missing_count = fill_missing_land_elevation(
        elevation,
        coverage,
        land,
        args.sea_level_m,
    )

    clipped = np.clip(elevation, args.sea_level_m, args.high_clip_m)
    altitude = (clipped - args.sea_level_m) / (args.high_clip_m - args.sea_level_m)
    altitude = np.clip(altitude, 0.0, 0.98)
    luminance = 1.0 - altitude
    luminance[~land] = 1.0

    rgba = np.zeros((args.resolution, args.resolution, 4), dtype=np.uint8)
    gray = np.round(luminance * 255.0).astype(np.uint8)
    rgba[:, :, 0] = gray
    rgba[:, :, 1] = gray
    rgba[:, :, 2] = gray
    rgba[:, :, 3] = np.where(land, alpha_array, 0).astype(np.uint8)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, mode="RGBA").save(args.output)
    if filled_missing_count > 0:
        np.savez_compressed(
            args.meters_output,
            elevation_m=elevation,
            coverage=coverage,
            alpha=alpha_array,
        )

    land_elevation = elevation[land]
    metadata = {
        "source": {
            "dataset": "Copernicus DEM GLO-90 COG",
            "base_url": COPERNICUS_GLO90_BASE_URL,
            "tile_list_url": COPERNICUS_GLO90_TILE_LIST_URL,
            "tile_list_path": str(args.tile_list.relative_to(REPO_ROOT)),
        },
        "outputs": {
            "heightmap_png": str(args.output.relative_to(REPO_ROOT)),
            "dem_meters_npz": str(args.meters_output.relative_to(REPO_ROOT)),
        },
        "resolution": [args.resolution, args.resolution],
        "bbox_wgs84": {
            "west": west,
            "south": south,
            "east": east,
            "north": north,
        },
        "mask_path": str(args.mask.relative_to(REPO_ROOT)),
        "alpha_bbox_px": list(alpha_bbox),
        "alpha_threshold": args.alpha_threshold,
        "normalization": {
            "sea_level_m": args.sea_level_m,
            "high_clip_m": args.high_clip_m,
            "altitude_cap": 0.98,
            "encoding": "luminance = 1.0 - normalized_altitude",
        },
        "tiles": {
            "candidate_count": len(candidates),
            "used_count": len(used_tiles),
            "failed_count": len(failed_tiles),
            "used": used_tiles,
            "failed": failed_tiles,
            "reused_meters": bool(args.reuse_meters),
            "filled_missing_land_pixels": filled_missing_count,
        },
        "elevation_stats_m": {
            "min": float(np.nanmin(land_elevation)),
            "max": float(np.nanmax(land_elevation)),
            "mean": float(np.nanmean(land_elevation)),
            "p50": float(np.nanpercentile(land_elevation, 50)),
            "p95": float(np.nanpercentile(land_elevation, 95)),
            "p99": float(np.nanpercentile(land_elevation, 99)),
        },
    }
    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    args.metadata.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return metadata


def main() -> None:
    args = parse_args()
    metadata = build_heightmap(args)
    print(
        "wrote {heightmap_png} using {used_count}/{candidate_count} tiles".format(
            heightmap_png=metadata["outputs"]["heightmap_png"],
            used_count=metadata["tiles"]["used_count"],
            candidate_count=metadata["tiles"]["candidate_count"],
        )
    )


if __name__ == "__main__":
    main()
