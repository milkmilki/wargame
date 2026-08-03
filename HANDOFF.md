# World-War 项目交接文档

> 面向接手的 AI agent / 开发者。目标：不读全部源码即可理解架构、约定、当前状态与安全改动边界。
> 最后更新：2026-08-02（战斗系统重构完成：item 1-17，见 [COMBAT_REFACTOR_CHANGES.md](COMBAT_REFACTOR_CHANGES.md)）。

---

## 0. 一句话概述

Godot 4.7.1 + GDScript 编写的 **2D 平面战略"看海"游戏**（简化版 EU4，纯观赏、全 AI、实时推进）。
从带 Alpha 的灰度高度图生成 64 城非规则图，4 国各 16 个连续城市，真实地图和平开局；AI 自动选择战争目标、评估储备、求和、宣战、结盟、退盟、寻路、交战与占领，直到一国统一。

---

## 1. 如何运行 / 测试（先做这个）

| 操作 | 命令 |
|---|---|
| Godot 可执行文件 | `/Users/bytedance/Godot.app/Contents/MacOS/Godot`（4.7.1.stable） |
| 运行游戏（图形） | 用 Godot 打开项目按 F5，或 `Godot --path /Users/bytedance/world-war` |
| **回归测试（改代码后必跑）** | `./run_tests.sh`（退出码 0=全过，非0=有失败） |
| 仅编译检查 | `Godot --headless --path <项目> --editor --quit`（无 `SCRIPT ERROR` 即通过） |

`run_tests.sh` 两阶段：①headless 导入捕获脚本错误 ②运行 `tests/test_suite.gd`（当前 **745 断言 / 0 失败**）。
Godot 路径可用环境变量覆盖：`GODOT=/path/to/godot ./run_tests.sh`。
战斗系统重构（item 1-17）另有两项独立验证脚本（不入快速回归以保持 `run_tests.sh` 快）：
`tests/combat_statistics.gd`（item 17 万场统计，verdict=STATISTICS_PASS）、`tests/ai_symmetric_duel.gd`（`AI_DUEL_MODE=balanced-fairness` + `AI_DUEL_RNG_SEED=N` 镜像公平基准）。

游戏内输入（[map_renderer.gd](scripts/view/map_renderer.gd)）：`Space` 暂停/继续、`+/-` 调速、`R` 重开。

---

## 2. 架构：三层 + SSoT

严格分层，**数据流单向**，这是本项目最重要的约定，改动务必遵守：

```
Model（纯数据 RefCounted，无逻辑）
   ├─ City / Edge / Nation / Army
        ↑ 被持有
GameState（SSoT 容器 + 确定性世界生成）
        ↑ 只写
Simulation（Node，实时时钟，**按天推进**全部逻辑；经济/粮草/士气恢复每月结算）
        │ 调用（静态、无状态）
        ├─ Pathfinding（Dijkstra）
        └─ Combat（战斗解算）
        ↓ 只读
View / MapRenderer（Node2D，单一 _draw 数据驱动渲染，绝不写状态）
```

**核心原则（不可违背）**：
- **SSoT（单一数据源）**：所有可变状态归 `GameState` 所有。派生量必须显式标注并由 `refresh_derived()` 重算，禁止第二真源。**时间真源是 `GameState.day`；`month = day / 30` 是派生显示量**。
- **数据/表现分离**：View 只读 GameState 渲染，任何游戏逻辑都不能写在 View。
- **确定性可复现**：所有随机走 `GameState.rng`（固定种子，默认 12345）。禁止用 `randf()` 全局随机、禁止依赖 Dictionary 遍历顺序做逻辑分支——否则破坏 test_suite 的 #7 确定性断言。
- **低熵渲染**：不为每个实体建节点，MapRenderer 用单个 `_draw()` 遍历数据绘制。

---

## 3. 文件清单

| 文件 | 角色 | 关键内容 |
|---|---|---|
| [scripts/model/city.gd](scripts/model/city.gd) | 数据 | 城市控制、地形、产出、粮仓、重点产地；工事强度真源 **`fort_strength`**（城防点量纲，item 6 由旧 `defense` 重命名）；和平确认前冻结直接交战方的 `occupation_sponsor_nation` |
| [scripts/model/edge.gd](scripts/model/edge.gd) | 数据 | `city_a<city_b, max_manpower(0/5000/15000/30000/60000/100000，每国每方向按满编兵力计), distance, danger, max_height_difference, occupied, passing_count(仅供显示的全方向军队数)` |
| [scripts/model/nation.gd](scripts/model/nation.gd) | 数据 | 国家资源、首都粮仓、外交解释字段、战争动员目标及持久战役梯队状态 |
| [scripts/model/army.gd](scripts/model/army.gd) | 数据 | `id, owner_nation, size, max_size(默认15000), attack, defense, location/state/path, on_edge, starving, morale, supply_debt(item10 每日减员整人化累计余额), AI命令元数据`；含占领声明国与防御反向边锁 |
| [scripts/model/battle.gd](scripts/model/battle.gd) | 数据 | 持久多回合战斗：双方/战场/驻防/增援/围城字段 + `tactical_key_a/b` 稳定战术随机键；士气由各 Army.morale 加权派生 |
| [scripts/core/game_state.gd](scripts/core/game_state.gd) | SSoT | 世界生成、粮仓、图查询、战斗、外交、三倍军队数上限与保持兵力/编制守恒的军队拆分 |
| [scripts/core/terrain_map_generator.gd](scripts/core/terrain_map_generator.gd) | 地图生成 | Alpha 陆地提取、平坦城市采样、陆地 Voronoi 省份、Delaunay 局部道路、高度剖面与连通骨架 |
| [scripts/core/pathfinding.gd](scripts/core/pathfinding.gd) | 静态 | 寻路、反向粮仓补给网络；等长路径/同损耗粮仓按势力局部物理序裁决 |
| [scripts/core/equivariant_order.gd](scripts/core/equivariant_order.gd) | 静态 | 镜像等变物理排序 SSoT：城市/军队/势力/边；禁止 ID/创建顺序参与行为决胜 |
| [scripts/core/combat.gd](scripts/core/combat.gd) | 静态 | 战斗解算、纯函数、共享战场骰 + 独立战术修正、结构化日志，见 §4 |
| [scripts/core/combat_log.gd](scripts/core/combat_log.gd) | 静态 | 战斗日志 JSONL 落盘/加载、逐回合确定性回放与篡改检测 |
| [scripts/core/simulation.gd](scripts/core/simulation.gd) | 逻辑 | 按天推进主循环 + `march_days(distance)` 行军时长（R1），见 §5 |
| [scripts/ai/](scripts/ai) | AI | 军事 Utility AI、战略图、威胁场、协调器，以及 `DiplomacyAI` 双边外交评分 |
| [scripts/view/map_renderer.gd](scripts/view/map_renderer.gd) | 渲染 | 只读 `_draw`，绘制省份填色/占领纹理/省界/国境/攻势箭头/城市/边/军队/HUD，处理输入 |
| [scripts/main.gd](scripts/main.gd) | 入口 | 装配 GameState/Simulation/MapRenderer |
| [main.tscn](main.tscn) | 场景 | 默认真实高度图场景（Main + Simulation + MapRenderer） |
| [square_map.tscn](square_map.tscn) | 场景 | 保留的原始 `8×8` 方形地图场景；Main 的 `use_grid_world=true` |
| [tests/test_suite.gd](tests/test_suite.gd) | 测试 | 745 断言，headless 运行 |
| [tests/map_visual_smoke.gd](tests/map_visual_smoke.gd) | 视觉烟测 | 构造占领省份与攻势事件，用 Godot Movie Maker 验证真实渲染路径 |
| [tests/ai_longrun.gd](tests/ai_longrun.gd) | 诊断 | 4 种子 × 1095 天 AI 长跑，检查领土变化、命令覆盖和非法实体 |
| [tests/ai_symmetric_duel.gd](tests/ai_symmetric_duel.gd) | 基准 | 64 城左右镜像；支持 `AI_DUEL_STRICT_MIRROR=1` 逐日全状态物理镜像门禁 |
| [tests/combat_statistics.gd](tests/combat_statistics.gd) | 统计 | item 17 万场：位置对称/独立战术随机无偏/优势胜率/拆分不变/地形单调/种子复现 |
| [run_tests.sh](run_tests.sh) | 测试 | 一键编译+测试封装 |

---

## 4. 战斗系统（[combat.gd](scripts/core/combat.gd) + [battle.gd](scripts/model/battle.gd)）—— EU4 式多回合

**核心变化**：战斗从"瞬时一击解算"改为 **EU4 式多回合掷骰持续战斗**。一场战斗是持久化的 [Battle](scripts/model/battle.gd) 对象，存在 `GameState.battles` 中，**每天（tick）打一个回合**（`Combat.resolve_round`），直到一方兵力归零或士气崩溃。均势会战约 10-13 天。

**统一模型**：野战（`Kind.FIELD`）与攻城（`Kind.SIEGE`）共用回合解算，但 SIEGE 走专用状态机 `_advance_siege`（见 §5）。攻方在城墙 `dist=L`，守军在城中 `dist=0` 且**当 `has_garrison=true` 时**享 `fort_strength` 城防加成。

**支持 N v M（多路打一路）**：`Battle.side_a` / `side_b` 是**军队数组**，同侧恒单一 nation。
- **攻击力（累加）**：`Σ(size×attack)`——所有参战军队火力直接相加。
- **防御力（兵力加权平均质量，不做原始相加）**：`_side_avg_defense` = Σ(size×defense)/Σsize，承伤基数 = 总兵力。**故意不把 defense 原始相加**：否则把一支大军拆成多支反而更耐揍（同兵力、防御总和翻倍）——非物理漏洞。因此"防御累加"的正确语义是**承伤容量随总兵力线性累加、人均减伤质量取加权平均**。此不变量由 [13](c) "防御反拆分"断言固化。
- 行军途中的同 nation 友军抵达同一战斗即 `join`（见 §5），并触发**增援士气**（见 §4.5）。

