# Godot 原生全球 atlas 预览

独立入口 `res://atlas_preview.tscn`，分支 `feature/civ-atlas-godot`，基线 `9d26b1b1ddbe7736ef62d781c1f01c4c77f8a464`。固定上游为 guaner-334/civ-atlas 的 `103afd3d998eac6750692a6813bf5aea03521448`。许可见 `assets/atlas/NOTICE.md`。

默认完整执行 **GDScript 生成 → Godot 2D／Shader 绘制**，不需要 `.dbg`、Node、TypeScript 或浏览器。正式入口仍为 `main.tscn`，未改欧亚、中国场景及游戏模板，未接军事、贸易、补给或战斗。

## 运行与操作

真实地球输入已另加独立入口 `res://atlas_earth_preview.tscn`，或点击预览中的“真实地球”。参见 [地球实机图与说明](EARTH.md)。地球高程与海陆是真实数据，省份、城市、国家及名称仍由模型生成。

地球默认使用 v5 季节降雨和 v6 两季封顶宜居度：最佳两季联合得分累计达到 1.6 后气候支撑封顶，不再追加全年普通湿热扣分。见 [当前评分与前后热力图](TWO_SEASON_CAP.md)、[降雨 v5 与已知偏差](RAINFALL_V5.md)。“地球降雨”可切回历史版本及原版气候；随机星球保持原版气候与聚落规则。

2026-10-09 检查点保留当前视觉和气候模型，作为下一阶段军事、贸易和统治者系统接入的基础。接入尚未实施；南部非洲偏湿、中国东南季节温度／降雨偏差仍保留，未将它们标记为已修复。

在 Godot 4.7.1 编辑器选择 `atlas_preview.tscn`，按 F6；或在项目目录运行：

```powershell
& 'D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe' --path . atlas_preview.tscn
```

默认种子 1，地块参数 36000，等距圆柱 2048×1024，省份面积参数 750（保留原版内部换算），城市治所宜居度严格大于 1，静态国家目标 40。首次生成约几十秒，UI 显示阶段；绘制冷启动另外计时，未设置性能门槛。

- 种子／重新生成：原生生成随机星球。
- 城市阈值／重建城市道路：只筛选城市并生成陆路，省份保持不变；阈值 50 可检查空城市世界。
- 政治、地形、省份、宜居度，及道路／城市／边界／文字开关；模式切换复用显示几何缓存。
- 滚轮缩放、中键平移、左键详情；横向循环，纵向限制两极。放大上限 8×。
- 选中省份可改属国家，或重置初始归属；仅更新政治显示及国家文字。
- 独立快照 `user://atlas_preview.snapshot` 保留生成参数、模型、完整道路连接、共享段、等级及初始归属；无效加载保留当前世界，不接受对象反序列化。
- 截图隐藏 HUD，由真实图形渲染器保存 `user://atlas-preview-SEED.png`。

原生参数 `--atlas-seed=7`；开发截图参数 `--atlas-capture=绝对路径.png`、`--atlas-labels`、`--atlas-zoom=4`、`--atlas-center=500,420`。截图模式默认关闭城市和文字，以便比较相同输入。关闭窗口会等待生成线程结束，暂不支持中途取消。

## 数据与模块边界

