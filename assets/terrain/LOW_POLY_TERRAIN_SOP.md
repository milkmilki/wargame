# 高程图转 3D 低模地形 SOP

这套流程把高程图当作数值数据，不把高程图的灰度或伪彩色直接显示在地图上。
Godot 在运行时确定性生成低模网格并使用平滑着色，底色来自同坐标表面图或中性陆海色，
体积感完全由网格法线与双灯光产生。

## 1. 准备输入

必需：

- 一张覆盖完整矩形地图的高程图。
- 地图边界 `WEST SOUTH EAST NORTH`，单位为 WGS84 经纬度。
- 高程编码说明：
  - 普通 8/16 位灰度图：使用 `normalized`，并指定黑/白对应的最低、最高米数。
  - 像素值本身就是米数：使用 `meters`，必要时设置 scale/offset。
  - 已是本项目 RGBA 打包源：使用 `packed-alpha --height-channel alpha`。
  该模式缩放时强制最近邻，绝不跨 0 米海岸插值。

可选：

- 当前运行时固定使用白色地形材质，不需要卫星图或手绘底色图。
- 海深渐变由数值高程在 Shader 中生成，不会生成高程伪彩色。

高程图与底色图必须使用同一矩形范围。不要把国界蒙版裁进高程或底色。
海陆分界必须由 0 米决定。

`normalized` 默认按 8 位 `0..255` 或 16 位 `0..65535` 的完整编码范围解释，
不会按单张图片恰好出现的最暗/最亮像素自动拉伸。浮点或特殊编码可额外传入
`--normalized-value-min` 与 `--normalized-value-max` 固定黑白点。
只有陆地高程、没有海底数据时可设 `--elevation-min-m 0`：黑色/零值会编码为
0 米海面（Alpha 128），所有正值编码为陆地。此模式不会凭空生成大陆架。

## 2. 生成运行时地图源

安装依赖：

```bash
python3 -m pip install -r scripts/tools/requirements-terrain.txt
```

灰度高程 + 同坐标底色：

```bash
python3 scripts/tools/prepare_low_poly_map_source.py \
  --heightmap /absolute/path/dem_16bit.png \
  --surface /absolute/path/surface.png \
  --encoding normalized \
  --elevation-min-m -8000 \
  --elevation-max-m 6200 \
  --bbox 73 18 135.5 54 \
  --output assets/terrain/custom_low_poly_map.png \
  --metadata assets/terrain/custom_low_poly_map.json \
  --manifest assets/terrain/map_source.json
```

米制浮点高程：

```bash
python3 scripts/tools/prepare_low_poly_map_source.py \
  --heightmap /absolute/path/dem_meters.tif \
  --encoding meters \
  --bbox WEST SOUTH EAST NORTH \
  --output assets/terrain/custom_low_poly_map.png \
  --metadata assets/terrain/custom_low_poly_map.json \
  --manifest assets/terrain/map_source.json
```

工具输出一张 RGBA PNG：

- RGB：表面图，或中性陆海底色。
- Alpha 1..128：-8000..0 米海底。
- Alpha 129..255：0..6200 米陆地。
- 不包含烘焙 hillshade，不包含高程伪彩色。

把输出放入项目后，Godot 的纹理导入必须保持无损 `Lossless`、Alpha 不重映射、
不启用法线图转换。Alpha 是数值高程，不是普通透明度。仓库当前正式地图源的
`.png.import` 已使用 `compress/mode=0`，新地图第一次导入后也要检查这一项。
更新 `map_source.json` 后重启运行场景，让 Godot 完成纹理导入并刷新地图源缓存。

## 3. 运行时低模转换

`StrategicTerrainRenderer` 会自动：

1. 从 Alpha 解码高程。
2. 采样为 `384 × 按地图宽高比缩放` 的共享顶点低模网格；当前正式地图约为
   `384×221 / 168520` 三角形。政治边界另走曲线与纹理抗锯齿，不靠堆地形面数；
   384 只负责改善真实 0 米海岸、小岛和地形轮廓。高程采样 UV 与网格顶点 UV 完全一致。
3. 将高度量化为 128 级，抑制噪点但不形成明显梯田。
4. 共享低模顶点并计算平滑法线；法线只在同一海陆域内取样，禁止海底高度污染陆地海岸。
5. 用受光 Shader 合成底色和政治覆色；Shader 不再计算高程假阴影。
6. 海底同样属于低模几何；Shader 直接以低模表面高度 `< 0m` 判定无主海洋，
   并以负高度计算浅海/深海色。0 米及以上才允许国家覆色。

这一步不需要离线导出 OBJ/GLB。相同输入与参数生成完全相同的低模，地图替换后
城市、道路、高程与渲染仍共享一个 `map_source.json` 真源。

## 4. 双灯光约定

项目的地图平面在 Godot 中是 XZ，Y 为高度；它等价于需求里的 XY 地图平面、Z 高度。

- `TerrainVerticalPlaneLight`：垂直向下，负责基础可读性，不投影。
- `TerrainNorthwestSculptPlaneLight`：从地图左上向右下，方向严格平行地图平面；
  平地几乎不受它影响，只照亮朝向它的平滑坡面，用来塑造体积。
- 环境光只保留较低能量，防止填平低模明暗。
- 游戏内“地形顶光”和“地形塑形光”滑杆分别调节两盏灯，均不修改高程纹理。顶光最大能量为 `1.5`、默认强度 `0.62`；塑形光最大能量提高到 `2.0`、默认强度 `0.42`，默认画面亮度与旧版基本一致但可调范围更大。
- 双灯只照低模地形专用渲染层，不改变城市、道路、军旗和战斗标记。

## 5. 验收

结构与灯光门禁：

```bash
/Users/bytedance/Godot.app/Contents/MacOS/Godot \
  --headless --path . --script res://tests/terrain_3d_smoke.gd
```

输出全图预览：

```bash
WW_VISUAL_OUTPUT=/tmp/lowpoly-map.png \
WW_VISUAL_WIDTH=1800 WW_VISUAL_HEIGHT=1000 \
/Users/bytedance/Godot.app/Contents/MacOS/Godot \
  --path . --script res://tests/terrain_3d_visual_smoke.gd
```

放大山区检查坡面：

```bash
WW_VISUAL_OUTPUT=/tmp/lowpoly-mountains.png \
WW_VISUAL_WIDTH=1800 WW_VISUAL_HEIGHT=1000 \
WW_VISUAL_ZOOM=0.48 WW_VISUAL_CENTER_X=0.30 WW_VISUAL_CENTER_Y=0.58 \
/Users/bytedance/Godot.app/Contents/MacOS/Godot \
  --path . --script res://tests/terrain_3d_visual_smoke.gd
```

验收重点：海岸线仍贴合 0 米且无白色碎点；山区有连续平滑的体积；平原没有碎面噪声；
政治覆色默认 93%；关闭“地形塑形光”后坡面方向性明暗应明显减弱，调节“地形顶光”只改变基础照明。
海洋作为无主政治区域，与国家颜色使用同一覆色百分比：混合模式不会突然切成
全强度深蓝，100% 政治模式才显示完整海洋色。
政治模式下所有填色都直接落在同一个低模表面；白模、政治色、海洋色不是
额外的平面。省界为常显 1px 暗红实线；国界是两侧各 3px 的本国色实线；海岸沿同一 0m 几何等值线仅向陆侧绘制同款国家色。道路和河流仍按同一低模高度贴地绘制。

导入工具的合成海岸门禁：

```bash
python3 tests/low_poly_map_source_tool.py
```
