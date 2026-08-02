# 战斗系统重构变更说明

> 对应方案书 [wargame_combat_system_refactor.md](wargame_combat_system_refactor.md) 十七条要求 + 推荐四阶段。
> 基线 commit：`c346dda`（Sustain offensives throughout active wars）。
> 验收：`./run_tests.sh` = **739 断言 / 0 失败**；`tests/combat_statistics.gd` = STATISTICS_PASS（10000 场）；
> 真实地图 4 种子 × 1095 天全部 4 国存活、`invalid=0`、`commit_failures=0`、`starving=0`；
> 12 种子 balanced-fairness 对战 L=7/R=5、均值 +87k、t=1.37（与 0 无统计差异，镜像公平达标）。

---

## 1. 修改的文件

| 文件 | 变更要点 |
|---|---|
| [scripts/core/combat.gd](scripts/core/combat.gd) | 集中常量；纯函数骨架（`distribute_casualties`/`combat_efficiency`/`decide_winner`/`siege_required_manpower`/`siege_daily_progress`）；对称判定 + 平局；士气→战斗效率；正面宽度/预备队；共享战场骰；连续地形关隘曲线；连续围城效率曲线；`_canonicalize_side` 规范排序修镜像；结构化战斗日志（item 15） |
| [scripts/core/simulation.gd](scripts/core/simulation.gd) | 增援 ETA（`REINFORCEMENT_RADIUS`）；补给月度跳变 → 每日滚动结算（经济/后果分离）；多方战斗串行接触点物理词典序选取（item 11）；四步移动分离；围城状态机；随机骰单次 `shared_roll` 下发 |
| [scripts/model/city.gd](scripts/model/city.gd) | `defense` → **`fort_strength`**（工事结构强度，城防点量纲，非兵力）；新增 `has_warehouse`/`war_disruption_until_day` 语义澄清 |
| [scripts/model/army.gd](scripts/model/army.gd) | 新增 `supply_debt`（每日减员整人化累计余额）；`supply_ratio` 注释补充为每日惩罚强度来源 |
| [scripts/model/battle.gd](scripts/model/battle.gd) | 士气去二元存储改 `side_morale` 派生；增援 tick 聚合字段 `reinforce_fresh_a/b`（防拆分套利）；`holding_side/holding_days` 快照；`siege_required` 兵力量纲字段 |
| [scripts/core/game_state.gd](scripts/core/game_state.gd) | 军队拆分守恒 + `fort_strength` 引用同步 |
| [scripts/ai/army_power.gd](scripts/ai/army_power.gd)、[diplomacy_ai.gd](scripts/ai/diplomacy_ai.gd)、[strategic_map.gd](scripts/ai/strategic_map.gd)、[utility_ai.gd](scripts/ai/utility_ai.gd) | 城防引用改 `fort_strength`；进攻门槛改用 `siege_required_manpower` 统一量纲，去除误用 5× 速度常量当进攻合法性门槛 |
| [scripts/view/map_renderer.gd](scripts/view/map_renderer.gd) | 城防显示引用 `fort_strength` |
| [tests/test_suite.gd](tests/test_suite.gd) | +667 行：对称/守恒/士气/拆分/空间/增援/围城/地形/多方/滚动补给/结构化日志断言（详见 §3） |
| [tests/ai_symmetric_duel.gd](tests/ai_symmetric_duel.gd) | 镜像基准 fixture 引用改 `fort_strength` |
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
- **item 8 随机性**：每 tick 只掷一次 `shared_roll` 下发给当日所有 `resolve_round`，镜像成对战斗抽到同一波动；`roll_multiplier` 同乘双方火力 → 骰只改战斗烈度/速度、不改相对胜负。**阵营独立侧骰有意放弃**（镜像公平 > 单场戏剧性，方案书 item 8 允许的取舍，已在代码与日志字段 `side_random_modifier`（恒 1）显式标注）。
- **item 9 地形平滑**：去除 danger 跨阈战力断崖。`danger ≥ CHOKEPOINT_DANGER_ONSET=0.85` 进入隘口带，攻击倍率从该点常规线性值**连续单调**降到 `danger=1.0` 处地板 `CHOKEPOINT_ATTACK_FLOOR=0.25`；地形参数小幅变化只产生小幅结果变化，极端隘口仍强力压制进攻。
- **item 10 补给滚动结算**：经济（月度扣 int 粮 + 写 `supply_ratio`/`starving`）与后果（每日按 `1/30` 摊派士气/减员/溃逃）分离。每日 `_apply_supply_pressure` 逐军独立、无跨军求和、无 id/RNG → 天然镜像等变；全月累计恰等旧月度口径（数值校准不变）。减员经 `supply_debt` 整人化累计（满 1 人才扣、余额留存），避免逐日 `ceil` 取整放大。**粮食扣除仍保持月度**（`food_storage` 为 int，日扣会 30× 通胀，量化证伪日扣方案）。
- **item 11 多方战斗规则**：一条边的交战核心对由物理词典序 argmin 选取（gap 升 → 两军兵力和降 → 势力对 `Vector2i(min,max)` 升），与军队 id、遍历顺序无关、可复现。二元 side_a/side_b 串行接战，第三方由 `_block_passthrough` 冻结待机、串行接战，不穿过。