| 层 | 原生模块 |
| --- | --- |
| 数值与球面 | math、simplex、delaunator、sphere_mesh、surface_geometry、chart |
| 随机世界环境 | continents、tectonics、erosion、climate、currents、sea_ice、world |
| 宜居度、省份、静态国家 | habitat、regions、ownership |
| 陆路 | roads：多源城市候选图、Urquhart、A*、已有路折扣、共享段及冗余清理 |
| 派生显示 | raster_cover、tile_noise、raster、ice_pixels、glyph_plan、borders、display_geometry、zoom_geometry |
| 原生绘制 | paint_fields、wash、symbols、ink_strokes、contours、coast_ink、ice_geometry、assets/atlas/*.gdshader |
| 名称与文字 | names、western_names、transcribe、places、polity_labels、text_layout、city_symbols、map_text |
| 管线、交互与保存 | generator、native_map、snapshot、preview |

独立数据包含 mesh、environment、regions、cities、roads、connections、ownership、nations、places。派生 raster 与 display 分开保存；逻辑省份编号只生成一次，显示编号由其派生。填色、边界识别及点击共用平滑边链；放大时 CPU 点击和 GPU 填色查询同源边段。

`roads` 是显示共享段去重后的地块段，`connections` 保留完整城市连接；分链在城市、岔口和等级交界处停止，三轮 Chaikin 固定端点。低宜居度省份有领土但无城市，岔口不创建城市。陆路可以经过中间省份，冰原／湖泊／海洋仍阻挡。

水文只用于环境供水与宜居度，`world.rivers=[]`，无显示河流、划省跨河成本、道路河流成本、码头或航线。国家采用确定性静态预览归属，城市符号等级是预览城市／主要城市／首都，不依赖人口增长或历史。

真实地球预设已通过 EarthSurface 输入替代 world.gd 的板块和侵蚀输出，沿用下游。任意 DEM 文件导入按钮尚未提供；固定地球数据来源与限制见 EARTH.md。

## 证据与复现

见 [验证与差异](VALIDATION.md)、[原版／Godot 对照图](COMPARISON.md)。算法通过与用户视觉验收分开记录。

| 种子 | 地块 | 省份 | 城市 | 去重路段 |
| --- | ---: | ---: | ---: | ---: |
| 1 | 33940 | 867 | 826 | 948 |
| 7 | 34043 | 856 | 809 | 845 |
| 2024 | 33976 | 951 | 907 | 1080 |

三个种子已完成完整原生管线对照和默认入口实机运行；12345、23456、34567 另检查重复生成、连通及空城市。生成日志位于 `user://debug_runs/atlas_preview/atlas-PID-TIME-WORLD_INDEX.jsonl`，记录实际种子、参数、上游完整提交、Godot、本地提交、源码 SHA256 指纹、模型、数量与阶段耗时。日志不消耗随机流；导出程序没有 `.git` 时提交记为 unavailable。

## 开发参考与测试

固定上游源码与锁定依赖放在 `.dbg/civ-atlas-source/civ-atlas-103afd3/`，仅用于开发。大参考文件和原生缓存均在忽略目录，不属于交付依赖。

```powershell
$atlasUpstream = '.dbg/civ-atlas-source/civ-atlas-103afd3'
$atlasOutput = '.dbg/atlas-native-reference'
$atlasTsx = "$atlasUpstream/node_modules/tsx/dist/cli.mjs"
node $atlasTsx scripts/tools/atlas_reference.mts $atlasUpstream $atlasOutput 1 7 2024
node $atlasTsx scripts/tools/atlas_reference_capture.mts $atlasUpstream $atlasOutput 1 7 2024
node $atlasTsx scripts/tools/atlas_environment_reference.mts $atlasUpstream $atlasOutput 1 7 2024
node $atlasTsx scripts/tools/atlas_raster_reference.mts $atlasUpstream $atlasOutput 1 7 2024
node $atlasTsx scripts/tools/atlas_places_reference.mts $atlasUpstream $atlasOutput
node $atlasTsx scripts/tools/atlas_names_reference.mts $atlasUpstream
node $atlasTsx scripts/tools/atlas_labels_reference.mts $atlasUpstream
node $atlasTsx scripts/tools/atlas_zoom_reference.mts $atlasUpstream
node $atlasTsx scripts/tools/atlas_display_cases_reference.mts $atlasUpstream
```

参考世界采用相同城市阈值、河流关闭及静态国家规则。参考绘制使用真实 Chromium Canvas；Godot 截图使用 AMD RX 7600 / OpenGL Compatibility。参考道路绘制年份显式传有限的 0；上游默认 Infinity 会与未停用道路的 Infinity 哨兵相撞，使显示道路为空。

无需上游或大缓存即可运行：atlas_native_compile、math、noise、names、contract、strokes、display_cases。其余逐阶段测试需要开发导出。atlas_native_pipeline 生成 `.dbg/atlas-native-generated-SEED.bin` 后，可运行 coasts、ice_geometry、snapshot 及真实图形的 preview 测试。

Windows 自动测试应等待真实进程，检查结尾 PASS／failures=0，同时扫描 SCRIPT ERROR／SHADER ERROR，不能只看退出码：

```powershell
$atlasRun = Start-Process -FilePath 'D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe' -ArgumentList '--headless --path . --script tests/atlas_native_names.gd --quit-after 3 --log-file .dbg/atlas-names.log' -WindowStyle Hidden -PassThru
$atlasRun.WaitForExit()
Get-Content .dbg/atlas-names.log
```

所有 tests/atlas_native_*.gd 均为独立检查点。真实图形交互用 tests/atlas_native_preview.gd，并传 `--atlas-cache=res://.dbg/atlas-native-generated-1.bin`；它检查快照、改属、阈值重建、几何缓存及开关，并输出四模式、2×／4×／8×、跨经线与极地截图。

视觉确认前不接入现有模拟；本轮未提交、未推送。
