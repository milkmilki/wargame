"""Native v3/v4 weather comparison, using one frozen mesh and a linear rain scale."""
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
RAW = ROOT / ".dbg/atlas-rainfall-v4"
COVER = ROOT / ".dbg/atlas-seasonal-heatmaps"
OUT = ROOT / "docs/atlas/rainfall_v4"
OUT.mkdir(parents=True,exist_ok=True)
meta = json.loads((RAW/"metadata.json").read_text(encoding="utf-8"))
W,H = (int(meta["projection_metadata"][key]) for key in ("width","height"))
font = "C:/Windows/Fonts/msyh.ttc"; font_manager.fontManager.addfont(font)
plt.rcParams.update({"font.family":font_manager.FontProperties(fname=font).get_name(),"font.size":11,
                     "axes.unicode_minus":False,"figure.facecolor":"#fafcfd","axes.edgecolor":"#7a8792"})
def read(folder,name,dtype): return np.fromfile(folder/name,dtype=dtype)
triangles=read(COVER,"triangles.i32","<i4").reshape(-1,3)
tri=read(COVER,"tri.i32","<i4")-1
assert np.all((tri>=0)&(tri<len(triangles)))
wa,wb=(read(COVER,name,"<f4") for name in ("wa.f32","wb.f32")); wc=np.maximum(0,1-wa-wb)
node_land=read(COVER,"node-water.u8","u1")==0
vertices=tuple(triangles[tri,i] for i in range(3)); weights=tuple(w*node_land[v] for w,v in zip((wa,wb,wc),vertices))
denominator=sum(weights)
water=np.frombuffer(gzip.decompress((ROOT/"assets/atlas/earth_water_06m.u8.gz").read_bytes()),dtype="u1").reshape(1800,3600)
ys=np.minimum(1799,((np.arange(H)+.5)*1800/H).astype(int)); xs=np.minimum(3599,((np.arange(W)+.5)*3600/W).astype(int))
land=water[np.ix_(ys,xs)]==0; valid=land.ravel()&(denominator>1e-6)
assert valid.sum()/land.sum()>.98
def project(name):
    values=read(RAW,name+".f32","<f4")
    assert values.shape==node_land.shape and np.isfinite(values).all() and values.min()>=0
    out=np.full(W*H,np.nan,dtype="<f4"); numerator=sum(w*values[v] for w,v in zip(weights,vertices))
    out[valid]=numerator[valid]/denominator[valid]
    return out.reshape(H,W)
rain={side:np.stack([project(f"rain-{side}-{q}") for q in range(4)]) for side in ("before","after")}
climate={side:project("climate-"+side) for side in ("before","after")}
habitat={side:project("habitat-"+side) for side in ("before","after")}
errors={side:float(np.nanmax(abs(rain[side].sum(axis=0)-project("annual-"+side)))) for side in rain}
assert max(errors.values())<.02
longitude=-180+(np.arange(W)+.5)*360/W; latitude=90-(np.arange(H)+.5)*180/H
np.savez_compressed(OUT/"weather_fields.npz",rain_before=rain["before"],rain_after=rain["after"],
                    climate_before=climate["before"],climate_after=climate["after"],
                    habitat_before=habitat["before"],habitat_after=habitat["after"],
                    longitude=longitude,latitude=latitude,land=land,metadata_json=np.array(json.dumps(meta,ensure_ascii=False)))
cmap=plt.get_cmap("YlGnBu").copy(); cmap.set_bad("#e5eaef")
green=plt.get_cmap("RdYlGn").copy(); green.set_bad("#e5eaef")
names=["DJF · 12–2月","MAM · 3–5月","JJA · 6–8月","SON · 9–11月"]
note="四季累计降水估计（含雨雪水当量）· 1°求解网格 → 4096×2048展示插值；高清不增加模拟精度。灰色为水体／无有效数据。"
def draw(ax,field,title,kind="rain",small=True):
    artist=ax.imshow(field,extent=(-180,180,-90,90),origin="upper",cmap=cmap if kind=="rain" else green,
                     vmin=0,vmax=800 if kind=="rain" else 30,interpolation="nearest",aspect="equal")
    ax.contour(longitude[::4],latitude[::4],land[::4,::4].astype("u1"),levels=[.5],colors="#53606b",linewidths=.25,alpha=.7)
    ax.set(xlim=(-180,180),ylim=(-90,90),xticks=np.arange(-180,181,60),yticks=np.arange(-90,91,30))
    ax.grid(color="#53606b",lw=.4,alpha=.25); ax.tick_params(labelsize=8 if small else 10)
    ax.set_title(title,fontsize=13 if small else 18,loc="left",pad=9); return artist
def bar(fig,artist,rectangle,kind="rain"):
    ticks=[0,100,200,400,600,800] if kind=="rain" else [0,5,10,15,20,25,30]
    obj=fig.colorbar(artist,cax=fig.add_axes(rectangle),orientation="horizontal",ticks=ticks,extend="max")
    obj.set_ticks(ticks,labels=[str(x) for x in ticks]); obj.set_label("季度累计降水（毫米）· 线性色标" if kind=="rain" else "最终宜居度",labelpad=5)

