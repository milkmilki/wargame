"""Render current native seasonal fields, without changing the climate model.

Requires the read-only Godot exporter atlas_export_seasonal_heatmaps.gd.
Interpolation refines the display grid, not the numerical climate resolution.
"""
import gc
import gzip
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.colors as colors
from matplotlib import font_manager
from matplotlib.backends.backend_pdf import PdfPages
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / ".dbg/atlas-seasonal-heatmaps"
OUT = ROOT / "docs/atlas/seasonal_heatmaps"
OUT.mkdir(parents=True, exist_ok=True)
META = json.loads((RAW / "metadata.json").read_text(encoding="utf-8"))
W, H = META["width"], META["height"]
font_path = Path("C:/Windows/Fonts/msyh.ttc")
font_manager.fontManager.addfont(str(font_path))
plt.rcParams.update({"font.family": font_manager.FontProperties(fname=str(font_path)).get_name(),
                     "font.size": 10, "axes.unicode_minus": False,
                     "figure.facecolor": "#fafcfd", "axes.edgecolor": "#7a8792"})

def raw(name, dtype):
    return np.fromfile(RAW / name, dtype=dtype)

triangles = raw("triangles.i32", "<i4").reshape(-1, 3)
tri = raw("tri.i32", "<i4") - 1
assert tri.shape == (W * H,) and np.all((tri >= 0) & (tri < len(triangles)))
wa = raw("wa.f32", "<f4")
wb = raw("wb.f32", "<f4")
wc = np.maximum(0, 1 - wa - wb)
assert np.max(np.abs(wa + wb + wc - 1)) < 1e-5
node_land = raw("node-water.u8", "u1") == 0
a, b, c = (triangles[tri, i] for i in range(3))
weights = (wa * node_land[a], wb * node_land[b], wc * node_land[c])
denominator = sum(weights)

water_path = ROOT / "assets/atlas/earth_water_06m.u8.gz"
water = np.frombuffer(gzip.decompress(water_path.read_bytes()), dtype="u1").reshape(1800, 3600)
ys = np.minimum(1799, ((np.arange(H) + .5) * 1800 / H).astype(int))
xs = np.minimum(3599, ((np.arange(W) + .5) * 3600 / W).astype(int))
land = water[np.ix_(ys, xs)] == 0
valid = land.ravel() & (denominator > 1e-6)
coverage = float(valid.sum() / land.sum())
assert coverage > .98, f"Unexpected loss of land coverage: {coverage}"

def project(values):
    assert values.shape == node_land.shape and np.all(np.isfinite(values))
    result = np.full(W * H, np.nan, dtype="<f4")
    numerator = weights[0] * values[a] + weights[1] * values[b] + weights[2] * values[c]
    result[valid] = numerator[valid] / denominator[valid]
    # Normalized land-only spherical interpolation never mixes ocean zero rain.
    assert np.nanmin(result) >= np.min(values[node_land]) - .01
    assert np.nanmax(result) <= np.max(values[node_land]) + .01
    return result.reshape(H, W)

temperature = np.stack([project(raw(f"temperature-{q}.f32", "<f4")) for q in range(4)])
rain = np.stack([project(raw(f"precipitation-{q}.f32", "<f4")) for q in range(4)])
annual_t = project(raw("annual-temperature.f32", "<f4"))
annual_p = project(raw("annual-precipitation.f32", "<f4"))
temperature_error = float(np.nanmax(np.abs(np.mean(temperature, axis=0) - annual_t)))
rain_error = float(np.nanmax(np.abs(np.sum(rain, axis=0) - annual_p)))
assert temperature_error < 1e-4 and rain_error < .02

longitude = -180 + (np.arange(W) + .5) * 360 / W
latitude = 90 - (np.arange(H) + .5) * 180 / H
np.savez_compressed(OUT / "seasonal_fields.npz", temperature_C=temperature, precipitation_quarter_mm=rain,
                    land=land, longitude=longitude, latitude=latitude,
                    metadata_json=np.array(json.dumps(META, ensure_ascii=False)))

# Downsampled coastline geometry only; fields remain on the full display grid.
coast_land = land[::4, ::4]
coast_lon, coast_lat = longitude[::4], latitude[::4]
season_names = ["DJF · 12–2月", "MAM · 3–5月", "JJA · 6–8月", "SON · 9–11月"]
extent = (-180, 180, -90, 90)
norms = {"temperature": colors.Normalize(-50, 35),
         "rainfall": colors.SymLogNorm(linthresh=20, linscale=1, vmin=0, vmax=3200, base=2)}
