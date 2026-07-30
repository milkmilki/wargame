# World-War 项目交接文档

> 面向接手的 AI agent / 开发者。目标：不读全部源码即可理解架构、约定、当前状态与安全改动边界。
> 最后更新：2026-07-30（灰度高度图城市/道路生成与四国连续分区完成并通过全量验证后）。

---

## 0. 一句话概述

Godot 4.7.1 + GDScript 编写的 **2D 平面战略"看海"游戏**（简化版 EU4，纯观赏、全 AI、实时推进）。
从带 Alpha 的灰度高度图生成 64 城非规则图，4 国各 16 个连续城市，开局全面战争，AI 自动寻路、交战、占领，直到一国统一。

---

## 1. 如何运行 / 测试（先做这个）

| 操作 | 命令 |
|---|---|
| Godot 可执行文件 | `/Users/bytedance/Godot.app/Contents/MacOS/Godot`（4.7.1.stable） |
| 运行游戏（图形） | 用 Godot 打开项目按 F5，或 `Godot --path /Users/bytedance/world-war` |
| **回归测试（改代码后必跑）** | `./run_tests.sh`（退出码 0=全过，非0=有失败） |
| 仅编译检查 | `Godot --headless --path <项目> --editor --quit`（无 `SCRIPT ERROR` 即通过） |

`run_tests.sh` 两阶段：①headless 导入捕获脚本错误 ②运行 `tests/test_suite.gd`（当前 **284 断言 / 0 失败**）。
Godot 路径可用环境变量覆盖：`GODOT=/path/to/godot ./run_tests.sh`。

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
| [scripts/model/city.gd](scripts/model/city.gd) | 数据 | `id, map_position, terrain_height, terrain_relief, owner_nation, defense, manpower_per_month, gold_per_month, food_per_half_year, is_capital, has_warehouse, food_storage(仅粮仓城市有效), at_war` |
| [scripts/model/edge.gd](scripts/model/edge.gd) | 数据 | `city_a<city_b, max_throughput(0=不可供大军/补给通行，1~4=每国每方向容量), distance, danger, max_height_difference, occupied, passing_count(全方向总占用派生)` |
| [scripts/model/nation.gd](scripts/model/nation.gd) | 数据 | `id, color, treasury_gold, manpower_pool(全国人口SSoT), capital_city_id, warehouse_city_ids, granary_food, alive` |
| [scripts/model/army.gd](scripts/model/army.gd) | 数据 | `id, owner_nation, size, max_size(默认15000), attack, defense, location/state/path, on_edge, starving, morale, AI命令元数据` |
| [scripts/model/battle.gd](scripts/model/battle.gd) | 数据 | 持久多回合战斗：`id, kind(FIELD/SIEGE), side_a[]/side_b[], edge, city, contact_dist_a/b, round_no, siege_progress(SIEGE累积破城), has_garrison(side_b是否驻城守军), garrison_ref(围城5×门槛的守方兵力基准快照), finished, winner_side`；`side_morale()` 兵力加权派生士气 |
| [scripts/core/game_state.gd](scripts/core/game_state.gd) | SSoT | `generate_world(seed)`、`warehouse_cities_of/deposit_food/remove_warehouse/relocate_capital`、`edge_of/neighbors/is_enemy/army_at_city/cities_of/refresh_derived`、`new_battle/battle_by_id`、`city_under_siege(id)`、`battles/day/month/winner/rng` |
| [scripts/core/terrain_map_generator.gd](scripts/core/terrain_map_generator.gd) | 地图生成 | Alpha 陆地提取、平坦城市采样、Delaunay 局部道路、高度剖面与连通骨架 |
| [scripts/core/pathfinding.gd](scripts/core/pathfinding.gd) | 静态 | 寻路、补给与 `can_reach_manpower_hub`；补给边损耗=`0.1×distance×(1+danger)` |
| [scripts/core/combat.gd](scripts/core/combat.gd) | 静态 | 战斗解算 + `siege_daily_progress(attacker_size,garrison_ref)` 确定性围城进度，见 §4 |
| [scripts/core/simulation.gd](scripts/core/simulation.gd) | 逻辑 | 按天推进主循环 + `march_days(distance)` 行军时长（R1），见 §5 |
| [scripts/ai/](scripts/ai) | AI | `AiWorldView` 只读视图、`StrategicMapSnapshot` 图论价值、`ThreatField` 60天威胁、`UtilityAI` 候选评分、`ArmyCoordinator` 合并/目标预留 |
| [scripts/view/map_renderer.gd](scripts/view/map_renderer.gd) | 渲染 | 只读 `_draw`，绘制地图/城市/边/军队/HUD(Day/Month)/攻城进度弧，处理输入 |
| [scripts/main.gd](scripts/main.gd) | 入口 | 装配 GameState/Simulation/MapRenderer |
| [main.tscn](main.tscn) | 场景 | 默认真实高度图场景（Main + Simulation + MapRenderer） |
| [square_map.tscn](square_map.tscn) | 场景 | 保留的原始 `8×8` 方形地图场景；Main 的 `use_grid_world=true` |
| [tests/test_suite.gd](tests/test_suite.gd) | 测试 | 284 断言，headless 运行 |
| [tests/ai_longrun.gd](tests/ai_longrun.gd) | 诊断 | 4 种子 × 1095 天 AI 长跑，检查领土变化、命令覆盖和非法实体 |
| [tests/ai_symmetric_duel.gd](tests/ai_symmetric_duel.gd) | 基准 | 64 城严格左右镜像；A 左侧改进 Utility AI、B 右侧修改前当前 Utility AI，十年对战并输出领土/军力/粮食/首都指标 |
| [run_tests.sh](run_tests.sh) | 测试 | 一键编译+测试封装 |

