# 战斗系统重构变更说明

> 对应方案书 [wargame_combat_system_refactor.md](wargame_combat_system_refactor.md) 十七条要求 + 推荐四阶段。
> 基线 commit：`c346dda`（Sustain offensives throughout active wars）。
> 验收：`./run_tests.sh` = **826 断言 / 0 失败**；`tests/combat_statistics.gd` = STATISTICS_PASS（10000 场）；
> 含真实边距与双河道硬阻隔的正式地图 4 种子 × 1095 天：`net_captures=88`、`turnovers=137`、`wars=17`、
> `offensives=63`、`multi_prep=3`、`max_parallel=3`，
> 且 `invalid=0`、`commit_failures=0`。strict-mirror 基准逐日校验
> 3650 天无破裂，优势分 `0.0`。

---

## 1. 修改的文件

| 文件 | 变更要点 |
|---|---|
| [scripts/core/combat.gd](scripts/core/combat.gd) | 集中常量；纯函数骨架；对称判定 + 平局；士气→战斗效率；正面宽度/预备队；共享战场骰 + 镜像等变独立战术修正；连续地形/围城曲线；`_canonicalize_side`；可回放结构化日志 |
| [scripts/core/combat_log.gd](scripts/core/combat_log.gd) | **新建**：结构化日志 JSONL 落盘、加载、逐回合确定性回放与篡改检测 |
| [scripts/core/equivariant_order.gd](scripts/core/equivariant_order.gd) | **新建**：城市/军队/势力/边的镜像等变物理排序唯一真源，禁止 ID/创建顺序参与行为决胜 |
| [scripts/core/simulation.gd](scripts/core/simulation.gd) | 增援 ETA；每日滚动补给；多方战斗；围城状态机；最多三目标攻势；两档军制；邻接驰援；纯双边全境失守立即投降；长距离行军不封顶 |
| [scripts/core/pathfinding.gd](scripts/core/pathfinding.gd) | 确定性二叉最小堆 Dijkstra 与等长裁决；寻路读取行军倍率，补给读取边级损耗倍率 |
| [scripts/core/terrain_map_generator.gd](scripts/core/terrain_map_generator.gd) | 黄河/长江控制点模板与纬向走廊；均匀保留约35% crossing并最小连通补点；其余穿河道路禁用；三类边统一由端点几何长度生成距离 |
| [scripts/model/city.gd](scripts/model/city.gd) | 当前/完整工事及易手恢复字段；`is_dock` 标识复用完整城市能力的码头 |
| [scripts/model/edge.gd](scripts/model/edge.gd) | 新增 `LAND/LANDING/RIVER` 类型、行军/粮损倍率和 `allows_holding` |
| [scripts/model/army.gd](scripts/model/army.gd) | 两类补给债；完全同构多方接触的瞬态 `encounter_blocked`（不伪装为驻防） |
| [scripts/model/battle.gd](scripts/model/battle.gd) | 每侧整场援军士气累计；显式前线优先级；单军溃退队列；驻防/围城/稳定战术随机字段 |
| [scripts/core/game_state.gd](scripts/core/game_state.gd) | 64 个陆城之外创建码头；按全部当前城市计算 5000/15000 两档目标军制；首都/资源核心只读取陆城；边键改为 int64 打包 |
| [scripts/ai](scripts/ai) | Hungarian 军队到城市多槽离散驻防；威胁与抵达时间读取河运速度；水路不生成驻边姿态；外交按战局、军力、钱粮和第三国边境集结计算双边和平意愿 |
| [scripts/view/map_renderer.gd](scripts/view/map_renderer.gd) | 绘制河道/水路/抢滩边/码头；运行时最高 30 FPS、暂停 5 FPS 重绘 |
| [tests/test_suite.gd](tests/test_suite.gd) | 826 断言：既有机制 + 双河走向/渡口压缩/硬阻隔 + 真实边距/长行军 + 双边全境投降 + 邻接驰援 + 两档军制/同城多军驻防 |
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

