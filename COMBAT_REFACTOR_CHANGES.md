# 战斗系统重构变更说明

> 对应方案书 [wargame_combat_system_refactor.md](wargame_combat_system_refactor.md) 十七条要求 + 推荐四阶段。
> 基线 commit：`c346dda`（Sustain offensives throughout active wars）。
> 验收：`./run_tests.sh` = **745 断言 / 0 失败**；`tests/combat_statistics.gd` = STATISTICS_PASS（10000 场）；
> 真实地图 4 种子 × 1095 天全部 4 国存活、`invalid=0`、`commit_failures=0`、`starving=0`；
> strict-mirror 基准逐日校验 3650 天无破裂，最终 32:32、有效战力 `504049/504049`、优势分 `0.0`。

---

## 1. 修改的文件

| 文件 | 变更要点 |
|---|---|
| [scripts/core/combat.gd](scripts/core/combat.gd) | 集中常量；纯函数骨架；对称判定 + 平局；士气→战斗效率；正面宽度/预备队；共享战场骰 + 镜像等变独立战术修正；连续地形/围城曲线；`_canonicalize_side`；可回放结构化日志 |
| [scripts/core/combat_log.gd](scripts/core/combat_log.gd) | **新建**：结构化日志 JSONL 落盘、加载、逐回合确定性回放与篡改检测 |
| [scripts/core/equivariant_order.gd](scripts/core/equivariant_order.gd) | **新建**：城市/军队/势力/边的镜像等变物理排序唯一真源，禁止 ID/创建顺序参与行为决胜 |
| [scripts/core/simulation.gd](scripts/core/simulation.gd) | 增援 ETA；每日滚动补给；多方战斗物理词典序；围城状态机；每 tick 单次共享骰/战术熵；全部 AI 军队选择改物理序 |
| [scripts/core/pathfinding.gd](scripts/core/pathfinding.gd) | Dijkstra 等长节点、等价前驱、最近目标和同损耗粮仓统一使用势力局部物理序 |
| [scripts/model/city.gd](scripts/model/city.gd) | `defense` → **`fort_strength`**（工事结构强度，城防点量纲，非兵力）；新增 `has_warehouse`/`war_disruption_until_day` 语义澄清 |
| [scripts/model/army.gd](scripts/model/army.gd) | 新增 `supply_debt`（每日减员整人化累计余额）；`supply_ratio` 注释补充为每日惩罚强度来源 |
| [scripts/model/battle.gd](scripts/model/battle.gd) | 士气派生；增援 tick 聚合；驻防快照；`siege_required`；稳定战术随机键 `tactical_key_a/b` |
| [scripts/core/game_state.gd](scripts/core/game_state.gd) | 军队拆分守恒 + `fort_strength` 引用同步 |
| [scripts/ai](scripts/ai) | 城防/围城量纲同步；`AiWorldView`、Utility、战略图、防御计划、威胁场、外交目标及同城合并全部去 ID 平局决胜 |
| [scripts/view/map_renderer.gd](scripts/view/map_renderer.gd) | 城防显示引用 `fort_strength` |
| [tests/test_suite.gd](tests/test_suite.gd) | 745 断言：原有机制 + 战术随机/日志落盘回放/物理排序镜像等变门禁 |
| [tests/ai_symmetric_duel.gd](tests/ai_symmetric_duel.gd) | 新增 `AI_DUEL_STRICT_MIRROR=1`：逐日比较城市、国家资源和忽略 ID 的军队物理状态多重集 |
| [tests/combat_statistics.gd](tests/combat_statistics.gd) | **新建**：item 17 万场统计（独立 SceneTree 脚本，不入快速回归） |

---

## 2. 核心规则变化（按方案书 item）

**阶段 1（正确性）**
- **item 1 去 A 方偏置 + 平局**：胜负裁决 `decide_winner` 为纯函数，判据全部为镜像不变量（歼灭优先 → 士气溃败 → 对称 `residual` 续战能力），与 side_a/b 位置、军队 id、遍历顺序无关；完全对称 → 平局（`winner_side=0`）。`_canonicalize_side` 在回合起始按纯物理键（size/atk/def/morale 全降序）规范排序两侧，使浮点求和顺序不再破坏镜像。
- **item 2 士气影响战力**：有效战力 = 名义 × `combat_efficiency(morale) = 0.2 + 0.8·morale`。士气是组织度，零士气仍能自卫（20% 火力）但不再打满。整侧派生士气 ≤ `SIDE_ROUT_THRESHOLD=0.15` 判溃败。
- **item 3 伤亡整数守恒**：`distribute_casualties` 纯函数，`Σ 各军实际减员 == 本侧总伤亡`（最大余数法分配，无浮点泄漏）。
- **item 12 增援士气防套利**：本 tick 新增兵力作为整体统一结算一次士气提振（`reinforce_fresh_a/b`），一支援军拆成多支依次加入不重复获奖；单场单侧累计上限 `REINFORCE_MORALE_MAX=0.20`。