---

## 4. 战斗系统（[combat.gd](scripts/core/combat.gd) + [battle.gd](scripts/model/battle.gd)）—— EU4 式多回合

**核心变化**：战斗从"瞬时一击解算"改为 **EU4 式多回合掷骰持续战斗**。一场战斗是持久化的 [Battle](scripts/model/battle.gd) 对象，存在 `GameState.battles` 中，**每天（tick）打一个回合**（`Combat.resolve_round`），直到一方兵力归零或士气崩溃。均势会战约 10-13 天。

**统一模型**：野战（`Kind.FIELD`）与攻城（`Kind.SIEGE`）共用回合解算，但 SIEGE 走专用状态机 `_advance_siege`（见 §5）。攻方在城墙 `dist=L`，守军在城中 `dist=0` 且**当 `has_garrison=true` 时**享 `city.defense` 城防加成。

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
attack_multiplier = 1 − 0.50 × danger
defense_multiplier = 1 − 0.40 × danger × exp(−holding_days / 30)
```

`danger` 是地形难度唯一持久真源，不存在 `terrain_type/is_pass`。攻击惩罚固定；只有战前处于 `HOLDING` 的防守侧可用驻防时间逐步消除防御惩罚，倍率无限趋近 1 但不超过 1。普通相向遭遇双方 `holding_days=0`。

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
| `SIEGE_PROGRESS_REQUIRED` | 100.0 | 破城所需累积进度（满 100 破城，`siege_progress += siege_daily_progress`） |
| `SIEGE_RATIO_MIN` | 5.0 | **R2 有效推进最低兵力倍数**：攻方/守方基准 < 5 则围城终止并强制撤离 |
| `SIEGE_DAYS_MIN` | 3.0 | **R2 饱和进攻(r→∞)最短围城天数** |
| `SIEGE_DAYS_BASE` | 90.0 | **R2 基准围城天数**（r=5 时） |
| `SIEGE_DECAY_K` | 435.0 | **R2 递减系数** = (90−3)×5，使 `围城天数 = clamp(3 + 435/r, 3, 90)` 在 r=5→90、r→∞→3 平滑递减 |
| `SIEGE_INTERRUPTION_DECAY_PER_DAY` | 0.25 | 守城/解围战每持续一天，既有攻城进度回退 0.25 点，最低为 0 |
| `SIEGE_STARVE_DEF_MULT` | 0.3 | **R3 粮尽守军城防加成衰减系数**（`food_storage≤0` 时城防 ×0.3，战力大幅下降） |

> **R2 围城确定性递减（本轮替换旧掷骰模型）**：`siege_daily_progress(attacker_size, garrison_ref)`：令 `r = attacker_size / max(garrison_ref,1)`；`r<5` 返回 0，`Simulation` 据此结束围城并让攻方撤离；否则 `days = clamp(3 + 435/r, 3, 90)`、返回 `100/days`。**去掉掷骰**使围城天数精确可测（r=5→90 天、r=10→48 天、r→∞→3 天），且**与 city.defense 解耦**。`garrison_ref` 是围城开始时的守方兵力基准快照，守军被歼后仍保留。

> 调参依据：`K_ROUND=120, MORALE_CASUALTY_K=1.2` 下，均势会战约 10-13 天、优势方约 5-7 天（战斗常量在天/月分层后**零改动**，因每天一回合恰好把原"月级回合"落到"天级"，会战时长更贴合真实）。

### 4.6 第十二轮平衡规格 R1-R4（本轮新增，需求 SSoT）

| 规格 | 规则 | 落地 |
|---|---|---|
| **R1 行军时间** | 任意长度道路 **最短 10 天、最长 30 天**，按长度线性插值 | `Simulation.march_days(distance) = clamp(10 + (distance−1)×5, 10, 30)`；distance∈[1,5]→[10,30] 天；每天推进 `1/march_days`。**副作用：speed_factor 与 danger 不再影响行军时长**（speed_factor 成行军侧死字段；danger 仍用于战斗地形惩罚 + 寻路边权） |
| **R2 围城** | 攻方兵力 **≥5×守方基准**才推进，不足则强制撤离；基准 **90 天**；兵力优势增 → 时间递减；饱和最短 **3 天** | `Combat.siege_daily_progress` + `Simulation._withdraw_failed_siege`；`garrison_ref` 快照分母 |
| **R3 粮草** | 被围城市切断外部补给；只有城市本身设有粮仓时可继续消耗本地库存，粮尽后战力大幅下降 | 当前每国仅首都有粮仓；`Simulation._drain_siege_food()` 每天扣被围粮仓库存；普通城市无本地库存，被围即断供；粮尽 → 守军城防 ×`SIEGE_STARVE_DEF_MULT=0.3` |
| **R4 空城弱攻退避** | 攻空城时**兵力 < 城基础防御**则不建围城、不占城，**自动向友方城撤离** | `Simulation._start_or_join_siege`：`defender==null and attacker.size < city.defense` → `_retreat_to_friendly`（`Pathfinding.nearest_friendly_city` 仅沿本国城市找最近本国城，无合法通道则溃散） |

> **用户两个架构拍板**：① 围城模型保留"守军实战"（有守军先打实战、歼灭后转纯围城递减），非改为 EU4 纯被动围城；② 断粮结局是"战力大幅下降"（城防 ×0.3 + 断粮士气加速崩溃），非"粮尽即投降破城"。
> **R4 触发频率提示**：world-gen `city.defense∈[10,30]` 远小于攻方兵力(size∈[500,1500])，故 R4 在默认参数下**极少触发**，作边界护栏存在（测试 [21] 用 `defense=300` 人工构造触发场景验证）。

### 4.7 第十三轮：士气崩溃撤退与驻城恢复

1. **撤退触发**：战斗结束时，败方所有存活军队进入 `RETREATING`；若双方同时崩溃，士气为 0 的名义胜方同样撤退，不得继续追击。
2. **最近友城**：边上溃败时，从真实 `move_progress` 分别计算到道路两端的剩余距离，再叠加端点到各友城的 Dijkstra 距离，选择全局最短路线。起点允许是刚失守的敌城，但离开起点后的路径只能经过本国城市，禁止穿越敌城。撤退途中不受 AI 指令，但可被普通 `MOVING` 敌军被动接战；两支 `RETREATING` 军不会互相主动开战。`forced_retreat` 在被动战斗中保留，获胜后继续原撤退路线。目的地失守时重新寻路，无可达友城则溃散。
3. **驻城恢复**：抵达目标友城后转 `RECOVERING`。该状态计入驻城守军，但 AI 不得调动；视图用稳定蓝圈标识。
4. **恢复资源**：每 30 天恢复至多 `MORALE_RECOVER=0.15`；从损耗最低的可达粮仓取粮，完整恢复月基础需求为 `ceil(size × RECOVERY_FOOD_PER_CAPITA)`，再计运输损耗。`RECOVERING` 不进入普通 `_resolve_supply`，避免双扣。
5. **解除条件**：士气回满，或无可达有粮粮仓，转 `IDLE`；后者保留尚未恢复满的士气。城市易主时，城内所有旧城主 `IDLE/RECOVERING` 驻军立即重新撤退，禁止滞留敌城。
6. **断粮联动**：自由态军队每月按补给缺口比例损失士气：`morale_loss = SUPPLY_MORALE_LOSS_MAX(0.20) × shortfall/demand`。士气从正值跌至 0 时立即触发溃逃；交战军仍由当日战斗结算触发撤退。

### 4.8 第十五轮：边上驻防、补给与地形适应

- **边上部署**：新增 `HOLDING`。军队固定在边中点、保持 `on_edge=true` 并占用 throughput；敌军接触后进入 FIELD，原驻防军获胜恢复 `HOLDING`。
- **适应累计**：满补给每天 `holding_days+1`；部分补给暂停；完全断粮每天 `−2`。换边、主动移动或撤退清零。
- **增援稀释**：驻防侧战斗快照保存兵力加权驻防天数；非驻防增援加入时按 `old_days×old_size/new_total` 稀释。
- **双端点补给**：边上军队按真实 `move_progress` 比较到两个端点的剩余距离，只要端点属于本国，就可从该端点接入补给网络；当前所在边出现敌军不会直接断供。端点之后的补给路径仍只能经过本国城市，且不能通过有敌军争夺的其他道路。
- **AI**：驻防边由 Utility AI 综合 `danger`、边战略价值、补给走廊、桥影响与局部威胁评分；同国同边只允许一个驻防命令。军队抵达驻防点后持续保持 `HOLDING`，不设时间上限。
- **视觉**：道路按 `max_throughput=1/2/3/4` 逐级加宽、提亮，3~4 级主通路带暗色外描边；`0` 容量边用暗色连接线与中点叉号显示高山/小渡口阻断。`danger` 仍叠加红色风险色，不增加第二地形真源。

### 4.9 无训练分层 Utility AI

- **只读边界**：`AiWorldView` 当前提供全知视野；决策层不直接遍历/修改 `GameState`，未来战争迷雾只替换视图筛选。
- **战略图**：城市价值综合首都、粮仓、经济、粮食与城防；Tarjan DFS 识别本国桥和割点；粮仓到前线的路径流量参与边价值。`ownership_revision` 变化时才失效重算。
- **威胁场**：军队按城市聚合，以 60 天为窗口传播；`power=size×质量×士气×补给`，贡献按 `exp(-arrival_days/30)` 衰减。
- **候选行动**：`HOLD/REINFORCE/MERGE/ATTACK/RETREAT` 同时评分，固定同分 ID 决胜。进攻只选当前敌方边境城，避免评分纵深目标但实际先撞边境城。
- **协调与滞回**：友军支援不使用可在多前线重复计数的威胁场，而由 `ArmyCoordinator` 一军一目标真实预留；前线军先决策，内线小军先在后方合并，单军能填补至少 50% 缺口才直接增援。命令记录 `target/score/reason/created_day/until_day`。
- **合并守恒**：每日合并同城同状态军队及同位置驻防军；兵力求和，攻击/防御/士气/补给/驻防天数按兵力加权，边容量同步释放。
- **驻防出击**：`HOLDING` 没有时间上限；只有士气、补给、局部战力和 5× 围城兵力（另留 1.5 倍战损余量）同时满足时，AI 才显式下达 `ATTACK`，从当前边位置连续推进。
- **同边敌军估值**：远方威胁可按抵达时间衰减，但同一条边上的敌军是下一场直接接战对象，必须按 `100%` 有效战力计入。驻防军出击使用“折扣威胁场”和“同边敌军实值”的较大者，避免未满编军误攻满编驻防军。
- **单军生存门槛**：联合兵力池决定整个攻势能否成立，但每支正常进攻参与军自身有效战力还必须达到目标局部敌军战力的 `35%`。这阻止几百人残部借用纸面联合战力分批冲锋；真正被围断粮军仍使用独立的 `0.70` 背水突围门槛。
- **多方向协同**：敌城相邻正容量边上的实际友军按来源邻城计为独立方向，联合兵力达到围城/战力门槛后才进攻。最慢方向先出发，较快方向等待到预计抵达时间差不超过 5 天，避免“同日下令、分批送死”。
- **断粮突围与解围**：补给率 `≤25%` 且无法经本国控制网抵达粮仓才算真正被围；突围优先级高于普通动作，但只攻击战力比 `≥0.70` 的最弱包围节点。被围城和断粮友军形成紧急救援缺口，相邻敌城作为打通通道的高价值目标。
- **建军/解散**：AI 国家级命令 `CREATE_ARMY/DISBAND_ARMY`。军队数低于 `max(前线数+2, ceil(城市数/4))` 时在未被围首都粮仓消耗 5000 人建军；仅在军队数超额时解散安全后方 `<500` 人残部，幸存人数全额返还人口库。
- **后勤中心守备**：首都最低有效战力=`max(5000, 60日威胁×1.25)`，其他粮仓=`max(3000, 60日威胁)`。抽走某军会跌破门槛时拒绝普通移动；缺口优先从人口库新建 5000 人守备军，人口不足时才生成定向 `REINFORCE`，避免从前线无上限抽兵。
- **调度**：每日先合并；每 5 天重算威胁并决策；城市易主通过版本号触发下一轮战略图重算。所有国家性格由 nation id 确定生成，不训练、不引入随机不可复现性。

### 4.10 全国人口与自动补员

- `Nation.manpower_pool` 是可用人口唯一真源；城市没有本地人口库存。
- `City.manpower_per_month` 每月立即汇入当前所属国；开局人口库按 `Σ(manpower_per_month×100)` 初始化。
- 每军 `max_size=15000`，新军固定 5000 人；自动合并只能补到满编，超出部分保留为另一支军队。
- 每月人口收入后、粮食结算前补员。单军每月最多补充 `750` 人；符合条件的缺编军按本月可补缺口比例公平分配人口，同余数按填充率和 army id 确定性分配。
- 友城和可接入本国粮仓网络的友方边允许补员；被围城、争夺边、`FIGHTING`、`RETREATING` 禁止补员。
- HUD 中“人”表示人口库，“兵”表示已部署总人数。

---

## 5. 天推进主循环（[simulation.gd](scripts/core/simulation.gd) `_advance_day`）—— 天/月分层（第七轮）

实时时钟：`_process(delta)` 累积到 `seconds_per_day`（默认 1.0，即 1 秒=1 天）触发一次 `_advance_day`。**基础 tick = 1 天**，行军/战斗/攻城每天推进；经济/粮草/士气恢复仍每月（30 天）结算，数值口径与原按月一致，仅还原到每 30 天一次。常量：`DAYS_PER_MONTH=30`、`DAYS_PER_HALF_YEAR=180`。

```
state.day += 1;  state.month = state.day / 30       # month 为派生显示量
if state.day % 30 == 0:                              # 每月结算块
    1. _resolve_economy()   金钱/人口月产出；(day%180==0 时半年注粮)
    1b._resolve_reinforcements() 全国人口库按缺口公平补员
    2. _resolve_supply()    补员后的军队取粮 + 刷新 army.starving
    2b._recover_morale()    普通非交战军恢复；RECOVERING 驻军从损耗最低的可达粮仓取粮
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
  - 无既有 SIEGE：**R4 空城弱攻退避**——空城（无守军）且 `attacker.size < city.defense` → 不建围城、`_retreat_to_friendly` 撤离（见 §4.6）；否则有守军建带守军 SIEGE（`has_garrison=true`、`garrison_ref=守军兵力`），**空城（强攻）建纯围城 SIEGE**（side_b 空、`garrison_ref=city.defense`），不再瞬占。
  - 既有 SIEGE 且与围城方同 nation → 并入 side_a（多路汇合）。
  - 既有 SIEGE 且与围城方敌对：
    - **守军仍在**（`has_garrison` 且 side_b 非空）：与守军同族者（=城主援军）**入城帮守**并入 side_b（享城防加成，[15](c)）；真第三国无处容身 → 以已抵达的目标城为锚点 `_retreat_to_friendly`，不得瞬移回来源城（[15](d)、[28]）。
