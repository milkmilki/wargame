# Atlas 运行期图计算迁移到 C++

## 范围和约束

本轮按已确认的计划优先优化持续推演，迁移威胁行军距离、Atlas 军事最短路、补给损耗场、贸易整数最短路和战略割点/桥梁分析。地形生成、像素栅格、气候、渲染和战争规则不属于本轮改动。

原 civ-atlas 项目也有逐像素重心插值、细节噪声、海岸扰动和群落判定，见锁定提交的 [raster.ts](https://github.com/guaner-334/civ-atlas/blob/103afd3d998eac6750692a6813bf5aea03521448/src/gen/raster.ts#L1-L17)。其 [worker.ts](https://github.com/guaner-334/civ-atlas/blob/103afd3d998eac6750692a6813bf5aea03521448/src/worker.ts#L275-L302) 的 `genMs` 在栅格化之前结束，总 `ms` 在返回主线程之前结束，因此不包含主线程绘制/DOM。本次未找到此前“750 ms”的原始计时记录，不能认定它是哪项指标，也不能直接与我们的 `Raster.build` 13.6 秒作同范围比较；这一启动热点仍待后续单独优化。

GDScript 保留调度、权限判定、缓存生命周期、游戏对象、资源扣账、战争和外交事务。查询内核消费冻结图拓扑、Packed 数组及只读数值字典，返回距离、前驱、来源和连通性结果；字典输入包括权限表和连通性城市价值。批次准备时，C++ 打包器读取 City/Edge 的普通字段，避免逐元素跨越脚本接口；打包发生在状态冻结阶段，不调用脚本方法、游戏规则或随机数，也不修改 GameState。原有后台任务继续负责并行，扩展内不再创建线程池。

要求与原实现逐位一致，包括浮点距离、前驱、Dictionary 插入顺序、随机流、家族/私人继承身份和完整存档快照。不同算法的原有堆规则分别保留；补给额外零距离源按原实现追加，不改变其入堆方式。贸易沿用 int64 距离与 Vector3i int32 堆项的原有截断行为。

Atlas 是生产路径。旧网格军事/补给通行包含有方向的共享码头规则，继续使用其既有 GDScript 实现作为兼容测试；这不是 Atlas 原生加载失败时的回退。

## 原生构建

扩展位于 `native/runtime_graph/`，描述符为 `runtime_graph.gdextension`，类名 `NativeGraphSnapshot`，接口版本 2，拒绝旧版 DLL。当前目标为 Windows x64、Godot 4.7.1、MSVC 14.44.35207。依赖锁记录 godot-cpp 的官方提交和 SCons wheel 校验值，API 从实际引擎导出。编译使用 `/fp:strict`，禁止 fast-math 和 LTO。

在仓库根目录执行：

```powershell
D:\PythonICreate\Python311\python.exe scripts/tools/build_native_compute.py --target both
D:\PythonICreate\Python311\python.exe scripts/tools/build_native_compute.py --target both --verify-only
```

工具、依赖和生成 API 放在扩展的 `.cache/`；编译输出放在 `bin/`。这些文件被 Git 忽略。DLL 旁的 `.build.json` 记录引擎、API、依赖提交、源码和二进制校验值。取得源码后必须先构建扩展，再执行 Godot 编辑器导入，随后运行游戏或测试。

## 后端和错误行为

`scripts/core/native_compute.gd` 统一管理接口。默认使用 `native`；Debug 允许环境变量 `WARGAME_COMPUTE_BACKEND=gdscript/native/compare`，或测试专用的后端切换。`compare` 对两个实现的原始字节进行比较，任何差异都会报错退出。Release 固定使用 `native`，忽略调试后端设置。

入口在地图生成前验证扩展存在和 API 版本。缺少 DLL、引擎/接口不兼容、查询输入无效均显式失败，不静默改用 GDScript。存档格式不变，原生缓存只存在于运行期适配层。

CSR 只缓存静态邻接和几何；道路控辖与边权同批次打包，权限和目标/退出例外使用同一份实时控辖输入。直接修改 `Edge.control_city_id` 后，即使节点/边数和路网版本不变，批次外查询和下一批查询也会观察到变化。已发布批次在已有只读阶段内保持不变，所有工作线程退出后回收。城市地形编辑、世界重置会显式清理几何缓存。

## 验证和复测

基础构建与回归入口：

```powershell
D:\PythonICreate\Python311\python.exe run_tests.py --godot D:\ProjectICreate\Godot_v4.7.1-stable_win64.exe --group all
```

`native_graph_equivalence.gd` 对照每类图算法，覆盖镜像/平局、敌方目标和退出城市、军事/宗藩后勤权限、断路、敌军占路、多源补给、贸易堆截断、割点和桥梁。`native_runtime_equivalence.gd` 对照同一地图逐日完整快照，可传 `--days=365 --seeds=1,7,2024` 或 `--days=720 --seeds=1`，`--sliced` 验证分帧执行。

性能探针只使用真实地球种子 1、初始 40 国、欧亚遮罩：`enabled=true,north=55,south=20,west=-15,east=145`。冻结第 0/330/600 天对象图并核对恢复后的原始状态散列；两个后端从相同文件起跑。每后端独立进程交错运行 5 次，计算时间与 GUI 帧时间分开。记录打包、原生查询、批次总耗时、每日均值/P95、月结算峰值、内存和输入/输出散列。

复测计算基准时，先生成与当前源码一致的冻结输入，再串行运行五对进程；计时期间不要并行运行测试、构建或游戏：

```powershell
& D:\ProjectICreate\Godot_v4.7.1-stable_win64.exe --headless --path . --script res://tests/native_runtime_benchmark.gd -- --capture --stages=0,330,600
D:\PythonICreate\Python311\python.exe tests/native_performance_report.py --godot D:\ProjectICreate\Godot_v4.7.1-stable_win64.exe --iterations 5 --days 30
```

性能驱动退出码 0 表示所有性能目标达成，2 表示计算结果一致但有性能目标未达成，1 表示执行、输入审计或正确性验证失败。

验收目标为迁移批次端到端至少缩短 50%，整日计算平均至少缩短 20%、P95 至少缩短 10%，月结算峰值和内存增加不超过 10%。目标须由实测判断，不用原生内核单项速度替代整日结果。

## 验证证据

计算基准已完成：Intel Core i5-14400F、Godot 4.7.1、同一严格浮点 Debug DLL；5 对交错独立进程，每进程从第 0、330、600 天分别推演 30 天，总计每后端 450 天。每对输入和输出原始状态散列一致；所有进程的引擎、CPU、源码和 DLL 散列相同。计时不含状态散列审计、地图生成和渲染，但包含批次准备、原生调用和结果容器构造。

| 指标 | GDScript | C++ | 缩短 |
| --- | ---: | ---: | ---: |
| 整日平均 | 164.34 ms | 159.98 ms | 2.65% |
| 整日 P95 | 817.06 ms | 728.23 ms | 10.87% |
| 整日 P99 | 1694.18 ms | 1637.38 ms | 3.35% |
| 月结算日峰值 | 1714.60 ms | 1701.25 ms | 0.78% |
| 军事寻路批次 | 23.78 ms | 12.60 ms | 47.00% |
| 补给损耗批次 | 34.17 ms | 18.92 ms | 44.62% |
| 威胁行军批次 | 19.22 ms | 2.14 ms | 88.87% |
| 贸易批次 | 188.21 ms | 5.54 ms | 97.06% |
| 战略连通性批次 | 33.91 ms | 18.52 ms | 45.39% |

Windows 进程峰值工作集从 726,138,880 字节增到 730,333,184 字节（+0.58%）。按 50 ms 采样记录实际进程峰值，包含 C++ 容器；Godot 的静态内存计数仅作为补充。连通性批次的 city_value 是真实调用方预先提供的输入，表内含其后的复制、根排序、图准备、DFS 和结果转换；调用方的准备耗时单独保存。

**未达到的目标**：整日均值缩短 20%，以及军事寻路、补给和连通性批次缩短 50%。P95、月峰值、内存、威胁行军和贸易通过对应性能门槛。性能报告因此明确记录 `performance_targets_met=false`，不能把目标未达成解释为计算结果不同。

整日收益小于独立查询收益，原因是查询在实际推演中存在缓存和调用频率差异。原生后端的阶段计时仍主要落在 AI（约占整日总计时 50%）和月结算（约 20%），月结算中的外交尤其明显；这些是父阶段，不能与其子阶段相加。下一轮应先细分这些实际热点，再决定迁移的数据边界。本轮没有迁移战争规则或扩大到整套 Simulation。

真实渲染窗口也已验证：Forward+ / D3D12 / Radeon RX 7600，1280×720，关闭 VSync，预热 120 帧后以 8 倍速自然分帧推演第 330～360 天。两个后端的初始化和最终完整状态均一致，且最终散列与对应同步计算报告相同。展示的 Simulation.setup 与计算探针的 setup 都会更新家族索引和粮食需求；探针用独立存档副本验证这一初始化过程，没有删除或归一化差异字段。

| 窗口指标（仅一对进程） | GDScript | C++ |
| --- | ---: | ---: |
| 帧间隔平均 | 15.13 ms | 15.35 ms |
| 帧间隔 P95 | 83.13 ms | 83.18 ms |
| 帧间隔 P99 | 113.34 ms | 110.42 ms |
| 日提交间隔平均，含等待和空闲 | 735.53 ms | 726.96 ms |

这一对窗口样本没有显示帧体验改善。不得用纯查询加速推断 FPS 提升，也不得把包含等待的日提交间隔当作纯计算时间。启动、地图显示准备和预热均不在采样窗口中。

机器可读的原始记录在 `.dbg/native-runtime/paired-summary.json` 和 `gui-*-<pid>.json`；精简归档见 [计算五对进程](native_runtime_compute_evidence/compute-five-pairs.json) 和 [真实窗口一对进程](native_runtime_compute_evidence/gui-single-pair.json)。这些终版记录的源码散列为 `d47fd07a19ef707635ead32198a5eec47f1ff06a644c7f8bd4ba5a992f9850ce`，Debug / Release DLL 散列分别为 `68850b08…` / `594cc966…`。修复前的记录另行归档，不计入最终指标。

以上性能、发行包与长程证据对应图计算迁移完成时的源码指纹。后续战斗详情与士气 v7 修改已改变游戏源码；这些历史记录不能作为后续版本的性能测量，当前源码复测必须重新捕获输入。后续规则与回归见 [士气仅用于溃败](morale_rout_only_20261012.md)。

专项检查已通过：图算法 2119 项、冻结批次和并发 500 项、边/所有者/实时控辖打包 298 项、旧世界提交门槛 15 项，以及交通补给在 gdscript/native/compare 三模式下各 18 项。构建元数据 9 项与临时导出配置恢复 5 项通过。边界覆盖包括直接控辖修改、非法控辖、目标/退出例外、写时分离、单节点战略路线、缺失路线/路段、镜像和平局、整数堆截断、私人继承身份和随机流。

原联盟运行夹具只预热 60 天，而正常 AI 的最小中立期为 90 天。夹具改为在 360 天上限内等待真实多国且绑定存活军队的战役，再对连续五个实际分帧日做完整状态对照；两个后端都在第 120 天进入该场景，五天均保持活跃并精确一致。没有降低断言或改变宣战规则。

完整 Windows Release 主场景已通过无错误启动、欧亚地图渲染截图和缺失包内 DLL 的明确失败检查，见 [发行包证据](native_runtime_compute_evidence/full-game-release.json)。该检查使用真实 `atlas_military.tscn` 入口，seed 1、40 国、1192 城市及正确遮罩，在第 0 天暂停；模拟运行证据来自另列的计算、窗口和长程对照。复现命令为：

原生构建不下载 Godot 发行模板。首次导出前，先执行下面的扩展发行契约检查，它会准备并校验官方模板；也可以向导出工具传入 `--release-template`，指定对应版本且散列一致的官方模板。

```powershell
D:\PythonICreate\Python311\python.exe tests/native_extension_contract.py --godot D:\ProjectICreate\Godot_v4.7.1-stable_win64.exe
D:\PythonICreate\Python311\python.exe scripts/tools/export_native_release.py --godot D:\ProjectICreate\Godot_v4.7.1-stable_win64.exe --verify-cache .dbg/wargame-release/inputs/atlas-military-eurasia-mask-9d9ebdaffeb26caac950f7745d96fc6fc2330fad10276789292a6479933f2eb8.bin
```

现有复现日志需要读取原始 `.gd` / `.tscn` 字节，导出工具因此使用文本脚本及临时 `editor/export/convert_text_resources_to_binary=false`，随后逐字节恢复 `project.godot` 并清理临时 preset。它不会覆盖已有导出配置。

最终启动验收复用了同一份已校验的 EXE/PCK/DLL，并改为上述独立只读地图输入快照；执行前后输入 SHA 相同。主场景 PID 28168 无错误，缺 DLL 的 PID 22360 明确退出 1，随后包内 DLL 恢复成功。日常测试使用的开发缓存会被重写，不能用其当前内容替代历史验收输入。精简证据同时记录直接运行现有发行包的命令；上面的导出工具命令会重新导出和验证，需要先前构建的 DLL 与对应构建清单，以及已经保存的输入快照。

正式源码的完整回归已通过：Core 61 项、Atlas 73 项，共 134 项，失败 0；每个进程退出 0，日志无脚本、解析或引擎错误，见 [完整回归证据](native_runtime_compute_evidence/full-regression.json)。两个测试组与长程对照并行执行，只用于正确性验证，其运行时间不作为性能证据。

长程矩阵也全部通过：三个种子（1、7、2024）各推演 365 天，种子 1 推演 720 天，以及种子 1 用真实 `advance_one_day` 分帧推进 30 天。总计 5 次初始和 1845 次逐日完整原始字节比较均一致，包含 schema 28 的权威状态、随机数状态、家族/私人继承身份、外交关系、战争目标和生成元数据，没有删除字段或归一化。每个案例前后源码、测试输入、DLL 和构建清单指纹一致，见 [长程一致性证据](native_runtime_compute_evidence/long-equivalence.json)。

## 后续瓶颈核查

以终版五对进程、每后端 450 天的记录重新聚合，原生后端的四个主要计算阶段如下。月结算耗时是摊到每个模拟日的平均数，实际集中在月末；这四行互不包含，AI 内部的子阶段另列时不能再次相加。

| 阶段 | 每模拟日平均 | 占整日计算时间 |
| --- | ---: | ---: |
| AI | 79.74 ms | 49.85% |
| 月结算 | 32.52 ms | 20.33% |
| 补给 | 21.81 ms | 13.64% |
| 移动与战斗 | 16.39 ms | 10.24% |

五类图查询的原生调用累计为 726.51 ms，约占上述 450 天总计算时间的 1.01%，包含原生返回的 Godot 结果容器构造，但不含输入打包。军事寻路输入准备累计 2454.10 ms，原生调用累计 489.92 ms，前者约为后者的 5 倍。真实推进中贸易原生查询仅调用 10 次；独立批次探针的 97% 加速不能直接代表财政和月结算的收益。

补给阶段整体从 9529.73 ms 变为 9816.45 ms，增加约 3.0%。其中准备阶段从 4342.65 ms 增到 5159.64 ms，而逐军计划从 2494.52 ms 降到 1964.80 ms；因此内核和计划的收益被准备开销抵消。不能用独立补给查询的加速宣称整个补给流程已经加速。

为继续定位，另用忽略目录中的诊断 Simulation 子类包装函数计时，开启已有快照子阶段计时。三个完整探针共做 150 次逐日原始字节对照；每次与独立原执行路径一致，各阶段最终散列也与终版基准一致。生产 GDScript、C++ 和 DLL 未改。两个独立世界同时驻留在诊断进程中，计时包含探针开销，只用于热点归因，不能替代五对独立进程的性能基准。原始报告及最后一版探针源码归档在 [瓶颈分析证据](native_runtime_compute_evidence/bottleneck-analysis.json)。

具体发现如下：

- 联盟规划 `_manage_coalition_campaigns` 在第 600～630 天的最后探针中累计 1809.82 ms、21 次调用，单次峰值 290.95 ms。它在真实分帧路径仍整段同步调用；外层 6 ms 预算不能中断这个函数。最大的子热点是 `_campaign_mobilization_claims`：累计 749.76 ms，占该入口约 41.4%，涉及前线兵力缺口、可用军队筛选、排序和动员预留。成员国 `RegionalStrategy.update_target` 约占 8.4%，并非这里的主体。
- 初期第 30 天的分封提交是月末尖峰的重要来源。90 天探针中，9 次 ENFEOFF 提交累计 1374.76 ms，单次峰值 712.69 ms。源码路径包括 `GameState.enfeoff`、领土事务、宗藩/外交继承以及相关派生量与结构检查；目前只测到整个动作，尚未把这些内部步骤逐项归因，不能断言其中某个检查就是主因。
- 财政预测 `_forecast_trade_and_gold_flows` 在 90 天探针中累计 2490.66 ms，单次峰值 193.32 ms。详细计时显示金流生成、贸易结构/区域路线和输入指纹明显；这一流程还在 GDScript 中，迁移贸易整数最短路没有迁移整个财政预测。
- `_prepare_supply_network_caches` 在 90 天探针中累计 1331.38 ms，3976 次 `_supply_network_fingerprint` 累计 826.59 ms，约占准备阶段 62.1%。即使网络最终命中缓存，逐国访问判定、依赖行拼接和指纹比较仍有成本。
- 战略快照内部的 `_finalize_edge_values` 和 `_select_priority_targets` 分别累计约 415.55 / 412.39 ms，远高于同组的补给走廊约 4.63 ms；图 DFS 的迁移没有覆盖边价值整理与目标选择。

窗口推进还受调度影响。8 倍速只把触发间隔设为 125 ms；一天必须等全部阶段完成，当前默认关闭日内追赶，保留 100 ms 的日后空闲安排，并在多处等待 `process_frame` 或只读后台任务。后台快照是单个串行任务，移出主线程能改善响应，但不会自动缩短计算时间。这解释了为什么不能用同步推进的日耗时直接预测窗口快进速度。已有窗口样本日提交间隔约 727 ms，包含等待和空闲；绘制 CPU、GPU 和具体帧等待尚未分别归因，不能把它与同步计算的差值都归给渲染。

下一轮优先处理联盟动员预留与长同步调用，再处理月末分封/领土事务、财政预测和补给指纹；先减少重复扫描、排序键重复求值及全量派生刷新，再确定需要整批搬到 C++ 的纯计算边界。当前计算基准使用 Debug 构建，发行包只验证过实际入口；Release 的同条件整日性能仍需单独测量。

## 依据

- [Godot GDExtension C++ 示例和构建流程](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/gdextension_cpp_example.html)
- [Godot CPU 优化建议](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)
- [Godot 线程安全 API 约束](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)