**河运与抢滩**
- 正式高度图世界使用两组固定控制点和纬向走廊代价生成北黄河、南长江。两河西向东、平均纵向分离至少 `0.18`、局部向西折返不超过 `0.08`，不再自由寻路重叠或在东北回转。
- 每条河均匀保留约 35% crossing，再用并查集补足全图连通所需的最少 crossing，码头数稳定在旧 35 座约一半的 8～22 门禁内。未选中的穿河道路整条禁用；选中道路的全部交点拆成 `LANDING` 边，因此硬阻隔保持成立。
- 码头继续复用 `City` 的占领、驻军、工事、补给和法理归属，初始产出为 0。相邻码头沿河连接 `RIVER` 边：容量 100000、同距离速度为陆运 `1.2×`、补给损耗倍率 0.25、禁止驻边。
- 河段 `danger` 由局部坡度和弯曲度确定，继续进入现有战斗地形模型。AI 威胁、进攻抵达和实际移动共用 `Simulation.edge_travel_days`；补给 Dijkstra 读取 `supply_loss_multiplier`。
- `LAND/LANDING/RIVER` 均按显示端点和地图宽高比计算欧氏长度，再以每地图高度 12 个单位生成整数 `distance`；抢滩分段不再继承原边比例，旧 `1～5` 截断已删除。`march_days=10+(distance-1)×5` 不再把长边封顶为 30 天。

**外交结算**
- 普通议和继续要求至少一方达到提议线且双方分别达到接受线。若战争降为纯双边，任一方失去全部实际控制城市则立即投降，不等待外交 tick、不要求胜方同意；多国战争不会误触发。投降复用和平领土确认和停战清理，并在历史事件记录败方。

**军制、驻防与性能**
- 正式地图按当前城市数维护两档编制：`5000` 编制军数量为 `ceil(0.5×城市数)`，`15000` 编制军数量为 `floor(0.05×城市数)`；战争动员不得突破目标实体数。城市易手后逐轮整建制增建或裁撤，30 天稳定窗口后必须精确匹配。
- 删除首都、粮仓、资源核心、新占城市和攻势抽调中的固定 5000/3000/10000 人门槛。粮食缩编只保留与 `max_size` 成比例的 30% 编制骨架。`CityDefensePlan` 以动态全国防御预算决定总槽数，每城槽上限为 `ceil(需求/平均军队战力)`，再用矩形 Hungarian 最大权匹配求解 `x[army,city_slot]∈{0,1}`。每军最多一个目标，高需求城市可获得多军；`15000` 编制军通过覆盖收益和过量投入惩罚优先覆盖高需求槽。
- 同四种子 4380 天插桩基准由 `313973ms` 降至 `152096ms`（`2.06×`）；渡口压缩基线约 `95.7s`，真实边距版本非插桩长跑约 `100.4s`，末期军队实体为 45～46。

---

## 3. 新增测试