- 每 tick 推进 `_resolve_battles()`：FIELD 走 `Combat.resolve_round` + `_finish_field_battle`；SIEGE 走 **`_advance_siege` 三阶段状态机**（见下），最后 filter 掉 `finished` 战斗。

**SIEGE 状态机 `_advance_siege`（守军歼灭 ≠ 破城）**：
1. **守军抵抗**（`has_garrison` 且 side_b 非空）：`resolve_round` 削守军。攻方被击退→真结束；守军溃散→`_retreat_defender` 清走守军、`has_garrison=false`、转纯围城（**不占领**）。战败守军必须排除当前守城城市撤往其他友城，抵达后才进入 `RECOVERING`；不能在原城恢复，无可达友城则溃散。
2. **城下决斗**（side_b 为敌对挑战者，无城防加成）：分胜负后——挑战者胜且**为城主（`side_b.owner==city.owner`）→ 解围成功，入城 `_settle_idle`、战斗结束**；挑战者胜且为敌对他国 → `_promote_challengers` 接管围城继续攻。围城方胜 → 挑战者撤退、围城继续。（第九轮修复：城主解围胜利不再被 `_promote_challengers` 误升为"围攻自己城"，[15](e)。）
3. **纯围城累积（R2 确定性递减）**：无对抗时计算 `siege_daily_progress`；`r<5` 立即结束围城并让攻方沿真实路径撤回友城，禁止永久切断补给；否则按 90→3 天递减累积。达 100 后破城。`_promote_challengers` 接管围城时重置 `garrison_ref=city.defense`。

