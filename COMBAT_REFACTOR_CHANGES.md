# 战斗系统重构变更说明

> 对应方案书 [wargame_combat_system_refactor.md](wargame_combat_system_refactor.md) 十七条要求 + 推荐四阶段。
> 基线 commit：`c346dda`（Sustain offensives throughout active wars）。
> 验收：`./run_tests.sh` = **783 断言 / 0 失败**；`tests/combat_statistics.gd` = STATISTICS_PASS（10000 场）；
> 真实地图 4 种子 × 1095 天全部 4 国存活、`invalid=0`、`commit_failures=0`，
> 共 34 次实际易手 / 10 次宣战 / 69 次攻势（其中 17 次满准备）；strict-mirror 基准逐日校验 3650 天无破裂，优势分 `0.0`。

---

## 1. 修改的文件

| 文件 | 变更要点 |
|---|---|
| [scripts/core/combat.gd](scripts/core/combat.gd) | 集中常量；纯函数骨架；对称判定 + 平局；士气→战斗效率；正面宽度/预备队；共享战场骰 + 镜像等变独立战术修正；连续地形/围城曲线；`_canonicalize_side`；可回放结构化日志 |
| [scripts/core/combat_log.gd](scripts/core/combat_log.gd) | **新建**：结构化日志 JSONL 落盘、加载、逐回合确定性回放与篡改检测 |
| [scripts/core/equivariant_order.gd](scripts/core/equivariant_order.gd) | **新建**：城市/军队/势力/边的镜像等变物理排序唯一真源，禁止 ID/创建顺序参与行为决胜 |
| [scripts/core/simulation.gd](scripts/core/simulation.gd) | 增援 ETA；每日滚动补给；多方战斗物理词典序；围城状态机；每 tick 单次共享骰/战术熵；全部 AI 军队选择改物理序 |
| [scripts/core/pathfinding.gd](scripts/core/pathfinding.gd) | Dijkstra 等长节点、等价前驱、最近目标和同损耗粮仓统一使用势力局部物理序 |
| [scripts/model/city.gd](scripts/model/city.gd) | `defense` → **`fort_strength`**（当前工事强度，城防点量纲，非兵力）；新增完整工事 `fort_strength_max`、最近易手日 `fort_last_capture_day` 及粮仓/战争破坏字段 |
| [scripts/model/army.gd](scripts/model/army.gd) | 两类补给债；完全同构多方接触的瞬态 `encounter_blocked`（不伪装为驻防） |
| [scripts/model/battle.gd](scripts/model/battle.gd) | 每侧整场援军士气累计；显式前线优先级；单军溃退队列；驻防/围城/稳定战术随机字段 |
| [scripts/core/game_state.gd](scripts/core/game_state.gd) | 军队拆分守恒；补给债按兵力比例分摊；`fort_strength` 引用同步 |
| [scripts/ai](scripts/ai) | 城防/围城量纲同步；`AiWorldView`、Utility、战略图、防御计划、威胁场、外交目标及同城合并全部去 ID 平局决胜 |
| [scripts/view/map_renderer.gd](scripts/view/map_renderer.gd) | 城防显示引用 `fort_strength` |
| [tests/test_suite.gd](tests/test_suite.gd) | 783 断言：原有机制 + 受限正面拆分轨迹 + 双边求和 + 城破工事恢复/满准备二阶段 + 五项机制闭环 + 回放/镜像等变门禁 |
| [tests/ai_symmetric_duel.gd](tests/ai_symmetric_duel.gd) | 新增 `AI_DUEL_STRICT_MIRROR=1`：逐日比较城市、国家资源和忽略 ID 的军队物理状态多重集 |
| [tests/combat_statistics.gd](tests/combat_statistics.gd) | **新建**：item 17 万场统计（独立 SceneTree 脚本，不入快速回归） |

---

## 2. 核心规则变化（按方案书 item）

