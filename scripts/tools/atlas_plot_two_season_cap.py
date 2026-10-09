"""Plot the native v5/v6 scoring comparison; physical climate inputs stay identical."""
import gzip
import hashlib
import json
import shutil
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / ".dbg/atlas-two-season-cap"
COVER = ROOT / ".dbg/atlas-seasonal-heatmaps"
OUT = ROOT / "docs/atlas/two_season_cap"
OUT.mkdir(parents=True, exist_ok=True)
meta = json.loads((RAW / "metadata.json").read_text(encoding="utf-8"))
W, H = (int(meta["projection_metadata"][key]) for key in ("width", "height"))
font = "C:/Windows/Fonts/msyh.ttc"
font_manager.fontManager.addfont(font)
plt.rcParams.update({"font.family":font_manager.FontProperties(fname=font).get_name(),
                     "font.size":11,"axes.unicode_minus":False,"figure.facecolor":"#fafcfd"})

def read(folder, name, dtype):
    return np.fromfile(folder / name, dtype=dtype)

triangles = read(COVER, "triangles.i32", "<i4").reshape(-1, 3)
tri = read(COVER, "tri.i32", "<i4") - 1
assert np.all((tri >= 0) & (tri < len(triangles)))
wa, wb = (read(COVER, name, "<f4") for name in ("wa.f32", "wb.f32"))
wc = np.maximum(0, 1 - wa - wb)
node_land = read(COVER, "node-water.u8", "u1") == 0
vertices = tuple(triangles[tri, i] for i in range(3))
weights = tuple(w * node_land[v] for w, v in zip((wa, wb, wc), vertices))
denominator = sum(weights)
water = np.frombuffer(gzip.decompress((ROOT / "assets/atlas/earth_water_06m.u8.gz").read_bytes()), dtype="u1").reshape(1800, 3600)
ys = np.minimum(1799, ((np.arange(H) + .5) * 1800 / H).astype(int))
xs = np.minimum(3599, ((np.arange(W) + .5) * 3600 / W).astype(int))
land = water[np.ix_(ys, xs)] == 0
valid = land.ravel() & (denominator > 1e-6)
assert valid.sum() / land.sum() > .98

def project(name):
    values = read(RAW, name + ".f32", "<f4")
    assert values.shape == node_land.shape and np.isfinite(values).all() and values.min() >= 0
    out = np.full(W * H, np.nan, dtype="<f4")
    numerator = sum(w * values[v] for w, v in zip(weights, vertices))
    out[valid] = numerator[valid] / denominator[valid]
    return out.reshape(H, W)

habitat = {side:project("habitat-" + side) for side in ("before", "after")}
climate = {side:project("climate-" + side) for side in ("before", "after")}
longitude = -180 + (np.arange(W) + .5) * 360 / W
latitude = 90 - (np.arange(H) + .5) * 180 / H
with np.load(ROOT / "docs/atlas/rainfall_v5/weather_fields.npz") as previous:
    baseline_error = float(np.nanmax(abs(habitat["before"] - previous["habitat_after"])))
assert baseline_error < 1e-5, baseline_error
np.savez_compressed(OUT / "habitat_fields.npz", habitat_before=habitat["before"],habitat_after=habitat["after"],
                    climate_before=climate["before"],climate_after=climate["after"],longitude=longitude,latitude=latitude,
                    land=land,metadata_json=np.array(json.dumps(meta,ensure_ascii=False)))
cmap = plt.get_cmap("RdYlGn").copy()
cmap.set_bad("#e5eaef")
note = "红色低、绿色高；灰色为水体／无有效数据。固定 0–30 线性色标。4096×2048 展示插值不增加气候模拟精度。"

def draw(ax, field, title, bounds=(-180, 180, -90, 90), tick=60):
    image = ax.imshow(field,extent=(-180,180,-90,90),origin="upper",cmap=cmap,vmin=0,vmax=30,
                      interpolation="nearest",aspect="equal")
    ax.contour(longitude[::4],latitude[::4],land[::4,::4].astype("u1"),levels=[.5],colors="#53606b",linewidths=.3,alpha=.7)
    ax.set(xlim=bounds[:2],ylim=bounds[2:],xticks=np.arange(bounds[0],bounds[1]+.01,tick),
           yticks=np.arange(bounds[2],bounds[3]+.01,30 if tick==60 else tick))
    ax.grid(color="#53606b",lw=.4,alpha=.25)
    ax.tick_params(labelsize=9)
    ax.set_title(title,fontsize=16,loc="left",pad=10)
    return image

def bar(fig, image, rectangle):
    colorbar = fig.colorbar(image,cax=fig.add_axes(rectangle),orientation="horizontal",ticks=[0,5,10,15,20,25,30],extend="max")
    colorbar.set_label("最终宜居度（包含环境供水、海拔与坡度）",labelpad=6)

fig = plt.figure(figsize=(20,11.25),dpi=256)
ax = fig.add_axes([.055,.15,.89,.74])
image = draw(ax,habitat["after"],"真实地球 · 种子1 · 两季封顶 v6")
fig.suptitle("宜居度热力图｜最佳两季累计达到 1.6，气候支撑封顶",x=.055,y=.98,ha="left",fontsize=21)
bar(fig,image,[.21,.095,.58,.021])
fig.text(.055,.025,"仅修改四季评分汇总；温度、降雨、地形保持原样；取消全年普通湿热额外扣分。\n"+note,fontsize=9,color="#52616e")
fig.savefig(OUT / "habitat-after.png",dpi=256)
plt.close(fig)