每个围城日开始，`_reconcile_siege_city_defenders` 都会重新收集目标城内尚未参战的 `IDLE/RECOVERING` 本国守军。任何守军都会先把围城切回战斗阶段；守城或解围战期间，`siege_progress` 每天回退 `0.25` 点，守军被击败前不得继续推进或占领。

**粮食/饥饿（首都粮仓 + 可扩展多粮仓）**：`Nation.capital_city_id` 是首都真源，`warehouse_city_ids` 登记本国粮仓；当前每国只有首都一个粮仓，但寻路按集合实现。每半年所有本国城市产出立即汇入首都。军队只从登记且有粮的粮仓取粮，并最小化路径损耗：每条边 `loss=0.1×distance×(1+danger)`，路径按边加总；月需求=`size×FOOD_PER_CAPITA×(1+route_loss)`，`FOOD_PER_CAPITA=0.0025`，总倍率封顶 3。镜像稳态门禁中每国 32 城、10 支满编 15000 人军队，一年粮食净增 `+414/+442`。
**首都失守**：旧首都粮仓注销，库存 30% 汇入胜方首都、70% 损毁；败方若仍有城市，选择防御最高（同防御按 id）的城市迁都并建立空粮仓，无城则不迁都。
**R3 补给孤岛**：被围城切断外部粮仓连接。若被围城市本身是有粮仓，则守军使用本地库存且由 `_drain_siege_food` 每日扣 1；普通城市无本地库存，被围后立即断供。粮尽后守军城防加成 ×`SIEGE_STARVE_DEF_MULT=0.3`。