**阶段 1（正确性）**
- **item 1 去 A 方偏置 + 平局**：胜负裁决 `decide_winner` 为纯函数，判据全部为镜像不变量（歼灭优先 → 士气溃败 → 对称 `residual` 续战能力），与 side_a/b 位置、军队 id、遍历顺序无关；完全对称 → 平局（`winner_side=0`）。`_canonicalize_side` 在回合起始按纯物理键（size/atk/def/morale 全降序）规范排序两侧，使浮点求和顺序不再破坏镜像。
- **item 2 士气影响战力与单军溃退**：每军基础效率仍为 `combat_efficiency(morale) = 0.2 + 0.8·morale`；本侧按各军名义攻击质量加权成统一前线效率，因此无限正面时严格等于原来的 `Σ(size×attack×offensive_multiplier×combat_efficiency(morale))`，受限正面时又不读取行政拆分边界。单军士气 ≤ `ARMY_ROUT_THRESHOLD=0.05` 时当回合立即退出 `Battle.side_*` 并由 Simulation 从真实战场位置执行撤退；不会继续占前线或输出最低火力。整侧兵力加权士气 ≤ `SIDE_ROUT_THRESHOLD=0.15` 判整线溃败；当回合刚退出的军队仍计入本轮侧级士气与续战能力，不能通过拆分删除低值样本。
- **item 3 伤亡整数守恒**：`distribute_casualties` 纯函数，`Σ 各军实际减员 == 本侧总伤亡`（最大余数法分配，无浮点泄漏）。
- **item 12 增援士气防套利**：本 tick 新增兵力作为整体统一结算；`Battle.reinforcement_morale_gained_a/b` 保存每侧整场累计消耗，单场单侧上限 `REINFORCE_MORALE_MAX=0.20`。同回合拆分、跨日分批或先合并后加入均不能刷新额度。

**阶段 2（空间）**
- **item 4 增援 ETA**：远援不能瞬间参战——只有归一化距离 ≤ `REINFORCEMENT_RADIUS=0.15`（物理逼近战线）才计入交战，否则继续行军。
- **item 5 正面宽度/预备队**：`frontline_allocation` 每轮明确记录各军 `committed` 兵力；一侧上限 = 野战道路容量 / 攻城 `SIEGE_FRONTAGE`。完整预备队不贡献火力、不承受伤亡和战斗士气侵蚀；前线减员或单军溃退后，下一轮按镜像等变物理优先级补入。`size × morale` 作为组织度质量守恒：伤亡按本侧战前平均密度移除组织度，战斗侵蚀只按幸存前线兵力扣除并回写前线军。火力读取同一侧级组织度密度，因此 `1×10000` 与 `2×5000` 不会因容器边界获得免费轮换效率。

**阶段 3（围城）**
- **item 6 驻军/城防/城市属性分离**：城市当前/完整工事真源 = `City.fort_strength/fort_strength_max`（城防点量纲，≠兵力）。易手后当前工事降到完整值 50%，365 天线性回满，再次易手重置。破城所需兵力 `siege_required_manpower(fort_strength) = fort_strength × 100` 显式换算（唯一量纲桥），**不含守军人数**——守军是城下决斗阶段消耗攻方的对手。禁止兵力与城防点直接相加/比较。
- **item 7 去 5× 硬门槛改连续曲线**：`manpower_ratio = effective_siege_strength / siege_required`。有效围城兵力只取城墙正面内 `committed manpower × combat_efficiency(morale) × supply_ratio`；低士气、缺粮和超额预备队不会按完整人数贡献。工程/指挥暂无独立模型字段。`ratio<0.5` 进度倒退；`0.5~1.0` 极慢；`ratio=1` 为 30 天；`days = 3 + 27/ratio` 单调递减。

**阶段 4（体验）**
- **item 8 随机性**：每 tick 只消费一次 `shared_roll`（共同天气/烈度）与一次 `tactical_entropy`。战斗两侧由稳定 `tactical_key_a/b` 分别派生 `±5%` 战术修正；键只依赖镜像轨道位置/势力中心，不含实体 ID、兵力、士气或平衡参数，故调参不会“重抽运气”，拆分也不增加随机机会。交换 A/B 严格交换修正；完全同构且映射到自身的两侧按等变性必要条件得到同值。
- **item 9 地形平滑**：去除 danger 跨阈战力断崖。`danger ≥ CHOKEPOINT_DANGER_ONSET=0.85` 进入隘口带，攻击倍率从该点常规线性值**连续单调**降到 `danger=1.0` 处地板 `CHOKEPOINT_ATTACK_FLOOR=0.25`；地形参数小幅变化只产生小幅结果变化，极端隘口仍强力压制进攻。
- **item 10 补给滚动结算**：路径、当日兵力、多个军队的共享库存竞争、实际扣粮及 `supply_ratio/starving` 全部每日重算。旧月需求除以 30 累积到 `Army.supply_food_debt`，满整粮才扣库存，因此 30 天总耗保持旧量纲且不会发生逐日 `ceil` 的 30 倍放大；拆分/合并时该债与减员债都守恒。生产、补员、外交和非战斗士气恢复仍按月。
- **item 11 多方战斗规则**：一条边的交战核心对由物理词典序 argmin 选取。多个核心对若在全部可观察物理键上完全同构，则不存在等变的单值选择，相关军队冻结在共同接触面等待外部状态破缺，而不读取数组顺序。二元 side_a/side_b 串行接战，第三方不穿过。