**阶段 2（空间）**
- **item 4 增援 ETA**：远援不能瞬间参战——只有归一化距离 ≤ `REINFORCEMENT_RADIUS=0.15`（物理逼近战线）才计入交战，否则继续行军。
- **item 5 正面宽度/预备队**：一侧同时参战兵力上限 = 野战道路容量 / 攻城 `SIEGE_FRONTAGE`；超出进预备队（不贡献火力、不受伤亡），前线损失后按序补入。拆分不增加总正面（基于总兵力前 N 名）。

**阶段 3（围城）**
- **item 6 驻军/城防/城市属性分离**：城市工事真源 = `City.fort_strength`（城防点量纲，≠兵力）。破城所需兵力 `siege_required_manpower(fort_strength) = fort_strength × 100` 显式换算（唯一量纲桥），**不含守军人数**——守军是城下决斗阶段消耗攻方的对手，被歼后封锁需求不变（城防仍来自 fort_strength）。禁止兵力与城防点直接相加/比较。
- **item 7 去 5× 硬门槛改连续曲线**：`manpower_ratio = 攻方有效兵力 / siege_required`。`ratio<0.5` 进度倒退；`0.5~1.0` 极慢；`ratio=1` 取正常下限 `SIEGE_DAYS_BASE=30` 天；`days = 3 + 27/ratio` 单调递减向 `SIEGE_DAYS_MIN=3`（ratio=2→16.5、4→9.75、∞→3）。无跳变、大兵力收益递减。

**阶段 4（体验）**
- **item 8 随机性**：每 tick 只消费一次 `shared_roll`（共同天气/烈度）与一次 `tactical_entropy`。战斗两侧由稳定 `tactical_key_a/b` 分别派生 `±5%` 战术修正；键只依赖镜像轨道位置/势力中心，不含实体 ID、兵力、士气或平衡参数，故调参不会“重抽运气”，拆分也不增加随机机会。交换 A/B 严格交换修正；完全同构且映射到自身的两侧按等变性必要条件得到同值。
- **item 9 地形平滑**：去除 danger 跨阈战力断崖。`danger ≥ CHOKEPOINT_DANGER_ONSET=0.85` 进入隘口带，攻击倍率从该点常规线性值**连续单调**降到 `danger=1.0` 处地板 `CHOKEPOINT_ATTACK_FLOOR=0.25`；地形参数小幅变化只产生小幅结果变化，极端隘口仍强力压制进攻。
- **item 10 补给滚动结算**：经济（月度扣 int 粮 + 写 `supply_ratio`/`starving`）与后果（每日按 `1/30` 摊派士气/减员/溃逃）分离。每日 `_apply_supply_pressure` 逐军独立、无跨军求和、无 id/RNG → 天然镜像等变；全月累计恰等旧月度口径（数值校准不变）。减员经 `supply_debt` 整人化累计（满 1 人才扣、余额留存），避免逐日 `ceil` 取整放大。**粮食扣除仍保持月度**（`food_storage` 为 int，日扣会 30× 通胀，量化证伪日扣方案）。
- **item 11 多方战斗规则**：一条边的交战核心对由物理词典序 argmin 选取（gap 升 → 两军兵力和降 → 镜像轨道实体键升），与军队/势力 id、遍历顺序无关、可复现。二元 side_a/side_b 串行接战，第三方冻结待机、串行接战，不穿过。

**§五 工程要求**
- **item 14 纯函数**：`combat_efficiency`/`distribute_casualties`/`decide_winner`/`siege_required_manpower`/`siege_daily_progress`/`_accrue_supply_pressure` 均无副作用、可独立单测。
- **item 15 结构化日志**：`Combat.battle_log_enabled` 默认关闭；启用后记录 day、回合前后军队快照、战场上下文、共享骰/战术熵/两侧修正及全部结果字段。`CombatLog` 提供 JSONL 落盘/加载和逐回合确定性回放校验；篡改任一结果状态会失败。日志不参与战斗逻辑。
- **item 13 集中配置 + item 单位注释**：全部可调参数集中在 combat.gd / simulation.gd 顶部并含单位/量纲注释。

---

## 3. 新增测试

