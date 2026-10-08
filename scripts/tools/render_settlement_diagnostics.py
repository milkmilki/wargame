"""Render the optional JSON emitted by settlement_environment_benchmark.gd.

Diagnostic-only dependencies: numpy and matplotlib. No climate data is imported.
"""
import argparse
import json
from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = json.loads(args.input.read_text(encoding="utf-8"))
    width, height = data["size"]
    land = np.asarray(data["land"]).reshape(height, width).astype(bool)
    positions = np.asarray(data["positions"])
    aspect = data["aspect"]
    panels = [
        ("winter_temperature", "Winter temperature (model, Celsius)", "coolwarm", (-30, 20)),
        ("rainfall", "Rainfall potential (model units)", "YlGnBu", (0, 1)),
        ("aridity", "Aridity: 0 moist, 1 dry", "YlOrBr", (0, 1)),
        ("water", "Runoff water potential (not navigable rivers)", "Blues", (0, 1)),
        ("farmland", "Usable flat hinterland fraction", "YlGn", (0, 1)),
        ("suitability", f"Settlement suitability + {len(positions)} cities", "YlGn", (0, 1)),
    ]
    fig, axes = plt.subplots(3, 2, figsize=(17, 11), layout="constrained", facecolor="#121c2b")
    for ax, (key, title, cmap, limits) in zip(axes.flat, panels):
        values = np.asarray(data[key]).reshape(height, width)
        ax.set_facecolor("#243c55")
        image = ax.imshow(
            np.ma.masked_where(~land, values), extent=(0, aspect, 1, 0),
            cmap=cmap, vmin=limits[0], vmax=limits[1], interpolation="nearest",
        )
        ax.contour(
            np.linspace(0, aspect, width), np.linspace(0, 1, height),
            land.astype(float), levels=[0.5], colors="#18212d", linewidths=0.35,
        )
        if key == "suitability" and len(positions):
            ax.scatter(positions[:, 0] * aspect, positions[:, 1], s=5, c="#ad2026", linewidths=0)
        ax.set_title(title, color="white", fontsize=11)
        ax.set_xticks([])
        ax.set_yticks([])
        bar = fig.colorbar(image, ax=ax, fraction=0.022, pad=0.015)
        bar.ax.tick_params(colors="white", labelsize=8)
    fig.suptitle(
        f"Procedural settlement environment — {data['environment_version']} / seed {data['seed']}",
        color="white", fontsize=16,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=145)
    plt.close(fig)
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
