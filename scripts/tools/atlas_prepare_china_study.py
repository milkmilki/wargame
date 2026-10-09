"""Prepare the validation-only Natural Earth study mask; never runtime terrain."""
import argparse
import hashlib
import json
from pathlib import Path

from rasterio.features import rasterize
from rasterio.transform import from_bounds

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
metadata = json.loads((root / "tests/fixtures/atlas_china_study_mask.json").read_text())
raw = args.source.read_bytes()
assert hashlib.sha256(raw).hexdigest() == metadata["source_sha256"], "Study dataset version/hash mismatch"
features = [f for f in json.loads(raw)["features"] if f["properties"].get("ADM0_A3") == "CHN"]
mask = rasterize([(f["geometry"], 1) for f in features], out_shape=(180, 360), transform=from_bounds(-180, -90, 180, 90, 360, 180), fill=0, dtype="uint8")
(root / "tests/fixtures/atlas_china_study_mask.u8").write_bytes(mask.tobytes())
