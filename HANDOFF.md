# World-War 项目交接文档

> 面向接手的 AI agent / 开发者。目标：不读全部源码即可理解架构、约定、当前状态与安全改动边界。
> 最后更新：2026-08-03（战斗系统重构及五项机制复查闭环，见 [COMBAT_REFACTOR_CHANGES.md](COMBAT_REFACTOR_CHANGES.md)）。

---

## 0. 一句话概述

Godot 4.7.1 + GDScript 编写的 **2D 平面战略"看海"游戏**（简化版 EU4，纯观赏、全 AI、实时推进）。
从带 Alpha 的灰度高度图生成 160 个陆城、道路、河流和动态码头，4 国各 40 个连续陆城，真实地图和平开局；AI 自动完成外交、河陆寻路、交战与占领，直到一国统一。`8×8` 的 64 城世界仅保留给严格镜像与局部状态机夹具。

---

## 1. 如何运行 / 测试（先做这个）

| 操作 | 命令 |
|---|---|
| Godot 可执行文件 | `/Users/bytedance/Godot.app/Contents/MacOS/Godot`（4.7.1.stable） |
| 运行游戏（图形） | 用 Godot 打开项目按 F5，或 `Godot --path /Users/bytedance/world-war` |
| **回归测试（改代码后必跑）** | `./run_tests.sh`（退出码 0=全过，非0=有失败） |
| 仅编译检查 | `Godot --headless --path <项目> --editor --quit`（无 `SCRIPT ERROR` 即通过） |

`run_tests.sh` 两阶段：①headless 导入捕获脚本错误 ②运行 `tests/test_suite.gd`（当前 **1116 断言 / 0 失败**）。
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
Simulation（Node，实时时钟，**按天推进**全部逻辑；补给每日分配，生产/补员/非战斗士气恢复按月）
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
| [scripts/model/city.gd](scripts/model/city.gd) | 数据 | 城市控制、地形、产出、工事和法理；`is_dock` 标识复用完整城市行为的码头 |
| [scripts/model/edge.gd](scripts/model/edge.gd) | 数据 | 容量、距离、危险；`LAND/LANDING/RIVER` 类型及行军时间、粮损、驻边许可 |
| [scripts/model/nation.gd](scripts/model/nation.gd) | 数据 | 国家资源、首都粮仓、外交解释字段、战争动员目标、持久战役梯队、多目标准备分配及 180 天满攻势准备状态 |
| [scripts/model/army.gd](scripts/model/army.gd) | 数据 | 军队兵力/质量/位置/状态/士气；两类补给债；`encounter_blocked` 表示完全同构多方接触的瞬态阻塞；含 AI 命令与占领元数据 |
| [scripts/model/battle.gd](scripts/model/battle.gd) | 数据 | 持久多回合战斗：双方/战场/驻防/围城、每侧整场援军士气累计、前线优先级、单军溃退队列、稳定战术随机键 |
| [scripts/core/game_state.gd](scripts/core/game_state.gd) | SSoT | 世界生成、码头城市、两档目标军制、无碰撞边键、粮仓、图查询、战斗和外交 |
| [scripts/core/terrain_map_generator.gd](scripts/core/terrain_map_generator.gd) | 地图生成 | 陆地/城市/省份/道路；高度图水系、道路交点码头、抢滩边和码头间水路 |
| [scripts/core/pathfinding.gd](scripts/core/pathfinding.gd) | 静态 | 寻路与补给网络；读取边级行军时间和粮损倍率 |
| [scripts/core/equivariant_order.gd](scripts/core/equivariant_order.gd) | 静态 | 镜像等变物理排序 SSoT：城市/军队/势力/边；禁止 ID/创建顺序参与行为决胜 |
| [scripts/core/combat.gd](scripts/core/combat.gd) | 静态 | 战斗解算、纯函数、共享战场骰 + 独立战术修正、结构化日志，见 §4 |
| [scripts/core/combat_log.gd](scripts/core/combat_log.gd) | 静态 | 战斗日志 JSONL 落盘/加载、逐回合确定性回放与篡改检测 |
| [scripts/core/simulation.gd](scripts/core/simulation.gd) | 逻辑 | 按天推进主循环；`edge_travel_days(edge)` 为实际行军时长真源，见 §5 |
| [scripts/ai/](scripts/ai) | AI | 军事 Utility AI、战略图、威胁场、协调器，以及 `DiplomacyAI` 双边外交评分 |
| [scripts/view/map_renderer.gd](scripts/view/map_renderer.gd) | 渲染 | 只读 `_draw` 的二战战略图风格渲染；牛皮纸、省份/国境、持续攻势箭头、军图城市/码头、NATO 兵牌、四档 UI 和城市/道路点击详情 |
| [scripts/main.gd](scripts/main.gd) | 入口 | 装配 GameState/Simulation/MapRenderer |
| [main.tscn](main.tscn) | 场景 | 默认真实高度图场景（Main + Simulation + MapRenderer） |
| [square_map.tscn](square_map.tscn) | 场景 | 保留的原始 `8×8` 方形地图场景；Main 的 `use_grid_world=true` |
| [tests/test_suite.gd](tests/test_suite.gd) | 测试 | 1116 断言，含全军维护费/建制费/攻势费/军费士气恢复、160 城分布、外交联盟残局、河运、真实边距、战略图交互、邻接驰援、灭国投降、两档军制与同城多军驻防门禁，headless 运行 |
| [tests/map_visual_smoke.gd](tests/map_visual_smoke.gd) | 视觉烟测 | 构造占领省份与攻势事件，用 Godot Movie Maker 验证真实渲染路径 |
| [tests/ai_longrun.gd](tests/ai_longrun.gd) | 诊断 | 4 种子 × 1095 天 AI 长跑，统计战争活动并校验零城市战争残留、两国永久联盟锁和城市数稳定 30 天后的两档军制精确收敛；支持旧版固定城防 A/B |
| [tests/ai_symmetric_duel.gd](tests/ai_symmetric_duel.gd) | 基准 | 64 城左右镜像；支持 `AI_DUEL_STRICT_MIRROR=1` 逐日全状态物理镜像门禁 |
| [tests/combat_statistics.gd](tests/combat_statistics.gd) | 统计 | item 17 万场：位置对称/独立战术随机无偏/优势胜率/无限与受限正面拆分不变/地形单调/种子复现 |
| [run_tests.sh](run_tests.sh) | 测试 | 一键编译+测试封装 |

---

## 4. 战斗系统（[combat.gd](scripts/core/combat.gd) + [battle.gd](scripts/model/battle.gd)）—— EU4 式多回合

**核心变化**：战斗从"瞬时一击解算"改为 **EU4 式多回合掷骰持续战斗**。一场战斗是持久化的 [Battle](scripts/model/battle.gd) 对象，存在 `GameState.battles` 中，**每天（tick）打一个回合**（`Combat.resolve_round`），直到一方兵力归零或士气崩溃。均势会战约 10-13 天。