**快速回归 [tests/test_suite.gd](tests/test_suite.gd)（826 断言 / 0 失败，`./run_tests.sh`）**
- 对称性/守恒/士气/拆分（阶段 1）：位置交换镜像、总伤亡守恒、士气影响战力、防御反拆分不变。
- 空间/增援（阶段 2）：接触点触发、增援 ETA（远援不瞬时参战）、正面宽度/预备队、拆分不增总正面；5000 正面下 `1×10000` 与 `2×5000` 完整多回合逐轮火力、伤亡、加权士气、胜负和时长一致。
- 围城（阶段 3）：`fort_strength` 量纲、`siege_required_manpower` 换算、连续围城曲线标定（ratio=1→30、2→16.5、∞→3）、驻军歼灭后城防仍来自工事。
- 城破恢复：首破 50%、半年部分恢复、第 364 天未满、第 365 天回满、再次易手刷新；既有围城同步当前工事，近期法理失地即时反攻。
- 多目标准备：国家级攻势线为 `1.00 / ai_aggression`，普通逐军 Utility 仍为 `1.35`；每 30 天最多并行准备 3 个目标，一军只归属一个方向，达到门槛的方向同批发动。
- 两档军制与离散驻防：正式世界初始数量匹配城市比例；城市数下降后在安全条件下精确收敛；每军最多一个目标，高需求城市可同时分配三军；5000 军覆盖低需求槽，15000 军覆盖高需求槽；关键城市不再有固定人数抽调预留。
- 均势破局：30 天准备仍低于攻击阈值时进入 180 天满准备；期间持续集结，到期以 2 倍攻击加成统一发动。每个方向至少到位原攻城人数门槛的 75%，且普通发动仍须满足实际战力比。
- 攻势延续：倍率和持续期均按实际准备天数计算并在 180 天封顶；满准备破城后按留守、士气、补给和下一目标战力选择追击、驻边或驻城。
- 双边求和：至少一方达到提议线，双方分别达到接受线才和平；合计分和战争时长均不能绕过任一方拒绝。和平意愿分解为战争疲劳、重要城市战局、`-1.2×` 归一化军力优势、钱粮耗尽压力、第三国边境实际集结、多线战争和进攻性，专项验证各项方向与重要城市权重。
- 批量命令容量竞态：冻结快照已通过首段容量仲裁的命令，若提交时因同批边上军队调头而临时满载，保留路径并每日重试；容量释放后继续行军，不产生提交失败。
- 地形（item 9）：`attack_multiplier(0)=1.000 → (0.95)=0.358` 连续单调、无断崖。
- 多方（item 11）：三方串行核心对选取 id-invariance（3 排列 → 单一结果）。
- 滚动补给（item 10，test [23]/[23b]）：逐日累积、相位无关（月初 vs 月末断粮结果一致）、恢复消退、减员整人化、部分缺粮线性、溃逃边沿单次触发。
- 战斗公平与守恒（[35]）：A/B 交换、ID 置换、伤亡守恒、拆分等价。
- **结构化日志（[36]，item 15）**：默认关闭、字段完整、JSONL 往返、逐回合确定性回放、篡改检测、开关不改结果。
- **镜像等变排序（[37]）**：左右镜像国家的城市物理序逐对一致；交换军队 ID 不改变决策顺序。
- **五项闭环（[38]）**：跨回合援军累计上限；预备队不伤亡/不掉士气及下一轮替换；单军即时溃退；有效围城兵力；每日粮耗、兵力变化和部分短缺；补给债拆并守恒；同日增援资格冻结。
- **河运（[1a]）**：两条河西向东、北南分离且无明显折返；码头为旧 35 座约一半；最小连通增补后全图及四国领土仍连通；所有可通行非水路边均无内部河流交点；水路禁止驻边。
- **邻接驰援**：普通城市受攻时，邻城闲置军与目标相邻边驻军同日生成入城命令；重点城市按 100% 缺口形成主会战，普通城市按 50% 兵力承担迟滞；低士气/低补给军不抽调。
- **投降与真实边距**：多国战争不误触发投降，纯双边全境失守立即停战并确认领土；正式地图所有三类边逐条等于端点几何长度换算值，最长边实际突破旧 `distance=5/30天` 上限。

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

**真实地图长跑 [tests/ai_longrun.gd](tests/ai_longrun.gd)（4 种子 × 1095 天）**
- 合计 `net_captures=88`、`turnovers=137`、`wars=17`、`offensives=63`，既有多城攻势也有邻接迟滞和主会战，没有形成静态僵局。
- 出现 3 个真实多目标准备计划，单国同轮最大实际并行方向数为 3；`invalid=0`、`commit_failures=0`，稳定超过 30 天的军制偏差为 0；总耗时约 `100.4s`。

---

## 4. 风险闭环

本轮五项机制缺口及上次审查的 4 个 P1 均已处理，无已知未闭环风险：

