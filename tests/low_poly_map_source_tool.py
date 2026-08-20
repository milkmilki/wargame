#!/usr/bin/env python3
"""Focused regression for packed low-poly map-source preparation."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
TOOL = REPO_ROOT / "scripts/tools/prepare_low_poly_map_source.py"


def main() -> None:
    ignored_test_root = REPO_ROOT / ".godot"
    ignored_test_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=ignored_test_root) as directory:
        root = Path(directory)
        source_path = root / "coast.png"
        output_path = root / "packed.png"
        metadata_path = root / "packed.json"
        manifest_path = root / "map_source.json"
        # Left half is shallow sea (Alpha 128), right half is first land level
        # (Alpha 129). Nearest-neighbor resize must retain only these two values.
        rgba = np.zeros((4, 4, 4), dtype=np.uint8)
        rgba[:, :2, :3] = (20, 60, 100)
        rgba[:, 2:, :3] = (100, 110, 90)
        rgba[:, :2, 3] = 128
        rgba[:, 2:, 3] = 129
        Image.fromarray(rgba).save(source_path)
        subprocess.run(
            [
                sys.executable, str(TOOL),
                "--heightmap", str(source_path),
                "--encoding", "packed-alpha",
                "--height-channel", "alpha",
                "--bbox", "0", "0", "2", "1",
                "--width", "17", "--height", "9",
                "--output", str(output_path),
                "--metadata", str(metadata_path),
                "--manifest", str(manifest_path),
            ],
            check=True,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        packed = np.asarray(Image.open(output_path).convert("RGBA"))
        alpha_values = set(map(int, np.unique(packed[:, :, 3])))
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        valid = (
            alpha_values == {128, 129}
            and metadata["render_contract"]["height_is_color"] is False
            and metadata["render_contract"]["baked_hillshade"] is False
            and metadata["output_size"] == [17, 9]
            and manifest["texture"].startswith("res://.godot/")
            and manifest["bbox_wgs84"] == [0.0, 0.0, 2.0, 1.0]
            and manifest["elevation_low_clip_m"] == -8000.0
            and manifest["elevation_high_clip_m"] == 6200.0
        )
        # 16-bit normalized inputs must use the full 0..65535 encoding range,
        # not per-image contrast stretching. A value of 32768 therefore maps
        # close to the midpoint between -8000m and +6200m.
        gray16_path = root / "gray16.png"
        gray16_output = root / "gray16-packed.png"
        gray16_metadata = root / "gray16-packed.json"
        gray16 = np.full((2, 2), 32768, dtype=np.uint16)
        gray16[0, 0] = 0
        Image.fromarray(gray16).save(gray16_path)
        subprocess.run(
            [
                sys.executable, str(TOOL),
                "--heightmap", str(gray16_path),
                "--encoding", "normalized",
                "--bbox", "0", "0", "2", "1",
                "--output", str(gray16_output),
                "--metadata", str(gray16_metadata),
            ],
            check=True, cwd=REPO_ROOT, capture_output=True, text=True,
        )
        gray_alpha = np.asarray(
            Image.open(gray16_output).convert("RGBA")
        )[:, :, 3]
        # Midpoint elevation is about -900m, hence a sea Alpha around 114.
        valid = valid and int(gray_alpha[1, 1]) in range(112, 117)
        print(
            "LOW_POLY_SOURCE_TOOL ",
            f"alpha={sorted(alpha_values)} size={packed.shape[1]}x{packed.shape[0]} ",
            f"gray16_mid_alpha={int(gray_alpha[1, 1])} ",
            f"verdict={'OK' if valid else 'INVALID'}",
        )
        raise SystemExit(0 if valid else 1)


if __name__ == "__main__":
    main()
