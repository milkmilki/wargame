# 欧亚横贯场景

在 Godot 打开 `eurasia.tscn`，按 F6 运行当前场景。默认主场景仍为 `main.tscn`。
新场景为真实地形上的随机国家开局，不复原历史罗马、汉朝或真实河道。

## 范围与开局

- WGS84 矩形：西经 12°至东经 136°，北纬 18°至57°；含伊比利亚、罗马、不列颠、地中海、中亚、中国，以及矩形内的北非和印度北部。
- 500 座陆地城市、40 个初始国家；码头另计。每次启动随机生成，并在 DebugRunLog 中记录实际种子、地图源和独立 world_index。
- 城市蒙版和政治蒙版默认留空，完整矩形内的真实陆地可生成聚落。城市密度峰值35°N，南北边缘倍率0.5、0.2。
- 空间倍率2、军旗倍率0.25，隐藏城名、显示国名。沿用程序化单字命名、战争、资源和交通规则。

## 地图源和兼容性

`assets/terrain/eurasia_mercator_map_source.json` 引用独立的
`eurasia_mercator_elevation_white_4096.png`，采用 Web Mercator（EPSG:3857）。
纹理分辨率为4096×4096，显示宽高比为2.8790009154；同等宽度下，比旧等距地图高约31.8%。
RGB 固定白色，Alpha 为数值高程；保留 -8000..0m / 0..6200m 编码和0米海陆分界，采用无损导入。
地形和省份分析仍沿用现有采样与低模流程，不提高省份分析分辨率或改变模拟规则。

主场景新增 `map_source_manifest`、`initial_city_mask_path` 导出属性。
`GameState.map_source_manifest` 是当前世界的地图源，`current_terrain_map_path()` 获取对应纹理；
原静态 `terrain_map_path()` 继续返回中国默认纹理，供旧调用方使用。
生成器和城市密度入口增加末尾可选清单参数，默认值保持中国地图。
地图模板版本仍为6，已有 `map_source_manifest` 字段现在实际参与读入和导出；
版本3至6的旧模板缺少该字段时使用中国源，指定的清单或纹理缺失则返回错误。
编辑重新生成、历史回看、2D和3D渲染均使用世界自身的清单，不修改全局默认源。

清单版本仍为1，新增可选 `projection`，支持 `equirectangular`、`web_mercator`；
缺省为旧等距投影。未知投影或超出墨卡托有效范围的边界会明确报错。
原 `eurasia_map_source.json` 和 `eurasia_elevation_white_4096.png` 保留，
引用它们的旧模板继续以3.79487179宽高比恢复，不迁移城市、省份或河流坐标。

