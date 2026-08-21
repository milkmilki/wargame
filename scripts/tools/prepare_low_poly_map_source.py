#!/usr/bin/env python3
"""Prepare a replaceable packed map source for the low-poly terrain renderer.

The height image is treated as numeric data only. It is packed into Alpha using
the runtime contract; RGB comes from an optional co-registered surface image or
from neutral land/sea colors. Runtime Godot code then builds the low-poly mesh and
lights it with the two-light rig. No hillshade is baked into this output.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = REPO_ROOT / "assets/terrain/custom_low_poly_map.png"
DEFAULT_METADATA = REPO_ROOT / "assets/terrain/custom_low_poly_map.json"
DEFAULT_MANIFEST = REPO_ROOT / "assets/terrain/map_source.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Pack a numeric heightmap and optional co-registered surface image "
            "for the runtime low-poly terrain renderer."
        )
    )
    parser.add_argument("--heightmap", type=Path, required=True)
    parser.add_argument("--surface", type=Path)
    parser.add_argument(
        "--encoding", choices=("normalized", "meters", "packed-alpha"),
        default="normalized",
        help=(
            "normalized maps channel min..max to elevation-min..max; "
            "meters reads pixel values as metres with scale/offset; "
            "packed-alpha reuses an existing WorldWar Alpha channel"
        ),
    )
    parser.add_argument(
        "--height-channel", choices=("luma", "red", "green", "blue", "alpha"),
        default="luma",
    )
    parser.add_argument("--elevation-min-m", type=float, default=-8000.0)
    parser.add_argument("--elevation-max-m", type=float, default=6200.0)
    parser.add_argument("--value-scale", type=float, default=1.0)
    parser.add_argument("--value-offset", type=float, default=0.0)
    parser.add_argument(
        "--normalized-value-min", type=float,
        help="Override the numeric black point for normalized encoding",
    )
    parser.add_argument(
        "--normalized-value-max", type=float,
        help="Override the numeric white point for normalized encoding",
    )
    parser.add_argument("--width", type=int)
    parser.add_argument("--height", type=int)
    parser.add_argument(
        "--bbox", type=float, nargs=4, required=True,
        metavar=("WEST", "SOUTH", "EAST", "NORTH"),
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument(
        "--manifest", type=Path,
        help="Optionally update a WorldWar map_source.json to reference output",
    )
    parser.add_argument(
        "--land-color", type=int, nargs=3, default=(102, 110, 92),
        metavar=("R", "G", "B"),
    )
    parser.add_argument(
        "--shallow-sea-color", type=int, nargs=3, default=(34, 91, 128),
        metavar=("R", "G", "B"),
    )
    parser.add_argument(
        "--deep-sea-color", type=int, nargs=3, default=(10, 29, 61),
        metavar=("R", "G", "B"),
    )
    return parser.parse_args()


def _validate_rgb(values: tuple[int, int, int] | list[int], name: str) -> np.ndarray:
    color = np.asarray(values, dtype=np.int32)
    if color.shape != (3,) or np.any(color < 0) or np.any(color > 255):
        raise ValueError(f"{name} must contain three values in 0..255")
    return color.astype(np.float32)


def _resample(
    image: Image.Image, size: tuple[int, int], numeric: bool, nearest: bool = False
) -> Image.Image:
    if image.size == size:
        return image
    method = (
        Image.Resampling.NEAREST
        if nearest
        else Image.Resampling.BILINEAR if numeric
        else Image.Resampling.LANCZOS
    )
    return image.resize(size, method)


def _channel_array(image: Image.Image, channel: str) -> tuple[np.ndarray, float, float]:
    if channel == "luma":
        original_mode = image.mode
        source = image.convert("F")
        values = np.asarray(source, dtype=np.float32)
        if original_mode.startswith("I;16"):
            lo, hi = 0.0, 65535.0
        elif original_mode in {"1", "L", "LA", "P", "RGB", "RGBA"}:
            lo, hi = 0.0, 255.0
        else:
            # Integer/float scientific rasters may use arbitrary ranges; users
            # can lock them with --normalized-value-min/max.
            lo, hi = map(float, source.getextrema())
        return values, lo, hi
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    index = {"red": 0, "green": 1, "blue": 2, "alpha": 3}[channel]
    values = rgba[:, :, index]
    return values, 0.0, 255.0


def _decode_packed_alpha(alpha: np.ndarray, low: float, high: float) -> np.ndarray:
    alpha = np.clip(np.rint(alpha), 1.0, 255.0)
    sea = alpha <= 128.0
    elevation = np.empty(alpha.shape, dtype=np.float32)
    elevation[sea] = low + (alpha[sea] - 1.0) / 127.0 * (-low)
    elevation[~sea] = (alpha[~sea] - 129.0) / 126.0 * high
    return elevation


def load_elevation(
    args: argparse.Namespace, size: tuple[int, int]
) -> tuple[np.ndarray, tuple[float, float] | None]:
    image = _resample(
        Image.open(args.heightmap), size, numeric=True,
        nearest=args.encoding == "packed-alpha",
    )
    values, source_min, source_max = _channel_array(image, args.height_channel)
    if args.encoding == "packed-alpha":
        if args.height_channel != "alpha":
            raise ValueError("packed-alpha requires --height-channel alpha")
        return _decode_packed_alpha(
            values, args.elevation_min_m, args.elevation_max_m
        ), None
    if args.encoding == "meters":
        return values * args.value_scale + args.value_offset, None
    if args.normalized_value_min is not None:
        source_min = args.normalized_value_min
    if args.normalized_value_max is not None:
        source_max = args.normalized_value_max
    if source_max <= source_min:
        raise ValueError("normalized heightmap has no value range")
    normalized = (values - source_min) / (source_max - source_min)
    return (
        args.elevation_min_m
        + normalized * (args.elevation_max_m - args.elevation_min_m),
        (float(source_min), float(source_max)),
    )


def load_packed_elevation(
    args: argparse.Namespace, size: tuple[int, int]
) -> tuple[np.ndarray, np.ndarray]:
    if args.height_channel != "alpha":
        raise ValueError("packed-alpha requires --height-channel alpha")
    image = _resample(
        Image.open(args.heightmap), size, numeric=True, nearest=True
    )
    alpha = np.asarray(image.convert("RGBA"), dtype=np.uint8)[:, :, 3]
    if np.any(alpha == 0):
        raise ValueError("packed-alpha input must use 1..255; Alpha 0 is invalid")
    elevation = _decode_packed_alpha(
        alpha.astype(np.float32),
        args.elevation_min_m,
        args.elevation_max_m,
    )
    return elevation, alpha.copy()


def pack_elevation(elevation: np.ndarray, low: float, high: float) -> np.ndarray:
    land = elevation > 0.0
    alpha = np.empty(elevation.shape, dtype=np.uint8)
    if low < 0.0:
        sea_normalized = np.clip((elevation[~land] - low) / -low, 0.0, 1.0)
        alpha[~land] = 1 + np.rint(sea_normalized * 127.0).astype(np.uint8)
    else:
        # Land-only DEM: black/zero is the sea surface and no bathymetry is
        # available. Alpha 128 is exactly 0m water in the runtime contract.
        alpha[~land] = 128
    land_normalized = np.clip(elevation[land] / high, 0.0, 1.0)
    alpha[land] = 129 + np.rint(land_normalized * 126.0).astype(np.uint8)
    return alpha


def build_surface(
    args: argparse.Namespace,
    elevation: np.ndarray,
    land_mask: np.ndarray | None = None,
) -> np.ndarray:
    height, width = elevation.shape
    if args.surface is not None:
        surface = _resample(
            Image.open(args.surface).convert("RGB"), (width, height), numeric=False
        )
        return np.asarray(surface, dtype=np.uint8)
    land_color = _validate_rgb(args.land_color, "--land-color")
    shallow = _validate_rgb(args.shallow_sea_color, "--shallow-sea-color")
    deep = _validate_rgb(args.deep_sea_color, "--deep-sea-color")
    rgb = np.empty((height, width, 3), dtype=np.float32)
    land = elevation > 0.0 if land_mask is None else land_mask
    rgb[land] = land_color
    depth = np.clip(-elevation / max(-args.elevation_min_m, 1.0), 0.0, 1.0)
    # Shelf remains shallow; abyss settles toward navy. No land hillshade or
    # elevation tint is baked—the runtime low-poly normals own all relief.
    mix = np.clip((depth - 0.06) / (0.375 - 0.06), 0.0, 1.0)[:, :, None]
    sea_rgb = shallow[None, None, :] * (1.0 - mix) + deep[None, None, :] * mix
    rgb[~land] = sea_rgb[~land]
    return np.clip(np.rint(rgb), 0, 255).astype(np.uint8)


def resource_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(REPO_ROOT)
    except ValueError as error:
        raise ValueError("manifest output must be inside the repository") from error
    return "res://" + relative.as_posix()


def write_manifest(
    path: Path,
    output: Path,
    bbox: list[float],
    elevation_min_m: float,
    elevation_max_m: float,
) -> None:
    manifest = {
        "format": "world-war-map-source",
        "version": 1,
        "texture": resource_path(output),
        "bbox_wgs84": bbox,
        "city_density": {
            "peak_latitude": 30.0,
            "south_edge_multiplier": 0.5,
            "north_edge_multiplier": 0.2,
        },
        "channels": {
            "rgb": "co-registered surface or neutral low-poly base color",
            "alpha": (
                f"1..128={elevation_min_m:g}..0m sea, "
                f"129..255=positive land..{elevation_max_m:g}m"
            ),
        },
        "elevation_low_clip_m": elevation_min_m,
        "elevation_high_clip_m": elevation_max_m,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    args = parse_args()
    if not args.heightmap.exists():
        raise FileNotFoundError(args.heightmap)
    if args.surface is not None and not args.surface.exists():
        raise FileNotFoundError(args.surface)
    if args.elevation_min_m > 0.0 or args.elevation_max_m <= 0.0:
        raise ValueError("elevation min must be <=0 and max must be positive")
    west, south, east, north = map(float, args.bbox)
    if not (west < east and south < north):
        raise ValueError("invalid --bbox")
    source = Image.open(args.heightmap)
    width = args.width or source.width
    height = args.height or source.height
    if width < 2 or height < 2:
        raise ValueError("output dimensions must be at least 2x2")
    if args.encoding == "packed-alpha":
        elevation, alpha = load_packed_elevation(args, (width, height))
        normalized_range = None
        land_mask = alpha >= 129
    else:
        elevation, normalized_range = load_elevation(args, (width, height))
        alpha = pack_elevation(
            elevation, args.elevation_min_m, args.elevation_max_m
        )
        land_mask = elevation > 0.0
    rgb = build_surface(args, elevation, land_mask)
    rgba = np.dstack((rgb, alpha))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba).save(args.output, optimize=True)
    metadata = {
        "heightmap": str(args.heightmap),
        "surface": str(args.surface) if args.surface else None,
        "encoding": args.encoding,
        "height_channel": args.height_channel,
        "normalized_value_range": (
            list(normalized_range) if normalized_range is not None else None
        ),
        "bbox_wgs84": [west, south, east, north],
        "output": str(args.output),
        "output_size": [width, height],
        "elevation_clip_m": [args.elevation_min_m, args.elevation_max_m],
        "elevation_stats_m": {
            "min": float(np.min(elevation)),
            "max": float(np.max(elevation)),
            "land_pixels": int(np.count_nonzero(elevation > 0.0)),
            "water_pixels": int(np.count_nonzero(elevation <= 0.0)),
        },
        "render_contract": {
            "mesh": "runtime deterministic smooth-shaded low-poly grid",
            "height_is_color": False,
            "baked_hillshade": False,
            "lighting": "vertical plane light + northwest-to-southeast horizontal sculpt light",
        },
    }
    args.metadata.parent.mkdir(parents=True, exist_ok=True)
    args.metadata.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    if args.manifest is not None:
        write_manifest(
            args.manifest, args.output, [west, south, east, north],
            args.elevation_min_m, args.elevation_max_m,
        )
    print(f"wrote {args.output} ({width}x{height})")
    print(f"metadata {args.metadata}")
    if args.manifest is not None:
        print(f"manifest {args.manifest}")


if __name__ == "__main__":
    main()