### 4.1 Battle 对象 与 士气 SSoT

```
Battle { id, kind(FIELD/SIEGE), side_a[], side_b[], edge, city,
         contact_dist_a/b, round_no, siege_progress, has_garrison,
         finished, winner_side }
```
Army 状态：`IDLE / MOVING / FIGHTING / RETREATING / RECOVERING / HOLDING`。`battle_id`（所属战斗，-1=未交战）；`on_edge`（边占用**唯一判据**）；**`morale`（持久士气 ∈[0,1]，真源在此）**；`holding_days` 为边上连续驻防天数。

> **士气 SSoT（第六轮重构）**：士气真源是 `Army.morale`，**持久跨战斗**。Battle 不再存 `morale_a/b`，改为 `side_morale(side)` 兵力加权派生。效果：惨胜残兵带低士气进入下一场 → 更易崩溃（"疲劳"自然涌现）；战斗外每月由 `_recover_morale` 回复（见 §5）。

### 4.2 danger 地形与驻防适应

```
attack_multiplier  = 1 − 0.50 × danger                              (danger < 0.85)
                   = 连续单调降到 0.25 的关隘曲线                    (danger ≥ 0.85，item 9 去断崖)
defense_multiplier = 1 − 0.40 × danger × exp(−holding_days / 30)
```

`danger` 是地形难度唯一持久真源，不存在 `terrain_type/is_pass`。攻击惩罚在 `danger<CHOKEPOINT_DANGER_ONSET(0.85)` 为普通线性；`danger≥0.85` 进入"隘口带"，攻击倍率从 0.85 处的线性值**连续、单调**降到 `danger=1.0` 时的地板 `CHOKEPOINT_ATTACK_FLOOR=0.25`（**item 9：地形参数小幅变化只产生小幅结果变化，无 0.001 跨阈战力减半**）。只有战前处于 `HOLDING` 的防守侧可用驻防时间逐步消除防御惩罚，倍率无限趋近 1 但不超过 1。普通相向遭遇双方 `holding_days=0`。

### 4.3 触发条件（**位置驱动两两交战**，在 Simulation `_detect_encounters` 判定，第七轮重写）

边上每支军队用「以 `edge.city_a` 为原点的归一化位置」`_norm_pos ∈[0,1]`（`move_from==city_a` 时 = `move_progress`，否则 = `1-move_progress`）与方向 `_edge_dir(±1)`。两军**接触** `_edge_contact` 判定：
- **相向**（方向相异）：正向者位置 ≥ 反向者位置 − `CONTACT_EPS` → 接近/交错即触发。
- **同向**（方向相同）：`|posX − posY| ≤ CONTACT_EPS` → 后军追上前军才触发（**修复"同向追逐永不开战"旧 bug**）。
- 相距远且未交错 → **不触发**（这就是需求要的"边内可能不开战"）。

`CONTACT_EPS = 0.15`（归一化单位）。一条边选归一化位置差最小的「敌对且接触」对为交战核心 `new_battle(FIELD)`，其余接触军队按归侧规则加入（见 §5）。**同点必战保证**：`CONTACT_EPS` 是一个正的接触带（不是零点相等），两支异 nation 军队位置完全重合（差=0 ≤ EPS）时必命中接触判定 ⇒ 必触发；[13](f) 断言固化"同点必触发"。
> ⚠️ 旧实现按"从哪端出发"二分 lo/hi，同向军队全落一侧 → `continue` 永不触发；且三方同端出发会被塞进同一 side 并肩敌对。均已被位置驱动逻辑修复。

### 4.4 单回合解算 `resolve_round`

每回合流程（就地修改 Battle 与其中军队）：
1. 双方各掷骰 `0..9`，`fire = Σ(size×attack) × 地形惩罚 × (1 + roll×DICE_STEP)`
2. 伤亡 `loss = 对方火力 / K_ROUND × DEF_REF/(DEF_REF+有效防御)`，按兵力比例摊到各军
3. **士气侵蚀**（`_erode_side_morale` 直接写各 `Army.morale`）：`morale −= 本侧伤亡比×MORALE_CASUALTY_K + MORALE_BASE_DECAY (+ 若本军断粮 MORALE_STARVE_DECAY)`
4. 结束判定：兵力归零 → 歼灭；**侧士气(派生)跌至 0 → 存活部队进入 `RETREATING`**。基础衰减保证战斗必然收敛。

**粮草特色（强化）**：交战军队照常被 `_resolve_supply` 每月扣粮（围城=持续消耗）；此外**断粮军队每回合额外掉 `MORALE_STARVE_DECAY` 士气**（按各军自身断粮状态）。围城掐断粮道 → 守军军心涣散加速崩溃，使粮草成为久战胜负手，而非被动记账。

### 4.5 可调常量（全在 combat.gd 顶部，改这里即可调平衡）

| 常量 | 值 | 含义 |
|---|---|---|
| `K_ROUND` | 120.0 | 单回合伤害除数（越大每回合伤亡越小，战斗越久） |
| `DEF_REF` | 10.0 | 防御减伤参考 |
| `DICE_MIN/MAX` | 0/9 | 每回合掷骰范围（EU4 式） |
| `DICE_STEP` | 0.15 | 每点骰值放大火力比例（满骰 +135%） |
| `MORALE_START` | 1.0 | 初始士气 |
| `MORALE_FLOOR` | 0.0 | 士气跌破此值该方崩溃 |
| `MORALE_CASUALTY_K` | 1.2 | 伤亡比例对士气侵蚀系数 |
| `MORALE_BASE_DECAY` | 0.01 | 每回合基础士气衰减（保证收敛） |
| `MORALE_STARVE_DECAY` | 0.10 | 断粮军队每回合额外士气衰减 |
| `MORALE_RECOVER` | 0.15 | 非交战有粮军队每月士气恢复量（战后疲劳消退，封顶 1.0） |
| `MORALE_REINFORCE` | 0.20 | 增援回气上限系数：新友军加入本侧时，按 `boost = 0.20 × newcomer.morale × (newcomer.size/本侧总兵力)` 提振既有（疲劳）成员士气（`Combat.reinforce_morale`，见 §5）。生力军愈壮、士气愈高 → 回气愈多；封顶 1.0 |
| `MIN_COMBAT_EFFICIENCY` | 0.2 | **item 2** 士气→战力：有效战力 = 名义 × `(0.2 + 0.8×morale)`。满士气=1.0、零士气=0.2（仍能自卫但火力大降） |
| `SIDE_ROUT_THRESHOLD` | 0.15 | 整侧派生士气 ≤ 此值判溃败（兵力归零前合理崩溃） |
| `FRONTAGE_FALLBACK / SIEGE_FRONTAGE` | 15000 | **item 5** 正面宽度：野战正面=道路容量、攻城正面=城墙可展开兵力；超出进预备队（不贡献火力/不受伤亡）；拆分不增总正面 |
| `CHOKEPOINT_DANGER_ONSET` | 0.85 | **item 9** 隘口带起点：`danger≥0.85` 攻击惩罚加速下探（连续，非跳变） |
| `CHOKEPOINT_ATTACK_FLOOR` | 0.25 | **item 9** `danger=1.0` 时攻击倍率地板（隘口最极端处） |
| `SIEGE_PROGRESS_REQUIRED` | 100.0 | 破城所需累积进度（满 100 破城，`siege_progress += siege_daily_progress`） |
| `FORT_MANPOWER_PER_POINT` | 100 | **item 6** 量纲桥：城防点 → 封锁兵力。`siege_required_manpower = fort_strength × 100`，**不含守军人数** |
| `SIEGE_RATIO_STALL` | 0.5 | **item 7** 倒退/推进分界比：`manpower_ratio<0.5` 进度每日倒退（工事修复），`0.5~1.0` 极慢正推进 |
| `SIEGE_DAYS_BASE` | 30.0 | **item 7** 正常围城下限天数（`ratio=1` 时）；`days = 3 + 27/ratio` 单调降 |
| `SIEGE_DAYS_MIN` | 3.0 | **item 7** 饱和进攻(`ratio→∞`)最短围城天数 |
| `SIEGE_DAYS_DECAY` | 27.0 | = `SIEGE_DAYS_BASE − SIEGE_DAYS_MIN`（曲线系数） |
| `SIEGE_REGRESS_PER_DAY` | 0.5 | `ratio<STALL` 时每日进度倒退量（最深，ratio=0 时） |
| `SIEGE_INTERRUPTION_DECAY_PER_DAY` | 0.25 | 守城/解围战每持续一天，既有攻城进度回退 0.25 点，最低为 0 |
| `SIEGE_STARVE_DEF_MULT` | 0.3 | 粮尽守军城防加成衰减系数（`food_storage≤0` 时城防 ×0.3，战力大幅下降） |

> **item 6/7 围城连续曲线（本轮替换旧 5× 硬门槛 + `garrison_ref` 掷骰模型）**：`manpower_ratio = 攻方有效兵力 / siege_required_manpower(fort_strength)`，其中 `siege_required_manpower = fort_strength × FORT_MANPOWER_PER_POINT`（**唯一量纲桥、不含守军人数** —— 守军是城下决斗阶段的对手，被歼后封锁需求不变，item 6 验收）。围城天数 `days = clamp(3 + 27/ratio, 3, 30)`：`ratio<0.5` 进度倒退、`0.5~1` 极慢、`ratio=1→30 天`、`2→16.5`、`4→9.75`、`→∞→3`。**无 5× 跳变、大兵力收益递减、与守军人数解耦**。旧 `SIEGE_RATIO_MIN=5 / SIEGE_DAYS_BASE=90 / SIEGE_DECAY_K=435 / garrison_ref` 已移除。