**统一模型**：野战（`Kind.FIELD`）与攻城（`Kind.SIEGE`）共用回合解算，但 SIEGE 走专用状态机 `_advance_siege`（见 §5）。攻方在城墙 `dist=L`，守军在城中 `dist=0` 且**当 `has_garrison=true` 时**享 `fort_strength` 城防加成。

**支持 N v M（多路打一路）**：`Battle.side_a` / `side_b` 是**军队数组**，同侧恒单一 nation。
- **显式前线**：`frontline_allocation()` 每轮按镜像等变物理优先级把各军的 `committed` 兵力填入道路/城墙正面；前线火力为 `Σ(committed×attack×offensive_multiplier) × 本侧攻击质量加权组织度效率`。无限正面时该式严格还原逐军效率求和。
- **预备队**：完整未投入者不输出、不承伤、不承受战斗士气侵蚀；前线减员或溃退后下一轮补入。防御质量只按本轮前线 committed 兵力加权。`size×morale` 是守恒的组织度质量，伤亡和战斗侵蚀得到的侧级目标只回写本轮前线；火力、整侧溃败与续战能力读取侧级兵力加权组织度，行政拆分不能制造免费轮换。
- 行军途中的同 nation 友军抵达同一战斗即 `join`（见 §5），并触发**增援士气**（见 §4.5）。

### 4.1 Battle 对象 与 士气 SSoT