**移动/边约定（易错点，改动前必读）**：
- 行军锚点统一用 `move_from`（不是 location_city）。`_begin_next_leg` 前置约定：调用前 `move_from` 已锚定当前城，末尾置 `army.on_edge=true`。
- **边占用的唯一判据是 `army.on_edge`**。`passing_count` 只统计全方向/全阵营总占用并供渲染使用；容量由 `_friendly_same_direction_count` 从军队 SSoT 实时派生。
- `max_throughput` 对每个国家、每个方向分别生效：仅同国同向军队互相占名额；同国反向与敌军均不占本方向容量，因此追逐和迎战不会被敌军交通量阻塞。
- 正式世界从 `china-map-...webp` 的 Alpha 最大连通区域提取陆地，在局部低起伏区域用确定性最远点采样生成 64 城；按地图真实宽高比强制最小城市间距 `0.075`。
- 真实地图道路使用 Delaunay 三角剖分生成自然局部邻接，超出地图尺度 `0.30` 的普通局部边不加入；按距离、陆地覆盖率和高度差加权的最小生成树只负责保证全图连通，最长边测试门禁为 `0.36`。真实地图不承诺固定总边数或每城固定度数。
- 每条边沿灰度图采样高度剖面，最大高度差决定 `max_throughput=0/1/2/3/4`；骨架边最低为 1，保证军事、补给和撤退网络连通。
- 四国按空间均衡分区，每国严格 16 城且本国正容量道路连通。首都选择本国城市几何中心附近的城市。
- `main.tscn` 使用 `generate_world()` 高度图世界；`square_map.tscn` 使用 `generate_grid_world()`，保留原 `8×8 / 112` 边方形地图。固定城市 ID 的状态机测试和严格左右镜像 A/B 基准同样使用网格世界。
- `max_throughput=0` 是统一的军事与补给不可通行语义；普通寻路、撤退、威胁传播、补给、战略桥/割点均跳过。旧路径遇到 `0` 边立即失效并重规划或回到驻地，不进入永久排队。
- `_release_edge(army)` 以 `on_edge` 为准，幂等，防止 `passing_count` 双重释放变负。
- `_settle_idle` / `_capture_city` / `_retreat` 均先 `_release_edge(army)` 并清 `battle_id=-1`。
- `_purge_dead_armies` 统一清理 size≤0 军队并用 `on_edge` 释放其占用边。