> 调参依据：`K_ROUND=120, MORALE_CASUALTY_K=1.2` 下，均势会战约 10-13 天、优势方约 5-7 天（战斗常量在天/月分层后**零改动**，因每天一回合恰好把原"月级回合"落到"天级"，会战时长更贴合真实）。

### 4.6 第十二轮平衡规格 R1-R4（本轮新增，需求 SSoT）

| 规格 | 规则 | 落地 |
|---|---|---|
| **R1 行军时间** | 任意长度道路 **最短 10 天、最长 30 天**，按长度线性插值 | `Simulation.march_days(distance) = clamp(10 + (distance−1)×5, 10, 30)`；distance∈[1,5]→[10,30] 天；每天推进 `1/march_days`。**副作用：speed_factor 与 danger 不再影响行军时长**（speed_factor 成行军侧死字段；danger 仍用于战斗地形惩罚 + 寻路边权） |
| **R2 围城** | ⚠️ **已被 item 6/7 取代**（见 §4.5）：旧"≥5×守方基准、基准 90 天"硬门槛已废，改为连续曲线 `manpower_ratio = 攻方兵力 / (fort_strength×100)`、`days = clamp(3+27/ratio, 3, 30)` | `Combat.siege_required_manpower` + `siege_daily_progress` + `Simulation._withdraw_failed_siege` |
| **R3 粮草** | 被围城市切断外部补给；只有城市本身设有粮仓时可继续消耗本地库存，粮尽后战力大幅下降 | 当前每国仅首都有粮仓；`Simulation._drain_siege_food()` 每天扣被围粮仓库存；普通城市无本地库存，被围即断供；粮尽 → 守军城防 ×`SIEGE_STARVE_DEF_MULT=0.3` |
| **R4 空城弱攻退避** | 攻空城时**兵力 < 破城所需兵力**（`fort_strength×100`）则不建围城、不占城，**自动向友方城撤离** | `Simulation._start_or_join_siege`：`defender==null and attacker.size < siege_required_manpower` → `_retreat_to_friendly`（`Pathfinding.nearest_friendly_city` 仅沿本国城市找最近本国城，无合法通道则溃散） |

> **用户两个架构拍板**：① 围城模型保留"守军实战"（有守军先打实战、歼灭后转纯围城递减），非改为 EU4 纯被动围城；② 断粮结局是"战力大幅下降"（城防 ×0.3 + 断粮士气加速崩溃），非"粮尽即投降破城"。
> **R4 触发频率提示**：world-gen `fort_strength∈[10,30]`（破城所需兵力 = ×100 = 1000~3000）相对攻方兵力(size∈[500,1500])，故 R4 在默认参数下作边界护栏存在（测试用大 `fort_strength` 人工构造触发场景验证）。

### 4.7 第十三轮：士气崩溃撤退与驻城恢复

1. **撤退触发**：战斗结束时，败方所有存活军队进入 `RETREATING`；若双方同时崩溃，士气为 0 的名义胜方同样撤退，不得继续追击。
2. **最近友城**：边上溃败时，从真实 `move_progress` 分别计算到道路两端的剩余距离，再叠加端点到各友城的 Dijkstra 距离，选择全局最短路线。起点允许是刚失守的敌城，但离开起点后的路径只能经过本国城市，禁止穿越敌城。撤退途中不受 AI 指令，但可被普通 `MOVING` 敌军被动接战；两支 `RETREATING` 军不会互相主动开战。`forced_retreat` 在被动战斗中保留，获胜后继续原撤退路线。目的地失守时重新寻路，无可达友城则溃散。
3. **驻城恢复**：抵达目标友城后转 `RECOVERING`。该状态计入驻城守军，但 AI 不得调动；视图用稳定蓝圈标识。
4. **恢复资源**：每 30 天恢复至多 `MORALE_RECOVER=0.15`；从损耗最低的可达粮仓取粮，完整恢复月基础需求为 `ceil(size × RECOVERY_FOOD_PER_CAPITA)`，再计运输损耗。`RECOVERING` 不进入普通 `_resolve_supply`，避免双扣。
5. **解除条件**：士气回满，或无可达有粮粮仓，转 `IDLE`；后者保留尚未恢复满的士气。城市易主时，城内所有旧城主 `IDLE/RECOVERING` 驻军立即重新撤退，禁止滞留敌城。
6. **断粮联动**：自由态军队每月按补给缺口比例损失士气：`morale_loss = SUPPLY_MORALE_LOSS_MAX(0.20) × shortfall/demand`。士气从正值跌至 0 时立即触发溃逃；交战军仍由当日战斗结算触发撤退。

### 4.8 第十五轮：边上驻防、补给与地形适应

- **边上部署**：新增 `HOLDING`。军队从己方端点出发后固定在边进度 `0.35`，双方物理位置分别为 `0.35/0.65`，保持 `on_edge=true` 并占用 capacity。和平时可在同边对峙而不重叠；宣战本身不触发战斗，只有一方主动推进至接触距离才进入 FIELD。
- **适应累计**：满补给每天 `holding_days+1`；部分补给暂停；完全断粮每天 `−2`。换边、主动移动或撤退清零。
- **增援稀释**：驻防侧战斗快照保存兵力加权驻防天数；非驻防增援加入时按 `old_days×old_size/new_total` 稀释。
- **双端点补给**：边上军队按真实 `move_progress` 比较到两个端点的剩余距离，只要端点属于本国，就可从该端点接入补给网络；当前所在边出现敌军不会直接断供。端点之后的补给路径仍只能经过本国城市，且不能通过有敌军争夺的其他道路。
- **AI**：驻防边由 Utility AI 综合 `danger`、边战略价值、补给走廊、桥影响与局部威胁评分；同国同方向可部署多支军队，唯一上限是满编兵力容量。军队抵达驻防点后持续保持 `HOLDING`，不设时间上限。
- **视觉**：道路按 `max_manpower=5000/15000/30000/60000/100000` 映射为四档宽度和亮度；十万人平原大道只占约 5%。`0` 容量边完全隐藏，`danger` 继续叠加红色风险色。

### 4.9 无训练分层 Utility AI

- **只读边界**：`AiWorldView` 当前提供全知视野；决策层不直接遍历/修改 `GameState`，未来战争迷雾只替换视图筛选。
- **战略图**：城市价值综合首都、粮仓、经济、粮食与城防；Tarjan DFS 识别本国桥和割点；粮仓到前线的路径流量参与边价值。`ownership_revision` 变化时才失效重算。
- **两层进攻规划**：对敌方边境城模拟占领后的友边/敌边变化、二跳门户价值及敌方首都网络失联价值，选出国家级 `campaign_target`。图论结果是有界先验：普通价值修正最多 `±0.5`，仅多方向进攻或占领后不增加暴露时再加 `1.0` 主战役分，不能覆盖战力、补给和单军生存门槛。
- **威胁场**：军队按城市聚合，以 60 天为窗口传播；`power=size×质量×士气×补给`，贡献按 `exp(-arrival_days/30)` 衰减。
- **候选行动**：`HOLD/REINFORCE/MERGE/ATTACK/RETREAT` 同时评分，固定同分 ID 决胜。进攻只选当前敌方边境城，避免评分纵深目标但实际先撞边境城。
- **协调与滞回**：友军支援不使用可在多前线重复计数的威胁场，而由 `ArmyCoordinator` 一军一目标真实预留；前线军先决策，同层级按有效战力降序让主力先确定攻势，小军随后补位；内线小军先在后方合并，单军能填补至少 50% 缺口才直接增援。命令记录 `target/score/reason/created_day/until_day`。
- **合并守恒**：每日合并同城同状态军队及同位置驻防军；兵力求和，攻击/防御/士气/补给/驻防天数按兵力加权，边容量同步释放。
- **驻防出击**：`HOLDING` 没有时间上限；只有士气、补给、局部战力和 5× 围城兵力（另留 1.5 倍战损余量）同时满足时，AI 才显式下达 `ATTACK`，从当前边位置连续推进。
- **驻边滞回**：城市出发驻边要求局部支援/威胁比达到 `0.60×性格系数`，边上撤退仍使用 `0.40×性格系数`。明确的准入/退出滞回带防止同一军队在城市和己方侧驻防点之间反复横跳。
- **同边敌军估值**：远方威胁可按抵达时间衰减，但同一条边上的敌军是下一场直接接战对象，必须按 `100%` 有效战力计入。驻防军出击使用“折扣威胁场”和“同边敌军实值”的较大者，避免未满编军误攻满编驻防军。
- **单军生存门槛**：联合兵力池决定整个攻势能否成立，但每支正常进攻参与军自身有效战力还必须达到目标局部敌军战力的 `35%`。这阻止几百人残部借用纸面联合战力分批冲锋；真正被围断粮军仍使用独立的 `0.70` 背水突围门槛。
- **多方向协同**：敌城相邻正容量边上的实际友军按来源邻城计为独立方向，联合兵力达到围城/战力门槛后才进攻。最慢方向先出发，较快方向等待到预计抵达时间差不超过 5 天，避免“同日下令、分批送死”。
- **断粮突围与解围**：补给率 `≤25%` 且无法经本国控制网抵达粮仓才算真正被围；突围优先级高于普通动作，但只攻击战力比 `≥0.70` 的最弱包围节点。被围城和断粮友军形成紧急救援缺口，相邻敌城作为打通通道的高价值目标。
- **建军/解散**：AI 国家级命令 `CREATE_ARMY/DISBAND_ARMY`。军队数低于 `max(前线数+2, ceil(城市数/4))` 时在未被围首都粮仓消耗 5000 人建军；仅在军队数超额时解散安全后方 `<500` 人残部，幸存人数全额返还人口库。
- **后勤中心守备**：没有敌方正容量道路直接接入时，首都只保留最低 5000、其他粮仓最低 3000，不再把两跳外的 60 日传播威胁全部折算为常驻军；敌军直接邻接后恢复首都=`max(5000, 60日威胁×1.25)`、粮仓=`max(3000, 60日威胁)`。抽走某军会跌破门槛时拒绝普通移动。
- **归一化防区**：一线为实际/潜在前线，二线为可及时回援的一线邻城。城市重要度=`城市价值×(1+粮道重要度)`，危险度取本地威胁与按行军时间衰减的一线威胁最大值；两者归一化后以几何平均合成权重。国家防御预算为 `P×T/(P+T)`，和平潜在威胁以全国战力封顶。多余兵力按“实际覆盖/目标战力”饱和度展开，使用 25% 滞回与移动后 110% 来源安全线，不做一城一军或固定国家防守比例。
- **稳定任务所有权**：攻势集结只能抽调 `CityDefensePlan.can_redeploy()` 判定的防线剩余兵力，不能覆盖有效防御部署锁。跨城合并按 `EquivariantOrder` 势力局部物理序确定唯一接收方向，使目标图严格无环且不依赖军队 ID；满编目标没有完整容量时不生成无效合并。
- **性能缓存**：`AiWorldView` 建立 `armies_by_city` 与驻军战力索引；AI 决策周期复用 Dijkstra 路径场；`ThreatField` 复用只依赖道路拓扑的传播距离；补给从粮仓反向构建国家网络；`EquivariantOrder` 缓存城市物理 rank。2026-08-03 当前 headless 实测 1095 天每种子约 24.6～35.9 秒，四种子约 123 秒。
- **调度**：每日先合并；每 5 天重算威胁并决策；城市易主通过版本号触发下一轮战略图重算。所有国家性格由 nation id 确定生成，不训练、不引入随机不可复现性。