```
Battle { id, kind(FIELD/SIEGE), side_a[], side_b[], edge, city,
         contact_dist_a/b, round_no, siege_progress, has_garrison,
         reinforcement_morale_gained_a/b, frontline_priority_a/b,
         routed_a/b, finished, winner_side }
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
1. 提取低于 `ARMY_ROUT_THRESHOLD` 的单军；结算本场每侧剩余援军士气额度；明确前线/预备队。
2. 每 tick 共享一个战场骰和一个战术熵，两侧用稳定 tactical key 派生各自 `±5%` 修正。
3. 伤亡只在 committed 前线池中守恒分配；以 `size×morale` 计算拆分无关的目标组织度质量，战斗侵蚀只回写前线。
4. 回合后再次提取单军溃退者，由 Simulation 当日从真实战场位置启动撤退；当回合退出者仍计入本轮侧级士气与续战能力，再判整侧溃败或歼灭。

**粮草特色（强化）**：交战军队由 `_resolve_supply` 每日重算线路、需求、共享库存竞争和实际扣粮；断粮前线每回合额外掉 `MORALE_STARVE_DECAY` 士气。围城掐断粮道会在当天进入战力与士气结算。

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
| `ARMY_ROUT_THRESHOLD` | 0.05 | 单军士气 ≤ 此值，当回合退出前线并立即撤退 |
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
| **R1 行军时间** | `distance=1` 为 10 天，此后每个距离单位增加 5 天，长边不封顶；特殊边再乘时间倍率 | `march_days(distance)=10+(max(distance,1)−1)×5`；实际移动、AI 威胁与抵达估算统一用 `edge_travel_days(edge)`。河运时间倍率为 `1/1.2≈0.8333`，即同距离速度为陆运 `1.2×`；danger 只影响战斗和寻路风险，不改变基础行军时间 |
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
6. **断粮联动**：自由态军队每天按当日补给缺口施加 `SUPPLY_MORALE_LOSS_MAX/30` 的士气损失和减员债；士气从正值跌至 0 时立即溃逃。交战军仍由当日战斗结算触发撤退。

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
- **候选行动**：`HOLD/REINFORCE/MERGE/ATTACK/RETREAT` 同时评分，同分使用镜像等变物理键；完全同构且无单值等变解的目标延迟决策。进攻只选当前敌方边境城。
- **协调与滞回**：友军支援不使用可在多前线重复计数的威胁场，而由 `ArmyCoordinator` 一军一目标真实预留；前线军先决策，同层级按有效战力降序让主力先确定攻势，小军随后补位；内线小军先在后方合并，单军能填补至少 50% 缺口才直接增援。命令记录 `target/score/reason/created_day/until_day`。
- **合并守恒**：每日合并同城同状态军队及同位置驻防军；兵力求和，攻击/防御/士气/补给/驻防天数按兵力加权，`supply_debt/supply_food_debt` 随转移兵力守恒，边容量同步释放。
- **驻防出击**：`HOLDING` 没有时间上限；只有士气、补给和局部战力满足当前连续围城/强攻需求时，AI 才显式下达 `ATTACK`，从当前边位置连续推进。
- **驻边滞回**：城市出发驻边要求局部支援/威胁比达到 `0.60×性格系数`，边上撤退仍使用 `0.40×性格系数`。明确的准入/退出滞回带防止同一军队在城市和己方侧驻防点之间反复横跳。
- **同边敌军估值**：远方威胁可按抵达时间衰减，但同一条边上的敌军是下一场直接接战对象，必须按 `100%` 有效战力计入。驻防军出击使用“折扣威胁场”和“同边敌军实值”的较大者，避免未满编军误攻满编驻防军。
- **单军生存门槛**：联合兵力池决定整个攻势能否成立，但每支正常进攻参与军自身有效战力还必须达到目标局部敌军战力的 `35%`。这阻止几百人残部借用纸面联合战力分批冲锋；真正被围断粮军仍使用独立的 `0.70` 背水突围门槛。
- **多方向协同**：敌城相邻正容量边上的实际友军按来源邻城计为独立方向，联合兵力达到围城/战力门槛后才进攻。最慢方向先出发，较快方向等待到预计抵达时间差不超过 5 天，避免“同日下令、分批送死”。
- **断粮突围与解围**：补给率 `≤25%` 且无法经本国控制网抵达粮仓才算真正被围；突围优先级高于普通动作，但只攻击战力比 `≥0.70` 的最弱包围节点。被围城和断粮友军形成紧急救援缺口，相邻敌城作为打通通道的高价值目标。
- **建军/解散**：AI 国家级命令 `CREATE_ARMY/DISBAND_ARMY`。正式地图分别比较轻军/重军现有数量与城市比例目标，缺额时在未被围粮仓创建对应满编军，超额时从安全闲置军中整建制裁撤；战争动员不额外突破目标。新建编制除完整人力外，还必须一次性支付该编制 10 个月维护费；支付失败时人力和金钱均不预扣。
- **统一驻防目标**：首都、粮仓、资源核心和粮道只提供城市价值与补给重要性，不再生成固定人数门槛。威胁、解围需求和城市重要性统一进入 `CityDefensePlan.required_power`。
- **角色化防区分配**：正式地图仅由 `5000` 编制军承担常态填线，槽位严格按“实际国界城市 → 潜在国界城市 → 国界边 → 国内码头/高等级要塞/资源与补给核心”排序；每个城市槽和边槽各最多一军。分配使用确定性分层贪心，已删除 Hungarian 和按战力生成多重城市槽的旧路径。`MOVING/HOLDING/RECOVERING` 填线军全程占用任务槽，避免长距离补位和战后恢复期间重复派军。
- **轻重军任务所有权**：`15000` 编制军不进入常态驻防，作为国家战役机动军；正式地图主攻方向投入全部可用重军突击组，仅在存在唯一最优候选时追加一支邻近 `5000` 边槽军，城市槽填线军不可抽调。宣战前集结的轻军数不得超过已投入重军数；邻城即时驰援最多两支 `5000`，不抽调重军。建军同时存在两档缺额时优先补足 `5000`。
- **性能**：`AiWorldView` 建立军队与驻军战力索引；AI 决策周期复用路径场；`ThreatField` 复用拓扑传播距离；补给从粮仓反向构建国家网络；Dijkstra 使用确定性二叉最小堆 `O((V+E)logV)`。正式地图驻防规划隔离基准由旧 Hungarian 的 `5.89ms/plan` 降至角色贪心的 `1.73ms/plan`，下降 `70.6%`。同机 seed 12345 的 1095 天基准由旧实现 `133.8s` 降至角色化实现 `110.7s`。四种子总耗时 `457.4s`，高于旧版 `406.6s`，但同期易手由 93 增至 114、攻势由 40 增至 60；不可把活动量增加造成的总耗时上升误报为单次规划回归。
- **调度**：每日先合并；每 10 天重算威胁并决策，降低重复调遣；城市易主或整数城防恢复通过独立版本号触发下一轮战略图重算。所有国家性格由 nation id 确定生成，不训练、不引入随机不可复现性。

### 4.10 外交关系与 Utility AI

- `GameState` 是外交关系唯一真源，任意国家对只有 `WAR / NEUTRAL / ALLIED` 三态；关系、起始日、停战截止日和事件历史均对称存储。
- 真实地形地图所有国家两两中立开局；方形地图和军事 A/B 夹具保持全面战争并关闭外交。外交 AI 每 30 天决策一次，每国每轮最多参与一次关系变化。
- 宣战前要求至少储备 6 个月预计净军费、6 个月军粮和 5000 人/现役 15% 的人力。和平时期常规补员与建军不得动用最后 5000 人战略预备役。
- 每个宣战候选必须选择一个可直接进攻的敌方边境目标城。评分综合金、粮、人力产出，首都/粮仓、己方接壤方向和切断敌方网络价值；恢复窗口内的弱城获得渐消机会分，本国法理失地获得更高反攻分。目标写入 `war_objectives`，并对军事 `campaign_target` 增加优先级。
- 和平与战争时期的每支存续军队都按 `ceil(当前兵力/3000)` 支付月维护费，按编制分别取整；`last_military_upkeep/unpaid_military_upkeep/military_payment_ratio` 记录应付、未付与实际支付率。组织一次国家级攻势，按全部计划参与编制（含后续梯队）分别收取“一个月维护费 + 1 金指挥费”；金库不足时保留准备计划但不发出攻击命令。
- 军费不足不直接扣士气，也不复用断粮惩罚。普通和驻城恢复统一乘 `0.5 + 0.5×military_payment_ratio`：完全未付仍以 50% 速度恢复，足额支付保持原恢复速度；粮食不足仍独立按实际供给比例限制恢复。
- 所有外交动作共用方向性态度分解：`态度 = 历史态度 + 军事态度 + 政治态度`。历史态度从和平事件记录的实际战局结果和投降方累计败战复仇；军事态度因直接接壤和可进攻的目标城市下降；政治态度因共同敌人、可释放的边境驻军上升，因对方与本国敌人结盟下降。该分解直接进入议和、结盟、宣战和退盟评分，动作原因同步记录态度与统一压力。
- 求和必须双边同意：至少一方达到 `1.25` 提议阈值，并且双方各自都达到 `0.60` 接受底线；合计分不能替代任何一方同意，战争满 900 天也不再强制停战。和平意愿由战争疲劳、战局、归一化军力、钱粮续航、第三国边境实际集结、多线战争、外交态度和进攻性组成；占领敌方重要城市或拥有军力优势会降低和平意愿，失地、军力劣势、钱粮将尽和中立邻国压境会提高和平意愿。停战期仍为 180 天。
- 全境失守是战争结算硬规则：任一方失去全部实际控制城市后，立即向其全部交战国逐一投降，不等待月度外交 tick，也不经过胜方和平接受线。每一条关系均复用普通和平路径，确认领土、结束战斗、清理战争目标并记录 `surrendering_nation`；零城市国家不得保留任何战争关系。
- 求和立即结束双方活跃战斗、撤销旧进攻目标、清除悬挂 `FIGHTING` 状态并删除战争目标；同时确认双方实际控制城市的领土转移，更新法理归属并移除占领斜线，不影响第三国领土。
- 共同防御联盟在仍能缓解战线时可跨越和平与战争长期存在，双方接受后至少持续 360 天，每国最多一个直接防御盟友。所有国家的终局目标均为独占全图：两国合计控制的地图份额越高、存活竞争者越少，连续增长的 `unification_rivalry` 越强，并同时抑制结盟、提高退盟与宣战收益。仅剩两个盟国二分全图时必定退盟，恢复中立后不会再次结盟，并转入最终统一竞争。
- 宣战要求停战期届满、可从本国或盟国边境接触目标、仅本国进攻战力足够且本国未陷入其他战争。主动战争不召唤攻击方盟友；被宣战方的直接盟友自动对攻击国参战。
- 主动战争采用 `PREPARE_WAR → DECLARE_WAR` 两阶段。AI 先保存目标国/目标城、完成战前动员，并把军队调往目标城相邻的己方城市或己方侧驻防点；准备至少 30 天且集结兵力达到攻城需求后才宣战。宣战同一 tick 将集结军转为 `ATTACK`，不再等待普通 Utility 重新选择。
- 战争中每 30 天进入下一轮国家级战役规划窗口。统一国家时钟下最多并行准备 3 个敌方目标，`campaign_preparation_assignments` 冻结一军一目标归属，不能在多个方向重复计算兵力；达到门槛的方向可同批发动。主方向优先满足，再用剩余可调兵力建立第二、第三方向。
- 每个方向按目标直接守军、`ThreatField` 威胁和城防反推所需战力；至少到位原攻城人数门槛的 75%，普通发动还须达到 `CAMPAIGN_ATTACK_ENTER_RATIO / ai_aggression = 1.00 / ai_aggression`。普通逐军 Utility 的 `1.35` 阈值不变。30 天窗口仍不足的目标进入 180 天满准备集合并持续集结，第 180 天以 `2.0×` 攻击加成发动；近期法理失地反攻不等待该周期。
- 攻势加成持续期等于实际准备天数并在 180 天封顶：30/60/180 天准备分别持续 30/60/180 天。满准备攻势还预存占城后二阶段：破城当天按剩余加成、士气、补给、留守战力和相邻敌城威胁，选择立即追击、前出驻边或就地驻城；不会刷新原加成截止日。
- 宣战时通过统一的年度战争粮食报告计算 `0～4` 支额外动员军：报告同时给出当前兵力、目标兵力和现有全部编制满员时的年耗、年结余及粮仓可支撑年数。主动战争目标必须至少可维持 2 年，防御战争按 1 年生存线规划；动员窗口 180 天，每军仍消耗 5000 人并承担正常粮耗/军费。
- 联盟提供双向军事通行和共享补给：军队可穿越并驻留盟国城市，也可从盟国边境发起攻势；占领城市始终归实际占领军所属国。退盟立即撤销通行权，滞留军队自动返国。
- `AiWorldView`、战略前线、威胁场、驻边与攻击候选统一通过 `GameState.is_enemy()` 筛选。外交和整数城防变化分别递增 `diplomacy_revision/fortification_revision`，立即使战略缓存失效。
- 和平期另计算潜在敌国威胁：综合联盟战力比、对方战争储备、直接接壤边数及对方宣战意愿。威胁达到阈值的中立边境进入 `potential_frontier_cities/edges`，参与补给走廊、增援和 `HOLDING` 驻边规划；盟国不计威胁。
- 顶部“国家统计”按钮控制可折叠统计窗口，默认收起；展开后为每国绘制独立详情卡，展示城市、兵力、人力、国库及月净现金流、粮食月需求、战争和盟友，并在窗口底部显示最近外交原因。收起后布局立即回收顶部空间并扩大地图；开关仅存于 `MapRenderer`，重开游戏保持当前 UI 偏好但不进入存档。

### 4.11 全国人口与自动补员

- `Nation.manpower_pool` 是可用人口唯一真源；城市没有本地人口库存。
- 普通城市 `manpower_per_month=10～30`、`food_per_half_year=400～600`。真实地图每国额外生成一个人口核心（至少 80/月）和一个粮食核心（至少 1600/半年），尽量不重合；地图分别标记“人/粮”。
- 资源核心获得额外战略价值，外交战争目标也显式加权并在理由中标记。占领重点产地会立即改变所属国后续人口或粮食收入。
- 每月人口立即汇入当前所属国；开局人口库按 `Σ(manpower_per_month×750)` 初始化，为旧 150 个月储备的 5 倍。
- 正式地图目标军制按当前城市数动态计算：`5000` 编制轻军为 `ceil(0.5×城市数)`，`15000` 编制重军为 `floor(0.05×城市数)`。码头具备完整城市语义，因此同样计入城市数；开局和城市易手后都由公式精确计算，不依赖固定总军数。
- 建军直接创建对应的 `5000/5000` 或 `15000/15000` 满编单位；战争动员不得突破两档目标实体数。自动合并不能突破单军 `max_size`；国家硬上限仍为 `城市数×3`，只作为异常保护和网格夹具拆分空间。
- 真实地图长跑要求城市数稳定超过 30 天的国家精确匹配两档目标；战斗中不会为瞬时满足公式而凭空删除部队。
- 每月人口收入后、粮食结算前补员。单军每月最多补充 `750` 人；和平期只补到 30% 编制（4500 人），开战后恢复补至满编。符合条件的缺编军按本月可补缺口比例公平分配人口。
- 和平国家保留至少 5000 人战略预备役，不用于常规补员或建军；进入战争后才允许动用。
- `DiplomacyAI.war_food_report` 是军粮规划真源。它结合真实月耗 EMA、预计运输损耗、年产粮、粮仓库存和战争态度，输出年结余、满编代价、库存 runway、可负担兵力和目标是否可持续。和平/戒备期不允许靠库存维持负结余，并在约 3 年内向 1.5 年目标库存恢复；战争期只允许动用超过 6 个月应急储备的库存。
- 粮食预算不足时只缩编可安全裁减的 `IDLE` 军队，并按 `max_size×30%` 保留编制骨架；不再按首都、粮仓、资源核心或边境设置固定人数下限。只有军制数量超额路径可整建制裁撤；城市重要性只进入统一驻防优化。
- `CityDefensePlan` 将驻防写成军队到城市槽的矩形 Hungarian 最大权匹配：真实槽表示派遣，虚拟槽表示不派遣；每军最多守一城，城市可按未覆盖需求拥有多个槽。效用综合城市价值、补给重要性、威胁、覆盖率、过量投入和距离。`15000` 编制军因覆盖收益更适合高需求首槽，并在低需求槽受到 overcommit 惩罚。
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
    2b._recover_morale()    普通非交战军恢复；RECOVERING 驻军从损耗最低的可达粮仓取粮
2. _resolve_supply()       【每日】重算线路/兵力/库存竞争；supply_food_debt 保持月耗量纲
2c. _apply_supply_pressure()  【每日】按当日 supply_ratio 施加 1/30 士气损失 + supply_debt 整人化减员
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
- 边中相遇：`_advance_movement` 末尾调 `_detect_encounters()`（§4.3 位置驱动）为最近接触敌对对 `new_battle(FIELD)`。既有战斗的增援先用回合开始时冻结的 `contact_dist` 批量判定到达资格，再统一加入，避免先加入者移动战线造成遍历顺序级联；新军只有更接近敌方战线时才推进本侧 contact。真第三国不介入，两侧恒单一 nation。
  > 增援门槛是“距己方 `contact_dist` ≤ `REINFORCEMENT_RADIUS`”，不是与某个本侧成员相邻。到达资格同日冻结批量计算；尚未抵达者继续行军。
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
3. **纯围城累积（item 7 连续曲线）**：分子使用城墙正面内 `committed manpower × morale efficiency × supply_ratio`，而非原始总人数；`manpower_ratio<SIEGE_RATIO_STALL(0.5)` 时进度倒退，否则按 `days=clamp(3+27/ratio,3,30)` 累积。达 100 后破城。

每个围城日开始，`_reconcile_siege_city_defenders` 都会重新收集目标城内尚未参战的 `IDLE/RECOVERING` 本国守军。任何守军都会先把围城切回战斗阶段；守城或解围战期间，`siege_progress` 每天回退 `0.25` 点，守军被击败前不得继续推进或占领。

**粮食/饥饿（首都粮仓 + 可扩展多粮仓）**：军队每天从本国及盟国全部可达粮仓取粮；路线、兵力与共享库存竞争每天重算。月需求仍为 `size×FOOD_PER_CAPITA×(1+加权route_loss)`，除以 30 累积进 `supply_food_debt`，满整粮才扣库存，因此 30 天总耗与旧月口径一致。
**首都失守**：旧首都粮仓注销，库存 30% 汇入胜方首都、70% 损毁；败方若仍有城市，选择防御最高（同防御按势力局部物理序）的城市迁都并建立空粮仓，无城则不迁都。
**R3 补给孤岛**：被围城切断外部粮仓连接。若被围城市本身是有粮仓，则守军使用本地库存且由 `_drain_siege_food` 每日扣 1；普通城市无本地库存，被围后立即断供。粮尽后守军城防加成 ×`SIEGE_STARVE_DEF_MULT=0.3`。

**移动/边约定（易错点，改动前必读）**：
- 行军锚点统一用 `move_from`（不是 location_city）。`_begin_next_leg` 前置约定：调用前 `move_from` 已锚定当前城，末尾置 `army.on_edge=true`。
- **边占用的唯一判据是 `army.on_edge`**。`passing_count` 只统计全方向/全阵营军队数并供渲染使用；容量由 `_friendly_same_direction_manpower` 实时累计每支军队的 `max_size`，不读取当前 `size`。
- `max_manpower` 对每个国家、每个方向分别生效：仅同国同向军队共享满编兵力容量；同国反向与敌军均不占本方向容量。两阶段命令的首段预留使用同一单位，寻路会过滤小于本军 `max_size` 的道路。
- 冻结快照阶段已通过首段容量仲裁的批量命令，若因同批边上军队调头导致提交时临时满载，保留 `MOVING + move_to=-1` 和完整路径，每日重试容量；不计为提交失败。普通未预校验即时命令仍保持原地并等待下一轮 AI 重规划。
- 正式世界从 `china-map-...webp` 的 Alpha 最大连通区域提取陆地，先生成黄河/长江路径，再用确定性加权最远点采样生成 160 个陆城。聚落密度统一由低海拔、低起伏、中东部/东南区位和河岸亲和度组成；局部间距以 `0.075×sqrt(64/城市数)` 为基准，再按密度反向缩放并保留硬下界，因此西北稀疏、中东南与低地密集。
- 每个有效陆地像素按欧氏距离归属最近城市，生成确定性的一城一省 Voronoi 栅格；海域保持 `-1`。`recognized_city_owners` 保存法理归属。军队跨入敌境时按出发城市/驻边友方端点冻结占领声明国；从盟友领土出发的占领归该盟友，城市另存直接交战方 sponsor，故联盟随后解散也不影响和平确认。
- 真实地图道路使用 Delaunay 三角剖分生成自然局部邻接，超出地图尺度 `0.30` 的普通局部边不加入；按距离、陆地覆盖率和高度差加权的最小生成树只负责保证全图连通，最长边测试门禁为 `0.36`。真实地图不承诺固定总边数或每城固定度数。
- 道路拓扑选边仍沿用分析图尺度，避免数值调整改变连接关系；边生成后，`LAND/LANDING/RIVER` 三类边统一按显示端点、地图真实宽高比计算欧氏长度，再以每地图高度 `12` 个距离单位取整。抢滩分段直接读取分段端点，不再按原边距离比例估算；距离不设 `1～5` 上限。
- 每条边沿灰度图采样高度剖面，最大高度差决定 `max_manpower=0/5000/15000/30000/60000/100000`；骨架边最低 5000。高危险关隘容量压低，仍可因桥梁/粮道成为高战略价值命脉。
- 高度图使用两组固定地理控制点生成黄河、长江：黄河控制点下压至归一化纵坐标 `0.50～0.59`，实际平均位置门禁为 `0.50～0.60`；长江保持原稳定走廊。两河西向东，平均纵向间隔至少 `0.06`，局部向西折返不超过 `0.08`。
- 渡口先沿每条河均匀保留约 25% crossing，再按正式地图空间分国结果用并查集补足每个初始国家内部连通所需的最少渡口，最后补足全图连通；码头数量仍受 8～22 门禁约束。保留道路的全部交点实体化为码头，其他穿河陆路禁用。
- 河流是硬陆路障碍：任何可通行 `LAND/LANDING` 边都不得从河流内部穿过。跨河只能先进入码头，再通过抢滩边或相邻码头间水路移动；同一原道路若依次穿过两条河，必须依次经过两个码头。
- 码头是 `City`，具备占领、驻军、工事、补给和法理归属；初始产出为 0，不额外扩大四国开局经济。首都和资源核心只从 160 个陆城选择；两档军制按全部当前城市（含码头）计算。
- 相邻码头连接 `RIVER` 边：容量 100000、行军时间倍率 `1/1.2≈0.8333`（同距离速度为陆运 `1.2×`）、粮损倍率 `0.25`，河段 danger 由坡度与弯曲度生成。水路可行军和交战，但 `allows_holding=false`，AI、命令执行与状态机均禁止驻边。
- 四国按空间均衡分区，每国严格 40 个陆城且本国正容量道路连通。首都选择本国陆城几何中心附近的城市。
- `main.tscn` 使用 `generate_world()` 高度图世界；`square_map.tscn` 使用 `generate_grid_world()`，保留原 `8×8 / 112` 边方形地图。固定城市 ID 的状态机测试和严格左右镜像 A/B 基准同样使用网格世界。
- `max_manpower=0` 是统一的军事与补给不可通行语义；普通寻路、撤退、威胁传播、补给、战略桥/割点均跳过。旧路径遇到 `0` 边立即失效并重规划或回到驻地，不进入永久排队。
- `_release_edge(army)` 以 `on_edge` 为准，幂等，防止 `passing_count` 双重释放变负。
- `_settle_idle` / `_capture_city` / `_retreat` 均先 `_release_edge(army)` 并清 `battle_id=-1`。
- `_purge_dead_armies` 统一清理 size≤0 军队并用 `on_edge` 释放其占用边。

**二战战略规划图视觉（[map_renderer.gd](scripts/view/map_renderer.gd)，纯只读派生）**：
- **牛皮纸主题**：全窗口深褐底、地图纸张投影、确定性纤维纹理和赭色高度图罩层统一色域；国家色先降饱和并混入纸色，避免覆盖道路、兵牌和箭头。
- **国家与道路描边**：海岸和当前国境使用深墨外线/金色内线，盟国边界独立青灰线；陆路按容量分四档墨线，高危险段叠加红色短划，河运为双层蓝灰线，抢滩为红色虚线。
- **固定视觉档位**：地图画布继续连续适配窗口，但图标、字体、线宽只使用 `0.80 / 1.00 / 1.25 / 1.50` 四档比例；同一档位内窗口变化不会改变符号尺寸。窄窗口仍自动减少国家卡片列数。
- **可折叠国家统计**：顶部命令栏右侧按钮始终可见；统计窗口展开时统一包住国家卡片和外交摘要，关闭时不保留空白占位，地图重新计算可用高度。城市/道路档案为独立上下文面板，不受该开关影响。
- **城市与码头**：城市为固定方形军图据点并带工事交叉线，码头为锚形圆标，首都加金色星标；围城只对当前争夺城市使用红色描边，资源核心保留“粮/人”短标签。
- **军队兵牌**：圆形军队改为固定尺寸 NATO 风格矩形兵牌；轻军使用步兵交叉线，重军使用装甲椭圆，顶部国家色带和状态字母区分行军/交战/撤退/恢复/驻边，底部士气条保持可读。
- **战斗反馈**：活跃 Battle 仍在真实接触点绘制脉动星芒、扩散环和回合数；攻城额外绘制 `siege_progress/REQUIRED` 进度弧。
- **持续攻势箭头**：弯曲双层箭头及流动箭羽在 `campaign_visual_events` 的完整 20 模拟日寿命内持续显示，只在事件最后数日淡出，不再按现实时间 3 秒隐藏。
- **点击详情**：左键优先命中城市，其次命中可通行道路；选中城市显示控制/法理、工事恢复、驻军、产出、库存和地形，选中道路显示类型、端点、距离、行军天数、容量、危险、高差和通行状态；右键或点击地图外取消。
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
| 围城旧掷骰模型天数不可精确测、且与城防耦合 | 改为确定性连续 `siege_daily_progress`；分母固定为 `fort_strength×100`，分子为受正面/士气/补给修正的有效围城兵力 |
| 守军被歼后若围城分母随守军人数消失，任意残兵都能推进 | `battle.siege_required` 快照工事需求，不含守军人数；守军只在城下战斗阶段作为对手 |
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
| 用无方向 `ThreatField` 判断进攻意图，或把 `potential_threat_of_edge` 外交评分当战力，会重复放大守备需求 | 实际敌军只按所在相邻城、驻守道路或明确 `move_to` 方向计入；潜在敌军使用 `potential_threat_at(city)` 的战力并按受威胁道路分摊。首都/粮仓只贡献重要性，不再提供固定最低守备 |
| 驻城与驻边没有经济取舍，AI 只比较战术分数 | 驻城军按“军队规模 / 城市人口承载”降低半年粮食产出，封顶 30%；驻边军不影响城市产出。单方向规划把避免的减产计入驻边收益，多方向则接受经济成本换取全方向覆盖 |
| 同一战斗回合按 side_a/side_b 顺序消费独立 RNG，镜像接战产生系统性侧偏 | 每 tick 只消费一次共享骰和一次战术熵；两侧由无 ID 的稳定空间键分别派生 `±5%` 修正，交换 A/B 严格交换；完全同构侧按等变性必要条件同值 |
| 高危险道路只有普通线性地形惩罚，无法形成虎牢关式少数战略关隘 | `danger` 仍是唯一地形真源；可通行边达到 `0.85` 后进入关隘区。敌军实际 `HOLDING` 该边时，进攻方攻击倍率降至 `0.25`，驻防方不承受进攻惩罚；空关不产生额外阻挡。战略图为关隘增加显式价值，AI 联合兵力池按每个受阻方向折算有效战力 |
| 城市战斗结束后经济立即恢复，长期战争没有地方破坏成本 | `City.war_disruption_until_day` 记录唯一截止日；活跃围城每天刷新为当前日加 365 天。破坏期内城市金钱和粮食产出在驻军修正后再乘 `0.50`，人口产出不变；外交军粮与金钱预算读取相同实际产出 |
| 备战只延迟宣战，没有把准备时间转化为首轮战斗优势 | 实际准备时间按 `1 + days / 180` 线性转为攻势攻击倍率，倍率和持续期都在 180 天封顶；后续梯队从实际投入日获得同轮持续期，地图以金环和 `攻x倍率` 标识 |
| 同步规划下相近防御目标每轮互为更优，军队会在几个位置间反复换防 | 防御命令成功后写入 90 天独立部署锁，覆盖最多 30 天行军和至少 60 天驻留；锁期内屏蔽非紧急换防和合并调动。城内敌军、围城解围、实际敌军抵近和战术撤退可打破迟滞，不降低全局 AI 决策频率 |
| 僵持期资源评分轻微波动或固定 360 天超时会反复触发“备战→取消→重新备战” | 删除无条件备战超时；`war_preparation_unready_since_day` 记录资源连续不足起点，连续 90 天不足才取消，期间任一次恢复即清零。目标失效或进攻道路中断仍立即取消；四种子长跑最终取消次数为 `0/0/0/0` |
| 敌军集中后要害城市守军按普通撤退阈值逃离，缺乏“必须守住”的战略约束 | `CityDefensePlan.must_hold_cities` 统一标记受压的首都、粮仓、资源核心、关键粮道和高价值城市，守备需求提高到 100% 威胁覆盖；最后一支必要守军不得离开防区，后方军读取同一缺口增援。本地军力低于来敌 40% 时先驻城待援，避免弱军在城与边之间送死式往返 |
| 国家攻势目标少，且同一军队可能在多个方向的纸面战力中重复出现 | `Nation.campaign_preparation_targets/assignments` 在统一时钟下保存最多 3 个准备目标及一军一目标分配。方向须同时满足 75% 原始攻城人数和按威胁反推的战力预算；达到门槛的目标同批转入 `campaign_attack_assignments` 并分别绘制攻势箭头 |
| 驻边 90 天锁到期后因微小评分变化回城，持续邻敌又被当作新紧急事件立即送回原边 | 当前方向压力不低于新方向的 80% 时保持原边；防御撤退记录刚离开的无向边，锁期内持续邻敌不能绕过锁生成同边反向命令，其他方向的新威胁仍可紧急解锁 |
| 联盟军从盟友领土进攻时，占领地一律归军队所属国；联盟若在和平前解散还会丢失归属链 | 跨入敌境时冻结 `Army.occupation_claimant_nation`，从盟友城市或驻边友方端点出发即归该盟友；`City.occupation_sponsor_nation` 保存直接交战侧，和平确认不依赖届时是否仍结盟 |
| 道路容量以军队支数计，无法表达残编大编制与多支小编制对道路的不同占用 | `Edge.max_manpower` 改为满编人数容量；执行、批处理首段预留和寻路统一按 `Army.max_size`。一支 `13021/15000` 占 15000，三支 `max_size=5000` 也占 15000；反向和敌军独立 |
| 宣战会清空 `war_preparation_target_nation`，旧 `campaign_locked` 因依赖该字段在战争开始后立即失效，计划军重新陷入局部同步等待 | 锁条件改为“存在逐军目标，且仍在备战或目标仍为敌城”；计划军回到集结城/驻边姿态后继续攻击原分配目标，真实要害防御仍可中断 |
| 本国法理城市被占后，反攻军击败占领军仍进入普通围城阶段，常出现胜而不占 | 法理收复只比较实际占领军：空城抵达即恢复控制，击败最后守军同日收复；近期失地优先于原进攻目标、绕过普通攻势冷却，集结不再重复计算本国工事和全国远征下限 |
| 旧版城破后一律固定城防 10 且永不恢复，既抹平城市差异又没有反复争夺窗口 | 易手后当前工事降至完整工事的 50%，按日线性恢复并在第 365 天回满；再次易手重置到 50% 并刷新日期。既有围城、战斗和 AI 统一读取当前 `fort_strength` |
| 溃败军只能把本国城市作为恢复终点，即使更近的盟友城市有通行权和补给也会绕路 | `nearest_friendly_city/route_from_edge` 的恢复终点改为所有拥有军事通行权的本国或盟友城市；抵达盟城后进入同一 `RECOVERING` 状态并使用联盟补给 |
| 15000 编制军无法通过 5000 容量道路，非零狭路在现有军制下等同不可通行 | AI 对有效战争目标先检查标准编制路径；仅当 15000 编制不可达而 5000 编制可达时，将静止军拆为三支 5000 编制。兵力、满编总额、士气、攻防属性及逐军战役目标保持守恒 |
| 国家没有显式军队数量硬上限，拆分后可能无限增加实体 | `GameState.max_army_count` 统一限制每国存活军队数为当前城市数的三倍；建军和拆分共用该门禁，粮食预算仍决定实际可维持规模 |
| 正式 AI 只有固定进攻性，无法配置国家风险偏好；纯僵持时宣战与外交动作不足 | `Nation.ai_aggression` 成为国家级唯一配置源，正式模式按 `0.5～1.5` 截断后同时影响宣战收益、战术进攻/撤退阈值和攻势重整周期；默认 `1.0` 保持镜像一致。当前全局宣战线和国家级攻势线均为 `1.00`，国家级攻势周期为 30 天；普通逐军攻击线仍为 `1.35` |
| 备战动员合法消耗人力储备后，又被和平期完整储备门槛判为不合格并在 90 天后取消 | 开始备战仍要求完整储备；进行中的备战改用独立生存线，保留欠薪、金钱 runway、粮食 runway 和至少 `max(1000, 3%现役兵力)` 应急人力硬约束 |
| 备战期间禁止结盟，AI 无法通过与非目标国结盟释放中立边境驻军 | 结盟意愿加入共同边境实际驻军占全国战力的释放价值；既有备战尚未完成时，可与非目标且非目标盟友结盟。联盟成立后 `CityDefensePlan` 从下一规划周期自然移除该潜在前线，不增加平行防区状态 |
| 持续攻势只在前梯队战败后接替，无法形成道路上的连续攻击纵队 | 前梯队进入目标围城即开放下一梯队；道路容量继续按 `Army.max_size` 实时控制，同梯队未出发成员和后续梯队在容量释放后立即进入道路。前梯队提前失能时仍保留次日接替规则 |
| 重点城市被围时只有普通五日防御规划，守方无法像攻方一样持续投入纵深预备队 | 每日只扫描活跃围城中的首都、粮仓、资源核心、关键粮道和高价值城市；以攻方战力减去城防、守军和已在途援军计算缺口，只调动 `CityDefensePlan.can_redeploy` 允许的最近军队。道路满载时后军等待，前军入城释放容量后次日跟进；缺口填平、围城结束或来源防线不足即停止 |
| 普通城市被攻击时邻城军与相邻边驻军继续执行原任务，无法形成主战场与迟滞战 | 所有活跃围城按防御缺口从大到小处理；邻城闲置军用 `REINFORCE`、目标相邻边驻军用 `RETREAT` 当日转向入城。重点城市按 100% 攻方战力组织主会战，普通城市只投入到 50% 作为迟滞；士气或补给低于 50% 的军队不再抽调 |
| 宣战后多数战争只有首攻：被宣战方没有国家级反攻目标，进攻方在 90 天冷却期完全不集结 | `_manage_campaign_offensive()` 将“组织”与“发动”分离：双方参战国都可选择敌城作为军事目标；防守方目标不覆盖宣战方的外交战争目标。冷却期持续调兵，但不覆盖仍在执行的当前梯队计划；到期才冻结并发动下一波 |
| AI 曾把最快围城档误作最低进攻门槛，导致过度集结 | `required_assault_troops()` 只要求守军/城防的局部优势，并保留全国现役兵力 25% 的主动远征下限；近期法理失地不适用远征下限。围城速度曲线不得跨层充当进攻合法性 |
| 均势战争中普通 Utility 加分始终无法跨过攻击阈值，国家长期只有驻防而无破局动作 | 国家攻势在 30 天窗口用实际集结军、目标威胁及当前准备倍率评估；暂时不足的方向进入显式 180 天满准备集合并持续集结，到期以 2 倍攻击加成统一发动 |
| 满准备攻势破城后立即回到普通逐军 Utility，可能浪费剩余 2 倍加成或把新占城市暴露给反攻 | 满准备发动时保存一次性占城后二阶段预案；破城当天比较留守需求、相邻敌城战力、士气和补给，明确选择追击、驻边或驻城 |
| 既有拆分统计只覆盖无限正面；狭窄正面下完整预备队可越过受损前线，行政拆分改变组织度轮换 | 火力读取侧级兵力加权组织度；`size×morale` 按伤亡和幸存前线侵蚀守恒回写；当回合 routed 军仍参与侧级裁决。5000 正面固定夹具与随机 2～10 支统计逐轮比较胜负、伤亡、火力、加权士气和时长 |
| 重要城市固定 5000/3000/10000 人守军与抽调保底互相叠加，既钉死主力又绕开全国比例预算 | 删除所有城市类型固定人数与攻势抽调保底；正式地图统一使用按重要性、威胁和距离求解的多槽二进制驻防匹配，`15000` 编制军通过覆盖收益/过量投入进入同一目标函数 |
| 码头扩张与军队膨胀使逐军 AI、每日补给和 O(V²) Dijkstra 乘法放大，Renderer 每显示帧全量重绘 | 正式军制降至两档城市比例；Dijkstra 改确定性最小堆；Renderer 运行时最高 30 FPS、暂停 5 FPS，并在日期/窗口变化时立即刷新。headless 同基准提速 `2.06×` |

---

## 7. 安全改动边界（给接手 agent 的护栏）

- **改战斗平衡** → 只动 [combat.gd](scripts/core/combat.gd) 顶部常量（伤害 `K_ROUND`/`DEF_REF`；士气 `MORALE_*`/`MIN_COMBAT_EFFICIENCY`/`SIDE_ROUT_THRESHOLD`；正面 `*_FRONTAGE`；地形 `CHOKEPOINT_*`；围城 `FORT_MANPOWER_PER_POINT`/`SIEGE_RATIO_STALL`/`SIEGE_DAYS_BASE/MIN/DECAY`/`SIEGE_STARVE_DEF_MULT`），跑 `./run_tests.sh` 确认不破坏断言。
- **改行军时长/边距** → 边距唯一换算在 `TerrainMapGenerator.distance_units_for_metric_length()`，三类边均由端点几何长度生成；普通陆路基础值在 `march_days(distance)` 且不设长距离上限，实际时间唯一真源是 `edge_travel_days(edge)`。修改比例或特殊边倍率时同步 Pathfinding、ThreatField、Utility AI 和河运测试。
- **改粮仓机制** → 首都/粮仓登记真源在 `Nation.capital_city_id/warehouse_city_ids`，库存真源在粮仓城市 `food_storage`；禁止重新让普通城市库存参与补给。
- **改补给损耗** → 全局参数为 `Pathfinding.SUPPLY_DISTANCE_LOSS/SUPPLY_DANGER_MULT`，特殊边再乘 `Edge.supply_loss_multiplier`；保持边损耗非负可加。
- **改战后恢复** → `RECOVERY_FOOD_PER_CAPITA` 决定基础需求，运输损耗与普通补给共用；必须同步 [22]，并保持 `RECOVERING` 不进入普通补给计划。
- **改军队拆分或数量上限** → 拆分只允许静止军并要求 `sum(size)`、`sum(max_size)` 守恒；子军继承攻防、士气、补给和战役目标。建军与拆分都必须经过 `GameState.max_army_count`。
- **改补给士气联动** → 路线、共享库存竞争、实际扣粮和 `supply_ratio` 每日重算；`supply_food_debt` 保持 30 天总耗量纲，`supply_debt` 保持减员整人化。拆分/合并必须守恒两类债；同步 [23]/[23b]/[38]。
- **改边地形** → 只动 `danger` 与 Combat 的 `ATTACK_DANGER_K/DEFENSE_DANGER_K/HOLDING_TAU_DAYS/CHOKEPOINT_*`；禁止增加关隘第二真源。关隘惩罚只有敌军实际驻边时才能进入 AI 进攻战力折算。
- **改道路容量** → 容量单位是满编人数，只允许 `0/5000/15000/30000/60000/100000`；必须同步执行期、两阶段首段预留、军队寻路、战略价值归一化和渲染映射，禁止重新使用军队支数。
- **改 AI** → 普通战术候选在 [utility_ai.gd](scripts/ai/utility_ai.gd)，城市防御需求和驻城/驻边姿态在 [city_defense_plan.gd](scripts/ai/city_defense_plan.gd)，战略价值在 [strategic_map.gd](scripts/ai/strategic_map.gd)，威胁窗口在 [threat_field.gd](scripts/ai/threat_field.gd)。修改后运行 `./run_tests.sh`、AI 长跑与严格镜像基准。
- **改攻势加成或部署迟滞** → 只动 `Simulation.OFFENSIVE_BONUS_*` / `DEFENSIVE_DEPLOYMENT_LOCK_DAYS`；攻势倍率必须通过 `ActionCandidate` 随统一命令提交。防御锁保留不同方向的真实紧急解锁，但不得让持续邻敌绕过 `defensive_blocked_edge_*` 返回刚撤离的同一边。
- **改备战或攻势计划** → 备战取消迟滞真源是 `Nation.war_preparation_unready_since_day`；准备期一军一方向真源是 `Nation.campaign_preparation_assignments`，发动后逐军目标真源是 `Nation.campaign_attack_assignments`。并行容量必须由可调兵力推导，不能固定占满三个方向；计划锁在宣战后必须继续生效并持续执行目标，但要害城市真实紧急威胁必须能解除冻结。
- **加新逻辑** → 写进 Simulation，不要写进 Model 或 View。新派生量必须进 `refresh_derived`。
- **加随机** → 必须用 `state.rng`，否则破坏确定性（test #7 会红）。
- **改时间粒度**（天/月分层）→ 时间真源是 `state.day`，`month=day/30` 派生。行军/战斗/攻城每天，经济/粮草/士气恢复在 `day%30==0` 块内。改动需同步 test_suite 中 #6/#7/#8 直接调 `_advance_day()` 的部分。
- **任何改动后** → 必须 `./run_tests.sh` 绿。新增功能应同时在 [tests/test_suite.gd](tests/test_suite.gd) 加断言。

AI 长跑命令：

```bash
/Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/ai_longrun.gd