cmaps = {"temperature": plt.get_cmap("RdYlBu_r").copy(), "rainfall": plt.get_cmap("YlGnBu").copy()}
for cmap in cmaps.values(): cmap.set_bad("#e5eaef")
titles = {"temperature": "全球陆地四季温度估算", "rainfall": "全球陆地四季累计降雨估计"}
units = {"temperature": "温度（℃）", "rainfall": "季度总量（mm）· 非线性色标"}
fields = {"temperature": temperature, "rainfall": rain}
footnotes = {
    "temperature": "源数据：33940 个球面节点；四季由年均温与纬度振幅推算，非逐季大气温度模拟。\n4096×2048 为球面插值展示网格；灰色为海洋、湖泊或无陆地样本。",
    "rainfall": "源模型：360×180（1°）网格；季度总量＝季节年化降雨率÷4，非观测降水。\n4096×2048 为球面插值展示网格；海洋降雨未计算，灰色不能理解为零雨。"
}

def draw(ax, key, q, small=False):
    artist = ax.imshow(fields[key][q], extent=extent, origin="upper", cmap=cmaps[key],
                       norm=norms[key], interpolation="nearest", aspect="equal")
    ax.contour(coast_lon, coast_lat, coast_land.astype("u1"), levels=[.5], colors="#53606b",
               linewidths=.25 if small else .4, alpha=.7)
    ax.set(xlim=(-180, 180), ylim=(-90, 90), xticks=np.arange(-180, 181, 60), yticks=np.arange(-90, 91, 30))
    ax.grid(color="#53606b", lw=.45, alpha=.24)
    ax.tick_params(labelsize=8 if small else 10)
    ax.set_title(season_names[q], fontsize=13 if small else 18, loc="left", pad=9)
    return artist

files = []
for key in fields:
    ticks = [-50, -30, -10, 0, 10, 20, 30, 35] if key == "temperature" else [0, 20, 50, 100, 200, 400, 800, 1600, 3200]
    for q in range(4):
        fig = plt.figure(figsize=(20, 11.25), dpi=256)
        ax = fig.add_axes([.055, .15, .89, .79])
        artist = draw(ax, key, q)
        fig.suptitle(titles[key] + "｜当前模型 v3 · 种子1", x=.055, y=.98, ha="left", fontsize=20)
        bar = fig.colorbar(artist, cax=fig.add_axes([.21, .095, .58, .021]), orientation="horizontal",
                           ticks=ticks, extend="both" if key == "temperature" else "max")
        bar.set_ticks(ticks, labels=[str(value) for value in ticks])
        bar.set_label(units[key], labelpad=5)
        fig.text(.055, .022, footnotes[key], fontsize=9, color="#52616e", va="bottom")
        name = f"{key}-{META['seasons'][q].lower()}.png"
        fig.savefig(OUT / name, dpi=256)
        plt.close(fig); files.append(name); gc.collect()
    fig, axes = plt.subplots(2, 2, figsize=(24, 14), dpi=256)
    fig.subplots_adjust(left=.04, right=.98, top=.90, bottom=.16, wspace=.06, hspace=.16)
    for q, ax in enumerate(axes.flat): artist = draw(ax, key, q, small=True)
    bar = fig.colorbar(artist, cax=fig.add_axes([.25, .085, .50, .022]), orientation="horizontal", ticks=ticks,
                       extend="both" if key == "temperature" else "max")
    bar.set_ticks(ticks, labels=[str(value) for value in ticks])
    bar.set_label(units[key], labelpad=5)
    fig.suptitle(titles[key] + "｜四季共用同一色标 · 当前模型 v3 · 种子1", fontsize=21, y=.965)
    fig.text(.04, .025, footnotes[key], fontsize=10, color="#52616e", va="bottom")
    name = key + "-four-seasons.png"
    fig.savefig(OUT / name, dpi=256); files.append(name)
    fig.savefig(OUT / (key + "-four-seasons.pdf"), dpi=256)
    plt.close(fig); gc.collect()

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
validation = {"land_sample_coverage_fraction":coverage,
              "max_interpolated_temperature_mean_error_C":temperature_error,
              "max_interpolated_quarter_sum_error_mm":rain_error,
              "all_fields_finite_on_valid_land":bool(np.isfinite(temperature[:, valid.reshape(H,W)]).all() and np.isfinite(rain[:, valid.reshape(H,W)]).all()),
              "all_precipitation_nonnegative":bool(np.nanmin(rain) >= 0)}
manifest = {"source":META,"validation":validation,"coastline":"current Natural Earth 6 arcminute mask; coastline geometry sampled every 4 display pixels",
            "projection_interpolation":"native spherical volumetric triangle weights, land-only normalized; no climate rerun",
            "color_scales":{"temperature_C":[-50,35],"rainfall_quarter_mm":[0,3200],"rainfall_norm":"symlog, linear below 20 mm, logarithmic base 2 above"},
            "temperature_note":"do not interpret as seasonal SST or observed temperature",
            "plotter_sha256":sha(Path(__file__)),"files":[]}
for path in sorted(OUT.iterdir()):
    if path.suffix not in [".png", ".pdf", ".npz"]: continue
    item = {"file":path.name,"bytes":path.stat().st_size,"sha256":sha(path)}
    if path.suffix == ".png":
        with Image.open(path) as img: item["pixels"] = list(img.size)
    manifest["files"].append(item)
(OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
print("ATLAS_SEASONAL_PLOTS", json.dumps(validation), "files=",len(manifest["files"]))
