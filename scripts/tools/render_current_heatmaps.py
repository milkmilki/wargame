"""Render unfiltered runtime diagnostics; no changes to climate or city weights."""
import argparse
import html
import json
import math
from pathlib import Path
import shutil

import matplotlib
matplotlib.use("Agg")
from matplotlib import font_manager
import matplotlib.pyplot as plt
import numpy as np


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    font = Path("C:/Windows/Fonts/msyh.ttc")
    if font.exists():
        font_manager.fontManager.addfont(str(font))
        plt.rcParams["font.family"] = font_manager.FontProperties(fname=str(font)).get_name()
    plt.rcParams["axes.unicode_minus"] = False
    data = json.loads(args.input.read_text(encoding="utf-8"))
    assert data["projection"] == "web_mercator"
    assert data["river_settlement_model"] == "flow_weighted", "Derived formula below is for the formal flow-weighted model"
    w, h = data["size"]
    land = np.asarray(data["land"], dtype=bool).reshape(h, w)
    fields = {k: np.asarray(v, dtype=float).reshape(h, w) for k, v in data.items()
              if isinstance(v, list) and len(v) == w * h}
    for k, v in fields.items():
        assert np.isfinite(v).all(), k
    fields["heights"] *= 6200
    fields["relief"] *= 6200
    fields["moisture"] = np.clip(fields["rainfed"] + .65 * fields["water"], 0, 1)
    t = np.clip((fields["moisture"] - .10) / .55, 0, 1)
    fields["water_factor"] = (t * t * (3 - 2 * t)) ** 1.5
    reconstructed = fields["cold"] * fields["water_factor"] * fields["flatness"] * (.15 + .85 * fields["farmland"])
    assert np.max(np.abs(reconstructed[land] - fields["suitability"][land])) < 1e-5
    entries = {
        "suitability": ("最终宜居度", "viridis", (0, 1), "高值更适宜；未经视觉平滑"),
        "water": ("河流供水支持", "Blues", (0, 1), "高值支持强；当前按流量加权"),
        "rainfed": ("降雨／蒸发供水比", "YlGnBu", (0, 1), "高值表示本地雨水更能满足蒸发需求"),
        "moisture": ("综合供水", "YlGnBu", (0, 1), "降雨供水＋0.65×河流支持，饱和到1"),
        "water_factor": ("供水对宜居度的保留系数", "viridis", (0, 1), "低值会强烈压低最终宜居度"),
        "cold": ("寒冷限制后的保留系数", "viridis", (0, 1), "1＝不受寒冷抑制；0＝完全抑制"),
        "temperature": ("温度估计", "coolwarm", None, "模型摄氏度；不是实测年均温"),
        "winter_temperature": ("冬季温度估计", "coolwarm", None, "模型摄氏度；包含海拔和内陆效应"),
        "rainfall": ("降雨潜力", "YlGnBu", (0, 1), "模型相对量；不是毫米降水量"),
        "aridity": ("干旱程度", "YlOrBr", (0, 1), "0＝湿润；1＝干旱"),
        "continentality": ("内陆性", "YlOrRd", (0, 1), "高值表示海洋调节较弱"),
        "local_runoff": ("本地产流", "Blues", (0, 1), "模型相对量；不等于河道累计流量"),
        "heights": ("地形高程", "terrain", (0, 6200), "米；分析格采样值"),
        "relief": ("邻域地形起伏", "magma", (0, 3000), "米；3×3分析格最大高差，超过3000同色"),
        "flatness": ("落点平坦度", "YlGn", (0, 1), "高值更平缓；使用原始高程局部采样"),
        "farmland": ("平缓腹地比例", "YlGn", (0, 1), "高值周围可用平地较多；不是现实耕地数据"),
    }
    aspect = data["aspect"]
    west, south, east, north = data["bbox"]
    merc = lambda lat: math.asinh(math.tan(math.radians(lat)))
    def xy(lon, lat):
        return (lon-west)/(east-west)*aspect, (merc(north)-merc(lat))/(merc(north)-merc(south))
    cities = np.asarray(data["positions"])
    assert cities.shape == (500, 2)
    def draw(ax, key, bounds=None, overlay=False):
        title, cmap, limits, note = entries[key]
        values = fields[key]
        if limits is None:
            limits = (math.floor(values[land].min()), math.ceil(values[land].max()))
        im = ax.imshow(np.ma.masked_where(~land, values), extent=(0, aspect, 1, 0),
                       cmap=cmap, vmin=limits[0], vmax=limits[1], interpolation="nearest")
        ax.set_facecolor("#dae2e9")
        if overlay:
            for r in data["rivers"]:
                p = np.asarray(r["points"])
                ax.plot(p[:, 0]*aspect, p[:, 1], lw=.55 if r["class"] == "major" else .22,
                        c="#3996de", alpha=.85)
            ax.scatter(cities[:, 0]*aspect, cities[:, 1], s=10 if bounds else 5,
                       c="#f33a46", edgecolors="white", linewidths=.25, zorder=4)
            title += "＋河网／城市"
            note = "蓝线＝现有河网；红点＝实际生成陆地城市，码头不计"
        b = bounds or data["bbox"]
        x0, y0 = xy(b[0], b[3]); x1, y1 = xy(b[2], b[1])
        ax.set(xlim=(x0, x1), ylim=(y1, y0), aspect="equal")
        lon_step = 20 if bounds is None else (5 if b[2]-b[0] < 40 else 10)
        lons = list(range(math.ceil(b[0]/lon_step)*lon_step, math.floor(b[2]/lon_step)*lon_step+1, lon_step))
        lats = list(range(math.ceil(b[1]/5)*5, math.floor(b[3]/5)*5+1, 5 if bounds else 10))
        ax.set_xticks([xy(v, 0)[0] for v in lons], [f"{v}°" for v in lons])
        ax.set_yticks([xy(0, v)[1] for v in lats], [f"{v}°N" for v in lats])
        ax.tick_params(labelsize=8)
        ax.set_title(title + "\n" + note, fontsize=10, loc="left", pad=9)
        return im
    subtitle = f"正式欧亚 · {data['environment_version']} · flow_weighted · 256×256 · Web Mercator · seed {data['seed']}"
    outputs = []
    def save_board(name, title, keys, bounds=None):
        fig, axes = plt.subplots(3, 2, figsize=(18, 12 if bounds is None else 16), layout="constrained")
        for ax, key in zip(axes.flat, keys):
            overlay = key == "cities"
            im = draw(ax, "suitability" if overlay else key, bounds, overlay)
            fig.colorbar(im, ax=ax, fraction=.026, pad=.018)
        fig.suptitle(title + "\n" + subtitle, fontsize=15)
        fig.savefig(args.output / f"{name}.png", dpi=145)
        plt.close(fig)
        outputs.append((title, f"{name}.png"))
    save_board("01-settlement", "宜居度与供水", ["suitability", "cities", "water", "rainfed", "moisture", "water_factor"])
    save_board("02-climate", "气候与干旱", ["temperature", "winter_temperature", "rainfall", "aridity", "continentality", "local_runoff"])
    save_board("03-terrain", "地形与限制因子", ["heights", "relief", "flatness", "farmland", "cold", "suitability"])
    for name, title, bounds in [("04-china", "中国内陆诊断", (98, 24, 122, 42)),
                                 ("05-africa-arabia", "北非与阿拉伯诊断", (-12, 18, 60, 38))]:
        save_board(name, title, ["cities", "water", "rainfall", "aridity", "cold", "farmland"], bounds)
    for key in entries:
        fig, ax = plt.subplots(figsize=(18, 7), layout="constrained")
        im = draw(ax, key)
        fig.colorbar(im, ax=ax, fraction=.02, pad=.015)
        fig.suptitle(subtitle, fontsize=11)
        fig.savefig(args.output / f"field-{key}.png", dpi=160)
        plt.close(fig)
        outputs.append((entries[key][0], f"field-{key}.png"))
    shutil.copyfile(args.input, args.output / "diagnostics.json")
    sections = "".join(f'<section><h2>{html.escape(title)}</h2><a href="{filename}"><img loading="lazy" src="{filename}" alt="{html.escape(title)}"></a></section>' for title, filename in outputs)
    text = f'''<!doctype html><html lang="zh"><meta charset="utf-8"><title>欧亚环境诊断图</title>
<style>body{{font:16px "Microsoft YaHei",sans-serif;background:#f2f4f6;color:#243343;margin:32px auto;max-width:1500px;padding:0 20px}}img{{width:100%;background:white}}section{{margin:32px 0}}p{{line-height:1.7}}a{{color:#175fa1}}</style>
<h1>欧亚环境诊断图</h1><p>{html.escape(subtitle)}<br>实际来源：{html.escape(data['map_source'])}<br>
当前密度下限配置：{html.escape(str(data['density_bounds']))}（空配置表示未启用2%候选下限）。
环境编号：{data['environment_id']}</p><p>灰蓝色为海面；所有热力图保留分析格，未做插值美化。
各图色标含义不同，请按标题读取；城市是固定种子12345的实际500城开局，并非你正在玩的随机局。
气候和供水为游戏推导值，不是真实观测。点击任意图查看原图。</p>
<a href="diagnostics.json">下载原始数值与配置 JSON</a>{sections}</html>'''
    (args.output / "index.html").write_text(text, encoding="utf-8")
    print(f"Wrote {len(outputs)} maps, index.html and diagnostics.json to {args.output}")


if __name__ == "__main__":
    main()
