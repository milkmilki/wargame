"""Offline checks for numeric packing and recoverable terrain downloads."""
import argparse
import importlib.util
import io
import json
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("surface_tool", ROOT / "scripts/tools/generate_china_surface_texture.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class TerrainSurfaceToolTests(unittest.TestCase):
    def test_generated_mercator_asset_matches_cached_dem_at_geographic_points(self):
        asset = ROOT / "assets/terrain/eurasia_mercator_elevation_white_4096.png"
        cache = ROOT / ".dbg/elevation_tiles"
        if not asset.exists() or not cache.exists():
            self.skipTest("generated asset and local source cache required")
        metadata = json.loads(asset.with_suffix(".json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["projection"], "web_mercator")
        self.assertEqual(len(metadata["elevation_source"]["tiles"]), 1026)
        with Image.open(asset) as image:
            rgba = np.asarray(image)
        self.assertEqual(rgba.shape, (4096, 4096, 4))
        self.assertTrue(np.all(rgba[:, :, :3] == 255))
        self.assertGreaterEqual(int(rgba[:, :, 3].min()), 1)
        self.assertTrue(np.any(rgba[:, :, 3] <= 128))
        self.assertTrue(np.any(rgba[:, :, 3] > 128))
        bbox = (-12, 18, 136, 57)
        left, top = tool.mercator_position(-12, 57, 7)
        right, bottom = tool.mercator_position(136, 18, 7)
        for lon, lat in [(12.5, 41.9), (51.4, 35.7), (108.9, 34.3), (20, 34), (126, 26)]:
            u, v = tool.lonlat_to_map(lon, lat, bbox, "web_mercator")
            px, py = int(u * 4096), int(v * 4096)
            wx = round(left + (px + .5) / 4096 * (right - left))
            wy = round(top + (py + .5) / 4096 * (bottom - top))
            with Image.open(cache / "terrarium/7" / str(wx // 256) / f"{wy // 256}.png") as tile:
                r, g, b = tile.convert("RGB").getpixel((wx % 256, wy % 256))
            elevation = r * 256 + g + b / 256 - 32768
            expected = 129 + round(min(elevation / 6200, 1) * 126) if elevation > 0 else 1 + round(max(0, (elevation + 8000) / 8000) * 127)
            self.assertEqual(int(rgba[py, px, 3]), expected, (lon, lat, elevation))

    def test_mercator_coordinates_and_uniform_projected_sampling(self):
        bbox = (-12, 18, 136, 57)
        for lon, lat, expected_x, expected_y in [
            (12.5, 41.9, .16554054054, .45680645848),
            (51.4, 35.7, .42837837838, .61173539668),
            (108.9, 34.3, .81689189189, .64498335668),
        ]:
            uv = tool.lonlat_to_map(lon, lat, bbox, "web_mercator")
            np.testing.assert_allclose(uv, [expected_x, expected_y], atol=1e-9, rtol=0)
        # Encode world pixel-row in the DEM; output must sample linear projected y.
        with tempfile.TemporaryDirectory() as temporary:
            cache = Path(temporary)
            for tile_y in range(2):
                rows = np.arange(tile_y * 256, (tile_y + 1) * 256, dtype=np.uint16)
                encoded = rows + 32768
                rgb = np.zeros((256, 256, 3), dtype=np.uint8)
                rgb[:, :, 0] = (encoded // 256)[:, None]
                rgb[:, :, 1] = (encoded % 256)[:, None]
                for tile_x in range(2):
                    path = cache / "terrarium/1" / str(tile_x) / f"{tile_y}.png"
                    path.parent.mkdir(parents=True, exist_ok=True)
                    Image.fromarray(rgb).save(path)
            dem, _ = tool.build_elevation(cache, bbox, 9, 1, projection="web_mercator")
            top = tool.mercator_position(-12, 57, 1)[1]
            bottom = tool.mercator_position(136, 18, 1)[1]
            expected = np.rint(top + (np.arange(9) + .5) / 9 * (bottom - top))
            np.testing.assert_array_equal(dem[:, 0], expected)

    def test_packing_preserves_zero_split_and_metadata_for_relative_output(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".dbg") as temporary:
            output = Path(temporary).relative_to(Path.cwd()) / "terrain.png"
            args = argparse.Namespace(
                resolution=3, high_clip_m=6200, low_clip_m=-8000,
                bbox=(-12, 18, 136, 57), cache_dir=Path(temporary),
                elevation_zoom=7, output=output, metadata=Path(temporary) / "terrain.json",
            )
            dem = np.array([[-9000, -8000, 0], [0.001, 3100, 6200], [10000, -10, 0]], dtype=np.float32)
            with patch.object(tool, "build_elevation", return_value=(dem, ["7/68/47"])):
                metadata = tool.build_texture(args)
            with Image.open(output) as image:
                rgba = np.asarray(image)
            np.testing.assert_array_equal(rgba[:, :, 3], [[1, 1, 128], [129, 192, 255], [255, 128, 128]])
            self.assertTrue(np.all(rgba[:, :, :3] == 255))
            self.assertEqual(metadata["bbox_wgs84"], {"west": -12, "south": 18, "east": 136, "north": 57})
            self.assertEqual(metadata["elevation_source"]["tiles"], ["7/68/47"])

    def test_interrupted_download_does_not_publish_partial_cache(self):
        buffer = io.BytesIO()
        Image.new("RGB", (256, 256), (128, 0, 0)).save(buffer, format="PNG")
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(tool.urllib.request, "urlopen", side_effect=[urllib.error.URLError("TLS EOF"), io.BytesIO(buffer.getvalue())]) as request:
                with patch.object(tool.time, "sleep"):
                    tile = tool.elevation_tile(Path(temporary), 7, 68, 47)
            self.assertEqual(request.call_count, 2)
            with Image.open(tile) as image:
                self.assertEqual(image.size, (256, 256))
            self.assertFalse(tile.with_suffix(".tmp").exists())
            with patch.object(tool.urllib.request, "urlopen") as request:
                self.assertEqual(tool.elevation_tile(Path(temporary), 7, 68, 47), tile)
                request.assert_not_called()


if __name__ == "__main__":
    unittest.main()
