# Atlas 持久绘制与分块缓存

默认由 `atlas_military.tscn` 使用，独立预览共用。运行时全部为 Godot 原生实现。
地图生成、气候、州府、交通路径和军事事务保持原有数据与规则。

## 实现

- 相机输入只改变坐标变换、线条 Shader 参数与可见索引；取消停止操作后140毫秒的同步全量刷新。
- 道路、海岸、国界、州府界和前线使用持久线带。相邻段以最近距离分配重叠区域，避免圆角积色；累计弧长跨块连续。纸色与墨色共享实际网格。
- 地形使用512像素瓦片，按符号和阴影实际范围计算余量。后台生成有序三角形，主线程分批上传，保留森林、树冠和山峰绘制顺序。
- Forward+ 中通过渲染线程复制已解析的GPU像素，缓存裁剪后的内区及1像素采样余量，释放临时视口、多重抗锯齿缓冲和绘制网格。Compatibility 使用像素复制备用路径。
- 细节按约√2间隔及原有阈值分档，5%回滞，120毫秒过渡。图形与罩染遮罩使用同一GPU合成结果。视野外围和相邻档位提前准备；取消已经离开需求范围的排队任务。
- 文字候选和冲突索引在世界坐标中保存。同档移动只处理新候选；首都和高优先级名称可取代低优先级标签。城市标记独立显示，原字体和文字描边保留。
- 政治变化后台准备填色、曲线、点击索引、名称及线条网格，上传完成后按版本发布。道路不因此重建；历史和当前状态分别捕获归属及敌对方向。
- 一个数值计算线程，主线程发布采用4毫秒软预算；单次Godot资源创建不可抢占，分小块执行。任务按可见性排序，过期结果不能覆盖新世界。缓存默认256 MiB，计入纹理、持久网格和文字布局估算；固定概览与正在使用的资源保留。

内部接口集中在渲染协调器、瓦片层和文字层：世界设置、相机设置、分域失效、可见内容就绪。没有修改游戏模板格式或军事接口。

## 验证约定

真实图形测试使用 Godot 4.7.1、D3D12 Forward+、RX 7600、1280×720。
固定输入为原生地球种子1、40国、1796治所、4321交通节点。
开发二进制缓存只跳过生成；绘制、交互和军事层仍走正式实现。

隐藏D3D12窗口在本机开启垂直同步时，空场景也会周期性出现约150毫秒的呈现等待。
性能基准显式关闭同步，单独测量渲染和输入工作；正式场景没有强制改动同步设置。
图形准备、强制绘制/读回、PNG编码分别计时，截图导出时间不计入细节就绪。

测试入口：`atlas_cached_navigation_visual`、`atlas_renderer_updates_visual`、
`atlas_city_markers_visual`、`atlas_tile_copy_visual`，以及 `run_tests.py --group all`。
最终结果、实际PID、代码指纹、配置和截图在 `cached_renderer_evidence/` 中记录。

开发对照开关：`--atlas-legacy-renderer`。截图导出等待当前内容完成，超时明确报错。
首次生成成本不属于本轮优化；缓存预算是派生绘制资源的估算，不等同于整个进程或驱动占用。

## 实测结果与未通过项

2026-10-10，工作树基线 `f2396b6136fb5df653444af2ae4bad0adf8f04ce`，未提交、未推送。
五个独立进程各以500个Godot鼠标拖动／滚轮事件驱动正式场景，共2500帧；
另一个独立进程在模拟运行时执行500个事件，推进12天。PNG编码不纳入就绪耗时。

| PID／状态 | 帧P95 | 帧P99 | 普通细节P95 | 最慢冷区补齐 |
|---|---:|---:|---:|---:|
| 31860／暂停 | 19.149 ms | 20.851 ms | 139.892 ms | 787.113 ms |
| 27100／暂停 | 16.975 ms | 18.627 ms | 143.262 ms | 733.766 ms |
| 11576／暂停 | 17.160 ms | 18.732 ms | 137.215 ms | 803.581 ms |
| 33320／暂停 | 16.892 ms | 18.805 ms | 142.426 ms | 831.495 ms |
| 32880／暂停 | 16.883 ms | 18.707 ms | 135.934 ms | 729.855 ms |
| 25288／运行 | **89.187 ms** | **109.359 ms** | **280.740 ms** | **1583.144 ms** |

暂停五次全部满足帧P95≤25、P99≤50、普通细节P95≤250和冷区≤1000毫秒。
停止后的就绪查询约0.09～0.10毫秒，未出现原来的约615～618毫秒同步重排。
驻留缓存估算约255.33 MiB，五次往返稳定；所有测试的道路与行政数据哈希保持不变。