投影定义见 [PROJ Web Mercator](https://proj.org/en/stable/operations/projections/webmerc.html)：
令 `m(φ) = ln(tan(π/4 + φ/2))`，纬度以弧度代入，
`u = (经度 - 西界)/(东界 - 西界)`，
`v = (m(北界) - m(纬度))/(m(北界) - m(南界))`，纵坐标向南递增。
宽高比为经度跨度的弧度值除以投影纬度跨度；地图中点为40.225966°N。
`MapSource.lonlat_to_map(lon, lat, manifest)` 和 `map_to_lonlat(u, v, manifest)`
返回 `PackedFloat64Array`，避免标准 Godot 的单精度 Vector2 降低地理往返精度。
进入游戏位置和渲染时才转为现有 Vector2。

城市密度、城市产出、区域策略和编辑器纬度覆盖均使用当前投影反变换。
编辑器墨卡托纬度限制为±85.0511287798°；中国和旧欧亚仍为±90°。
墨卡托城市间距和省份增长将栅格横向距离乘以
`投影宽高比 × 栅格高度 / 栅格宽度`，保留既有地形代价和省界扰动。
初始生成和移动城市后的重建共用该度量；旧等距源继续使用原生成距离。
墨卡托省份增长堆使用双精度成本，避免成本舍入触发过期节点过滤而留下陆地空洞。
河流从初始省界派生，因此新投影的编辑重建也不将派生河流反向加入增长代价；
同一城市坐标无论是否传入现有河流，省份结果均与初始生成一致。
编辑器墨卡托纬度输入不按小数下界吸附，箭头仍以0.5°调整，保留准确的57°/18°及自定义值。
缓存身份包括实际清单、纹理及投影类型，DebugRunLog 生成参数增加 `projection`。
游戏距离继续沿用平面单位，接受墨卡托高纬度面积放大，不引入公里距离或等面积经济配额。

沿用现有规则：无城市的小岛不分配省份；海峡不会生成非法陆路。
整块孤立陆地由一个国家控制时，可能没有外交邻国；本次不新增跨海航线生成规则。

## 再生成与来源署名

从项目根目录运行：

```powershell
python scripts/tools/generate_china_surface_texture.py --bbox -12 18 136 57 --projection web_mercator --resolution 4096 --elevation-zoom 7 --download-workers 8 --output assets/terrain/eurasia_mercator_elevation_white_4096.png --metadata assets/terrain/eurasia_mercator_elevation_white_4096.json --cache-dir .dbg/elevation_tiles
```

依赖沿用 `scripts/tools/requirements-terrain.txt`。1026张 Terrarium 瓦片（x=59..112，y=39..57）可缓存复用；
下载支持超时和重试，校验完整PNG后才发布缓存文件。运行游戏不需要网络或这些缓存。
高程工具默认仍为等距模式；墨卡托模式均匀采样投影纵坐标，输出元数据记录投影。
重新导入时须保留 `compress/mode=0`、`process/fix_alpha_border=false`、
`process/premult_alpha=false` 和原始Alpha通道，不能将数值高程当透明蒙版处理。

数据来源：[AWS Terrain Tiles](https://registry.opendata.aws/terrain-tiles/)，
许可和署名要求：[Tilezen attribution](https://github.com/tilezen/joerd/blob/master/docs/attribution.md)。
全球 SRTM/GMTED2010 高程来源为 USGS，ETOPO1 来源为 NOAA；欧洲包括 EU-DEM，
使用 Copernicus 和欧盟资助数据。英国 Environment Agency、奥地利开放地形数据、
挪威 Kartverket 等区域来源的版权声明与开放许可应按上述供应商清单保留。
本项目的白色底图与数值打包不包含另行购买的卫星影像或地图绘制素材。

## 验证

```powershell
godot --headless --path . --script res://tests/map_projection.gd
godot --headless --path . --script res://tests/map_source_isolation.gd
godot --headless --path . --script res://tests/eurasia_world.gd
godot --headless --path . --script res://tests/eurasia_scene_smoke.gd
python tests/terrain_surface_tool.py
$env:AI_LONGRUN_MAP_SOURCE = 'res://assets/terrain/eurasia_mercator_map_source.json'
$env:AI_LONGRUN_DAYS = '365'
$env:AI_LONGRUN_SEED = '12345'
godot --headless --path . --script res://tests/ai_longrun.gd
```

四个生成种子为12345、23456、34567、45678。检查陆地城市数、初始国家数、河流和码头、
西欧—中亚—中国的非海运交通、模板读入，以及同一进程中国→旧欧亚→墨卡托欧亚→中国的隔离。
真实场景烟测覆盖移动城市后重建、编辑重新生成、模板读入、历史回看、宽高比和射线拾取；设置 `EURASIA_VISUAL_DIR`
并去掉 `--headless` 可输出全图、地中海、中国三张预览。

年度审计检查领土结构、战斗绑定、继承、AI命令提交、财政和战争生命周期。
中国80国压力脚本额外要求每国至少有一个两跳内外交对象，不能直接将该断言用于包含孤立陆地的欧亚场景。

2026-10-07 墨卡托验收记录：

- 投影正反变换误差不超过1e-6°，北/南边界57°/18°，中点40.225966°。
- Python与Godot在罗马、德黑兰、西安的UV落点一致；这些落点及两处海洋样本的PNG高程Alpha与原始瓦片编码一致。
- 四个种子均500城/40国，码头分别49、62、60、56，河流与非海运交通契约通过；有种子的陆地连通块省份覆盖完整。
- 同进程地图源隔离及旧模板坐标恢复通过；墨卡托初始省份与编辑重建结果完全一致，包含传入派生河流的情况。
- 移动城市的3D验证暴露贸易共享道路的重复网格分配；渲染按道路/颜色样式合并，
  保留各类贸易颜色和受阻虚线，贸易结算与路线不变。1001条相同贸易路线的网格顶点数与单路线一致。
- 修复编辑重建用道路键查询省界键而误关闭合法陆路的已有缺陷；
  通过省界接口检查接壤，保留道路容量和真实陆地路径，不新增跨海连接。中国编辑回归通过。
- 欧亚真实3D场景：城市移动后西欧—中亚—中国通道仍连通，编辑再生成、模板读入、历史回看、相机移动和射线拾取通过；
  全图、地中海、中国预览已输出并检查。DebugRunLog 的四次开局均保留投影、实际seed=12345及独立world_index=1..4。
- 新投影365天审计：14次宣战、112次城池归属变更、85座净攻占；领土结构、战斗绑定、继承、AI命令提交和财政合法性错误均为0。
  资源审计记录正常的粮食短缺事件（4014个缺粮军队日），不是“全年无缺粮”的验收。
  诊断另记录1个残留整合准备，冷却违规和重复绑定均为0；脚本退出码为0。
- 中国原500城场景完成真实3D渲染与2天模拟烟测；纬度密度、区域策略、地形、道路、码头、地图模板、贸易结算及缓存回归通过。

已有回归限制：`ai_500_city_stress.gd` 默认500城/80国/seed=12345/120天
未通过“每国外交两跳对象数大于0”的断言（最少对象数为0）。
在未改动的 `HEAD d9bd18567f92642d00e149ec7e35108f79aff460` 独立副本上复现相同失败：
两者均544总城、1215边、421外交候选对、15贸易节点、105路线，
领土结构错误和AI提交错误均为0。保留该断言及失败证据，没有为了通过验收修改贸易/跨海规则。

## 道路生成性能（2026-10-07）

独立陆地区域的原有 SEA 骨架搜索改为先按距离排除不可能入选的城市对，再检查河流相交；
高程与海陆比例仅对最终选中的连接采样。遍历次序、距离容差、等长选择规则及交通规则保持一致。
不修改 A*、城市选点、道路容量或随机数流，生成缓存版本保持不变。

针对最近用户随机局 seed=2342006650、墨卡托欧亚、500城/40国，
优化前道路阶段约12.07秒，首次优化后约1.49秒；两次输出的24个生成字段逐字节一致。
这是本机 Debug/headless 单次测量，实际启动还包括国家初始化与渲染，不能视作完整启动时间。

新增 `tests/road_generation_equivalence.gd` 与原始穷举搜索对照，覆盖多个独立区域、
河流阻断最短候选、等长候选、已连通/空输入及大量远处河段。可单独启用性能门禁：

```powershell
$env:ROAD_GENERATION_BENCHMARK = '1'
godot --headless --path . --script res://tests/road_generation_equivalence.gd
Remove-Item Env:ROAD_GENERATION_BENCHMARK
```

性能门禁要求压力夹具耗时低于原始搜索的一半；请避免与其他性能测试同时运行。
优化前该门禁失败（83.90ms 对84.24ms）；优化后通过（4.05ms 对83.00ms）。

七组完整生成对照通过：墨卡托欧亚种子2342006650、12345、23456、34567、45678，
以及旧欧亚/中国各seed=12345（均500城/40国）。全部24个生成字段逐字节一致，包含城市、
省份、河流、码头、交通边及路径。对应证据保存在本地 `.dbg/roads_compare.log`。
同一用户种子的完整 `GameState.generate_world` 冷进程复测约12.91秒，优化前约23.10秒；
其中道路阶段复测1.53秒，剩余主要耗时是城市选点。计时不含画面初始化。

优化后回归通过：road_generation_equivalence（含性能门禁）、road_network_runtime、road_province_probe、eurasia_world（四种子500城/40国，省份、河流、码头、欧亚陆路连通）。