### 4.10 外交关系与 Utility AI

- `GameState` 是外交关系唯一真源，任意国家对只有 `WAR / NEUTRAL / ALLIED` 三态；关系、起始日、停战截止日和事件历史均对称存储。
- 真实地形地图所有国家两两中立开局；方形地图和军事 A/B 夹具保持全面战争并关闭外交。外交 AI 每 30 天决策一次，每国每轮最多参与一次关系变化。
- 宣战前要求至少储备 6 个月预计净军费、6 个月军粮和 5000 人/现役 15% 的人力。和平时期常规补员与建军不得动用最后 5000 人战略预备役。
- 每个宣战候选必须选择一个可直接进攻的敌方边境目标城。评分综合金、粮、人力产出，首都/粮仓、己方接壤方向和切断敌方网络价值；目标写入 `war_objectives`，并对军事 `campaign_target` 增加优先级。
- 交战国家按“每 100 名现役军人每月 1 金”支付战争军费；`last_war_upkeep/unpaid_war_cost` 记录本月军费与缺口。
- 求和需要双方接受；财政按“月收入－月军费”的净现金流和国库可支撑月数判断，月收入覆盖军费时即使余额为 0 也不是危机；实际欠费、粮草承受力不足、人力低于应急线、战争目标已达成/失守、战力劣势和长期战争疲劳都会提高意愿。战争满 900 天后强制允许停战，停战期 180 天。
- 求和立即结束双方活跃战斗、撤销旧进攻目标、清除悬挂 `FIGHTING` 状态并删除战争目标；同时确认双方实际控制城市的领土转移，更新法理归属并移除占领斜线，不影响第三国领土。
- 共同防御联盟在和平与战争时期都可长期存在，不要求当前拥有共同敌国；双方接受后至少持续 360 天，每国最多一个直接防御盟友。无共同敌人不是退盟理由，只有防御负担、外交冲突或严重力量失衡才提高退盟意愿。
- 宣战要求停战期届满、可从本国或盟国边境接触目标、仅本国进攻战力足够且本国未陷入其他战争。主动战争不召唤攻击方盟友；被宣战方的直接盟友自动对攻击国参战。
- 主动战争采用 `PREPARE_WAR → DECLARE_WAR` 两阶段。AI 先保存目标国/目标城、完成战前动员，并把军队调往目标城相邻的己方城市或己方侧驻防点；准备至少 30 天且集结兵力达到攻城需求后才宣战。宣战同一 tick 将集结军转为 `ATTACK`，不再等待普通 Utility 重新选择。
- 战争中每 90 天进入下一轮国家级战役规划窗口：若目标仍有效且兵力已齐则立即发动，否则先重新集结；目标已占领时重新选择敌方前线目标。单轮计划按目标需求把逐军分工拆成持久梯队，首梯队只投入最小充分兵力，后续梯队留在出发地；前梯队全部撤退/恢复/歼灭且目标仍属敌方时，下一支兵力充分的梯队在次日立即接战，不等待新的 90 天窗口。后续梯队继承整轮备战倍率，但 30 天加成从实际投入日计算。
- 宣战时通过统一的年度战争粮食报告计算 `0～4` 支额外动员军：报告同时给出当前兵力、目标兵力和现有全部编制满员时的年耗、年结余及粮仓可支撑年数。主动战争目标必须至少可维持 2 年，防御战争按 1 年生存线规划；动员窗口 180 天，每军仍消耗 5000 人并承担正常粮耗/军费。
- 联盟提供双向军事通行和共享补给：军队可穿越并驻留盟国城市，也可从盟国边境发起攻势；占领城市始终归实际占领军所属国。退盟立即撤销通行权，滞留军队自动返国。
- `AiWorldView`、战略前线、威胁场、驻边与攻击候选统一通过 `GameState.is_enemy()` 筛选。外交变更递增 `diplomacy_revision`，立即使战略缓存失效。
- 和平期另计算潜在敌国威胁：综合联盟战力比、对方战争储备、直接接壤边数及对方宣战意愿。威胁达到阈值的中立边境进入 `potential_frontier_cities/edges`，参与补给走廊、增援和 `HOLDING` 驻边规划；盟国不计威胁。
- HUD 为每国绘制独立详情卡，展示城市、兵力、人力、国库及月净现金流、粮食月需求、战争和盟友；战争卡片使用暗红底，和平卡片使用深蓝底。盟国国境内线为青色，普通国境保持金色；最近外交原因仍单独显示，完整记录保存在 `GameState.diplomatic_history`。

### 4.11 全国人口与自动补员

- `Nation.manpower_pool` 是可用人口唯一真源；城市没有本地人口库存。
- 普通城市 `manpower_per_month=10～30`、`food_per_half_year=400～600`。真实地图每国额外生成一个人口核心（至少 80/月）和一个粮食核心（至少 1600/半年），尽量不重合；地图分别标记“人/粮”。
- 资源核心获得额外战略价值，外交战争目标也显式加权并在理由中标记。占领重点产地会立即改变所属国后续人口或粮食收入。
- 每月人口立即汇入当前所属国；开局人口库按 `Σ(manpower_per_month×150)` 初始化。
- 初始军制按城市数确定：每城一支满编 `5000/5000` 轻军，每两城一支满编 `15000/15000` 重军。16 城国家开局为 24 军、20 万人；和平 AI 以 `ceil(城市数×1.5)` 为常态军队数基线。
- 普通新军仍固定 5000 人、满编 15000；自动合并只能补到满编，超出部分保留为另一支军队。国家硬上限仍为 `城市数×3`，给战时动员和狭路拆分保留空间。
- 战时军费按每 3000 名已部署士兵每月 1 金计算。16 城最低月金收入 80，20 万满编军月军费 67，因此基础军制在战争中也保持正现金流。
- 每月人口收入后、粮食结算前补员。单军每月最多补充 `750` 人；和平期只补到 30% 编制（4500 人），开战后恢复补至满编。符合条件的缺编军按本月可补缺口比例公平分配人口。
- 和平国家保留至少 5000 人战略预备役，不用于常规补员或建军；进入战争后才允许动用。
- `DiplomacyAI.war_food_report` 是军粮规划真源。它结合真实月耗 EMA、预计运输损耗、年产粮、粮仓库存和战争态度，输出年结余、满编代价、库存 runway、可负担兵力和目标是否可持续。和平/戒备期不允许靠库存维持负结余，并在约 3 年内向 1.5 年目标库存恢复；战争期只允许动用超过 6 个月应急储备的库存。
- 粮食预算不足时，一次决策可缩编多支安全后方军队；首都、粮仓、粮食核心、人口核心最后裁，至少保留 1500 人，边防/驻边军可缩至 500 人应急骨干。有限补员先按关键性分层：首都/粮仓，其次资源核心、战区和驻边军，同层按缺口公平分配。
- 固定种子纯和平 1080 天诊断中，四国均精确维持 24 军、20 万人，月产粮 `1376.7～1576.0`、月耗 `701～773`、年结余 `+7652～+9864`，库存连续增长。
- 友城和可接入本国粮仓网络的友方边允许补员；被围城、争夺边、`FIGHTING`、`RETREATING` 禁止补员。
- HUD 中“人”表示人口库，“兵”表示已部署总人数。

---

## 5. 天推进主循环（[simulation.gd](scripts/core/simulation.gd) `_advance_day`）—— 天/月分层（第七轮）

实时时钟：`_process(delta)` 累积到 `seconds_per_day`（默认 1.0，即 1 秒=1 天）触发一次 `_advance_day`。**基础 tick = 1 天**，行军/战斗/攻城每天推进；经济与**粮食扣除**仍每月（30 天）结算（`food_storage` 为 int，日扣会 30× 通胀）；**item 10 后：断粮后果（士气/减员/溃逃）改为每日滚动施加**，全月累计恰等旧月度口径。常量：`DAYS_PER_MONTH=30`、`DAYS_PER_HALF_YEAR=180`。

