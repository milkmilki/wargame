"""Visualize controlled radius trials; every panel uses the same seed and river geometry."""
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
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    datasets = [json.loads((args.input/f"fields-{r:03d}.json").read_text(encoding="utf-8")) for r in [40,60,80,120]]
    assert len({d["seed"] for d in datasets}) == 1
    aspect = datasets[0]["aspect"]
    mercator = lambda lat: math.asinh(math.tan(math.radians(lat)))
    def xy(lon, lat):
        return (lon+12)/148*aspect,(mercator(57)-mercator(lat))/(mercator(57)-mercator(18))
    args.output.mkdir(parents=True,exist_ok=True)
    for name,bbox in {"china":(100,26,123,40),"sahara-arabia":(0,18,55,35),"full":(-12,18,136,57)}.items():
        x0,y0=xy(bbox[0],bbox[3]);x1,y1=xy(bbox[2],bbox[1])
        fig,axes=plt.subplots(2,4,figsize=(24,7 if name=="full" else 11),layout="constrained")
        for col,data in enumerate(datasets):
            width,height=data["size"]
            land=np.asarray(data["land"]).reshape(height,width).astype(bool)
            for row,field in enumerate(["water","suitability"]):
                ax=axes[row,col]
                values=np.asarray(data[field]).reshape(height,width)
                im=ax.imshow(np.ma.masked_where(~land,values),extent=(0,aspect,1,0),vmin=0,vmax=1,cmap="YlGnBu" if row==0 else "YlGn",interpolation="nearest")
                for river in data["rivers"]:
                    points=np.asarray(river["points"])
                    ax.plot(points[:,0]*aspect,points[:,1],color="#1273ba",lw=.4,alpha=.65)
                if row==1:
                    points=np.asarray(data["positions"])
                    ax.scatter(points[:,0]*aspect,points[:,1],s=6 if name=="full" else 18,color="#b42120",edgecolors="white",linewidths=.3,zorder=4)
                ax.set(xlim=(x0,x1),ylim=(y1,y0),aspect="equal",title=f"radius {data['radius']:.2f} | {field}")
                ax.set_xticks([]);ax.set_yticks([]);ax.set_facecolor("#dfebf3")
            if name=="china":
                for city,lon,lat in [("Chengdu",104.07,30.67),("Xi'an",108.94,34.34),("Wuhan",114.3,30.59)]:
                    x,y=xy(lon,lat)
                    axes[1,col].plot(x,y,marker="+",color="#252525",ms=7)
                    axes[1,col].annotate(city,(x,y),xytext=(3,5),textcoords="offset points",fontsize=8)
        fig.suptitle(f"{name} | same terrain, rivers, climate, seed {datasets[0]['seed']} | red dots: 500 land cities | '+' reference locations, not generated cities")
        for extension in ["png","svg"]: fig.savefig(args.output/f"radius-{name}.{extension}",dpi=150)
        plt.close(fig)
    print("Rendered radius trials to",args.output)


if __name__=="__main__": main()