**模拟运行状态未达到整体验收目标。** 56个超过50毫秒的输入帧中，
39个落在 `ai_view_setup`、12个在 `ai_force_food`、4个在 `ai_force_commit`、
1个在 `movement_battles`。这些是长帧对应的活动阶段，不能视为已精确拆开的纯CPU耗时。
本轮保留军事、AI及日结算法；运行期的帧目标、细节目标和冷区目标均列为未通过，
不能用暂停结果替代。暂停按钮不会取消已在执行的当天模拟，因此运行进程后续拍照时仍可能受其未完成阶段影响。

文字现在采用固定世界锚点，国家名或城市名的取舍可能与旧的视口重排不同；
保留原字体、字号规则、优先级和避让，具体视觉效果仍需用户验收。
新绘制器已默认启用并保留旧绘制器对照开关；不把本轮记录称为完整性能或用户视觉验收通过。

## 正确性与画面记录

综合回归50个独立入口全部通过，包括505断言的共享模拟套件、州府／共享道路、
真实战争事务、模板和历史恢复。新增调度、过期任务、缓存释放、持久网格、
增量排版、经线冲突及城市实例回归通过。

真实GPU检查：易主／外交／历史／四模式进程12784、窗口／待处理任务重载／
完整模板往返进程26576、完整地图城市像素回归进程32904，均退出0且stderr为空。
城市批量实例最初存在空绘制命令未失效的问题；缓冲发布后明确更新CanvasItem命令，
完整视图的163个标记产生38767个可见像素变化，已加入回归。
GPU解析像素复制另验证逐字节一致，并且释放源视口后仍保持图像。

全图、中国、欧洲、海岸、经线、前线、府辖区以及1×／2×／4×／8×画面已实际查看。
截图直接来自Godot，没有后处理。当前检查未发现瓦片接缝、断头道路或符号遮罩位移；
用户视觉确认仍待实际体验。

原基线：[4×中国](navigation_evidence/seed1-china-4x.png)、[8×中国](navigation_evidence/seed1-china-8x.png)。
当前：[4×中国](cached_renderer_evidence/china4.png)、[8×中国](cached_renderer_evidence/china8.png)、
[欧洲](cached_renderer_evidence/europe4.png)、[前线](cached_renderer_evidence/front4.png)、
[地形](cached_renderer_evidence/lifecycle-terrain4.png)、[模板恢复](cached_renderer_evidence/lifecycle-template4.png)。
完整证据索引为 [manifest.json](cached_renderer_evidence/manifest.json)，
性能分布与六次逐帧样本分别为 `performance.json` 和 `run-1.json`～`run-6.json`。

代码图谱已增量更新：409文件、4148节点、57066边，无解析错误。
GDScript动态调用仍有未解析边，源码和实测作为行为依据。Git暂存区为空，没有提交或推送。

## 复现

```powershell
python run_tests.py --godot D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe --group all --timeout 240
```

实机脚本使用 `--script res://tests/atlas_cached_navigation_visual.gd -- --samples=500 --evidence=res://.dbg/render-probe`。
增加 `--simulate` 开启运行阶段测量。无需开发缓存时走原生生成；
已有开发输入可增加 `--atlas-cache=res://.dbg/atlas-military-earth.bin`，只跳过生成。
启动后台Windows检查时使用 `Start-Process -WindowStyle Hidden`。

独立GPU入口还包括 `atlas_renderer_updates_visual`（真实易主／战争／历史）、
`atlas_cached_lifecycle_visual`（1×／2×／四模式／尺寸／重载／模板）、
`atlas_city_glyph_repro`（完整地图图标像素回归）、`atlas_strokes_visual` 与 `atlas_tile_copy_visual`。

## 后续运行期修复

最新默认改为[静态世界图层](STATIC_RENDERER.md)：自然符号、自然名称和城市标记覆盖全球，
拖动、缩放不再补瓦片或排布固定文字；国名在归属变化时单独更新。下述瓦片方案保留为开发对照。

本页保留重构初期记录。静态底图冻结、缓存按事件更新和日结算分批修复的最新结果见
[运行期性能修复](RUNTIME_PERFORMANCE.md)，其模拟运行测量已达到P95／P99帧目标。

## 技术来源

保留 civ-atlas `103afd3d998eac6750692a6813bf5aea03521448` 的绘制算法来源与AGPL声明。
新增缓存、调度和原生网格组织代码不引入浏览器运行时。

- [Godot 缓存绘制命令](https://docs.godotengine.org/en/stable/tutorials/2d/custom_drawing_in_2d.html)
- [线程安全约束](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)
- [CanvasItem Shader](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)
- [RenderingDevice 纹理复制](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html)
- [RenderingServer 渲染线程及纹理接口](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)
