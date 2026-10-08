"""Same-scale before/after rainfall maps for the high-mountain barrier change."""
import argparse
import json
import math
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
from matplotlib import font_manager
import matplotlib.pyplot as plt
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    font_manager.fontManager.addfont("C:/Windows/Fonts/msyh.ttc")
    plt.rcParams["font.family"] = font_manager.FontProperties(fname="C:/Windows/Fonts/msyh.ttc").get_name()
    plt.rcParams["axes.unicode_minus"] = False
    old, new = [json.loads(p.read_text(encoding="utf-8")) for p in (args.before, args.after)]
    assert old["seed"] == new["seed"] and old["map_source"] == new["map_source"]
    for key in ["size", "bbox", "aspect", "heights", "land", "temperature", "winter_temperature", "cold", "flatness", "farmland", "continentality"]:
        assert old[key] == new[key], f"Unrequested input/factor changed: {key}"
    w, h = new["size"]
    land = np.asarray(new["land"], bool).reshape(h, w)
    before = np.asarray(old["rainfall"]).reshape(h, w)
    after = np.asarray(new["rainfall"]).reshape(h, w)
    change = after - before
    aspect = new["aspect"]
    merc = lambda lat: math.asinh(math.tan(math.radians(lat)))
    def xy(lon, lat):
        return (lon + 12) / 148 * aspect, (merc(57) - merc(lat)) / (merc(57) - merc(18))
    regions = [("欧亚全图", (-12, 18, 136, 57)), ("中国及亚洲东南部（南界18°N）", (95, 18, 130, 43))]
    fig, axes = plt.subplots(2, 3, figsize=(22, 12), layout="constrained")
    stats = {}
    grid_x = (np.arange(w) + .5) / w * aspect
    grid_y = (np.arange(h) + .5) / h
    for row, (name, bounds) in enumerate(regions):
        x0, y0 = xy(bounds[0], bounds[3]); x1, y1 = xy(bounds[2], bounds[1])
        mask = land & (grid_x[None, :] >= x0) & (grid_x[None, :] <= x1) & (grid_y[:, None] >= y0) & (grid_y[:, None] <= y1)
        stats[name] = {"before_mean": float(before[mask].mean()), "after_mean": float(after[mask].mean()),
                       "increased_land_fraction": float((change[mask] > 1e-6).mean()), "land_cells": int(mask.sum())}
        for col, (values, title, cmap, limits) in enumerate([
            (before, "修改前 · 低海拔也会阻挡水汽", "YlGnBu", (0, 1)),
            (after, "修改后 · 高山才明显阻挡水汽", "YlGnBu", (0, 1)),
            (change, "变化量 · 绿增雨／棕减雨", "BrBG", (-.5, .5)),
        ]):
            ax = axes[row, col]
            im = ax.imshow(np.ma.masked_where(~land, values), extent=(0, aspect, 1, 0),
                           cmap=cmap, vmin=limits[0], vmax=limits[1], interpolation="nearest")
            ax.set_facecolor("#dae2e9")
            ax.set(xlim=(x0, x1), ylim=(y1, y0), aspect="equal", title=name + "\n" + title)
            ax.set_xticks([]); ax.set_yticks([])
            fig.colorbar(im, ax=ax, fraction=.035, pad=.015)
    fig.suptitle("仅调整山地对降雨的阻挡 · 2500m以下不扣水汽，2500–3500m平滑过渡\n同一地图／256×256分析格／固定色标；降雨为模型相对量", fontsize=16)
    fig.savefig(args.output / "rainfall-before-after.png", dpi=145)
    plt.close(fig)
    (args.output / "rainfall-comparison-stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == "__main__":
    main()
