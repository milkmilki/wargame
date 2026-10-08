"""Export the runtime-selected rivers as SVG, PNG and WGS84 GeoJSON."""
import argparse
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--bbox", nargs=4, type=float, default=(-12, 18, 136, 57))
    args = parser.parse_args()
    data = json.loads(args.input.read_text(encoding="utf-8"))
    args.output.mkdir(parents=True, exist_ok=True)
    west, south, east, north = args.bbox
    m = lambda lat: math.asinh(math.tan(math.radians(lat)))
    def xy(lon, lat):
        return (lon - west) / (east - west) * data["aspect"], (m(north) - m(lat)) / (m(north) - m(south))
    def lonlat(p):
        return [west + p[0] * (east - west), math.degrees(math.atan(math.sinh(m(north) - p[1] * (m(north) - m(south)))))]
    geo = {"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {"river_class": r["class"], "terminal": r["terminal"]}, "geometry": {"type": "LineString", "coordinates": [lonlat(p) for p in r["points"]]}} for r in data["rivers"]]}
    (args.output / "rivers.geojson").write_text(json.dumps(geo, separators=(",", ":")), encoding="utf-8")
    width, height = data["size"]
    land = np.array(data["land"]).reshape(height, width).astype(bool)
    terrain = np.array(data["heights"]).reshape(height, width)
    relief_colors = LinearSegmentedColormap.from_list("land", ["#e4ead8", "#b6c9a1", "#a8a58d", "#eee8df"])
    for name, bounds in [("full", args.bbox), ("china", (95, 24, 124, 43)), ("nile", (25, 18, 36, 33))]:
        l, bottom, r, top = bounds
        x0, y0 = xy(l, top)
        x1, y1 = xy(r, bottom)
        fig, ax = plt.subplots(figsize=(16, max(5, 16 * (y1-y0)/(x1-x0))), layout="constrained")
        ax.set_facecolor("#d7e9f0")
        ax.imshow(np.ma.masked_where(~land, terrain), extent=(0, data["aspect"], 1, 0), cmap=relief_colors, vmin=0, vmax=1, interpolation="bilinear", rasterized=True)
        for river in sorted(data["rivers"], key=lambda r: r["class"] == "major"):
            p = np.asarray(river["points"])
            major = river["class"] == "major"
            ax.plot(p[:, 0] * data["aspect"], p[:, 1], color="#126bbc" if major else "#54a6c9", lw=1.6 if major else 0.7, solid_capstyle="round", solid_joinstyle="round")
        ax.set(xlim=(x0,x1), ylim=(y1,y0), aspect="equal", title=f"Terrain-derived vector rivers — {name} (8192 × 2845 DEM)")
        ax.set_xticks([])
        ax.set_yticks([])
        for extension in ("svg", "png"):
            fig.savefig(args.output / f"rivers-{name}.{extension}", dpi=130)
        plt.close(fig)
    print(f"Wrote vector previews and GeoJSON: {args.output}")


if __name__ == "__main__":
    main()