fig, axes = plt.subplots(2,1,figsize=(20,20),dpi=256)
fig.subplots_adjust(left=.055,right=.965,top=.935,bottom=.12,hspace=.16)
for ax, side in zip(axes,("before","after")):
    image = draw(ax,habitat[side],"修改前 v5：最佳两季＋全年湿热扣分" if side=="before" else "修改后 v6：两季封顶，不追加全年扣分")
fig.suptitle("全球宜居度前后对照｜同一地形、气候、种子与色标",fontsize=22,y=.98)
bar(fig,image,[.21,.064,.58,.014])
fig.text(.055,.025,note,fontsize=10,color="#52616e")
fig.savefig(OUT / "habitat-global-comparison.png",dpi=256)
plt.close(fig)

fig, axes = plt.subplots(1,2,figsize=(20,11),dpi=256)
fig.subplots_adjust(left=.05,right=.975,top=.88,bottom=.16,wspace=.12)
for ax, side in zip(axes,("before","after")):
    image = draw(ax,habitat[side],"修改前 v5" if side=="before" else "修改后 v6",(95,125,18,43),5)
fig.suptitle("中国及周边宜居度｜两季封顶前后对照",fontsize=22,y=.96)
bar(fig,image,[.21,.09,.58,.02])
fig.text(.05,.025,"温度季节相位、秋冬降水偏低等已知偏差仍保留，本图仅比较评分机制。\n"+note,fontsize=9,color="#52616e")
fig.savefig(OUT / "habitat-china-comparison.png",dpi=256)
plt.close(fig)

regions = {"CentralPlains":[110,116,32,37],"ChinaSouth":[105,122,22,34],"SoutheastCoast":[112,122,22,30],
           "Europe":[-10,30,45,55],"Congo":[15,30,-5,5],"SoutheastAfrica":[28,40,-25,-10],
           "CaspianNorth":[46,54,46,50],"CaspianEast":[53,59,38,46]}
metrics = {}
for name,b in regions.items():
    mask = (longitude[None,:]>=b[0]) & (longitude[None,:]<=b[1]) & (latitude[:,None]>=b[2]) & (latitude[:,None]<=b[3]) & valid.reshape(H,W)
    area = np.broadcast_to(np.cos(np.deg2rad(latitude))[:,None],mask.shape)[mask]
    row = {"bounds_W_E_S_N":b}
    for side in ("before","after"):
        row[side+"_habitat_mean"] = float(np.average(habitat[side][mask],weights=area))
        row[side+"_climate_mean"] = float(np.average(climate[side][mask],weights=area))
    metrics[name] = row

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {"source":meta,"metrics":metrics,"validation":{"baseline_projection_error":baseline_error,"valid_land_fraction":float(valid.sum()/land.sum())},
            "color_scale":"linear final habitat 0-30; above30 darkest green; uncapped values retained in NPZ",
            "plotter_sha256":sha(Path(__file__)),"files":[]}
preview_log = ROOT / ".dbg/atlas-two-season-preview.log"
if preview_log.exists():
    lines = preview_log.read_text(encoding="utf-8").splitlines()
    summaries = [json.loads(line.split(" ",1)[1]) for line in lines if line.startswith("ATLAS_TWO_SEASON_PREVIEW ")]
    if summaries:
        assert summaries[-1]["failures"] == 0
        manifest["preview"] = summaries[-1]
        run_paths = [line[len("ATLAS_PREVIEW_LOG "):] for line in lines if line.startswith("ATLAS_PREVIEW_LOG ")]
        if run_paths:
            run_path = Path(run_paths[-1])
            events = [json.loads(line) for line in run_path.read_text(encoding="utf-8").splitlines()]
            ready = [event for event in events if event.get("event")=="ready"][-1]
            assert ready["options"]["settlement_model"] == "climate_capacity_v6"
            manifest["preview"]["ready_event"] = ready
            manifest["preview"]["runtime_log"] = str(run_path)
            shutil.copyfile(run_path,OUT / "preview-run.jsonl")
logs = OUT / "logs"
logs.mkdir(exist_ok=True)
for name in ["atlas-two-season-red.log","atlas-two-season-green.log","atlas-two-season-export.log",
             "atlas-two-season-preview.log","atlas-two-season-preview.err","atlas_two_season_consistency-cap.log",
             "atlas_seasonal_capacity-cap.log","atlas_climate_settlement-cap.log","atlas_climate_limits-cap.log",
             "atlas_climate_v5_consistency-cap.log"]:
    source = ROOT / ".dbg" / name
    if source.exists(): shutil.copyfile(source,logs / name)
for path in sorted(OUT.rglob("*")):
    if path.suffix not in (".png",".npz",".jsonl",".log",".err"): continue
    item = {"file":str(path.relative_to(OUT)).replace("\\","/"),"bytes":path.stat().st_size,"sha256":sha(path)}
    if path.suffix==".png":
        with Image.open(path) as image: item["pixels"] = list(image.size)
    manifest["files"].append(item)
(OUT / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
print("ATLAS_TWO_SEASON_PLOTS",json.dumps(metrics),"files=",len(manifest["files"]))