for q,season in enumerate(("djf","mam","jja","son")):
    fig=plt.figure(figsize=(20,11.25),dpi=256); ax=fig.add_axes([.055,.15,.89,.74])
    artist=draw(ax,rain["after"][q],names[q],small=False)
    fig.suptitle("真实地球降水修正版｜季节环流 v4 · 种子1",x=.055,y=.98,ha="left",fontsize=21)
    bar(fig,artist,[.21,.095,.58,.021]); fig.text(.055,.022,note,fontsize=9,color="#52616e")
    fig.savefig(OUT/("rain-"+season+".png"),dpi=256); plt.close(fig)
fig,axes=plt.subplots(2,2,figsize=(24,14),dpi=256)
fig.subplots_adjust(left=.04,right=.98,top=.90,bottom=.16,wspace=.06,hspace=.16)
for q,ax in enumerate(axes.flat): artist=draw(ax,rain["after"][q],names[q])
bar(fig,artist,[.25,.085,.50,.022]); fig.suptitle("四季累计降水｜短时锋面与海洋水汽修正版 v4 · 种子1",fontsize=21,y=.965)
fig.text(.04,.025,note,fontsize=10,color="#52616e")
fig.savefig(OUT/"rain-four-seasons.png",dpi=256); fig.savefig(OUT/"rain-four-seasons.pdf",dpi=256); plt.close(fig)
fig,axes=plt.subplots(2,4,figsize=(30,12.5),dpi=256)
fig.subplots_adjust(left=.035,right=.985,top=.90,bottom=.16,wspace=.08,hspace=.18)
for row,side in enumerate(("before","after")):
    for q in range(4): artist=draw(axes[row,q],rain[side][q],("旧v3 · " if row==0 else "新v4 · ")+names[q])
bar(fig,artist,[.25,.07,.50,.02]); fig.suptitle("四季降水修正前后｜相同地形、温度与网格 · 八图共用线性色标",fontsize=21,y=.955)
fig.text(.035,.019,note,fontsize=10,color="#52616e"); fig.savefig(OUT/"rain-before-after.png",dpi=256); plt.close(fig)
fig=plt.figure(figsize=(20,11.25),dpi=256); ax=fig.add_axes([.055,.15,.89,.74])
artist=draw(ax,habitat["after"],"全球陆地 · 真实地球 · 种子1",kind="habitat",small=False)
fig.suptitle("降水修正后的最终宜居度｜沿用四季评分 v4",x=.055,y=.98,ha="left",fontsize=21)
bar(fig,artist,[.21,.095,.58,.021],kind="habitat")
fig.text(.055,.022,"温度、宜居度公式不变；降水改变气候因子和环境供水，仍扣除原有地形成本。\n"+note,fontsize=9,color="#52616e")
fig.savefig(OUT/"habitat-after.png",dpi=256); plt.close(fig)

regions={"CentralPlains":[110,116,32,37],"ChinaSouth":[105,122,22,34],"Europe":[-10,30,45,55],
         "WestSiberia":[60,90,55,65],"EastSiberia":[100,140,55,65],"ArcticSiberia":[100,160,65,72],
         "Congo":[15,30,-5,5],"SoutheastAfrica":[28,40,-25,-10],"Gobi":[95,115,40,47]}
metrics={}
for name,b in regions.items():
    mask=(longitude[None,:]>=b[0])&(longitude[None,:]<=b[1])&(latitude[:,None]>=b[2])&(latitude[:,None]<=b[3])&valid.reshape(H,W)
    area=np.broadcast_to(np.cos(np.deg2rad(latitude))[:,None],mask.shape)[mask]
    row={"bounds_W_E_S_N":b}
    for side in rain:
        row[side+"_quarter_mm"]=np.average(rain[side][:,mask],axis=1,weights=area).tolist()
        row[side+"_climate_mean"]=float(np.average(climate[side][mask],weights=area))
        row[side+"_habitat_mean"]=float(np.average(habitat[side][mask],weights=area))
    metrics[name]=row
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
manifest={"source":meta,"metrics":metrics,"validation":{"quarter_sum_max_errors_mm":errors,"valid_land_fraction":float(valid.sum()/land.sum())},
          "color_scale":"linear 0-800 mm per quarter; above800 darkest; actual values retained in NPZ",
          "plotter_sha256":sha(Path(__file__)),"files":[]}
for path in sorted(OUT.iterdir()):
    if path.suffix not in (".png",".pdf",".npz"): continue
    item={"file":path.name,"bytes":path.stat().st_size,"sha256":sha(path)}
    if path.suffix==".png":
        with Image.open(path) as img: item["pixels"]=list(img.size)
    manifest["files"].append(item)
(OUT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
print("ATLAS_RAIN_V4_PLOTS",json.dumps(metrics),"files=",len(manifest["files"]))