**§五 工程要求**
- **item 14 纯函数**：`combat_efficiency`/`distribute_casualties`/`decide_winner`/`siege_required_manpower`/`siege_daily_progress`/`_accrue_supply_pressure` 均无副作用、可独立单测。
- **item 15 结构化日志**：`Combat.battle_log_enabled` 默认关闭；启用后记录前线分配、溃退者、整场援军累计、战场上下文、共享骰、战术熵、稳定 tactical key 与两侧派生修正。回放器先从 entropy/context/key 重新派生修正，再重算回合；篡改结果、战术熵或 tactical key 均会失败。
- **item 13 集中配置 + item 单位注释**：全部可调参数集中在 combat.gd / simulation.gd 顶部并含单位/量纲注释。

---

## 3. 新增测试

**快速回归 [tests/test_suite.gd](tests/test_suite.gd)（783 断言 / 0 失败，`./run_tests.sh`）**
- 对称性/守恒/士气/拆分（阶段 1）：位置交换镜像、总伤亡守恒、士气影响战力、防御反拆分不变。
- 空间/增援（阶段 2）：接触点触发、增援 ETA（远援不瞬时参战）、正面宽度/预备队、拆分不增总正面；5000 正面下 `1×10000` 与 `2×5000` 完整多回合逐轮火力、伤亡、加权士气、胜负和时长一致。
- 围城（阶段 3）：`fort_strength` 量纲、`siege_required_manpower` 换算、连续围城曲线标定（ratio=1→30、2→16.5、∞→3）、驻军歼灭后城防仍来自工事。
- 城破恢复：首破 50%、半年部分恢复、第 364 天未满、第 365 天回满、再次易手刷新；既有围城同步当前工事，近期法理失地即时反攻。
- 均势破局：60 天准备仍低于攻击阈值时进入 180 天满准备；期间禁止零散提前攻击，到期以 2 倍攻击加成统一发动。
- 攻势延续：倍率和持续期均按实际准备天数计算并在 180 天封顶；满准备破城后按留守、士气、补给和下一目标战力选择追击、驻边或驻城。
- 双边求和：一方提出、另一方接受且双方总效用达标才和平；占领收益、失地止损和战争目标兑现进入双方评分，900 天仍保留强制停战上限。
- 地形（item 9）：`attack_multiplier(0)=1.000 → (0.95)=0.358` 连续单调、无断崖。
- 多方（item 11）：三方串行核心对选取 id-invariance（3 排列 → 单一结果）。
- 滚动补给（item 10，test [23]/[23b]）：逐日累积、相位无关（月初 vs 月末断粮结果一致）、恢复消退、减员整人化、部分缺粮线性、溃逃边沿单次触发。
- 战斗公平与守恒（[35]）：A/B 交换、ID 置换、伤亡守恒、拆分等价。
- **结构化日志（[36]，item 15）**：默认关闭、字段完整、JSONL 往返、逐回合确定性回放、篡改检测、开关不改结果。
- **镜像等变排序（[37]）**：左右镜像国家的城市物理序逐对一致；交换军队 ID 不改变决策顺序。
- **五项闭环（[38]）**：跨回合援军累计上限；预备队不伤亡/不掉士气及下一轮替换；单军即时溃退；有效围城兵力；每日粮耗、兵力变化和部分短缺；补给债拆并守恒；同日增援资格冻结。