**战斗视觉反馈（[map_renderer.gd](scripts/view/map_renderer.gd)，纯只读派生，第六轮新增）**：
- **士气条**：每支军队圆下方细横条，宽度=士气值，红(0)→黄(0.5)→绿(1)。直观展示疲劳/濒溃。
- **交战军队**：`FIGHTING` 状态额外画脉动红圈描边，一眼区分“正在打仗”与行军。
- **战斗爆发标记 `_draw_battles`**：每场活跃 Battle 在交战点（野战=边上 `contact_dist_a` 处，攻城=城中心）画脉动星芒 + 扩散环（半径随 `round_no` 增大）+ `R{round_no}` 回合数文字；**SIEGE 额外画 `siege_progress/REQUIRED` 攻城进度弧**（青色圆弧，直观展示破城进度）。
- **HUD 头部**：显示 `Day %d (M%d) ...`（`state.day` 为真源，`state.month` 派生）。
- **响应式布局**：项目禁用固定逻辑画布拉伸，`MapRenderer.compute_layout_for_viewport` 按实际窗口尺寸同比缩放地图、标记、线宽与字号；地图水平居中，窄窗口的国家概览自动减少列数并换行。
- **高度图底图**：渲染器按生成器记录的 Alpha 陆地包围盒裁切同一灰度图，以低亮度半透明背景先绘制；道路、城市和军队保持前景层。城市标记使用紧凑尺寸，避免 64 城互相遮挡。
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
| 两支敌军同日到达边中点时若先转 HOLDING、后做遭遇检测，会因双方都非主动方而互相无视 | 到达驻防点只先 clamp，遭遇检测完成后仍未交战者才转 HOLDING，[25] 固化 |
| 驻防时间上限会让军队在无战术事件时自动离开阵地，与驻防语义冲突 | 删除 180 天自动推进机制；`HOLDING` 持续到接战、撤退或其他显式命令改变状态 |
| 驻防增援若直接继承老兵适应天数，可用小军提前驻防再让大军免费获得满适应 | Battle 快照按兵力加权稀释驻防天数，[27] 固化 |
| `_detect_encounters` 要求至少一方为 `MOVING`，导致 `HOLDING × RETREATING` 接触后互相无视 | 只排除 `RETREATING × RETREATING`；驻防军可截击溃逃军，[28] 固化 |
| 到达中间城后下一边拥堵，`move_from` 已更新但 `location_city` 仍指旧城，渲染跳回旧锚点 | `_arrive_at_node` 到达后同步 `location_city=arrived`，[28] 固化 |
| 多军共同破城时非主占领军 `_settle_idle(a, a.move_from)`，从城墙端点瞬移回出发城 | 统一落位 `battle.city.id`；四种子 × 1095 天位置连续性验证通过，[28] 固化 |
| 第三方抵达已有守军的围城后 `_settle_idle(attacker, attacker.move_from)`，从道路末端瞬移回来源城 | 改为从已抵达的目标城 `_retreat_to_friendly`，保持道路连续性，[12]/[15]/[28] 固化 |
| Renderer 重开复用旧世界位置快照，相同 army id 会从旧坐标插值飞向新坐标 | `MapRenderer.setup` 清空 `_prev_pos/_curr_pos` 并重置 `_last_day`，[28] 固化 |

