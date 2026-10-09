"""Plot native Godot v4 suitability on the unchanged frozen Earth climate."""
import gzip
import hashlib
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / ".dbg/atlas-seasonal-capacity"
COVER = ROOT / ".dbg/atlas-seasonal-heatmaps"
OUT = ROOT / "docs/atlas/seasonal_capacity"
OUT.mkdir(parents=True, exist_ok=True)
meta = json.loads((RAW / "metadata.json").read_text(encoding="utf-8"))
W, H = (int(meta["projection_metadata"][key]) for key in ("width", "height"))
font_path = "C:/Windows/Fonts/msyh.ttc"
font_manager.fontManager.addfont(font_path)
plt.rcParams.update({"font.family": font_manager.FontProperties(fname=font_path).get_name(),
                     "font.size": 11, "axes.unicode_minus": False,
                     "figure.facecolor": "#fafcfd", "axes.edgecolor": "#7a8792"})

def read(folder, name, dtype):
    return np.fromfile(folder / name, dtype=dtype)

triangles = read(COVER, "triangles.i32", "<i4").reshape(-1, 3)
tri = read(COVER, "tri.i32", "<i4") - 1
assert np.all((tri >= 0) & (tri < len(triangles)))
wa, wb = (read(COVER, name, "<f4") for name in ("wa.f32", "wb.f32"))
wc = np.maximum(0, 1-wa-wb)
node_land = read(COVER, "node-water.u8", "u1") == 0
vertices = tuple(triangles[tri, i] for i in range(3))
weights = tuple(w*node_land[v] for w, v in zip((wa, wb, wc), vertices))
denominator = sum(weights)
water = np.frombuffer(gzip.decompress((ROOT / "assets/atlas/earth_water_06m.u8.gz").read_bytes()), dtype="u1").reshape(1800, 3600)
ys = np.minimum(1799, ((np.arange(H)+.5)*1800/H).astype(int))
xs = np.minimum(3599, ((np.arange(W)+.5)*3600/W).astype(int))
land = water[np.ix_(ys, xs)] == 0
valid = land.ravel() & (denominator > 1e-6)
assert valid.sum()/land.sum() > .98

def project(name):
    values = read(RAW, name+".f32", "<f4")
    assert values.shape == node_land.shape and np.isfinite(values).all() and values.min() >= 0
    result = np.full(W*H, np.nan, dtype="<f4")
    numerator = sum(w*values[v] for w, v in zip(weights, vertices))
    result[valid] = numerator[valid]/denominator[valid]
    assert np.nanmax(result) <= values.max()+1e-5
    return result.reshape(H, W)

fields = {key: project(key) for key in ("climate-before", "climate-after", "habitat-before", "habitat-after")}
quarters = np.stack([project(f"quarter-{q}") for q in range(4)])
assert np.nanmax(fields["climate-after"]) <= 1.000001 and np.nanmax(quarters) <= 1.000001
longitude = -180+(np.arange(W)+.5)*360/W
latitude = 90-(np.arange(H)+.5)*180/H
np.savez_compressed(OUT / "suitability_fields.npz", **{k.replace("-", "_"): v for k,v in fields.items()},
                    quarter_scores=quarters, land=land, longitude=longitude, latitude=latitude,
                    metadata_json=np.array(json.dumps(meta, ensure_ascii=False)))
season_names = ["DJF · 12–2月", "MAM · 3–5月", "JJA · 6–8月", "SON · 9–11月"]
cmap = plt.get_cmap("RdYlGn").copy(); cmap.set_bad("#e5eaef")
footnote = "四季温度与降雨输入不变；原生 Godot 节点评分 → 4096×2048 球面插值。灰色为海洋、湖泊或无有效陆地样本。"

def draw(ax, field, title, climate=True, small=False):
    maximum = 100 if climate else 30
    artist = ax.imshow(field*100 if climate else field, extent=(-180,180,-90,90), origin="upper",
                       cmap=cmap, vmin=0, vmax=maximum, interpolation="nearest", aspect="equal")
    ax.contour(longitude[::4], latitude[::4], land[::4,::4].astype("u1"), levels=[.5], colors="#53606b", linewidths=.25, alpha=.7)
    ax.set(xlim=(-180,180), ylim=(-90,90), xticks=np.arange(-180,181,60), yticks=np.arange(-90,91,30))
    ax.grid(color="#53606b", lw=.45, alpha=.24)
    ax.tick_params(labelsize=8 if small else 10)
    ax.set_title(title, fontsize=13 if small else 18, loc="left", pad=9)
    return artist

def colorbar(fig, artist, rect, climate=True):
    ticks = [0,20,40,60,80,100] if climate else [0,5,10,15,20,25,30]
    bar = fig.colorbar(artist, cax=fig.add_axes(rect), orientation="horizontal", ticks=ticks,
                       extend="neither" if climate else "max")
    bar.set_ticks(ticks, labels=[str(value) for value in ticks])
    bar.set_label("气候适宜度（0–100分）" if climate else "最终宜居度（城市／省份生成所用数值）", labelpad=5)