**批量统计 [tests/combat_statistics.gd](tests/combat_statistics.gd)（item 17，独立脚本，10000 场，STATISTICS_PASS）**
- ① 位置对称：10000/10000 交换 A/B 逐位镜像（平局 0）。
- ② 独立战术随机：9997/10000 次两侧修正不同，A 较高占比 0.5020，交换 A/B 严格交换。
- ③ 优势方胜率：1.3~2.0 倍优势 = 1.0000。
- ④ 20% 明显兵力优势方 10000/10000 获胜（`±5%` 战术波动不覆盖明显优势）。
- ⑤ 拆分不变性：2000 场拆前后胜负与总伤亡逐位一致。
- ⑥ 受限正面拆分不变性：固定 5000 正面 `1×10000` / `2×5000`，以及随机 2000 场、2～10 支、`frontage < total manpower`；胜负、总伤亡、逐轮有效攻击力、全军兵力加权士气和战斗时长逐位一致。
- ⑦ 地形单调压制：201 点采样单调不增。
- ⑧ 固定种子完全复现：10000 场两遍逐位一致。

> item 8 数学边界：若两侧在镜像变换下完全同构且战斗映射到自身，逐局等变要求两侧修正相同；不可能同时强制“不同修正”。非同构空间角色使用独立修正，统计无 A/B 偏置。

---

## 4. 风险闭环

本轮五项机制缺口及上次审查的 4 个 P1 均已处理，无已知未闭环风险：

1. **ID/创建顺序平局决胜**：`EquivariantOrder` 的中轴自映射势力改用 `abs(x-0.5)` 镜像轨道，同 key 城市共享 rank；完全等价的跨城合并目标和多方核心对延迟决策。ID 仅保留作 SSoT 标识/字典键/边界检查。
2. **AI 决策层镜像等变性**：`AI_DUEL_STRICT_MIRROR=1` 每天比较镜像城市、国家资源与忽略 ID 的军队物理状态多重集；seed 1 连续 3650 天无破裂，最终优势分 `0.0`。
3. **独立战术随机**：已实现 `±5%` 双侧修正和无偏统计门禁；稳定战术键与战力参数正交，不产生调参重抽或拆分套利。
4. **日志落盘/回放**：`CombatLog` 完成 JSONL 文件序列化、加载和逐回合回放；随机输入及派生修正同样被验证。
5. **五项机制闭环**：援军额度跨整场累计；显式前线/预备队；单军即时溃退；有效围城兵力；每日实际供给与库存竞争。
6. **受限正面拆分套利**：组织度质量按兵力守恒，侧级火力和溃败判据不读取行政编组边界；固定夹具与随机 2～10 支统计均逐轮一致。

---

## 5. 影响存档兼容性的字段变化

> 本项目**无存档序列化机制**（仅 git 快照，脚本无 `to_dict/from_dict/store_var/ResourceSaver`），故以下字段变化不破坏任何持久化面；此处按 DoD 要求如实列出，供未来引入存档时参考。

| 模型 | 变化 | 说明 |
|---|---|---|
| `City.defense` | **重命名 → `City.fort_strength`** | 语义不变（城防点量纲），仅正名以杜绝与兵力量纲混用（item 6）。全仓引用已同步。 |
| `City.fort_strength_max/fort_last_capture_day`（新增） | 完整工事和最近实际易手日；当前工事由 Simulation 每日线性恢复。未来引入存档时必须持久化。 |
| `Nation.campaign_preparation_started_day/campaign_full_preparation_target_city`（新增） | 国家级攻势准备起点和满准备目标；用于跨日等待至 180 天，未来引入存档时必须持久化。 |
| `Nation.campaign_launched_attack_multiplier/campaign_launched_bonus_days/campaign_post_capture_plans`（新增） | 已发动轮次加成真源及满准备占城后二阶段预案；避免下一轮准备时钟覆盖后续梯队，未来引入存档时必须持久化。 |
| `Army.supply_debt`（新增 `float=0.0`） | item 10 每日减员整人化累计余额；默认 0 即满足行为，无需持久化重置。 |
| `Army.supply_food_debt`（新增 `float=0.0`） | 将月需求平滑到每日扣粮的累计小数余额；拆分/合并时按兵力守恒。 |
| `Battle.morale_a/morale_b`（**移除**） | 士气真源改为 `Army.morale`，Battle 层用 `side_morale()` 兵力加权派生。 |
| `Battle.reinforce_fresh_a/b`、`reinforcement_morale_gained_a/b`、`routed_a/b`、`frontline_priority_a/b`、`holding_side/holding_days`、`siege_required`、`tactical_key_a/b`（新增） | 战斗内瞬态/累计字段；若未来引入存档，活跃战斗必须完整持久化这些字段。 |
| `Combat.battle_log_enabled/battle_log`（新增 static） | 调试用，默认关闭；非世界状态、不属 SSoT。 |