**快速回归 [tests/test_suite.gd](tests/test_suite.gd)（745 断言 / 0 失败，`./run_tests.sh`）**
- 对称性/守恒/士气/拆分（阶段 1）：位置交换镜像、总伤亡守恒、士气影响战力、防御反拆分不变。
- 空间/增援（阶段 2）：接触点触发、增援 ETA（远援不瞬时参战）、正面宽度/预备队、拆分不增总正面。
- 围城（阶段 3）：`fort_strength` 量纲、`siege_required_manpower` 换算、连续围城曲线标定（ratio=1→30、2→16.5、∞→3）、驻军歼灭后城防仍来自工事。
- 地形（item 9）：`attack_multiplier(0)=1.000 → (0.95)=0.358` 连续单调、无断崖。
- 多方（item 11）：三方串行核心对选取 id-invariance（3 排列 → 单一结果）。
- 滚动补给（item 10，test [23]/[23b]）：逐日累积、相位无关（月初 vs 月末断粮结果一致）、恢复消退、减员整人化、部分缺粮线性、溃逃边沿单次触发。
- 战斗公平与守恒（[35]）：A/B 交换、ID 置换、伤亡守恒、拆分等价。
- **结构化日志（[36]，item 15）**：默认关闭、字段完整、JSONL 往返、逐回合确定性回放、篡改检测、开关不改结果。
- **镜像等变排序（[37]）**：左右镜像国家的城市物理序逐对一致；交换军队 ID 不改变决策顺序。

**批量统计 [tests/combat_statistics.gd](tests/combat_statistics.gd)（item 17，独立脚本，10000 场，STATISTICS_PASS）**
- ① 位置对称：10000/10000 交换 A/B 逐位镜像（平局 0）。
- ② 独立战术随机：9997/10000 次两侧修正不同，A 较高占比 0.5020，交换 A/B 严格交换。
- ③ 优势方胜率：1.3~2.0 倍优势 = 1.0000。
- ④ 20% 明显兵力优势方 10000/10000 获胜（`±5%` 战术波动不覆盖明显优势）。
- ⑤ 拆分不变性：2000 场拆前后胜负与总伤亡逐位一致。
- ⑥ 地形单调压制：201 点采样单调不增。
- ⑦ 固定种子完全复现：10000 场两遍逐位一致。

> item 8 数学边界：若两侧在镜像变换下完全同构且战斗映射到自身，逐局等变要求两侧修正相同；不可能同时强制“不同修正”。非同构空间角色使用独立修正，统计无 A/B 偏置。

---

## 4. 风险闭环

原列 4 项风险已全部处理，无已知未闭环风险：

1. **ID 平局决胜**：新增 `EquivariantOrder`，覆盖 AI 视图、Utility、战略图、防御计划、外交、补给余数、Dijkstra 等长路径、军队合并、战役集结和多方接战。ID 仅保留作 SSoT 标识/字典键/边界检查。
2. **AI 决策层镜像等变性**：`AI_DUEL_STRICT_MIRROR=1` 每天比较镜像城市、国家资源与忽略 ID 的军队物理状态多重集；seed 1 连续 3650 天无破裂，最终优势分 `0.0`。
3. **独立战术随机**：已实现 `±5%` 双侧修正和无偏统计门禁；稳定战术键与战力参数正交，不产生调参重抽或拆分套利。
4. **日志落盘/回放**：`CombatLog` 完成 JSONL 文件序列化、加载、逐回合确定性回放及篡改检测。

---

## 5. 影响存档兼容性的字段变化

> 本项目**无存档序列化机制**（仅 git 快照，脚本无 `to_dict/from_dict/store_var/ResourceSaver`），故以下字段变化不破坏任何持久化面；此处按 DoD 要求如实列出，供未来引入存档时参考。

| 模型 | 变化 | 说明 |
|---|---|---|
| `City.defense` | **重命名 → `City.fort_strength`** | 语义不变（城防点量纲），仅正名以杜绝与兵力量纲混用（item 6）。全仓引用已同步。 |
| `Army.supply_debt`（新增 `float=0.0`） | item 10 每日减员整人化累计余额；默认 0 即满足行为，无需持久化重置。 |
| `Battle.morale_a/morale_b`（**移除**） | 士气真源改为 `Army.morale`，Battle 层用 `side_morale()` 兵力加权派生。 |
| `Battle.reinforce_fresh_a/b`、`holding_side/holding_days`、`siege_required`、`tactical_key_a/b`（新增） | 战斗内瞬态/快照字段，战斗结束即失效，无持久化意义。 |
| `Combat.battle_log_enabled/battle_log`（新增 static） | 调试用，默认关闭；非世界状态、不属 SSoT。 |