**§五 工程要求**
- **item 14 纯函数**：`combat_efficiency`/`distribute_casualties`/`decide_winner`/`siege_required_manpower`/`siege_daily_progress`/`_accrue_supply_pressure` 均无副作用、可独立单测。
- **item 15 结构化日志**：`Combat.battle_log_enabled`（默认关闭、零开销）+ `battle_log`（`Array[Dictionary]`）+ `clear_battle_log()`。启用后每回合末尾追加纯数据快照（battle_id/round_no/frontline·reserve strength/effective attack·defense/shared·side random modifier/terrain·supply modifier/casualties/morale before·after/reinforcements/rout_reason/winner）；只读、镜像安全、不参与任何逻辑判断。
- **item 13 集中配置 + item 单位注释**：全部可调参数集中在 combat.gd / simulation.gd 顶部并含单位/量纲注释。

---

## 3. 新增测试

**快速回归 [tests/test_suite.gd](tests/test_suite.gd)（739 断言 / 0 失败，`./run_tests.sh`）**
- 对称性/守恒/士气/拆分（阶段 1）：位置交换镜像、总伤亡守恒、士气影响战力、防御反拆分不变。
- 空间/增援（阶段 2）：接触点触发、增援 ETA（远援不瞬时参战）、正面宽度/预备队、拆分不增总正面。
- 围城（阶段 3）：`fort_strength` 量纲、`siege_required_manpower` 换算、连续围城曲线标定（ratio=1→30、2→16.5、∞→3）、驻军歼灭后城防仍来自工事。
- 地形（item 9）：`attack_multiplier(0)=1.000 → (0.95)=0.358` 连续单调、无断崖。
- 多方（item 11）：三方串行核心对选取 id-invariance（3 排列 → 单一结果）。
- 滚动补给（item 10，test [23]/[23b]）：逐日累积、相位无关（月初 vs 月末断粮结果一致）、恢复消退、减员整人化、部分缺粮线性、溃逃边沿单次触发。
- 战斗公平与守恒（[35]）：共享骰下 5% 兵力优势方确定性全胜（200/200）。
- **结构化日志（[36]，item 15）**：默认关闭零记录、启用后字段完整可读、开/关日志战斗结果逐位一致（镜像安全）。

**批量统计 [tests/combat_statistics.gd](tests/combat_statistics.gd)（item 17，独立脚本，10000 场，STATISTICS_PASS）**
- ① 位置对称：10000/10000 交换 A/B 逐位镜像（平局 0）。
- ② 优势方胜率：1.3~2.0 倍优势 = 1.0000。
- ③ 5% 兵力优势方确定性全胜：10000/10000（随机不覆盖兵力优势）。
- ④ 拆分不变性：2000 场拆前后胜负与总伤亡逐位一致。
- ⑤ 地形单调压制：201 点采样单调不增。
- ⑥ 固定种子完全复现：10000 场两遍逐位一致。

> item 17 诚实说明：因 item 8 单 `shared_roll` 同乘双方，固定阵容单场野战是**确定性**的，随机不改相对胜负；故验收呈现为更强的确定性不变量（位置对称、优势胜率、优势不被随机夺走、拆分不变、地形单调、种子复现），而非"胜率分布落在区间内"。

---

## 4. 尚未处理的风险

1. **同类 id tie-break 残留（低优先）**：simulation.gd 仍有约 7 处按军队 id 决胜的旧点（line 434/1595/1696/2325/2439/2697/3196），多为 AI 决策层效用平局。12 种子对战已近均衡（L=7/R=5、t=1.37），残余 day-330 破裂属 AI 决策层对称平局，方案书归类为"允许的对称战斗小幅非对称"，未追字节镜像。
2. **AI 决策层非战斗对称**：本次重构范围是战斗系统；AI 效用评分层的镜像等变性未系统性审计，长跑指标健康但非字节镜像。
3. **item 8 阵营独立侧骰有意放弃**：单场戏剧性（同一场两侧不同运气波动）被牺牲以换镜像公平。若未来要"公平且有独立戏剧性"，需引入镜像配对的独立骰（成对同分布、异实例），非本次范围。
4. **结构化日志无落盘/回放器**：item 15 只提供内存快照与读取接口，未实现文件序列化或图形化回放；按需扩展。

---

## 5. 影响存档兼容性的字段变化

> 本项目**无存档序列化机制**（仅 git 快照，脚本无 `to_dict/from_dict/store_var/ResourceSaver`），故以下字段变化不破坏任何持久化面；此处按 DoD 要求如实列出，供未来引入存档时参考。

| 模型 | 变化 | 说明 |
|---|---|---|
| `City.defense` | **重命名 → `City.fort_strength`** | 语义不变（城防点量纲），仅正名以杜绝与兵力量纲混用（item 6）。全仓引用已同步。 |
| `Army.supply_debt`（新增 `float=0.0`） | item 10 每日减员整人化累计余额；默认 0 即满足行为，无需持久化重置。 |
| `Battle.morale_a/morale_b`（**移除**） | 士气真源改为 `Army.morale`，Battle 层用 `side_morale()` 兵力加权派生。 |
| `Battle.reinforce_fresh_a/b`、`holding_side/holding_days`、`siege_required`（新增） | tick 内瞬态/快照字段，战斗结束即失效，无持久化意义。 |
| `Combat.battle_log_enabled/battle_log`（新增 static） | 调试用，默认关闭；非世界状态、不属 SSoT。 |