```
state.day += 1;  state.month = state.day / 30       # month 为派生显示量
if state.day % 30 == 0:                              # 每月结算块
    1. _resolve_economy()   金钱/人口月产出；(day%180==0 时半年注粮)
    1b._resolve_reinforcements() 全国人口库按缺口公平补员
    2. _resolve_supply()    补员后的军队月度扣粮 + 写 supply_ratio/starving（item10：只管经济，不再直接扣士气/减员）
    2b._recover_morale()    普通非交战军恢复；RECOVERING 驻军从损耗最低的可达粮仓取粮
2c. _apply_supply_pressure()  【每日，item10】按 supply_ratio 逐军滚动施加 1/30 士气损失 + supply_debt 整人化减员 + 士气跨 0 触发溃逃
3. ArmyCoordinator.merge_colocated()  同位置兼容军队守恒合并
3b.每5天 _ai_assign_targets()  战略图缓存 + 威胁场 + Utility候选评分与目标预留
4. _advance_movement()   四步严格分离（时序关键，勿合并）：
                         ①推进所有 MOVING/RETREATING 的 move_progress（步长=1/march_days；可 >=1.0）
                         ②_detect_encounters + _block_passthrough（MOVING 可主动接战；RETREATING 只可被动接战）
                         ③到达节点 _arrive_at_node（RETREATING 到最终友城后转 RECOVERING）
                         ④_resolve_battles + _purge_dead_armies
4a._advance_holding_adaptation()  满补给累计驻防；部分补给暂停；断粮衰减；无时间上限
4b._drain_siege_food()   R3：被围城每天扣 SIEGE_CITY_FOOD_PER_DAY=1 粮（补给孤岛的粮草时钟）
5. _refresh_war_flags()  刷新 edge.occupied 与 city.at_war
6. _check_victory()      仅剩一国有城 → winner，暂停
7. refresh_derived()     重算 nation.granary_food（登记粮仓库存求和）/ alive
```

**战斗触发与推进点**：
- 边中相遇：`_advance_movement` 末尾调 `_detect_encounters()`（§4.3 位置驱动）为最近接触敌对对 `new_battle(FIELD)`。**归侧规则 `_join_field_battle`（第八轮重写）**：因 `is_enemy` 等价"异 nation"，同侧不得含敌对军队 ⇒ 后到军队**只要 nation 与某一侧相同即无条件并入该侧**（不再要求与本侧成员"近邻接触"）；与两侧都异 nation 的真三方**不介入**。保证每侧恒单一 nation、第三方不被迫并肩。相遇军队置 `FIGHTING`、冻结在 `move_progress`；并入时调 `Combat.reinforce_morale` 触发增援回气（§4.5）。
  > ⚠️ 旧实现用 `_touches_side`（要求新军与本侧成员归一化位置差 ≤ `CONTACT_EPS`）作聚合门槛 ⇒ **同边靠后的同国友军被漏掉、只有最前一对开打 = "多军队被逐个击破/无法聚合"旧 bug**。已删除该门槛（连同死代码 `_touches_side`），改为按 nation 即并入。[13](a) 断言固化"靠后友军（gap>EPS）必被聚合"。
- 敌占点卡位 `_block_passthrough`（第八轮新增，在 `_detect_encounters` 之后、`_resolve_battles` 之前调用）：任何 MOVING 军队若在同边逼近一场进行中 FIELD 战斗的交战线（位置差 ≤ `CONTACT_EPS`）、且与该战斗**任一方敌对**，则被**冻结在交战线位置待机**（`move_progress` 被夹到交战线、不得穿过）。待该战斗分出胜负、`_resolve_battles` 清掉后，下一 tick 由 `_detect_encounters` 让其与幸存者开战——实现**三方同点"串行化接战、必不穿过"**。同 nation 军队不卡位（它们由 `_join_field_battle` 直接并入）。[14] 断言固化。
- 攻城 `_start_or_join_siege`（**一城一围城方**）：`_arrive_at_node` 到达城 → **只要该城有进行中 SIEGE（`_siege_battle_of != null`），无论城归属都转 `_start_or_join_siege`**；否则再按 `is_enemy(owner)` 分流（敌城→攻城，己方/中立且无围城→驻扎/续行）。
  > ⚠️ 第九轮修复"到达被围城不触发"：旧实现只凭 `is_enemy(army.owner, city.owner)` 分流。**被围城破城前 owner 不易主**，故城主（=守方）援军回援时 `is_enemy=false` → 被误判"回己方城"直接 `_settle_idle` **旁观穿过、不参战**。[15] 断言固化。
  - 无既有 SIEGE：**R4 空城弱攻退避**——空城（无守军）且 `attacker.size < siege_required_manpower(fort_strength)` → 不建围城、`_retreat_to_friendly` 撤离（见 §4.6）；否则有守军建带守军 SIEGE（`has_garrison=true`），**空城（强攻）建纯围城 SIEGE**（side_b 空），围城比值分母统一为 `battle.siege_required = siege_required_manpower(fort_strength)`，不再瞬占。
  - 既有 SIEGE 且与围城方同 nation → 并入 side_a（多路汇合）。
  - 既有 SIEGE 且与围城方敌对：
    - **守军仍在**（`has_garrison` 且 side_b 非空）：与守军同族者（=城主援军）**入城帮守**并入 side_b（享城防加成，[15](c)）；真第三国无处容身 → 以已抵达的目标城为锚点 `_retreat_to_friendly`，不得瞬移回来源城（[15](d)、[28]）。
- 每 tick 推进 `_resolve_battles()`：FIELD 走 `Combat.resolve_round` + `_finish_field_battle`；SIEGE 走 **`_advance_siege` 三阶段状态机**（见下），最后 filter 掉 `finished` 战斗。

**SIEGE 状态机 `_advance_siege`（守军歼灭 ≠ 破城）**：
1. **守军抵抗**（`has_garrison` 且 side_b 非空）：`resolve_round` 削守军。攻方被击退→真结束；守军溃散→`_retreat_defender` 清走守军、`has_garrison=false`、转纯围城（**不占领**）。战败守军必须排除当前守城城市撤往其他友城，抵达后才进入 `RECOVERING`；不能在原城恢复，无可达友城则溃散。
2. **城下决斗**（side_b 为敌对挑战者，无城防加成）：分胜负后——挑战者胜且**为城主（`side_b.owner==city.owner`）→ 解围成功，入城 `_settle_idle`、战斗结束**；挑战者胜且为敌对他国 → `_promote_challengers` 接管围城继续攻。围城方胜 → 挑战者撤退、围城继续。（第九轮修复：城主解围胜利不再被 `_promote_challengers` 误升为"围攻自己城"，[15](e)。）
3. **纯围城累积（item 7 连续曲线）**：无对抗时计算 `siege_daily_progress`；`manpower_ratio<SIEGE_RATIO_STALL(0.5)` 时进度倒退，若持续无法封锁则结束围城让攻方沿真实路径撤回友城（禁止永久切断补给）；否则按 `days=clamp(3+27/ratio,3,30)` 递减累积。达 100 后破城。`_promote_challengers` 接管围城时按 `city.fort_strength` 重算 `battle.siege_required`。

每个围城日开始，`_reconcile_siege_city_defenders` 都会重新收集目标城内尚未参战的 `IDLE/RECOVERING` 本国守军。任何守军都会先把围城切回战斗阶段；守城或解围战期间，`siege_progress` 每天回退 `0.25` 点，守军被击败前不得继续推进或占领。

**粮食/饥饿（首都粮仓 + 可扩展多粮仓）**：`Nation.capital_city_id` 是首都真源，`warehouse_city_ids` 登记本国粮仓；当前每国只有首都一个粮仓，但寻路按集合实现。每半年所有本国城市产出立即汇入首都。军队可从本国及盟国全部可达粮仓取粮，每条边 `loss=0.1×distance×(1+danger)`；分摊权重=`库存/sqrt(1+route_loss)`，因此库存更多、距离更近的粮仓承担更多，耗尽后自动重分配且总扣粮守恒。月需求=`size×FOOD_PER_CAPITA×(1+加权route_loss)`，`FOOD_PER_CAPITA=0.0025`，总倍率封顶 3。
**首都失守**：旧首都粮仓注销，库存 30% 汇入胜方首都、70% 损毁；败方若仍有城市，选择防御最高（同防御按势力局部物理序）的城市迁都并建立空粮仓，无城则不迁都。
**R3 补给孤岛**：被围城切断外部粮仓连接。若被围城市本身是有粮仓，则守军使用本地库存且由 `_drain_siege_food` 每日扣 1；普通城市无本地库存，被围后立即断供。粮尽后守军城防加成 ×`SIEGE_STARVE_DEF_MULT=0.3`。

**移动/边约定（易错点，改动前必读）**：
- 行军锚点统一用 `move_from`（不是 location_city）。`_begin_next_leg` 前置约定：调用前 `move_from` 已锚定当前城，末尾置 `army.on_edge=true`。
- **边占用的唯一判据是 `army.on_edge`**。`passing_count` 只统计全方向/全阵营军队数并供渲染使用；容量由 `_friendly_same_direction_manpower` 实时累计每支军队的 `max_size`，不读取当前 `size`。
- `max_manpower` 对每个国家、每个方向分别生效：仅同国同向军队共享满编兵力容量；同国反向与敌军均不占本方向容量。两阶段命令的首段预留使用同一单位，寻路会过滤小于本军 `max_size` 的道路。
- 正式世界从 `china-map-...webp` 的 Alpha 最大连通区域提取陆地，在局部低起伏区域用确定性最远点采样生成 64 城；按地图真实宽高比强制最小城市间距 `0.075`。
- 每个有效陆地像素按欧氏距离归属最近城市，生成确定性的一城一省 Voronoi 栅格；海域保持 `-1`。`recognized_city_owners` 保存法理归属。军队跨入敌境时按出发城市/驻边友方端点冻结占领声明国；从盟友领土出发的占领归该盟友，城市另存直接交战方 sponsor，故联盟随后解散也不影响和平确认。
- 真实地图道路使用 Delaunay 三角剖分生成自然局部邻接，超出地图尺度 `0.30` 的普通局部边不加入；按距离、陆地覆盖率和高度差加权的最小生成树只负责保证全图连通，最长边测试门禁为 `0.36`。真实地图不承诺固定总边数或每城固定度数。
- 每条边沿灰度图采样高度剖面，最大高度差决定 `max_manpower=0/5000/15000/30000/60000/100000`；骨架边最低 5000。高危险关隘容量压低，仍可因桥梁/粮道成为高战略价值命脉。
- 四国按空间均衡分区，每国严格 16 城且本国正容量道路连通。首都选择本国城市几何中心附近的城市。
- `main.tscn` 使用 `generate_world()` 高度图世界；`square_map.tscn` 使用 `generate_grid_world()`，保留原 `8×8 / 112` 边方形地图。固定城市 ID 的状态机测试和严格左右镜像 A/B 基准同样使用网格世界。
- `max_manpower=0` 是统一的军事与补给不可通行语义；普通寻路、撤退、威胁传播、补给、战略桥/割点均跳过。旧路径遇到 `0` 边立即失效并重规划或回到驻地，不进入永久排队。
- `_release_edge(army)` 以 `on_edge` 为准，幂等，防止 `passing_count` 双重释放变负。
- `_settle_idle` / `_capture_city` / `_retreat` 均先 `_release_edge(army)` 并清 `battle_id=-1`。
- `_purge_dead_armies` 统一清理 size≤0 军队并用 `on_edge` 释放其占用边。

