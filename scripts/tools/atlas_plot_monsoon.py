"""Plot exported numeric rainfall fields, not edited renderer screenshots."""
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

root = Path(__file__).resolve().parents[2]
fig, axes = plt.subplots(1, 2, figsize=(12, 4.8), layout="constrained", sharex=True, sharey=True)
for ax, key, title in zip(axes, ("before", "after"), ("Original atlas climate", "Reused seasonal moisture transport")):
    rain = np.fromfile(root / f".dbg/atlas-rain-{key}.f32", dtype="<f4").reshape(1024, 2048)
    water = np.fromfile(root / f".dbg/atlas-rain-{key}.u8", dtype="u1").reshape(1024, 2048)
    rain = np.ma.masked_where(water != 0, rain)
    artist = ax.imshow(rain, extent=(-180, 180, -90, 90), origin="upper", cmap="YlGnBu", vmin=0, vmax=2000)
    cities = np.array(json.loads((root / f".dbg/atlas-rain-{key}-cities.json").read_text()))
    ax.scatter(cities[:, 0], cities[:, 1], s=14, color="#191919", edgecolors="white", linewidths=.4, label="Generated city")
    ax.set(xlim=(95, 145), ylim=(15, 50), title=title, xlabel="Longitude", ylabel="Latitude", facecolor="#e4e4e4")
    ax.legend(loc="lower left", fontsize=8)
fig.colorbar(artist, ax=axes, shrink=.65, label="Effective moisture (mm-equivalent; not observed annual rainfall)")
fig.suptitle("Earth seed 1 | Same terrain, mesh, city threshold > 1 and province area 750", fontsize=12)
fig.savefig(root / "docs/atlas/monsoon/moisture-comparison.png", dpi=180)
