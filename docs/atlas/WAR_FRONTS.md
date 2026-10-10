# Atlas 敌国前线

当前军事场景的政治模式直接使用当前国界链：只有两侧都是存活国家、
且 `GameState.is_enemy(left, right)` 为真的共享段替换为前线。
海岸和其他国界保持原样。没有把两国全部边界或地图上的道路当作前线。

原生实现位于 `scripts/atlas/war_fronts.gd`，来源为 civ-atlas
`103afd3d998eac6750692a6813bf5aea03521448` 的
[warfare.ts](https://github.com/guaner-334/civ-atlas/blob/103afd3/src/render/civ/warfare.ts)。
保持原版朱红实线、暖纸衬底、圆角、朝守方的短齿及缩放公式：

| 参数 | 1× 地图单位 |
|---|---:|
| 前线／衬底宽度 | 3.6／8.4 |
| 短齿间距／长度 | 6.5／3.45 |
| 短齿／衬底宽度 | 1.95／5.4 |
| 红色 | `(168, 38, 26, 0.95)` |
| 纸色 | `(250, 242, 222, 0.85)` |

线宽和齿长在 3× 时变为屏幕上的 2×，齿距为 3×。跨经线直接复用连续
展开的边界及横向副本，不再次平滑或偏移国界。

短齿朝向优先使用已有编年史中的原始攻守双方，反攻目标不会翻转方向；
其次使用战争目标的守方。无宣战记录和战争目标的直接敌对关系使用较大
国家编号一侧作为稳定显示方向，此回退不代表实际攻守身份。

宣战、停战、国家存亡及领土版本变化使分类缓存失效；单纯外交变化不
重建边界几何、显示归属或交通图。历史视图使用其已有的外交关系、战争
目标及编年史快照，不读取当前外交。其他地图模式隐藏前线。

## 验证与复现

无窗口回归：

```powershell
python run_tests.py --godot D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe --tests atlas_war_fronts political_history_test atlas_preview_lifecycle atlas_military_persistence atlas_territory_transactions project_compile --timeout 180
```

真实 GPU 验证（独立测试进程，不操作用户正在运行的地图）：

```powershell
$frontProcess = Start-Process D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe -ArgumentList @('--path','D:/ProjectICreate/Wargame/wargame','--script','res://tests/atlas_war_fronts_visual.gd') -WindowStyle Hidden -PassThru
```

可另传 `-- --atlas-cache=res://.dbg/atlas-military-earth.bin` 读取本地原生地球
开发缓存；缓存不随程序交付，无缓存时走正式原生生成入口。
截图和实际 PID、种子、生成参数见 `fronts_evidence/manifest.json`。
测试通过真实界面宣战入口触发敌对，验证和平恢复、历史回看、模式切换、
方向、几何和道路保持；截图包含 1× 全图及 2×、4×、8× 东亚近景。

2026-10-09 验证结果：六项自动回归通过，GPU 集成测试 17 项检查、0 失败；
PID 32116、地球种子 1、40 国，实际测试相邻国家 1 与 36。停战后的 4×
截图与宣战前逐字节相同。进程正常退出，stderr 为空；完整测试输出和
截图 SHA256 记录在 `fronts_evidence/`。

代码图谱已在当前 `feature/civ-atlas-godot`／`f2396b6` 工作树重建，并补入
尚未提交的新增模块：378 个文件、3922 个节点、54745 条边；前线文件
查询可找到 10 个节点。动态图层调用的覆盖以实际测试为准，不以图谱
中的静态“未测试”或未解析调用作为最终判断。

此次只移植前线显示；沿用现有战斗标记，不移植原版占领斜线和双剑。
许可证及来源声明见 `assets/atlas/NOTICE.md`。
