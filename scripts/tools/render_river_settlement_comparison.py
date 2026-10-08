"""Render identical-seed settlement water/suitability comparisons from runtime diagnostics."""
import argparse
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--before-label", default="Before: flow weighted")
    parser.add_argument("--after-label", default="Candidate: uniform banks")
    args = parser.parse_args()
    datasets = [json.loads(p.read_text(encoding="utf-8")) for p in (args.before, args.after)]
    assert datasets[0]["seed"] == datasets[1]["seed"]
    assert datasets[0]["size"] == datasets[1]["size"]
    aspect = datasets[1]["aspect"]
    mercator = lambda lat: math.asinh(math.tan(math.radians(lat)))
    def xy(lon, lat):
        return (lon + 12) / 148 * aspect, (mercator(57) - mercator(lat)) / (mercator(57) - mercator(18))
    args.output.mkdir(parents=True, exist_ok=True)
    regions = {"full": (-12, 18, 136, 57), "sichuan": (102, 27, 109, 34), "guanzhong": (105, 32, 113, 37), "central-china": (108, 29, 118, 37), "nile": (25, 18, 36, 33)}
    for name, (west, south, east, north) in regions.items():
        x0, y0 = xy(west, north)
        x1, y1 = xy(east, south)
        fig, axes = plt.subplots(2, 2, figsize=(16, 9 if name == "full" else 13), layout="constrained")
        for col, data in enumerate(datasets):
            width, height = data["size"]
            land = np.asarray(data["land"]).reshape(height, width).astype(bool)
            for row, field in enumerate(("water", "suitability")):
                ax = axes[row, col]
                values = np.asarray(data[field]).reshape(height, width)
                im = ax.imshow(np.ma.masked_where(~land, values), extent=(0, aspect, 1, 0), vmin=0, vmax=1, cmap="YlGnBu" if row == 0 else "YlGn", interpolation="nearest")
                for river in data["rivers"]:
                    points = np.asarray(river["points"])
                    ax.plot(points[:, 0]*aspect, points[:, 1], color="#1273ba", lw=.45, alpha=.75)
                if row == 1:
                    points = np.asarray(data["positions"])
                    ax.scatter(points[:, 0]*aspect, points[:, 1], s=10 if name == "full" else 32, color="#b42120", edgecolors="white", linewidths=.35, zorder=4)
                label = args.before_label if col == 0 else args.after_label
                ax.set(xlim=(x0,x1), ylim=(y1,y0), aspect="equal", title=f"{label} / {field}")
                ax.set_facecolor("#dfebf3")
                ax.set_xticks([])
                ax.set_yticks([])
                fig.colorbar(im, ax=ax, shrink=.65)
        fig.suptitle(f"{name} | seed {datasets[0]['seed']} | red dots = 500 land cities | candidate not promoted")
        for extension in ("png", "svg"):
            fig.savefig(args.output / f"uniform-{name}.{extension}", dpi=140)
        plt.close(fig)
    print("Rendered comparison maps to", args.output)


if __name__ == "__main__":
    main()