**战斗视觉反馈（[map_renderer.gd](scripts/view/map_renderer.gd)，纯只读派生，第六轮新增）**：
- **城市红框**：只表示该城存在尚未结束的守城战或围城；不再使用开局全局 `at_war` 状态常驻标红。
- **士气条**：每支军队圆下方细横条，宽度=士气值，红(0)→黄(0.5)→绿(1)。直观展示疲劳/濒溃。
- **交战军队**：`FIGHTING` 状态额外画脉动红圈描边，一眼区分“正在打仗”与行军。
- **战斗爆发标记 `_draw_battles`**：每场活跃 Battle 在交战点（野战=边上 `contact_dist_a` 处，攻城=城中心）画脉动星芒 + 扩散环（半径随 `round_no` 增大）+ `R{round_no}` 回合数文字；**SIEGE 额外画 `siege_progress/REQUIRED` 攻城进度弧**（青色圆弧，直观展示破城进度）。
- **HUD 头部**：显示 `Day %d (M%d) ...`（`state.day` 为真源，`state.month` 派生）。
- **响应式布局**：项目禁用固定逻辑画布拉伸，`MapRenderer.compute_layout_for_viewport` 按实际窗口尺寸同比缩放地图、标记、线宽与字号；地图水平居中，窄窗口的国家概览自动减少列数并换行。
- **高度图底图**：渲染器按生成器记录的 Alpha 陆地包围盒裁切同一灰度图，以低亮度半透明背景先绘制；道路、城市和军队保持前景层。城市标记使用紧凑尺寸，避免 64 城互相遮挡。
- **省份与国境**：国家色以 `0.30` Alpha 覆盖地形；省界用细暗线，当前控制区国境用深色粗描边和金色内线。战争占领保留法理国家底色并叠加占领国高透明度斜线；和平确认领土转移后改为新国家纯色。
- **战略攻势箭头**：`_launch_campaign_offensive()` 向 `GameState.campaign_visual_events` 发布起点、目标、波次和 20 模拟日清理寿命；渲染器绘制弯曲双层箭头，每个事件按真实时间显示 3 秒并在末 0.65 秒淡出，避免游戏速度改变可读性。
- **中文字体**：HUD 从明确的跨平台 CJK 字体文件候选加载 `FontFile`，当前 macOS 使用 `Hiragino Sans GB.ttc`；找不到候选时才回退到 Godot 默认字体。测试直接校验“国”字字形存在。
- 全部基于 `_blink` 计时器做动画，**不写任何 state**；截图验证已确认生效。

---

## 6. 已知历史坑（修过的，别踩回去）

