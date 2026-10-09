"""Plot exported native climate fields; no renderer screenshots are edited."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

root = Path(__file__).resolve().parents[2]
out = root / "docs/atlas/circulation"
zones = [("China / Hu line", (90, 140, 20, 55)), ("Central Africa / Sahara", (-20, 45, -15, 35)), ("Europe", (-15, 40, 35, 65))]
fig, axes = plt.subplots(3, 2, figsize=(12, 11), layout="constrained")
records = {}
for column, key in enumerate(("before", "after")):
    records[key] = json.loads((root / f".dbg/circulation-{key}-cells.json").read_text())
    rain = np.fromfile(root / f".dbg/circulation-{key}-rain.f32", dtype="<f4").reshape(1024, 2048)
    water = np.fromfile(root / f".dbg/circulation-{key}-water.u8", dtype="u1").reshape(1024, 2048)
    cities = np.array(records[key]["cities"])
    for row, (name, (x0, x1, y0, y1)) in enumerate(zones):
        ax = axes[row, column]
        artist = ax.imshow(np.ma.masked_where(water != 0, rain), extent=(-180, 180, -90, 90), origin="upper", cmap="YlGnBu", vmin=0, vmax=2400)
        ax.scatter(cities[:, 0], cities[:, 1], s=10, color="#222222", linewidths=.4, edgecolors="white")
        ax.set(xlim=(x0, x1), ylim=(y0, y1), facecolor="#e4e4e4", xlabel="Longitude", ylabel="Latitude")
        ax.set_title(name + (" | v1 effective moisture" if key == "before" else " | v2 estimated annual rain"), fontsize=10)
        if row == 0:
            ax.plot([98.5, 127.49], [25.02, 50.25], "--", color="#b62024", lw=1.5, label="Heihe-Tengchong reference")
            ax.legend(loc="lower right", fontsize=7)
fig.colorbar(artist, ax=axes, shrink=.65, label="Model moisture in mm-equivalent (not observed rainfall)")
fig.suptitle("Same Earth / seed 1 / city threshold > 1 | Dots: generated cities", fontsize=12)
fig.savefig(out / "rainfall-comparison.png", dpi=160)

cells = np.array(records["after"]["cells"])
chosen, seen = [], set()
for i, (lon, lat, _) in enumerate(cells):
    if not (-20 <= lon <= 150 and -25 <= lat <= 65):
        continue
    tile = (int((lon + 180) // 6), int((lat + 90) // 6))
    if tile not in seen:
        chosen.append(i)
        seen.add(tile)
chosen = np.array(chosen)
fig, axes = plt.subplots(1, 2, figsize=(13, 4.8), layout="constrained")
for ax, quarter, name in zip(axes, (0, 2), ("DJF circulation", "JJA circulation")):
    wind = records["after"]["winds"][quarter]
    u = np.array(wind["u"])[chosen] / np.maximum(.25, np.cos(np.deg2rad(cells[chosen, 1])))
    v = np.array(wind["v"])[chosen]
    magnitude = np.maximum(.01, np.hypot(u, v))
    ax.imshow(water == 0, extent=(-180, 180, -90, 90), origin="upper", cmap="Greys", vmin=-1, vmax=4)
    ax.quiver(cells[chosen, 0], cells[chosen, 1], u / magnitude, v / magnitude, angles="xy", scale_units="xy", scale=1 / 3, width=.003, color="#2b5871")
    ax.set(xlim=(-20, 150), ylim=(-25, 65), xlabel="Longitude", ylabel="Latitude", title=name)
fig.suptitle("Native reduced seasonal winds | Arrow direction, normalized length", fontsize=12)
fig.savefig(out / "seasonal-winds.png", dpi=160)