---

## 7. 安全改动边界（给接手 agent 的护栏）

- **改战斗平衡** → 只动 [combat.gd](scripts/core/combat.gd) 顶部常量（含围城 `SIEGE_RATIO_MIN`/`SIEGE_DAYS_MIN/BASE`/`SIEGE_DECAY_K`/`SIEGE_STARVE_DEF_MULT`），跑 `./run_tests.sh` 确认不破坏断言。
- **改行军时长** → 只动 [simulation.gd](scripts/core/simulation.gd) 的 `MARCH_DAYS_MIN/MAX` 与 `march_days(distance)`（R1 唯一真源）；改斜率须同步 [18] 断言。
- **改粮仓机制** → 首都/粮仓登记真源在 `Nation.capital_city_id/warehouse_city_ids`，库存真源在粮仓城市 `food_storage`；禁止重新让普通城市库存参与补给。
- **改补给损耗** → 只动 `Pathfinding.SUPPLY_DISTANCE_LOSS/SUPPLY_DANGER_MULT`；保持边损耗可加，才能用单标量 Dijkstra 保证全局最优。
- **改战后恢复** → `RECOVERY_FOOD_PER_CAPITA` 决定基础需求，运输损耗与普通补给共用；必须同步 [22]，并保持 `RECOVERING` 不进入普通补给计划。
- **改补给士气联动** → `SUPPLY_MORALE_LOSS_MAX` 是完全断粮月度士气损失，部分缺粮按比例缩放；必须同步 [23]。
- **改边地形** → 只动 `danger` 与 Combat 的 `ATTACK_DANGER_K/DEFENSE_DANGER_K/HOLDING_TAU_DAYS`；禁止增加关隘第二真源。
- **改 AI** → 评分权重与阈值只在 [utility_ai.gd](scripts/ai/utility_ai.gd)，战略价值只在 [strategic_map.gd](scripts/ai/strategic_map.gd)，威胁窗口只在 [threat_field.gd](scripts/ai/threat_field.gd)。修改后运行 `./run_tests.sh` 与 AI 长跑。
- **加新逻辑** → 写进 Simulation，不要写进 Model 或 View。新派生量必须进 `refresh_derived`。
- **加随机** → 必须用 `state.rng`，否则破坏确定性（test #7 会红）。
- **改时间粒度**（天/月分层）→ 时间真源是 `state.day`，`month=day/30` 派生。行军/战斗/攻城每天，经济/粮草/士气恢复在 `day%30==0` 块内。改动需同步 test_suite 中 #6/#7/#8 直接调 `_advance_day()` 的部分。
- **任何改动后** → 必须 `./run_tests.sh` 绿。新增功能应同时在 [tests/test_suite.gd](tests/test_suite.gd) 加断言。

AI 长跑命令：

```bash
/Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/ai_longrun.gd
```

左右镜像 A 改进 AI / B 当前 AI 对战：

```bash
/Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/ai_symmetric_duel.gd
```

当前基准结论（固定种子，两侧均为同版 Utility AI，仅 A 启用 `0.35` 单军生存门槛、B 使用修改前的 `0`）：第 1 年 A 为 `28:36`，第 2 年反超至 `37:27`，第 3650 天 A 为 `63:1`，优势分 `132579.7`，退出码 `0`，结论 **IMPROVED_AI_BETTER**。基准启动前会验证城市、军队、道路左右镜像及 32 城满编稳态年度粮食结余为正。

---

## 8. 未完成 / 可扩展方向（预留，非 bug）

- `Nation.political_system` 预留字段，未使用。
- `Nation.at_war_with` 双边战争关系被注释掉；当前是"全面战争"（`owner_a != owner_b` 即敌对）。若要做外交/联盟需启用它并改 `GameState.is_enemy`。
- AI 当前全知；未来战争迷雾应只改 `AiWorldView` 的可见信息过滤，不要在 Utility 评分层散落可见性判断。
- 无存档/读档。
- `city.at_war` 用"相邻异属"近似，未精确反映"是否有敌军正逼近"。