| 坑 | 现状 |
|---|---|
| 友军过境后 location_city 陈旧 | 行军统一用 `move_from` 锚定 |
| 攻城失败边双重释放（passing_count 变负） | 失败分支只 `_settle_idle`，不重复 `_release_edge` |
| GDScript 函数级作用域，同函数重复声明变量报错 | 循环变量避免重名（如 `_resolve_supply` 第二循环用 `a`） |
| `owner` 遮蔽 Node 内置属性 | 局部变量改名 `nation` |
| nearest_enemy_city 每候选跑一次 Dijkstra（慢） | 改单源 `dijkstra_field` 一次算全场 + `reconstruct` |
| 测试脚本 `new()` 的 Node 未释放 → 退出 leak 告警 | 测试内显式 `sim.free()` |
| 同向追逐永不触发战斗（旧 lo/hi 二分） | `_detect_encounters` 改位置驱动 `_norm_pos`+`_edge_contact`（§4.3） |
| 三方同端出发被塞进同一 side 并肩敌对 | `_join_field_battle` 只允许同 nation 加入，真三方待机 |
| 新增 `has_garrison` gate 后旧测试工厂未置该标志 → 城防加成不生效 | `_make_siege_battle` 补 `has_garrison=true` |
| 三方战斗测试用等距位置（0.50/0.48/0.46）→ 浮点噪声令"最近对"判定翻转 | 测试用非等距（0.50/0.49/0.44）使核心对无歧义 |
| `_join_field_battle` 用近邻门槛 `_touches_side` 聚合 → 同边靠后的同国友军被漏、多军被逐个击破 | 删门槛（连同死代码 `_touches_side`），改按 nation 即并入（§5） |
| 防御力若"原始相加" → 把一支大军拆成多支反更耐揍（非物理漏洞） | 防御用兵力加权平均质量、承伤基数=总兵力（`_side_avg_defense`），[13](c) 断言固化（§4） |
| 三方同点：A-B 开战冻结后第三敌国 C 因两侧皆异族被拒、且 A/B 已 FIGHTING 不再配对 → C 下一 tick 穿过交战点 | 新增 `_block_passthrough` 卡位（§5），C 冻结待机、串行接战 |
| 到达被围城不触发：只凭 `is_enemy(army.owner, city.owner)` 分流，被围城破城前 owner 不易主 → 城主援军 `is_enemy=false` 被判"回己方城"旁观穿过 | `_arrive_at_node` 先查 `_siege_battle_of != null` 就转攻城（§5），[15] 固化 |
| 城主援军入 side_b 解围**胜利**后被 `_promote_challengers` 误升为"围攻自己的城" | `_advance_siege` 阶段2 判 `side_b.owner==city.owner` → 入城驻守、战斗结束（§5），[15](e) 固化 |
| 相向两军错身穿过：`_advance_movement` 旧实现推进即就地 `_arrive_at_node`，先到敌城的一方在 `_detect_encounters` 前离边进入攻城 → 遭遇检测漏掉它、对方落单穿过，两敌军永不野战 | 拆成四步：①推进 ②遭遇检测 ③到达节点 ④解算（§5）。走到边末端者与相向敌军必先接触野战，[16] 固化 |
| 单槽边错身：全边共用 `passing_count` 容量会让敌军或反向友军阻塞追逐 | 容量改为同国同方向实时计数；反向和敌军独立。[17]/[17b] 固化 |
| 围城旧掷骰模型 `siege_gain(roll,defense)` 天数不可精确测、且与城防耦合 | R2 改确定性 `siege_daily_progress`（90→3 天，与城防解耦，见 §4.5/§4.6）；旧测试 [9]"高城防更慢/概率分布"随之作废、重写为"5× 门槛 + 递减标定" |
| 若不快照守方基准，守军被歼后 5× 门槛失效（分母消失，任意攻方都能推进） | 围城开始时快照 `battle.garrison_ref`（有守军=守军兵力，空城=city.defense），守军歼灭后仍保留，纯围城阶段持续用它做 5× 门槛分母 |
| 分布式每城粮仓让补给源过多，无法形成可切断的战略后勤线 | 改为每国首都单粮仓，`warehouse_city_ids` 为多粮仓扩展位；补给按 `distance×(1+danger)` 最小损耗路径选择，[26b] 固化 |
| 士气崩溃旧逻辑 `_retreat` 直接瞬移回来源城并立即 `IDLE`，导致下一 tick 重新出征 | 新增 `RETREATING→RECOVERING` 状态机；按真实边位置选最近友城，恢复期间锁定 AI，[22] 固化 |
| 同城多支驻军时 `army_at_city` 只取第一支参战，城市易主后其余恢复军可能滞留敌城 | `_capture_city` 统一驱逐该城所有异国 `IDLE/RECOVERING` 军队并重新撤退；四种子 × 1095 天冒烟验证 |
| 溃逃军完全排除在遭遇索引外，与“只会被动接战”不符 | `_detect_encounters` 同时索引 `MOVING/RETREATING`，但要求交战核心至少一方为 `MOVING`；`forced_retreat` 保证被动战斗获胜后继续撤退，[23] 固化 |
| 攻城顺序若在守军战败同 tick 推进进度，会把“正面战斗”和“围城”合并结算 | `_advance_siege` 守军战败分支立即 return，下一天才进入纯围城；守军撤退排除当前攻城城市，[24] 固化 |
| 围城建立后才落位的 `IDLE/RECOVERING` 守军不在 `side_b`，攻城可直接满进度占领并在清理阶段驱逐守军 | 每个围城日重新收集全部城内本国守军；战斗中每天回退 0.25 进度，守军未败不得占领，[24b] 固化 |
| 和平双方若都驻扎边中点，宣战瞬间会无准备直接接战 | 双方分别驻扎在从己方端点出发的 `0.35` 位置；宣战不触发战斗，只有主动推进至接触距离才接战，[25]/[32] 固化 |
| 驻防时间上限会让军队在无战术事件时自动离开阵地，与驻防语义冲突 | 删除 180 天自动推进机制；`HOLDING` 持续到接战、撤退或其他显式命令改变状态 |
| 驻防增援若直接继承老兵适应天数，可用小军提前驻防再让大军免费获得满适应 | Battle 快照按兵力加权稀释驻防天数，[27] 固化 |
| `_detect_encounters` 要求至少一方为 `MOVING`，导致 `HOLDING × RETREATING` 接触后互相无视 | 只排除 `RETREATING × RETREATING`；驻防军可截击溃逃军，[28] 固化 |
| 到达中间城后下一边拥堵，`move_from` 已更新但 `location_city` 仍指旧城，渲染跳回旧锚点 | `_arrive_at_node` 到达后同步 `location_city=arrived`，[28] 固化 |
| 多军共同破城时非主占领军 `_settle_idle(a, a.move_from)`，从城墙端点瞬移回出发城 | 统一落位 `battle.city.id`；四种子 × 1095 天位置连续性验证通过，[28] 固化 |
| 第三方抵达已有守军的围城后 `_settle_idle(attacker, attacker.move_from)`，从道路末端瞬移回来源城 | 改为从已抵达的目标城 `_retreat_to_friendly`，保持道路连续性，[12]/[15]/[28] 固化 |
| Renderer 重开复用旧世界位置快照，相同 army id 会从旧坐标插值飞向新坐标 | `MapRenderer.setup` 清空 `_prev_pos/_curr_pos` 并重置 `_last_day`，[28] 固化 |
| `corridor_flow` 只提高道路评分，唯一粮道即将被截断时不会产生守备或增援命令 | `StrategicMapSnapshot` 用“粮流占比 × 桥梁切断影响”识别关键粮道；受威胁节点产生显式守备缺口和 `REINFORCE` 候选，[30] 专项夹具固化 |
| 把所有高流量道路设为硬守备会钉死整支 15000 人主力，双向 A/B 均失败 | 仅图论桥梁形成硬缺口；每节点最多需求 3000，仅允许 ≤5000 有效战力的小军响应，并只在全国战力比 `0.8～1.5` 时触发；内部节点不用永久留守约束 |
| 攻击候选用无限制路径排序，可能选中必须穿过另一敌城的纵深目标；执行阶段路径为空后整轮空转 | 候选阶段先构建本国/盟国可达场，只保留有合法进攻入口的敌城；专项夹具验证旧 AI 选纵深目标失败、新 AI 攻击门户城市成功 |
| 直接修正道路军队从两端重复传播威胁，或允许多军分层驻边 | 两类方案均在双向 A/B 中出现单侧灾难或十年零占领，已完整撤回；不得只凭局部模型更“正确”重新引入 |
| `nation_id` 隐式生成 aggression/caution，且国家按固定 ID 顺序边规划边执行 | 正式 AI 默认统一性格；旧 ID 性格只保留为 A/B 开关。军事命令改为冻结快照→全国家收集→首段容量仲裁→交错统一提交，消除后决策国家读取同 tick 敌军命令的问题 |
| 批处理命令各自认为首段道路有容量，统一提交时后续命令静默失败 | 收集期按“国家+方向”预留首段容量，并缓存合法路径供提交复用；长跑硬断言 `commit_failures=0` |
| 对称粮食测试按两国城市列表相同下标放军，实际位置不镜像，产生 `414/442` 假差 | 左侧选点后映射到右侧镜像城市；年度结余严格相等为 `414/414` |
| 城市守备、前线增援、驻边和驻边回城分别计算目标，规则互相覆盖且容易重复算威胁 | 新增 `CityDefensePlan`，每国每次 AI tick 只计算一次 `required_power + posture + preferred_edge`。城市是防御目标：单一明确方向选 `EDGE`，多方向、城内敌军和围城解围选 `CITY`；`ArmyCoordinator` 分别预留驻城覆盖与各道路方向覆盖。旧 `_reinforce_candidate/_hold_candidate` 及重复辅助函数已删除 |
| 用无方向 `ThreatField` 判断进攻意图，或把 `potential_threat_of_edge` 外交评分当战力，会重复放大守备需求 | 实际敌军只按所在相邻城、驻守道路或明确 `move_to` 方向计入；潜在敌军使用 `potential_threat_at(city)` 的战力并按受威胁道路分摊。首都/粮仓只提供最低守备，战时增量统一由 `CityDefensePlan` 计算 |
| 驻城与驻边没有经济取舍，AI 只比较战术分数 | 驻城军按“军队规模 / 城市人口承载”降低半年粮食产出，封顶 30%；驻边军不影响城市产出。单方向规划把避免的减产计入驻边收益，多方向则接受经济成本换取全方向覆盖 |
| 同一战斗回合按 side_a/side_b 顺序消费独立 RNG，镜像接战产生系统性侧偏 | 每 tick 只消费一次共享骰和一次战术熵；两侧由无 ID 的稳定空间键分别派生 `±5%` 修正，交换 A/B 严格交换；完全同构侧按等变性必要条件同值 |
| 高危险道路只有普通线性地形惩罚，无法形成虎牢关式少数战略关隘 | `danger` 仍是唯一地形真源；可通行边达到 `0.85` 后进入关隘区。敌军实际 `HOLDING` 该边时，进攻方攻击倍率降至 `0.25`，驻防方不承受进攻惩罚；空关不产生额外阻挡。战略图为关隘增加显式价值，AI 联合兵力池按每个受阻方向折算有效战力 |
| 城市战斗结束后经济立即恢复，长期战争没有地方破坏成本 | `City.war_disruption_until_day` 记录唯一截止日；活跃围城每天刷新为当前日加 365 天。破坏期内城市金钱和粮食产出在驻军修正后再乘 `0.50`，人口产出不变；外交军粮与金钱预算读取相同实际产出 |
| 备战只延迟宣战，没有把准备时间转化为首轮战斗优势 | 实际准备时间按 `1 + days / 180` 线性转为攻势攻击倍率，180 天及以上封顶 `2.0`；只有成功加入国家攻势的军队获得，持续 30 天。后续攻势按距上一波的重整时间计算；倍率作为两阶段命令载荷在实际提交时写入军队，AI 综合战力按 `sqrt(倍率)` 识别威胁，地图以金环和 `攻x倍率` 标识 |
| 同步规划下相近防御目标每轮互为更优，军队会在几个位置间反复换防 | 防御命令成功后写入 90 天独立部署锁，覆盖最多 30 天行军和至少 60 天驻留；锁期内屏蔽非紧急换防和合并调动。城内敌军、围城解围、实际敌军抵近和战术撤退可打破迟滞，不降低全局 AI 决策频率 |
| 僵持期资源评分轻微波动或固定 360 天超时会反复触发“备战→取消→重新备战” | 删除无条件备战超时；`war_preparation_unready_since_day` 记录资源连续不足起点，连续 90 天不足才取消，期间任一次恢复即清零。目标失效或进攻道路中断仍立即取消；四种子长跑最终取消次数为 `0/0/0/0` |
| 敌军集中后要害城市守军按普通撤退阈值逃离，缺乏“必须守住”的战略约束 | `CityDefensePlan.must_hold_cities` 统一标记受压的首都、粮仓、资源核心、关键粮道和高价值城市，守备需求提高到 100% 威胁覆盖；最后一支必要守军不得离开防区，后方军读取同一缺口增援。本地军力低于来敌 40% 时先驻城待援，避免弱军在城与边之间送死式往返 |
| 国家攻势只有一个目标，没有明确哪支军队攻击哪座城市 | `Nation.campaign_attack_assignments` 保存当前波次 `army_id -> target_city_id`。主攻先满足 120% 攻城门槛；只有剩余军队能独立满足第二目标门槛时才开第二路。计划建立后冻结，主攻组失效、目标变化或下一波攻势才重建；国家卡片显示 `计划Wn 军x>城y`，多目标分别绘制攻势箭头 |
| 驻边 90 天锁到期后因微小评分变化回城，持续邻敌又被当作新紧急事件立即送回原边 | 当前方向压力不低于新方向的 80% 时保持原边；防御撤退记录刚离开的无向边，锁期内持续邻敌不能绕过锁生成同边反向命令，其他方向的新威胁仍可紧急解锁 |
| 联盟军从盟友领土进攻时，占领地一律归军队所属国；联盟若在和平前解散还会丢失归属链 | 跨入敌境时冻结 `Army.occupation_claimant_nation`，从盟友城市或驻边友方端点出发即归该盟友；`City.occupation_sponsor_nation` 保存直接交战侧，和平确认不依赖届时是否仍结盟 |
| 道路容量以军队支数计，无法表达残编大编制与多支小编制对道路的不同占用 | `Edge.max_manpower` 改为满编人数容量；执行、批处理首段预留和寻路统一按 `Army.max_size`。一支 `13021/15000` 占 15000，三支 `max_size=5000` 也占 15000；反向和敌军独立 |
| 宣战会清空 `war_preparation_target_nation`，旧 `campaign_locked` 因依赖该字段在战争开始后立即失效，计划军重新陷入局部同步等待 | 锁条件改为“存在逐军目标，且仍在备战或目标仍为敌城”；计划军回到集结城/驻边姿态后继续攻击原分配目标，真实要害防御仍可中断 |
| 本国法理城市被占后，反攻军击败占领军仍进入普通 5 倍围城阶段，常出现胜而不占 | 法理收复只比较实际占领军：空城抵达即恢复控制，击败最后守军同日收复；Utility AI 忽略该城抽象城防并给予显式收复优先级 |
| 溃败军只能把本国城市作为恢复终点，即使更近的盟友城市有通行权和补给也会绕路 | `nearest_friendly_city/route_from_edge` 的恢复终点改为所有拥有军事通行权的本国或盟友城市；抵达盟城后进入同一 `RECOVERING` 状态并使用联盟补给 |
| 15000 编制军无法通过 5000 容量道路，非零狭路在现有军制下等同不可通行 | AI 对有效战争目标先检查标准编制路径；仅当 15000 编制不可达而 5000 编制可达时，将静止军拆为三支 5000 编制。兵力、满编总额、士气、攻防属性及逐军战役目标保持守恒 |
| 国家没有显式军队数量硬上限，拆分后可能无限增加实体 | `GameState.max_army_count` 统一限制每国存活军队数为当前城市数的三倍；建军和拆分共用该门禁，粮食预算仍决定实际可维持规模 |
| 正式 AI 只有固定进攻性，无法配置国家风险偏好；纯僵持时宣战与外交动作不足 | `Nation.ai_aggression` 成为国家级唯一配置源，正式模式按 `0.5～1.5` 截断后同时影响宣战收益、战术进攻/撤退阈值和攻势重整周期；默认 `1.0` 保持镜像一致。全局宣战线从 `1.35` 调至 `1.20`，资源、粮食和路径硬门槛不变 |
| 备战动员合法消耗人力储备后，又被和平期完整储备门槛判为不合格并在 90 天后取消 | 开始备战仍要求完整储备；进行中的备战改用独立生存线，保留欠薪、金钱 runway、粮食 runway 和至少 `max(1000, 3%现役兵力)` 应急人力硬约束。四种子长跑取消备战均为 0 |
| 备战期间禁止结盟，AI 无法通过与非目标国结盟释放中立边境驻军 | 结盟意愿加入共同边境实际驻军占全国战力的释放价值；既有备战尚未完成时，可与非目标且非目标盟友结盟。联盟成立后 `CityDefensePlan` 从下一规划周期自然移除该潜在前线，不增加平行防区状态 |
| 持续攻势只在前梯队战败后接替，无法形成道路上的连续攻击纵队 | 前梯队进入目标围城即开放下一梯队；道路容量继续按 `Army.max_size` 实时控制，同梯队未出发成员和后续梯队在容量释放后立即进入道路。前梯队提前失能时仍保留次日接替规则 |
| 重点城市被围时只有普通五日防御规划，守方无法像攻方一样持续投入纵深预备队 | 每日只扫描活跃围城中的首都、粮仓、资源核心、关键粮道和高价值城市；以攻方战力减去城防、守军和已在途援军计算缺口，只调动 `CityDefensePlan.can_redeploy` 允许的最近军队。道路满载时后军等待，前军入城释放容量后次日跟进；缺口填平、围城结束或来源防线不足即停止 |
| 宣战后多数战争只有首攻：被宣战方没有国家级反攻目标，进攻方在 90 天冷却期完全不集结 | `_manage_campaign_offensive()` 将“组织”与“发动”分离：双方参战国都可选择敌城作为军事目标；防守方目标不覆盖宣战方的外交战争目标。冷却期持续调兵，但不覆盖仍在执行的当前梯队计划；到期才冻结并发动下一波 |
| AI 把 `Combat.SIEGE_RATIO_MIN=5` 的最快围城档误作最低进攻门槛，再乘 `1.5` 后要求 7.5 倍守军才进攻 | `required_assault_troops()` 只要求守军/城防的 `1.5` 倍局部优势，并保留全国现役兵力 25% 的战役投入下限。5 倍常量只属于围城速度曲线，不得再跨层用于进攻合法性 |