# A/B 对照旧版“易手后固定城防10且不恢复”
AI_LONGRUN_LEGACY_CAPTURE_FORT=1 /Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/ai_longrun.gd
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

**战斗系统重构（item 1-17 + 五项机制复查 + 多目标准备，2026-08-03）验收状态**（详见 [COMBAT_REFACTOR_CHANGES.md](COMBAT_REFACTOR_CHANGES.md)）：
- 快速回归 `./run_tests.sh` = **1124 passed / 0 failed**（含轻重军角色分离、填线槽位顺序、移动/恢复任务占用、攻势协同、建军优先级，以及既有财政、160 城、外交、河运、战斗和 UI 门禁）。
- item 17 万场统计 = **STATISTICS_PASS**：位置对称 10000/10000；独立战术修正 9997/10000 次不同，A 较高占比 0.5020；20% 明显优势方 10000/10000 获胜；无限正面拆分 2000 场逐位一致；受限正面固定夹具及随机 2000 场、2～10 支在胜负、伤亡、逐轮火力、全军加权士气和时长上逐位一致。
- 160 陆城正式地图 4 种子 × 1095 天：各种子 `eliminated_wars=0`、`terminal_alliance_lock=0`，且 `invalid=0`、`commit_failures=0`；`net_captures=12`、`turnovers=114`、wars 8、offensives 60。城市数稳定超过 30 天的军制偏差为 0；总耗时 `457.4s`。诊断记录的单城瞬时峰值为 13 支，但构成是低士气 `RECOVERING` 残部和战役临时汇合，不是常态驻防槽；正式常态槽仍为每城一军、每边一军。
- 当前并行容量按主方向最低到位兵力后的真实富余量推导，不固定占满三个方向。关键城市没有固定人数保底，正式地图受威胁驻防由 `CityDefensePlan` 的角色槽位决定。
- strict-mirror：seed 1 连续 **3650 天逐日无破裂**，优势分 `0.0`。

---

## 8. 未完成 / 可扩展方向（预留，非 bug）

- `Nation.political_system` 预留字段，未使用。
- AI 当前全知；未来战争迷雾应只改 `AiWorldView` 的可见信息过滤，不要在 Utility 评分层散落可见性判断。
- 无存档/读档。
- `city.at_war` 用“与敌国城市接壤”近似，未精确反映是否有敌军正逼近。