1. **ID/创建顺序平局决胜**：`EquivariantOrder` 的中轴自映射势力改用 `abs(x-0.5)` 镜像轨道，同 key 城市共享 rank；完全等价的跨城合并目标和多方核心对延迟决策。ID 仅保留作 SSoT 标识/字典键/边界检查。
2. **AI 决策层镜像等变性**：`AI_DUEL_STRICT_MIRROR=1` 每天比较镜像城市、国家资源与忽略 ID 的军队物理状态多重集；seed 1 连续 3650 天无破裂，最终优势分 `0.0`。
3. **独立战术随机**：已实现 `±5%` 双侧修正和无偏统计门禁；稳定战术键与战力参数正交，不产生调参重抽或拆分套利。
4. **日志落盘/回放**：`CombatLog` 完成 JSONL 文件序列化、加载和逐回合回放；随机输入及派生修正同样被验证。
5. **五项机制闭环**：援军额度跨整场累计；显式前线/预备队；单军即时溃退；有效围城兵力；每日实际供给与库存竞争。
6. **受限正面拆分套利**：组织度质量按兵力守恒，侧级火力和溃败判据不读取行政编组边界；固定夹具与随机 2～10 支统计均逐轮一致。
7. **攻势组织不足**：单目标状态改为统一时钟下最多三目标；准备分配按目标威胁和 30 天倍率计算，一军一目标且可增量补兵。关键城市不再使用固定人数保底，调动合法性统一读取离散防御计划。
8. **河运跨系统一致性**：码头仍是城市，水路仍是边；生成、寻路、补给、威胁、实际移动、驻边命令、战斗日志、等变排序和渲染读取同一组 Edge 字段。旧 `lo*64+hi` 边键已统一替换为 int64 打包。
9. **性能乘法放大**：军队实体按城市比例收敛；Dijkstra 从 O(V²) 扫描改为确定性最小堆；Renderer 不再每显示帧无条件全量重绘。
10. **全境占领仍不议和**：普通双边同意公式不再承担国家消亡结算；纯双边战争由每日强制投降规则闭环，多国战争保持原外交语义。
11. **视觉长边逻辑距离过短**：三类边共用端点几何长度换算，删除生成端 `1～5` 和行军端 30 天双重截断。

---

## 5. 影响存档兼容性的字段变化

> 本项目**无存档序列化机制**（仅 git 快照，脚本无 `to_dict/from_dict/store_var/ResourceSaver`），故以下字段变化不破坏任何持久化面；此处按 DoD 要求如实列出，供未来引入存档时参考。

| 模型 | 变化 | 说明 |
|---|---|---|
| `City.defense` | **重命名 → `City.fort_strength`** | 语义不变（城防点量纲），仅正名以杜绝与兵力量纲混用（item 6）。全仓引用已同步。 |
| `City.fort_strength_max/fort_last_capture_day`（新增） | 完整工事和最近实际易手日；当前工事由 Simulation 每日线性恢复。未来引入存档时必须持久化。 |
| `City.is_dock`（新增） | 标识码头显示与初始生成身份；码头其余行为完全复用城市字段。 |
| `Edge.kind/travel_time_multiplier/supply_loss_multiplier/allows_holding`（新增） | 区分陆路、抢滩边和水路，并控制速度、粮损与驻边合法性；旧状态默认值保持普通陆路行为。 |
| `Nation.campaign_preparation_started_day/campaign_preparation_targets/campaign_preparation_assignments/campaign_full_preparation_targets`（新增） | 统一准备时钟、并行目标、一军一目标分配和满准备目标集合；用于多方向跨日集结及批量发动，未来引入存档时必须持久化。 |
| `Nation.campaign_launched_attack_multiplier/campaign_launched_bonus_days/campaign_post_capture_plans`（新增） | 已发动轮次加成真源及满准备占城后二阶段预案；避免下一轮准备时钟覆盖后续梯队，未来引入存档时必须持久化。 |
| `Army.supply_debt`（新增 `float=0.0`） | item 10 每日减员整人化累计余额；默认 0 即满足行为，无需持久化重置。 |
| `Army.supply_food_debt`（新增 `float=0.0`） | 将月需求平滑到每日扣粮的累计小数余额；拆分/合并时按兵力守恒。 |
| `Battle.morale_a/morale_b`（**移除**） | 士气真源改为 `Army.morale`，Battle 层用 `side_morale()` 兵力加权派生。 |
| `Battle.reinforce_fresh_a/b`、`reinforcement_morale_gained_a/b`、`routed_a/b`、`frontline_priority_a/b`、`holding_side/holding_days`、`siege_required`、`tactical_key_a/b`（新增） | 战斗内瞬态/累计字段；若未来引入存档，活跃战斗必须完整持久化这些字段。 |
| `Combat.battle_log_enabled/battle_log`（新增 static） | 调试用，默认关闭；非世界状态、不属 SSoT。 |