---

## 7. 安全改动边界（给接手 agent 的护栏）

- **改战斗平衡** → 只动 [combat.gd](scripts/core/combat.gd) 顶部常量（伤害 `K_ROUND`/`DEF_REF`；士气 `MORALE_*`/`MIN_COMBAT_EFFICIENCY`/`SIDE_ROUT_THRESHOLD`；正面 `*_FRONTAGE`；地形 `CHOKEPOINT_*`；围城 `FORT_MANPOWER_PER_POINT`/`SIEGE_RATIO_STALL`/`SIEGE_DAYS_BASE/MIN/DECAY`/`SIEGE_STARVE_DEF_MULT`），跑 `./run_tests.sh` 确认不破坏断言。
- **改行军时长** → 只动 [simulation.gd](scripts/core/simulation.gd) 的 `MARCH_DAYS_MIN/MAX` 与 `march_days(distance)`（R1 唯一真源）；改斜率须同步 [18] 断言。
- **改粮仓机制** → 首都/粮仓登记真源在 `Nation.capital_city_id/warehouse_city_ids`，库存真源在粮仓城市 `food_storage`；禁止重新让普通城市库存参与补给。
- **改补给损耗** → 只动 `Pathfinding.SUPPLY_DISTANCE_LOSS/SUPPLY_DANGER_MULT`；保持边损耗可加，才能用单标量 Dijkstra 保证全局最优。
- **改战后恢复** → `RECOVERY_FOOD_PER_CAPITA` 决定基础需求，运输损耗与普通补给共用；必须同步 [22]，并保持 `RECOVERING` 不进入普通补给计划。
- **改军队拆分或数量上限** → 拆分只允许静止军并要求 `sum(size)`、`sum(max_size)` 守恒；子军继承攻防、士气、补给和战役目标。建军与拆分都必须经过 `GameState.max_army_count`。
- **改补给士气联动** → `SUPPLY_MORALE_LOSS_MAX` 是完全断粮月度士气损失，部分缺粮按比例缩放；**item 10 后为每日滚动施加**（`_apply_supply_pressure`/纯函数 `_accrue_supply_pressure`，按 `1/DAYS_PER_MONTH` 摊派），粮食扣除仍月度（`food_storage` 为 int）；减员经 `Army.supply_debt` 整人化累计；必须同步 [23]/[23b]。
- **改边地形** → 只动 `danger` 与 Combat 的 `ATTACK_DANGER_K/DEFENSE_DANGER_K/HOLDING_TAU_DAYS/CHOKEPOINT_*`；禁止增加关隘第二真源。关隘惩罚只有敌军实际驻边时才能进入 AI 进攻战力折算。
- **改道路容量** → 容量单位是满编人数，只允许 `0/5000/15000/30000/60000/100000`；必须同步执行期、两阶段首段预留、军队寻路、战略价值归一化和渲染映射，禁止重新使用军队支数。
- **改 AI** → 普通战术候选在 [utility_ai.gd](scripts/ai/utility_ai.gd)，城市防御需求和驻城/驻边姿态在 [city_defense_plan.gd](scripts/ai/city_defense_plan.gd)，战略价值在 [strategic_map.gd](scripts/ai/strategic_map.gd)，威胁窗口在 [threat_field.gd](scripts/ai/threat_field.gd)。修改后运行 `./run_tests.sh`、AI 长跑与严格镜像基准。
- **改攻势加成或部署迟滞** → 只动 `Simulation.OFFENSIVE_BONUS_*` / `DEFENSIVE_DEPLOYMENT_LOCK_DAYS`；攻势倍率必须通过 `ActionCandidate` 随统一命令提交。防御锁保留不同方向的真实紧急解锁，但不得让持续邻敌绕过 `defensive_blocked_edge_*` 返回刚撤离的同一边。
- **改备战或攻势计划** → 备战取消迟滞真源是 `Nation.war_preparation_unready_since_day`；逐军目标真源是 `Nation.campaign_attack_assignments`。计划锁在宣战后必须继续生效并持续执行目标，计划军不进入普通战术重部署，但要害城市真实紧急威胁必须能解除冻结。
- **加新逻辑** → 写进 Simulation，不要写进 Model 或 View。新派生量必须进 `refresh_derived`。
- **加随机** → 必须用 `state.rng`，否则破坏确定性（test #7 会红）。
- **改时间粒度**（天/月分层）→ 时间真源是 `state.day`，`month=day/30` 派生。行军/战斗/攻城每天，经济/粮草/士气恢复在 `day%30==0` 块内。改动需同步 test_suite 中 #6/#7/#8 直接调 `_advance_day()` 的部分。
- **任何改动后** → 必须 `./run_tests.sh` 绿。新增功能应同时在 [tests/test_suite.gd](tests/test_suite.gd) 加断言。

AI 长跑命令：

```bash
/Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/ai_longrun.gd
```

左右镜像 A 改进 AI / B 当前 AI 对战入口：

```bash
/Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/ai_symmetric_duel.gd
```

检查统一提交后的严格公平基线：

```bash
# 镜像公平基准：必须用 AI_DUEL_RNG_SEED（不是 AI_DUEL_SEED）指定种子，否则退化到默认种子 991199、多种子输出字节相同。
AI_DUEL_MODE=balanced-fairness AI_DUEL_RNG_SEED=1 /Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/ai_symmetric_duel.gd

# 严格门禁：逐日比较镜像城市、国家资源和忽略 ID 的军队物理状态多重集，首个破裂立即失败。
AI_DUEL_MODE=balanced-fairness AI_DUEL_RNG_SEED=1 AI_DUEL_STRICT_MIRROR=1 /Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/ai_symmetric_duel.gd
```

**战斗系统重构（item 1-17，2026-08-02）验收状态**（详见 [COMBAT_REFACTOR_CHANGES.md](COMBAT_REFACTOR_CHANGES.md)）：
- 快速回归 `./run_tests.sh` = **745 passed / 0 failed**（含 [36] JSONL 落盘/确定性回放/篡改检测与 [37] 镜像等变排序）。
- item 17 万场统计 = **STATISTICS_PASS**：位置对称 10000/10000；独立战术修正 9997/10000 次不同，A 较高占比 0.5020；20% 明显优势方 10000/10000 获胜；拆分不变、地形单调、种子复现。
- 真实地图 4 种子 × 1095 天：全部 4 国存活，`invalid=0`、`commit_failures=0`、`starving=0`，稳态粮 115～123k，captures 11 / offensives 33。
- strict-mirror：seed 1 连续 **3650 天逐日无破裂**，最终 32:32、有效战力 `504049/504049`、优势分 `0.0`。旧 12-seed t 检验已被更强的确定性状态门禁取代。

---

## 8. 未完成 / 可扩展方向（预留，非 bug）

- `Nation.political_system` 预留字段，未使用。
- AI 当前全知；未来战争迷雾应只改 `AiWorldView` 的可见信息过滤，不要在 Utility 评分层散落可见性判断。
- 无存档/读档。
- `city.at_war` 用“与敌国城市接壤”近似，未精确反映是否有敌军正逼近。