for key, title in (("climate-after", "全年气候适宜度"), ("habitat-after", "最终宜居度 · 含地形与环境供水")):
    climate = key.startswith("climate")
    fig = plt.figure(figsize=(20,11.25), dpi=256)
    ax = fig.add_axes([.055,.15,.89,.74])
    artist = draw(ax, fields[key], "全球陆地 · 真实地球 · 种子1", climate)
    fig.suptitle(title+"｜四季联合评分 v4", x=.055, y=.98, ha="left", fontsize=21)
    colorbar(fig, artist, [.21,.095,.58,.021], climate)
    description = "每季＝温度分×降雨分；全年＝最高两季平均值的1.5次方。" if climate else "气候限制基础分与供水／海岸加成，再扣除高程和坡度；高分不等于实际历史人口。"
    fig.text(.055,.022,description+"\n"+footnote, fontsize=9, color="#52616e", va="bottom")
    fig.savefig(OUT / (key+".png"),dpi=256); fig.savefig(OUT / (key+".pdf"),dpi=256); plt.close(fig)

for q, season in enumerate(("djf","mam","jja","son")):
    fig = plt.figure(figsize=(20,11.25),dpi=256)
    ax = fig.add_axes([.055,.15,.89,.74])
    artist = draw(ax,quarters[q],season_names[q])
    fig.suptitle("单季气候适宜度｜温度分×同季降雨分 · v4 · 种子1",x=.055,y=.98,ha="left",fontsize=21)
    colorbar(fig,artist,[.21,.095,.58,.021])
    fig.text(.055,.022,"10–20℃、200–800毫米满分；四季共用0–100色标。\n"+footnote,fontsize=9,color="#52616e",va="bottom")
    fig.savefig(OUT / ("quarter-"+season+".png"),dpi=256); plt.close(fig)

fig, axes = plt.subplots(2,2,figsize=(24,14),dpi=256)
fig.subplots_adjust(left=.04,right=.98,top=.90,bottom=.16,wspace=.06,hspace=.16)
for q,ax in enumerate(axes.flat): artist = draw(ax,quarters[q],season_names[q],small=True)
colorbar(fig,artist,[.25,.085,.50,.022])
fig.suptitle("四季联合适宜度｜各季分别评分 · 共用色标 · 种子1",fontsize=21,y=.965)
fig.text(.04,.025,"温度满分10–20℃；季度雨量满分200–800毫米；区间外平滑下降。\n"+footnote,fontsize=10,color="#52616e")
fig.savefig(OUT / "four-seasons.png",dpi=256); plt.close(fig)

fig, axes = plt.subplots(2,2,figsize=(24,14),dpi=256)
fig.subplots_adjust(left=.04,right=.98,top=.90,bottom=.20,wspace=.06,hspace=.40)
for row,kind in enumerate(("climate","habitat")):
    for col,version in enumerate(("before","after")):
        label=("气候适宜度" if row==0 else "最终宜居度")+(" · 旧v3" if col==0 else " · 新v4")
        artist=draw(axes[row,col],fields[f"{kind}-{version}"],label,climate=row==0,small=True)
    colorbar(fig,artist,[.25,.555 if row==0 else .11,.50,.018],climate=row==0)
fig.suptitle("宜居度调整前后｜同一气候输入、地形与供水 · 每行共用色标",fontsize=21,y=.965)
fig.text(.04,.025,footnote,fontsize=10,color="#52616e")
fig.savefig(OUT / "before-after.png",dpi=256); plt.close(fig)

regions={"中原近似范围":[110,116,32,37],"欧洲中纬度近似范围":[-10,30,45,55],
         "刚果盆地近似范围":[15,30,-5,5],"东南亚近似范围":[95,120,-5,20],"非洲东南近似范围":[28,40,-25,-10]}
metrics={}
for name,bounds in regions.items():
    mask=(longitude[None,:]>=bounds[0])&(longitude[None,:]<=bounds[1])&(latitude[:,None]>=bounds[2])&(latitude[:,None]<=bounds[3])&valid.reshape(H,W)
    weight=np.broadcast_to(np.cos(np.deg2rad(latitude))[:,None],mask.shape)[mask]
    metrics[name]={"bounds_W_E_S_N":bounds}
    for key,field in fields.items():
        metrics[name][key+"_mean"]=float(np.average(field[mask],weights=weight))
    metrics[name]["high_climate_fraction_after"]=float(np.average(fields["climate-after"][mask]>=.8,weights=weight))

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
manifest={"source":meta,"metrics":metrics,"land_coverage_fraction":float(valid.sum()/land.sum()),
          "plotter_sha256":sha(Path(__file__)),"projection":"land-only native spherical interpolation of node scores; scoring is NOT applied after climate interpolation","files":[]}
for path in sorted(OUT.iterdir()):
    if path.suffix not in (".png",".pdf",".npz"): continue
    item={"file":path.name,"bytes":path.stat().st_size,"sha256":sha(path)}
    if path.suffix==".png":
        with Image.open(path) as img: item["pixels"]=list(img.size)
    manifest["files"].append(item)
(OUT / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
print("ATLAS_CAPACITY_PLOTS",json.dumps(metrics,ensure_ascii=False),"files=",len(manifest["files"]))
