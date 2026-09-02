class_name Simulation
extends Node
## 模拟系统：实时驱动时间。行军/战斗/占领/军粮分配/士气恢复每天推进；
## 资源生产、补员与外交每月结算。
## 只写 GameState，调用 Pathfinding / Combat。表现层只读，不在此处理渲染。

signal runtime_day_committed(day: int)

enum SiegeRole {
	REJECTED,
	BESIEGER,
	CITY_DEFENDER,
	CHALLENGER,
}

# ---- 时间（天/月分层）----
## 基础 tick = 1 天。军粮月耗通过小数债摊到每天，经济生产等仍每 DAYS_PER_MONTH 天结算。
const DAYS_PER_MONTH: int = 30
const DAYS_PER_HALF_YEAR: int = 180        ## 半年 = 180 天（粮食注入周期）
# ---- 行军时长（平衡规格 R1：纯距离线性）----
const MARCH_DAYS_MIN: float = 10.0         ## 任意边最短行军 10 天（distance=1）
const MARCH_DAYS_PER_DISTANCE_STEP: float = 5.0
const MISSING_EDGE_TRAVEL_DAYS: float = 30.0
var seconds_per_day: float = 1.0           ## 默认 1 秒 = 1 天
var paused: bool = false
const SPEED_MIN: float = 0.25
## 快进「看海」上限。步进为 ×2，可依次到 8/16/32。注意：实际帧率仍受单日
## 算力约束——40 国重决策日单日约 10s，远超 8x 所需的 0.125s/天，故高倍速
## 在重决策日只会「尽力追赶」，普通日才真正跑满设定倍速。
const SPEED_MAX: float = 32.0

# ---- 粮食 / 饥饿 调参常量（§6.7）----
const FOOD_PER_CAPITA: float = 0.0025      ## 每人月耗（400 人耗 1 粮）
const MAX_SUPPLY_MULT: float = 3.0         ## 消耗倍率上限（最大 3 倍）
const STARVE_RATE: float = 0.5             ## 完全断粮时每月减员比例
const SUPPLY_MORALE_LOSS_MAX: float = 0.20 ## 完全断粮时每月士气损失；部分缺粮按缺口比例缩放
const HOLDING_TARGET_PROGRESS: float = 0.35 ## 从己方端点出发，驻防在边的己方侧
const HOLDING_STARVE_DECAY: int = 2        ## 完全断粮时每天损失的驻防适应天数
const CITY_GARRISON_CAPACITY_PER_MANPOWER: float = 1000.0
const CITY_GARRISON_FOOD_PENALTY_RATE: float = 0.20
const CITY_GARRISON_FOOD_PENALTY_MAX: float = 0.30
const CITY_WAR_DISRUPTION_DAYS: int = 365
const CITY_WAR_OUTPUT_MULTIPLIER: float = 0.50
## 藩王就近治理加成：藩王实控疆域内城市的钱/粮产出乘此系数（体现分权就近治理的
## 更高产出，并弥补藩王需上缴的贡赋）。仅按「城市实控 owner 是否为藩王」派生，不烧进
## 城市基础字段——owner 变更（分封/兼并/割地/易手）后自动生效，零维护、单一真源。
const VASSAL_GOVERNANCE_OUTPUT_MULTIPLIER: float = 1.5
## 撤退驻城恢复每月消耗：复用普通驻军月耗口径（size × FOOD_PER_CAPITA）。
## 资源不足时按实际供给比例恢复；士气回满或本城粮尽后解除 RECOVERING。
const RECOVERY_FOOD_PER_CAPITA: float = FOOD_PER_CAPITA
## 规格 R3：被围粮仓城市每日消耗本地库存；普通城市无粮仓，被围即失去外部补给。
const SIEGE_CITY_FOOD_PER_DAY: int = 1     ## 被围城每日粮草消耗系数
# ---- 占领 ----
const CITY_FORT_CAPTURE_MULTIPLIER: float = 0.50
const CITY_FORT_RECOVERY_DAYS: int = 365
## 分封战争加成：宗藩体系处于对外战争时，「不接壤敌国」的后方藩王把贡赋率临时提到此值，
## 用后方财税支撑中央战争机器；接壤敌国的前线藩王不加税、以自有军团守卫封地。
const VASSAL_WARTIME_REAR_TRIBUTE_RATE: float = 0.60
# ---- 遭遇战触发 ----
## 边内接触阈值（以边长归一化的 move_progress 为单位，即 [0,1] 区间）。
## 双方沿同边推进，当各自「以 city_a 为原点的归一化位置」之差 <= 此值（或相向已交错）才触发。
const CONTACT_EPS: float = 0.15
## 增援抵达半径（item 4）：已开战后，后续逼近的军队（含 MOVING）必须行进到距己方战线
## 归一化距离 <= 此值才算「抵达战场」并加入战斗。抵达前继续行军、不贡献攻击/不受伤亡/不占 frontage。
## eta = 剩余归一化距离 × edge_travel_days(edge)，由 move_progress 每日推进兑现。
const REINFORCEMENT_RADIUS: float = 0.15
const AI_DECISION_INTERVAL_DAYS: int = 10
const GRID_AI_DECISION_INTERVAL_DAYS: int = 5
const AI_RUNTIME_SLICE_BUDGET_USEC: int = 6000
const AI_CONTEXT_SLICE_BUDGET_USEC: int = 6000
## ThreatField 按国家并行；4 路通常能覆盖性能核且避免图搜索争抢内存带宽。
const AI_THREAT_MAX_WORKERS: int = 4
const AI_DEFENSE_MAX_WORKERS: int = 4
## 大地图开局没有既有战争或占领事件，不需要第1天让所有国家同时构建完整
## 战略快照。超过一个决策周期的国家从首日即按相位铺开；后续外交/领土突变
## 仍使用 force_all，保证真正需要同步响应时不延迟。
const AI_INITIAL_STAGGER_NATION_THRESHOLD: int = AI_DECISION_INTERVAL_DAYS
## 补给网络含大量图搜索与内存访问；超过 4 路后通常受缓存/内存带宽限制，并会制造
## 过多短生命周期任务。保留一个逻辑核给主线程，再以此上限约束实际并发。
const SUPPLY_NETWORK_MAX_WORKERS: int = 4
const DIPLOMACY_DECISION_INTERVAL_DAYS: int = DAYS_PER_MONTH
const NEW_ARMY_SIZE: int = 5000
const DISBAND_SIZE_MAX: int = 499
const REINFORCE_PER_ARMY_PER_MONTH: int = (
	ReinforcementRules.REINFORCE_PER_ARMY_PER_MONTH
)
const PEACETIME_MANPOWER_RESERVE: int = (
	ReinforcementRules.PEACETIME_MANPOWER_RESERVE
)
const PEACETIME_STRENGTH_RATIO: float = (
	ReinforcementRules.PEACETIME_STRENGTH_RATIO
)
## 战时也保留的人力下限：即使在战争中也不把 manpower_pool 抽到 0，
## 保证每月补员始终有燃料，避免暴兵后全军长期缺编、攻势因战力门槛卡死。
const WARTIME_MANPOWER_RESERVE: int = (
	ReinforcementRules.WARTIME_MANPOWER_RESERVE
)
## 财政储备不是“现金不得为负”的补丁，而是军队规模预算的目标状态：
## 和平积累约三年月收入；进入连续战争时冻结战前月收入并只保留半年。
const PEACE_GOLD_RESERVE_MONTHS: int = 36
const WAR_GOLD_RESERVE_MONTHS: int = 6
const GOLD_RESERVE_RECOVERY_MONTHS: int = 36
const FOOD_SECURITY_RESERVE_MONTHS: int = 6
const FOOD_RESERVE_RECOVERY_MONTHS: int = 6
const DEMOBILIZATION_STEP_MIN: int = 500
const WAR_MOBILIZATION_DAYS: int = 180
## 国家级攻势以约二十天为基础波次。AI 仍按性格缩放，且必须完成实际
## 集结/战力门槛；这里只缩短成功攻势后的重整空窗，不放宽送兵条件。
const CAMPAIGN_OFFENSIVE_INTERVAL_DAYS: int = 20
const CAMPAIGN_OFFENSIVE_COMMIT_DAYS: int = 30
const CAMPAIGN_ARROW_DURATION_DAYS: int = 20
## 一次 AI 规划可为整批已分配主战军写入集结路径；道路状态机随后按
## 真实容量逐日放行。此值只防止异常旧档产生无界命令量。
const PREPARATION_MAX_ORDERS_PER_CYCLE: int = 64
const CAMPAIGN_ATTACK_ENTER_RATIO: float = 1.00
const CAMPAIGN_TARGET_COMMIT_RATIO: float = 1.00
const CAMPAIGN_STAGED_TROOP_RATIO: float = 0.75
const CAMPAIGN_PARALLEL_SURPLUS_STEP_RATIO: float = 0.33
const CAMPAIGN_THEATER_MAX_TRANSFER_COST: float = 18.0
## 单波最多覆盖八个方向：是旧生产运行峰值（2）的四倍，足够形成宽正面；
## 同时阻止全地图十几路目标每轮重复做路径/战力规划。
const CAMPAIGN_MAX_PARALLEL_TARGETS: int = 8
## 八路双梯队对应最多十六个战时主战团。决定性单目标仍可获得至少三团，
## 但不会因前线目标总数增长而无限扩编到三十余团。
const CAMPAIGN_MAX_WARTIME_GROUPS: int = 16
const CAMPAIGN_PREPARED_ECHELONS: int = 2
## 敌国最后一城会持续集中守军、补员并享首都防御。至少三支独立战团
## 轮换投入，避免一团在窄路上反复消耗、全国主力却留作填线。
const CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS: int = 3
const OFFENSIVE_BONUS_MAX_PREPARATION_DAYS: int = 120
const OFFENSIVE_BONUS_MAX_MULTIPLIER: float = 2.0
const CAMPAIGN_REQUIRED_ATTACK_STEPS: int = 2
const DEFENSIVE_DEPLOYMENT_LOCK_DAYS: int = 90
const LIGHT_ONLY_OFFENSIVE_MAX_ARMIES: int = 2
## 正式地图的独立 LINE 已由 CityDefensePlan.can_join_offensive 拒绝。此上限只处理角色整理与
## 防区快照交界：同一轮攻势最多接纳一支仍残留防区记录、但已归入战团成为 MAIN 的轻军，
## 避免旧防区快照让多个防守槽同时进入攻势。
const CAMPAIGN_DEFENSE_ASSIGNED_MAX_ARMIES: int = 1
const SMALL_NATION_SURVIVAL_MAX_CITIES: int = (
	GameState.SMALL_NATION_SURVIVAL_MAX_CITIES
)
const SMALL_NATION_MOBILE_RESERVE_ARMIES: int = (
	GameState.SMALL_NATION_MOBILE_RESERVE_ARMIES
)
const EMERGENCY_RECRUITMENT_MIN_RUNWAY_YEARS: float = 0.25

var state: GameState
var _time_acc: float = 0.0
var _ai_strategy_cache: Dictionary = {}    ## nation_id -> StrategicMapSnapshot
var _ai_strategy_revision: Dictionary = {} ## nation_id -> [ownership, diplomacy, fortification]
var _ai_base_city_values_revision: Array[int] = []
var _ai_base_city_values: Dictionary = {}
var _ai_base_edge_values: Dictionary = {}
var _threat_travel_cache: Dictionary = {}  ## 静态道路行军天数、威胁衰减权重及稳定遍历序
var _ai_path_field_cache_by_nation: Dictionary = {}
var _ai_supply_source_cache: Dictionary = {}
var _ai_supply_network_cache: Dictionary = {}
var _ai_city_partition_cache: Dictionary = {}
## 外交拓扑缓存：军事接壤矩阵依赖外交关系，两跳距离只依赖领土与边类型。
## 两者均按各自 revision 跨外交动作、月度外交与 AI 决策复用。
var _diplomacy_topology_cache: Dictionary = {}
var _ai_defense_plan_cache: Dictionary = {}
## nation_id -> 最后一次完成战争攻势管理的日期。120天硬截止兜底只补漏，
## 不得在同一日常规 AI 已评估后再无上下文重复构建快照/威胁/防区。
var _campaign_evaluated_day_by_nation: Dictionary = {}
## 行军位置每日缓存；驻城位置跨日复用，仅在该国网络或该城围城状态变化时失效。
var _daily_supply_source_cache: Dictionary = {}
var _stable_supply_city_source_cache: Dictionary = {}
var _supply_source_besieged_cities: Dictionary = {}
var _daily_supply_network_cache: Dictionary = {}
## 当日指纹阶段已按国家汇总的敌军占据边；后台建网直接复用，避免再次全军扫描。
var _prepared_supply_blocked_edges: Dictionary = {}
## 补给网络依赖指纹（owner_nation -> Array[int]）：仅当指纹变化才丢弃对应网络重建，
## 拓扑不变的天数直接复用其损耗场，削减每日全量 O(粮仓×E) 重建（实测约省 12%）。
var _supply_network_fingerprints: Dictionary = {}
## 贸易预测分两层缓存：结构层跨日复用昂贵图搜索；完整预测只在所有结算
## 输入完全相同时复用。缓存结果只供 Simulation 内部只读消费者共享。
var _trade_structure_fingerprint: PackedByteArray = PackedByteArray()
var _trade_structure_probe: Array = []
var _trade_structure_cache: Dictionary = {}
var _trade_shared_caches: Dictionary = {}
var _trade_domestic_ideal_cache_generation: Array[int] = []
var _trade_settlement_fingerprint: PackedByteArray = PackedByteArray()
var _trade_result_cache: Dictionary = {}
var _trade_gold_flows_cache: Array[Dictionary] = []
var _trade_summary_settlement_fingerprint: PackedByteArray = PackedByteArray()
var _trade_summary_result_cache: Dictionary = {}
var _trade_summary_gold_flows_cache: Array[Dictionary] = []
## 战争财政快照只依赖外交关系转换。普通日以 O(1) 版本比较跳过，
## 外部脚本直接调用 set_diplomatic_relation 也会因 revision 变化被补同步。
var _war_gold_snapshot_diplomacy_revision: int = -1
var _ai_last_decision_day: int = -1
## 局部拓扑变化只提前重算受影响国家；全局外交变化仍用
## _ai_last_decision_day == -1 触发全体重算。
var _ai_forced_nations: Dictionary = {}
## 同日城市实控变化后的窄域前线刷新集合；仅重建受影响国家的 LINE 防区。
var _frontline_dirty_nations: Dictionary = {}
var _collect_ai_commands: bool = false
var _ai_command_buffer: Array[AiCommandIntent] = []
var _ai_planned_armies: Dictionary = {}
var _ai_planned_first_legs: Dictionary = {}
var _ai_command_sequence: Dictionary = {}
var _ai_snapshot_armies: Dictionary = {}
var _ai_queue_transaction_id: int = -1
var _next_ai_command_transaction_id: int = 1
var _pending_campaign_launch_transactions: Dictionary = {}
## campaign transaction 预留整波所有成员（含后续梯队），防止同批普通
## 战术/紧急防御 intent 在事务提交前改写其状态。army_id -> transaction_id。
var _ai_transaction_reserved_armies: Dictionary = {}
var _parallel_ai_context_jobs: Array[Dictionary] = []
var _pending_declaration_launches: Dictionary = {}
var _pending_war_mobilizations: Array[Dictionary] = []
var _defer_declaration_launches: bool = false
var _runtime_day_in_progress: bool = false
var ai_last_command_commit_failures: int = 0
var ai_command_commit_failure_total: int = 0
var ai_command_commit_failure_log: Array[String] = []
var ai_defense_topology_rebuild_total: int = 0
var ai_defense_topology_reuse_total: int = 0
var ai_defense_dynamic_reuse_total: int = 0
var frontline_refresh_batch_total: int = 0
var frontline_refresh_nation_total: int = 0
var frontline_refresh_build_total: int = 0
## 贸易预测缓存诊断计数。build 表示实际执行 build_structure/settle，
## cache_hit 表示复用了对应层；setup() 会统一清零。
var trade_structure_build_total: int = 0
var trade_structure_cache_hit_total: int = 0
var trade_forecast_build_total: int = 0
var trade_forecast_cache_hit_total: int = 0
var trade_domestic_ideal_cache_build_total: int = 0
var trade_domestic_ideal_cache_hit_total: int = 0
var trade_domestic_ideal_cache_miss_total: int = 0
var trade_domestic_ideal_cache_generation_clear_total: int = 0
var trade_domestic_ideal_graph_fingerprint_total: int = 0
var trade_domestic_ideal_graph_fingerprint_usec_total: int = 0
## 运行时 ThreatField worker 墙钟统计，供多核 A/B 与现场诊断。
var ai_threat_worker_count_last: int = 0
var ai_threat_worker_last_usec: int = 0
var ai_threat_worker_total_usec: int = 0
var ai_threat_worker_runs: int = 0
var ai_defense_worker_count_last: int = 0
var ai_defense_worker_last_usec: int = 0
var ai_defense_worker_total_usec: int = 0
var ai_defense_worker_runs: int = 0
## 测试/基准注入点：nation_id -> Callable(state, nation_id, simulation)。
## 正式游戏保持为空，所有国家均使用 Utility AI。
var ai_policy_overrides: Dictionary = {}
## A/B 基准注入点：nation_id -> 正常进攻单军最低战力占比；正式游戏使用 UtilityAI 默认值。
var ai_assault_participant_ratio_overrides: Dictionary = {}
## A/B 注入点：false 关闭“同层级主力优先”，平局仍使用镜像等变物理序。
var ai_tactical_decision_order_overrides: Dictionary = {}
## A/B 注入点：false 关闭粮道桥梁/割点的守备与增援需求。
var ai_supply_corridor_defense_overrides: Dictionary = {}
## A/B 注入点：false 复现攻击候选不检查实际通行路径的旧逻辑。
var ai_executable_attack_paths_overrides: Dictionary = {}
## A/B 注入点：true 复现由 nation_id 隐式生成 AI 性格的旧逻辑。
var ai_legacy_id_personality_overrides: Dictionary = {}
## 每个 AI 决策轮次轮换统一提交顺序，避免固定国家永久先提交。
var rotate_ai_nation_order: bool = true
## A/B 基准注入点：false 保留修改前的静态进攻评分。
var ai_strategic_planning_overrides: Dictionary = {}
## A/B 基准注入点：false 保留修改前的 60 天传播威胁守备策略。
var ai_adaptive_garrison_overrides: Dictionary = {}
## 隔离军事状态机测试时可关闭；正式游戏始终保持 true。
var diplomacy_enabled: bool = true
## AI 决策错峰：true 时各国按相位分散到决策周期内的不同天（削峰）；false 时全体
## 在 day%interval==0 同日决策（错峰前的旧行为）。仅用于 A/B 对照平衡性影响。
var ai_staggered_decisions: bool = true
## 性能 A/B 守卫：正式运行均为 false；分别关闭资源缓存贯通和单 tick 决策上下文。
var ai_force_resource_cache_disabled: bool = false
var ai_decision_context_disabled: bool = false
## 等价/性能 A/B：true 时军制不复用战略快照已构建的同 tick 外交资源缓存。
var ai_snapshot_resource_cache_reuse_disabled: bool = false
## A/B 与等价性测试开关；正式运行 false，按国家多核构建威胁场。
var ai_parallel_threat_disabled: bool = false
var ai_parallel_defense_disabled: bool = false
## 分封开关：true 时执行 AI 产出的 ENFEOFF 动作；false 时忽略（评估仍算，无副作用）。
## 正式游戏保持 true；仅供分封收益 A/B 对照关闭。
var enfeoff_enabled: bool = true
## 性能诊断开关。默认关闭；开启后 _advance_day 记录各阶段耗时到 tick_profile_last_usec。
## 正式运行不读取时钟，不引入每日 profiling 开销。
var tick_phase_profiling_enabled: bool = false
var tick_profile_last_usec: Dictionary = {}
## StrategicMapSnapshot 细粒度 profiling。默认关闭；仅在 snapshot cache miss 时
## 记录 frontier/connectivity/supply_corridors/finalize_edges/offensive/priority。
## 关闭时不为 snapshot build 构造 profile sink，近零开销；开启后每次 build 仍写入
## 任务私有 Dictionary，再由主线程合并到 tick_profile_last_usec。
var ai_snapshot_substage_profiling_enabled: bool = false
var _empty_snapshot_profile_sink: Dictionary = {}
## 运行时慢帧归因开关。默认关闭；探针开启后记录当前跨帧阶段，不读取时钟。
var runtime_stage_profiling_enabled: bool = false
var runtime_profile_stage: StringName = &""
## 等价性守卫用：置 true 强制补给网络每天全量重建（指纹缓存前的旧行为），
## 正式游戏始终 false，走指纹选择性失效。
var supply_network_cache_disabled: bool = false
## A/B 守卫：true 时后台预热仍在单个 worker 内串行构建；正式运行 false，按国家并行。
var supply_network_parallel_prebuild_disabled: bool = false
## 等价性守卫用：置 true 时运行时路径也用同步 _resolve_supply（不分帧），
## 以隔离「补给分帧」相对「补给同步」在同一运行时路径下的等价性。正式游戏 false。
var supply_frame_slicing_disabled: bool = false
## 等价性守卫用：置 true 时运行时路径也用同步 _resolve_reinforcements（不分帧），
## 以隔离「补员分帧」在同一运行时路径下的等价性。正式游戏 false。
var reinforcement_frame_slicing_disabled: bool = false
## 等价性/性能 A/B：true 时恢复逐军图搜索判断补员枢纽可达性；正式游戏 false。
var reinforcement_network_cache_disabled: bool = false
## 外交结构缓存 A/B：true 恢复同一次月度评估内重复构建联盟/敌对集团。
var diplomacy_structure_cache_disabled: bool = false
## 外交动员共享资源缓存 A/B：true 时每个参战成员各建一份评估上下文。
## 正式运行保持 false，同一次外交 action 的联盟成员共享只读派生。
var diplomacy_mobilization_cache_disabled: bool = false
var diplomacy_mobilization_evaluation_cache_total: int = 0
## 贸易预测 A/B：true 时每次请求都重新 build_structure + settle。
## 正式运行保持 false；该开关不改变结算路径或结果，只禁用两层复用。
var trade_forecast_cache_disabled: bool = false
## 等价性门禁用：true 时 AI/外交也强制使用完整贸易结算；正式游戏 false。
var trade_summary_forecast_disabled: bool = false
## domestic ideal field 跨 build shared cache A/B：true 时不传 shared cache 且清空。
## 正式运行保持 false；关闭后仅回退该层缓存，其余 trade forecast 行为不变。
var trade_domestic_ideal_field_cache_disabled: bool = false
## 行军容量索引 A/B：true 恢复每次入边都扫描全部军队的旧逻辑；正式运行 false。
var movement_capacity_index_disabled: bool = false
## 仅在单次 _advance_movement 内存活的局部索引。键为
## Vector3i(owner_nation, from_city, to_city)，值为同国同向运输负载。
var _movement_capacity_load_by_direction: Dictionary = {}
## army instance id -> [direction key, indexed load]，用于离边、死亡与途中掉头时精确回滚。
var _movement_capacity_entry_by_army: Dictionary = {}
var _movement_capacity_index_active: bool = false
## 等价性守卫用：置 true 时运行时路径也用同步 _resolve_line_edge_assignment_emergencies
## （不分帧），以隔离「填线防区分帧」在同一运行时路径下的等价性。正式游戏 false。
var line_edge_frame_slicing_disabled: bool = false
## 等价性守卫用：置 true 时重点城市防御梯队保持同步推进；正式游戏 false。
var priority_defense_frame_slicing_disabled: bool = false



func setup(game_state: GameState) -> void:
	state = game_state
	trade_domestic_ideal_field_cache_disabled = (
		trade_domestic_ideal_field_cache_disabled
		or OS.get_environment(
			"TRADE_DISABLE_DOMESTIC_IDEAL_CACHE"
		) == "1"
	)
	_normalize_city_fortifications()
	state.refresh_derived()
	_reset_trade_forecast_cache()
	_publish_initial_food_snapshot()
	_synchronize_war_gold_income_snapshots()
	_ai_strategy_cache.clear()
	_ai_strategy_revision.clear()
	_ai_base_city_values_revision.clear()
	_ai_base_city_values.clear()
	_ai_base_edge_values.clear()
	_threat_travel_cache.clear()
	_ai_path_field_cache_by_nation.clear()
	_ai_supply_source_cache.clear()
	_ai_supply_network_cache.clear()
	_ai_city_partition_cache.clear()
	_diplomacy_topology_cache.clear()
	_ai_defense_plan_cache.clear()
	_campaign_evaluated_day_by_nation.clear()
	_daily_supply_source_cache.clear()
	_stable_supply_city_source_cache.clear()
	_supply_source_besieged_cities.clear()
	_daily_supply_network_cache.clear()
	_prepared_supply_blocked_edges.clear()
	_supply_network_fingerprints.clear()
	_ai_last_decision_day = -1
	_ai_forced_nations.clear()
	_frontline_dirty_nations.clear()
	_pending_declaration_launches.clear()
	_pending_war_mobilizations.clear()
	_defer_declaration_launches = false
	ai_last_command_commit_failures = 0
	ai_command_commit_failure_total = 0
	ai_command_commit_failure_log.clear()
	ai_defense_topology_rebuild_total = 0
	ai_defense_topology_reuse_total = 0
	ai_defense_dynamic_reuse_total = 0
	frontline_refresh_batch_total = 0
	frontline_refresh_nation_total = 0
	frontline_refresh_build_total = 0
	diplomacy_mobilization_evaluation_cache_total = 0
	_clear_ai_command_collection()
	_parallel_ai_context_jobs.clear()
	_runtime_day_in_progress = false


func on_road_network_rebuilt() -> void:
	## 路网参数变化会使路径、补给、防区和威胁场缓存全部失效。
	## 复用 setup 的集中失效逻辑，避免遗漏某个跨日缓存。
	var was_paused := paused
	setup(state)
	paused = was_paused


func _process(delta: float) -> void:
	if (
		state == null
		or paused
	):
		return
	_time_acc += delta
	if _runtime_day_in_progress:
		return
	if _time_acc >= seconds_per_day:
		_time_acc -= seconds_per_day
		_runtime_day_in_progress = true
		_advance_runtime_day()


func _advance_runtime_day() -> void:
	await _advance_day(true)
	_runtime_day_in_progress = false
	runtime_day_committed.emit(state.day)


func set_speed_multiplier(mult: float) -> void:
	## mult 表示"相对默认速度"的倍率。seconds_per_day = 1/mult。
	var m := clampf(mult, SPEED_MIN, SPEED_MAX)
	seconds_per_day = 1.0 / m


func speed_multiplier() -> float:
	return 1.0 / seconds_per_day


func runtime_day_in_progress() -> bool:
	return _runtime_day_in_progress


# ================================================================== 天推进

func _advance_day(spread_runtime_work: bool = false) -> void:
	var profile_total_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var profile_stage_started := profile_total_started
	if tick_phase_profiling_enabled:
		tick_profile_last_usec.clear()
	_set_runtime_profile_stage(&"maintenance")
	state.day += 1
	state.month = state.day / DAYS_PER_MONTH
	if (
		state.diplomacy_revision
		!= _war_gold_snapshot_diplomacy_revision
	):
		_synchronize_war_gold_income_snapshots()
	state.prune_campaign_visual_events()
	_expire_offensive_bonuses()
	_recover_city_fortifications()
	_record_tick_profile_stage("maintenance", profile_stage_started)
	profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	# 每月结算资源生产、补员与外交；普通军粮在下方每日重新分配。
	if state.day % DAYS_PER_MONTH == 0:
		_set_runtime_profile_stage(&"monthly_economy")
		var monthly_profile_started := (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
		_resolve_economy()
		_record_tick_profile_stage(
			"monthly_economy",
			monthly_profile_started
		)
		monthly_profile_started = (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
		if spread_runtime_work and not reinforcement_frame_slicing_disabled:
			_set_runtime_profile_stage(&"monthly_reinforcements")
			await _resolve_reinforcements_over_frames()
		else:
			_resolve_reinforcements()
		_record_tick_profile_stage(
			"monthly_reinforcements",
			monthly_profile_started
		)
		monthly_profile_started = (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
		_set_runtime_profile_stage(&"monthly_rebellions")
		RebellionSystem.resolve_month(state)
		_record_tick_profile_stage(
			"monthly_rebellions",
			monthly_profile_started
		)
		monthly_profile_started = (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
		if spread_runtime_work:
			_set_runtime_profile_stage(&"monthly_diplomacy")
			await _resolve_diplomacy_over_frames()
		else:
			_resolve_diplomacy()
		_record_tick_profile_stage(
			"monthly_diplomacy",
			monthly_profile_started
		)
	_record_tick_profile_stage("monthly", profile_stage_started)
	profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	if spread_runtime_work and not line_edge_frame_slicing_disabled:
		_set_runtime_profile_stage(&"line_emergencies")
		await _resolve_line_edge_assignment_emergencies_over_frames()
	else:
		_resolve_line_edge_assignment_emergencies()
	_record_tick_profile_stage("line_emergencies", profile_stage_started)
	profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	# 日供应量与路径、兵力、共享库存竞争同日更新；月耗通过 Army.supply_food_debt
	# 按 1/30 累积到整粮后扣除，不放大整数库存。
	if spread_runtime_work and not supply_frame_slicing_disabled:
		_set_runtime_profile_stage(&"supply")
		await _resolve_supply_over_frames()
	else:
		_resolve_supply()
	_record_tick_profile_stage("supply", profile_stage_started)
	profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"morale_merge")
	_recover_morale()
	# 断粮后果读取刚计算的当日满足率，按 1/30 累计士气与减员。
	_apply_supply_pressure()
	ArmyCoordinator.merge_colocated(state)
	_record_tick_profile_stage("morale_merge", profile_stage_started)
	profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var ai_decision_interval := (
		AI_DECISION_INTERVAL_DAYS
		if state.uses_heightmap
		else GRID_AI_DECISION_INTERVAL_DAYS
	)
	_force_mature_campaign_evaluations()
	# 错峰下几乎每天都有一批国家到期；力求「有到期国家或需强制重算」即进入决策。
	# 关闭错峰（A/B 对照）时退回旧门控：仅在 day%interval==0 全体决策。
	var force_recompute := (
		_ai_last_decision_day == -1
		or not _ai_forced_nations.is_empty()
	)
	var ai_decision_due := force_recompute
	if ai_staggered_decisions:
		ai_decision_due = ai_decision_due or not _ai_nation_ids_for_day(
			state.nations.size(),
			state.day,
			rotate_ai_nation_order,
			ai_decision_interval,
			false,
			true
		).is_empty()
	else:
		ai_decision_due = ai_decision_due or state.day % ai_decision_interval == 0
	if ai_decision_due:
		if spread_runtime_work:
			_set_runtime_profile_stage(&"ai")
			await _ai_assign_targets(true)
		else:
			_ai_assign_targets()
	# 满准备截止后每天复核一次，避免错峰/其他外交备战分支让国家跳过
	# 当日战争攻势检查。正常准备期仍只在 AI 周期评估。
	_launch_mature_campaign_offensives()
	_record_tick_profile_stage("ai", profile_stage_started)
	profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"campaign_echelons")
	_advance_campaign_echelons()
	if (
		spread_runtime_work
		and not priority_defense_frame_slicing_disabled
	):
		_set_runtime_profile_stage(&"campaign_priority_defense")
		await _advance_priority_city_defense_echelons(true)
	else:
		_advance_priority_city_defense_echelons()
	_record_tick_profile_stage("campaign", profile_stage_started)
	profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"movement_battles")
	_advance_movement()
	_record_tick_profile_stage("movement_battles", profile_stage_started)
	profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"cleanup_capitulations")
	_resolve_eliminated_nation_capitulations()
	_set_runtime_profile_stage(&"cleanup_holding")
	_advance_holding_adaptation()
	_set_runtime_profile_stage(&"cleanup_siege_food")
	_drain_siege_food()   # 规格 R3：被围城每日耗粮（补给孤岛的粮草时钟）
	_set_runtime_profile_stage(&"cleanup_war_flags")
	_refresh_war_flags()
	_set_runtime_profile_stage(&"cleanup_victory")
	_check_victory()
	# 领土/存亡结算后修复死亡国造成的悬空宗藩记录，保持宗藩不变量。
	_set_runtime_profile_stage(&"cleanup_suzerainty")
	state.prune_dead_suzerainty()
	state.prune_rebellions()
	# 道路断联只影响通行、补给和防守，不再凭空改变城市实控。
	# 领土易手必须来自真实攻城、叛乱、分封、兼并或明确和平事务。
	# 兜底：驱离「定居在无通行权敌城节点」的己方军队（占领驱逐漏网 / 锚点城易主后滞留），
	# 避免 LINE 军在敌城 IDLE 卡死（hostile_stationed 死锁）。
	_set_runtime_profile_stage(&"cleanup_evict")
	_evict_stranded_hostile_armies()
	# 同日窄域前线刷新必须读取 cleanup 后的最终控制/存亡/驱离结果，避免按
	# 中间态重建防区。它只重算 LINE 防御部署；_ai_forced_nations 刻意保留到次日，
	# 继续触发完整 AI pass（campaign/force/diplomacy）。
	_set_runtime_profile_stage(&"frontline_refresh")
	_flush_same_day_frontline_refresh()
	_set_runtime_profile_stage(&"cleanup_refresh")
	state.refresh_derived()
	_record_tick_profile_stage("cleanup", profile_stage_started)
	if tick_phase_profiling_enabled:
		tick_profile_last_usec["total"] = (
			Time.get_ticks_usec() - profile_total_started
		)


func _record_tick_profile_stage(stage: String, started_usec: int) -> void:
	if not tick_phase_profiling_enabled:
		return
	tick_profile_last_usec[stage] = (
		int(tick_profile_last_usec.get(stage, 0))
		+ Time.get_ticks_usec() - started_usec
	)


func _merge_tick_profile_stage_values(profile: Dictionary) -> void:
	if not tick_phase_profiling_enabled or profile.is_empty():
		return
	for stage_value in profile.keys():
		var stage := str(stage_value)
		if stage == "enabled":
			continue
		tick_profile_last_usec[stage] = (
			int(tick_profile_last_usec.get(stage, 0))
			+ int(profile[stage_value])
		)


func _set_runtime_profile_stage(stage: StringName) -> void:
	if runtime_stage_profiling_enabled:
		runtime_profile_stage = stage


static func offensive_preparation_multiplier(
	preparation_days: int
) -> float:
	var ratio := clampf(
		float(maxi(preparation_days, 0))
			/ float(OFFENSIVE_BONUS_MAX_PREPARATION_DAYS),
		0.0,
		1.0
	)
	return lerpf(1.0, OFFENSIVE_BONUS_MAX_MULTIPLIER, ratio)


static func offensive_bonus_duration_days(
	preparation_days: int
) -> int:
	return clampi(
		preparation_days,
		0,
		OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
	)


func _campaign_preparation_days(nation_id: int) -> int:
	var nation := state.nations[nation_id]
	if nation.campaign_preparation_started_day < 0:
		nation.campaign_preparation_started_day = (
			nation.campaign_last_offensive_day
			if nation.campaign_last_offensive_day >= 0
			else state.day
		)
	return maxi(
		state.day - nation.campaign_preparation_started_day,
		0
	)


func _clear_campaign_preparation_plan(nation_id: int) -> void:
	var nation := state.nations[nation_id]
	nation.campaign_preparation_plan = null
	nation.campaign_preparation_targets.clear()
	nation.campaign_preparation_assignments.clear()
	nation.campaign_preparation_group_assignments.clear()
	nation.campaign_full_preparation_targets.clear()
	nation.campaign_preparation_started_day = -1
	nation.campaign_preparation_multiplier = 1.0


func _remove_campaign_preparation_target(
	nation_id: int,
	target_city: int
) -> void:
	var nation := state.nations[nation_id]
	# 目标级原地删除只供网格地图的旧军队规划使用。正式地图必须重新
	# 生成完整 CampaignAllocationPlan 后原子替换，不能局部改写真源。
	if state.uses_heightmap:
		return
	nation.campaign_preparation_targets.erase(target_city)
	nation.campaign_full_preparation_targets.erase(target_city)
	nation.campaign_preparation_group_assignments.erase(
		target_city
	)
	for army_id_value in (
		nation.campaign_preparation_assignments.keys().duplicate()
	):
		var army_id := int(army_id_value)
		if int(
			nation.campaign_preparation_assignments.get(
				army_id,
				-1
			)
		) == target_city:
			nation.campaign_preparation_assignments.erase(
				army_id
			)
	if nation.campaign_preparation_targets.is_empty():
		nation.campaign_preparation_started_day = -1
		nation.campaign_preparation_multiplier = 1.0


func _campaign_projected_assault_ratio(
	nation_id: int,
	objective_city: int,
	preparation_days: int,
	threat: ThreatField = null,
	assigned_only: bool = false,
	precomputed_staged_armies: Array[Army] = []
) -> float:
	if objective_city < 0 or objective_city >= state.cities.size():
		return 0.0
	var attack_power := 0.0
	var staged_armies := (
		precomputed_staged_armies
		if assigned_only and not precomputed_staged_armies.is_empty()
		else _campaign_preparation_staged_armies(
				nation_id,
				objective_city
			)
		if assigned_only
		else _campaign_staged_armies(
			nation_id,
			objective_city
		)
	)
	for army in staged_armies:
		if not _campaign_army_can_attack_target(
			army,
			nation_id,
			objective_city
		):
			continue
		attack_power += ArmyPower.effective(army)
	attack_power *= offensive_preparation_multiplier(
		preparation_days
	)
	var defense_power := _campaign_objective_defense_power(
		nation_id,
		objective_city,
		threat
	)
	return attack_power / maxf(defense_power, 1.0)


func _campaign_objective_defense_power(
	nation_id: int,
	objective_city: int,
	threat: ThreatField = null
) -> float:
	var direct_defense := 0.0
	for defender in state.armies_at_city(objective_city):
		if state.is_enemy(nation_id, defender.owner_nation):
			direct_defense += ArmyPower.effective(defender)
	var defense_power := direct_defense
	if threat != null:
		defense_power = maxf(
			defense_power,
			threat.threat_at(objective_city)
		)
	if state.recognized_owner_of(objective_city) != nation_id:
		defense_power += ArmyPower.city_defense(
			state.cities[objective_city]
		)
	return defense_power


func _campaign_attack_ratio_threshold(nation_id: int) -> float:
	return CAMPAIGN_ATTACK_ENTER_RATIO / clampf(
		state.effective_ai_aggression(nation_id),
		0.35,
		1.85
	)


func _campaign_minimum_staged_troops(
	nation_id: int,
	target_city: int
) -> int:
	if (
		state.uses_heightmap
		and state.nations[nation_id].campaign_preparation_plan != null
		and state.nations[nation_id].campaign_preparation_plan
			.assigned_target_ids.has(target_city)
	):
		# 这里只是本波能否开始的最低哨兵。完整集结量由
		# _campaign_planned_staging_troops 独立计算。
		return 1
	return maxi(
		int(ceil(
			float(
				DiplomacyAI.required_assault_troops(
					state,
					nation_id,
					target_city
				)
			) * CAMPAIGN_STAGED_TROOP_RATIO
		)),
		1
	)


func _campaign_planned_staging_troops(
	nation_id: int,
	target_city: int
) -> int:
	var nation := state.nations[nation_id]
	var plan := nation.campaign_preparation_plan
	if plan == null or not plan.assigned_target_ids.has(target_city):
		return _campaign_minimum_staged_troops(nation_id, target_city)
	var army_by_id := {}
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			army_by_id[army.id] = army
	var planned_troops := 0
	for group_id in plan.groups_for_target(target_city):
		for army_id in plan.member_ids_for_group(group_id):
			var planned_army: Army = army_by_id.get(army_id)
			if planned_army != null:
				planned_troops += planned_army.size
	return maxi(planned_troops, 1)


func _campaign_offensive_interval(nation_id: int) -> int:
	var aggression := clampf(
		state.effective_ai_aggression(nation_id),
		0.35,
		1.85
	)
	return int(round(
		float(CAMPAIGN_OFFENSIVE_INTERVAL_DAYS)
			/ aggression
	))


static func city_fort_strength_after_capture(
	full_strength: int,
	elapsed_days: int
) -> int:
	var maximum := maxi(full_strength, 0)
	if maximum <= 0:
		return 0
	var damaged := clampi(
		int(round(
			float(maximum) * CITY_FORT_CAPTURE_MULTIPLIER
		)),
		0,
		maximum
	)
	if damaged >= maximum or elapsed_days <= 0:
		return damaged
	if elapsed_days >= CITY_FORT_RECOVERY_DAYS:
		return maximum
	var progress := clampf(
		float(elapsed_days)
			/ float(CITY_FORT_RECOVERY_DAYS),
		0.0,
		1.0
	)
	# 整数城防在一年到期前不得因四舍五入提前回满。
	return clampi(
		int(floor(lerpf(
			float(damaged),
			float(maximum),
			progress
		))),
		damaged,
		maximum - 1
	)


static func city_fort_vulnerability(
	city: City,
	current_day: int
) -> float:
	if city == null or city.fort_last_capture_day < 0:
		return 0.0
	return 1.0 - clampf(
		float(maxi(
			current_day - city.fort_last_capture_day,
			0
		)) / float(CITY_FORT_RECOVERY_DAYS),
		0.0,
		1.0
	)


func _normalize_city_fortifications() -> void:
	for city in state.cities:
		city.fort_strength_max = maxi(
			city.fort_strength_max,
			city.fort_strength
		)


func _recover_city_fortifications() -> void:
	var fortification_changed := false
	for city in state.cities:
		city.fort_strength_max = maxi(
			city.fort_strength_max,
			city.fort_strength
		)
		if city.fort_last_capture_day < 0:
			continue
		var recovered := city_fort_strength_after_capture(
			city.fort_strength_max,
			maxi(
				state.day - city.fort_last_capture_day,
				0
			)
		)
		if recovered != city.fort_strength:
			city.fort_strength = recovered
			fortification_changed = true
	if fortification_changed:
		state.fortification_revision += 1
	# 已建立的围城也必须读取恢复后的当前工事，不能永久冻结在开战日。
	for battle in state.battles:
		if (
			battle.finished
			or battle.kind != Battle.Kind.SIEGE
			or battle.city == null
			or battle.city.fort_last_capture_day < 0
		):
			continue
		battle.siege_required = Combat.siege_required_manpower(
			battle.city.fort_strength
		)


func _expire_offensive_bonuses() -> void:
	for army in state.armies:
		if (
			army.offensive_bonus_until_day >= 0
			and state.day >= army.offensive_bonus_until_day
		):
			army.offensive_attack_multiplier = 1.0
			army.offensive_bonus_until_day = -1

# ------------------------------------------------------------------ 1. 经济

## 宗藩体系是否正处于对外战争。削藩内战不算体系外战。
static func suzerainty_system_at_war(
	game_state: GameState,
	subject_id: int
) -> bool:
	if game_state.is_in_civil_war(subject_id):
		return false
	var root := game_state.suzerainty_root(subject_id)
	for member in game_state.suzerainty_members(root):
		if not game_state.wars_of(member).is_empty():
			return true
	return false


## 当月有效贡赋率的单一真源：后方藩王在体系外战期间提高贡赋，
## 前线藩王维持记录中的基础税率。
static func effective_tribute_rate(
	game_state: GameState,
	subject_id: int
) -> float:
	if (
		subject_id < 0
		or subject_id >= game_state.nations.size()
		or not game_state.suzerainty.has(subject_id)
	):
		return 0.0
	# A rebelling vassal no longer recognizes the overlord's fiscal authority.
	# Keep the suzerainty record for civil-war victory/inheritance semantics,
	# but suspend this direct tribute edge until the civil war is resolved.
	if game_state.is_in_civil_war(subject_id):
		return 0.0
	var rate := float(
		game_state.suzerainty[subject_id].get(
			"tribute_rate",
			0.0
		)
	)
	if (
		suzerainty_system_at_war(game_state, subject_id)
		and not game_state.vassal_borders_system_enemy(
			subject_id
		)
	):
		rate = maxf(
			rate,
			VASSAL_WARTIME_REAR_TRIBUTE_RATE
		)
	return clampf(rate, 0.0, 1.0)


## 清空单个 Simulation 实例拥有的贸易预测缓存和诊断计数。
func _reset_trade_forecast_cache() -> void:
	_trade_structure_fingerprint = PackedByteArray()
	_trade_structure_probe.clear()
	_trade_structure_cache.clear()
	_trade_shared_caches.clear()
	_trade_domestic_ideal_cache_generation.clear()
	_trade_settlement_fingerprint = PackedByteArray()
	_trade_result_cache.clear()
	_trade_gold_flows_cache.clear()
	_trade_summary_settlement_fingerprint = PackedByteArray()
	_trade_summary_result_cache.clear()
	_trade_summary_gold_flows_cache.clear()
	trade_structure_build_total = 0
	trade_structure_cache_hit_total = 0
	trade_forecast_build_total = 0
	trade_forecast_cache_hit_total = 0
	trade_domestic_ideal_cache_build_total = 0
	trade_domestic_ideal_cache_hit_total = 0
	trade_domestic_ideal_cache_miss_total = 0
	trade_domestic_ideal_cache_generation_clear_total = 0
	trade_domestic_ideal_graph_fingerprint_total = 0
	trade_domestic_ideal_graph_fingerprint_usec_total = 0


## 当前贸易结算和财政预测的完整、无碰撞 token。结构 fingerprint 负责路线、
## 道路、领土与贸易政策；这里补齐战时收益倍率、粮池、库存、需求、国库、
## 军费、战乱减产日期及君主经济输入。仅将这些字段序列化，不使用 hash。
func _trade_settlement_token(
	structure_fingerprint: PackedByteArray
) -> PackedByteArray:
	var fields: Array = [
		"trade_settlement_v1",
		structure_fingerprint,
		["trade_price_enabled", state.trade_price_enabled],
		["wartime_nations", TradeNetwork.wartime_nation_mask(state)],
	]
	for city in state.cities:
		fields.append([
			"city", city.id, city.food_storage,
			city_war_disrupted(state, city),
		])
	var suzerainty_subjects := state.suzerainty.keys()
	suzerainty_subjects.sort()
	for subject_value in suzerainty_subjects:
		var subject_id := int(subject_value)
		var record: Dictionary = state.suzerainty[subject_value]
		fields.append([
			"suzerainty", subject_id,
			int(record.get("overlord_id", -1)),
			float(record.get("tribute_rate", 0.0)),
			bool(record.get("civil_war", false)),
		])
	for nation in state.nations:
		fields.append([
			"nation", nation.id, nation.alive,
			state.food_pool_holder(nation.id),
			nation.granary_food, nation.last_food_demand,
			nation.food_demand_ema, nation.treasury_gold,
			nation.manpower_pool,
			nation.ruler_revision, nation.ruler_archetype,
			nation.ruler_traits,
			RulerProfile.gold_output_multiplier(nation),
			RulerProfile.food_consumption_multiplier(nation),
			RulerProfile.reserve_months_bonus(nation),
			RulerProfile.upkeep_multiplier(nation),
		])
	for army in state.armies:
		if army.size <= 0:
			continue
		fields.append([
			"army", army.owner_nation, army.size,
		])
	return var_to_bytes(fields)


## Simulation 级贸易/财政预测入口。所有生产内调用均经此处：结构相同可跨日
## 复用；完整 token 相同则连 settle 与 gold_flows 也直接复用。
func _forecast_trade_and_gold_flows(
	summary_only: bool = false
) -> Dictionary:
	var forecast_substage_enabled := (
		tick_phase_profiling_enabled
		and ai_snapshot_substage_profiling_enabled
	)
	var part_started := (
		Time.get_ticks_usec() if forecast_substage_enabled else 0
	)
	var structure_probe := _trade_structure_runtime_probe()
	var structure_fingerprint := (
		_trade_structure_fingerprint
		if (
			not trade_forecast_cache_disabled
			and not _trade_structure_fingerprint.is_empty()
			and _trade_structure_probe == structure_probe
		)
		else TradeNetwork.structure_fingerprint(state)
	)
	_trade_structure_probe = structure_probe
	if forecast_substage_enabled:
		_record_tick_profile_stage(
			"ai_snapshot_forecast_structure_fingerprint",
			part_started
		)
	var structure: Dictionary
	part_started = (
		Time.get_ticks_usec() if forecast_substage_enabled else 0
	)
	var structure_profile: Dictionary = (
		{"enabled": true} if forecast_substage_enabled else {}
	)
	var domestic_shared_caches := _trade_domestic_ideal_shared_caches(
		structure_profile
	)
	if (
		not trade_forecast_cache_disabled
		and not _trade_structure_cache.is_empty()
		and _trade_structure_fingerprint == structure_fingerprint
	):
		structure = _trade_structure_cache
		trade_structure_cache_hit_total += 1
	else:
		structure = TradeNetwork.build_structure(
			state,
			true,
			structure_profile,
			domestic_shared_caches
		)
		trade_structure_build_total += 1
		var counters := TradeNetwork.connectivity_prefilter_counters()
		trade_domestic_ideal_cache_build_total += int(
			counters.get("domestic_ideal_shared_cache_builds", 0)
		)
		trade_domestic_ideal_cache_hit_total += int(
			counters.get("domestic_ideal_shared_cache_hits", 0)
		)
		trade_domestic_ideal_cache_miss_total += int(
			counters.get("domestic_ideal_shared_cache_misses", 0)
		)
		if not trade_forecast_cache_disabled:
			_trade_structure_fingerprint = structure_fingerprint
			_trade_structure_cache = structure
	if forecast_substage_enabled:
		_merge_tick_profile_stage_values(structure_profile)
	if forecast_substage_enabled:
		_record_tick_profile_stage(
			"ai_snapshot_forecast_structure_stage",
			part_started
		)

	part_started = (
		Time.get_ticks_usec() if forecast_substage_enabled else 0
	)
	var settlement_fingerprint := _trade_settlement_token(
		structure_fingerprint
	)
	if forecast_substage_enabled:
		_record_tick_profile_stage(
			"ai_snapshot_forecast_settlement_token",
			part_started
		)
	part_started = (
		Time.get_ticks_usec() if forecast_substage_enabled else 0
	)
	if (
		not trade_forecast_cache_disabled
		and (
			(
				not _trade_result_cache.is_empty()
				and _trade_settlement_fingerprint == settlement_fingerprint
			)
			or (
				summary_only
				and not _trade_summary_result_cache.is_empty()
				and _trade_summary_settlement_fingerprint
					== settlement_fingerprint
			)
		)
	):
		trade_forecast_cache_hit_total += 1
		if forecast_substage_enabled:
			_record_tick_profile_stage(
				"ai_snapshot_forecast_settlement_stage",
				part_started
			)
		if (
			not _trade_result_cache.is_empty()
			and _trade_settlement_fingerprint == settlement_fingerprint
		):
			return {
				"trade": _trade_result_cache,
				"gold_flows": _trade_gold_flows_cache,
			}
		return {
			"trade": _trade_summary_result_cache,
			"gold_flows": _trade_summary_gold_flows_cache,
		}
	if forecast_substage_enabled:
		_record_tick_profile_stage(
			"ai_snapshot_forecast_settlement_stage",
			part_started
		)

	part_started = (
		Time.get_ticks_usec() if forecast_substage_enabled else 0
	)
	var trade := (
		TradeNetwork.settle_nation_summary(state, structure)
		if summary_only
		else TradeNetwork.settle(state, structure)
	)
	if forecast_substage_enabled:
		_record_tick_profile_stage(
			"ai_snapshot_forecast_trade_settle",
			part_started
		)
	part_started = (
		Time.get_ticks_usec() if forecast_substage_enabled else 0
	)
	var gold_flows := _monthly_gold_flows_from_trade(state, trade)
	if forecast_substage_enabled:
		_record_tick_profile_stage(
			"ai_snapshot_forecast_gold_flows",
			part_started
		)
	trade_forecast_build_total += 1
	if not trade_forecast_cache_disabled:
		if summary_only:
			_trade_summary_settlement_fingerprint = settlement_fingerprint
			_trade_summary_result_cache = trade
			_trade_summary_gold_flows_cache = gold_flows
		else:
			_trade_settlement_fingerprint = settlement_fingerprint
			_trade_result_cache = trade
			_trade_gold_flows_cache = gold_flows
	return {
		"trade": trade,
		"gold_flows": gold_flows,
	}


## Simulation 内部的低成本失效探针。结构 fingerprint 仍是最终权威；
## 这里只在能证明同一运行态没有相关变更时复用上次结果，避免一日内多个
## 财政/AI消费者反复序列化整张地图。战争、围城和军队位置不属于路线结构。
func _trade_structure_runtime_probe() -> Array:
	var result: Array = [
		state.get_instance_id(),
		state.cities.size(),
		state.nations.size(),
		state.edges.size(),
		state.ownership_revision,
		state.road_network_revision,
	]
	for nation in state.nations:
		result.append_array([
			nation.id, nation.alive, nation.capital_city_id,
			nation.trade_policy, nation.ruler_revision,
		])
	return result


func _trade_domestic_ideal_shared_caches(
	structure_profile: Dictionary
) -> Dictionary:
	if trade_forecast_cache_disabled or trade_domestic_ideal_field_cache_disabled:
		_trade_shared_caches.clear()
		_trade_domestic_ideal_cache_generation.clear()
		return {}
	var generation: Array[int] = [
		state.road_network_revision,
	]
	if _trade_domestic_ideal_cache_generation != generation:
		_trade_shared_caches.clear()
		_trade_domestic_ideal_cache_generation = generation.duplicate()
		trade_domestic_ideal_cache_generation_clear_total += 1
	if not _trade_shared_caches.has("domestic_ideal_fields"):
		_trade_shared_caches["domestic_ideal_fields"] = {}
	if not _trade_shared_caches.has("international_ideal_fields"):
		_trade_shared_caches["international_ideal_fields"] = {}
	if not _trade_shared_caches.has("operational_fields"):
		_trade_shared_caches["operational_fields"] = {}
	return _trade_shared_caches


## 为只接受 Dictionary 的静态 AI 评估器注入同一份实例预测。Dictionary 每次
## 新建，内部大型结果只读共享；AI 只会新增自己的派生 key，不改写预测值。
func _seed_trade_forecast(
	evaluation_cache: Dictionary
) -> Dictionary:
	var forecast := _forecast_trade_and_gold_flows(
		not trade_summary_forecast_disabled
	)
	if not diplomacy_structure_cache_disabled:
		evaluation_cache["__diplomacy_topology_cache"] = (
			_diplomacy_topology_cache
		)
	evaluation_cache["trade_network_result"] = forecast["trade"]
	evaluation_cache["monthly_gold_flows"] = forecast["gold_flows"]
	return evaluation_cache


## 全体国家下一次月结算的财政派生。贡赋只对藩王自己的城市税收计征，
## 不对下级藩王汇入的贡赋重复征税；因此逐级宗藩与结算遍历顺序无关。
static func monthly_gold_flows(
	game_state: GameState
) -> Array[Dictionary]:
	# 真实月结会把已经构建的贸易快照注入，保证昂贵的路线派生每月只做一次；
	# 纯预测调用则在这里派生同一份结果。TradeNetwork 不依赖 Simulation，
	# 因而这条默认路径不会递归回财政报告。
	var trade := TradeNetwork.build(game_state)
	return _monthly_gold_flows_from_trade(game_state, trade)


static func _monthly_gold_flows_from_trade(
	game_state: GameState,
	trade: Dictionary
) -> Array[Dictionary]:
	return EconomyRules.monthly_gold_flows_from_trade(
		game_state,
		trade,
		effective_monthly_military_upkeep,
		city_gold_output,
		effective_tribute_rate
	)


static func _trade_array_value(
	trade_snapshot: Dictionary,
	key: String,
	index: int
) -> int:
	return EconomyRules.trade_array_value(trade_snapshot, key, index)


static func effective_monthly_military_upkeep(
	game_state: GameState,
	nation_id: int,
	base_upkeep: int = -1
) -> int:
	if (
		game_state == null
		or nation_id < 0
		or nation_id >= game_state.nations.size()
	):
		return 0
	var base := base_upkeep
	if base < 0:
		base = game_state.nation_monthly_military_upkeep(nation_id)
	return _ruler_adjusted_upkeep(
		base,
		RulerProfile.upkeep_multiplier(game_state.nations[nation_id])
	)


static func _ruler_adjusted_upkeep(
	base_upkeep: int,
	multiplier: float
) -> int:
	return maxi(int(ceil(
		float(maxi(base_upkeep, 0)) * maxf(multiplier, 0.0)
	)), 0)


## 国家财政储备策略的唯一真源。收入使用“城市税收+净贡赋”，不扣军费：
## - 和平目标 = 当前月收入 × 36；
## - 战争目标 = 首次进入当前连续战争前冻结的月收入 × 6。
## 低于目标时把缺口按 36 个月摊为月度储蓄预算；和平从空库恢复时会尽量
## 留存完整月收入，战争从空库恢复只留存约六分之一，体现半年目标的宽松。
## 若已有月赤字，所需节流额还会覆盖赤字。
static func gold_reserve_policy(
	game_state: GameState,
	nation_id: int,
	gold_flows: Array[Dictionary] = []
) -> Dictionary:
	if (
		nation_id < 0
		or nation_id >= game_state.nations.size()
	):
		return {}
	var flows := (
		gold_flows
		if not gold_flows.is_empty()
		else monthly_gold_flows(game_state)
	)
	var flow: Dictionary = flows[nation_id]
	var nation := game_state.nations[nation_id]
	var at_war := not game_state.wars_of(nation_id).is_empty()
	var current_income := maxi(int(flow["net_income"]), 0)
	var baseline_income := current_income
	if at_war and nation.war_gold_income_snapshot >= 0:
		baseline_income = nation.war_gold_income_snapshot
	var reserve_months := (
		WAR_GOLD_RESERVE_MONTHS
		if at_war else PEACE_GOLD_RESERVE_MONTHS
	)
	reserve_months = maxi(
		reserve_months + RulerProfile.reserve_months_bonus(nation),
		0
	)
	var target := baseline_income * reserve_months
	var gap := maxi(target - nation.treasury_gold, 0)
	var monthly_balance := int(flow["balance"])
	# 战争军制承载能力使用战前冻结收入；真实国库仍按 current income 结算。
	# 因此失地不会在同一 AI 周期把月收入骤降直接放大成等额裁军，
	# 但储备逐月消耗和实际欠饷仍会温和/强制地推动后续缩编。
	var budget_monthly_balance := (
		baseline_income - int(flow["military_upkeep"])
		if at_war and nation.war_gold_income_snapshot >= 0
		else monthly_balance
	)
	var target_savings := 0
	if gap > 0:
		target_savings = int(ceil(
			float(gap)
			/ float(GOLD_RESERVE_RECOVERY_MONTHS)
		))
	var required_upkeep_savings := maxi(
		target_savings - budget_monthly_balance,
		0
	)
	# 战前收入快照只负责防止失地后的即时连环裁军；当半年储备真正
	# 耗尽并产生实际欠饷时仍须收缩。缩编入口另按世界月份限频。
	if nation.unpaid_military_upkeep > 0:
		required_upkeep_savings = maxi(
			required_upkeep_savings, nation.unpaid_military_upkeep
		)
	return {
		"at_war": at_war,
		"current_monthly_income": current_income,
		"baseline_monthly_income": baseline_income,
		"reserve_months": reserve_months,
		"reserve_target": target,
		"reserve_gap": gap,
		"monthly_balance": monthly_balance,
		"budget_monthly_balance": budget_monthly_balance,
		"target_monthly_savings": target_savings,
		"required_upkeep_savings": required_upkeep_savings,
		"ready": nation.treasury_gold >= target,
	}


## 补齐外部脚本/旧地图直接改外交后的财政快照，并在最后一场战争结束时清空。
## 正常 AI 宣战会在关系改为 WAR 前调用 _capture_war_gold_income_snapshots，
## 因而这里不会用战后领土/贡赋覆盖战前基准。
func _synchronize_war_gold_income_snapshots() -> void:
	if state == null or state.nations.is_empty():
		return
	_war_gold_snapshot_diplomacy_revision = (
		state.diplomacy_revision
	)
	var needs_snapshot: Array[int] = []
	for nation in state.nations:
		var at_war := not state.wars_of(nation.id).is_empty()
		if at_war and nation.war_gold_income_snapshot < 0:
			needs_snapshot.append(nation.id)
		elif not at_war and nation.war_gold_income_snapshot >= 0:
			nation.war_gold_income_snapshot = -1
			nation.war_gold_income_snapshot_day = -1
	if needs_snapshot.is_empty():
		return
	# 正常路径在宣战前已主动冻结，不会走到这里。只有旧存档、测试或
	# 外部脚本直接改关系时才惰性汇总一次，避免每个普通日扫描全军/全城。
	var flows: Array[Dictionary] = (
		_forecast_trade_and_gold_flows(true)["gold_flows"]
	)
	for nation_id in needs_snapshot:
		var nation := state.nations[nation_id]
		nation.war_gold_income_snapshot = maxi(
			int(flows[nation_id]["net_income"]), 0
		)
		nation.war_gold_income_snapshot_day = state.day


func _capture_war_gold_income_snapshots(
	nation_ids: Array[int],
	frozen_gold_flows: Array[Dictionary] = []
) -> void:
	if state == null or nation_ids.is_empty():
		return
	var eligible: Array[int] = []
	for nation_id in nation_ids:
		if (
			nation_id < 0
			or nation_id >= state.nations.size()
			or not state.wars_of(nation_id).is_empty()
		):
			continue
		if (
			not eligible.has(nation_id)
		):
			eligible.append(nation_id)
	if eligible.is_empty():
		return
	var flows: Array[Dictionary] = (
		frozen_gold_flows
		if not frozen_gold_flows.is_empty()
		else _forecast_trade_and_gold_flows(true)["gold_flows"]
	)
	for nation_id in eligible:
		var nation := state.nations[nation_id]
		nation.war_gold_income_snapshot = maxi(
			int(flows[nation_id]["net_income"]), 0
		)
		nation.war_gold_income_snapshot_day = state.day
	_war_gold_snapshot_diplomacy_revision = (
		state.diplomacy_revision
	)


func _resolve_economy() -> void:
	var forecast := _forecast_trade_and_gold_flows()
	var trade: Dictionary = forecast["trade"]
	_publish_trade_snapshot(trade)
	var gold_flows: Array[Dictionary] = forecast["gold_flows"]
	var garrison_by_city := build_garrison_index(state)
	# 累计每国当月金钱税收（含战乱减产），作为贡赋基数。
	var gold_income: Array[int] = []
	gold_income.resize(state.nations.size())
	gold_income.fill(0)
	var half_year_food_produced: Array[int] = []
	half_year_food_produced.resize(state.nations.size())
	half_year_food_produced.fill(0)
	for city in state.cities:
		var nation := state.nations[city.owner_nation]
		var gold := city_gold_output(state, city)
		nation.treasury_gold += gold
		gold_income[city.owner_nation] += gold
		nation.manpower_pool += city_manpower_output(state, city)
		half_year_food_produced[city.owner_nation] += city_food_output(
			state,
			city,
			garrison_by_city
		)
	# 贸易税是新增收入；买粮、买人的金钱支出已在 trade_net_income 内一次性
	# 扣除。这里只应用国库净变动，再把「凭空买到」的粮/人落到库存/人力。
	for nation in state.nations:
		nation.treasury_gold += int(
			gold_flows[nation.id]["trade_net_income"]
		)
	_resolve_trade_purchases(trade)
	# 贡赋在军费之前结算：藩王先向宗主上缴，再用余款支付本国军费。
	_resolve_tribute(gold_income)
	_resolve_military_finance(gold_flows)
	_publish_food_snapshot(trade, half_year_food_produced)
	if state.day % DAYS_PER_HALF_YEAR == 0:
		for nation in state.nations:
			state.deposit_food(
				nation.id,
				half_year_food_produced[nation.id]
			)
		state.refresh_derived()
		_publish_granary_snapshot()


func _publish_food_snapshot(
	trade: Dictionary,
	half_year_produced: Array[int]
) -> void:
	for nation in state.nations:
		var imports := _trade_array_value(
			trade, "nation_food_import", nation.id
		)
		var exports := _trade_array_value(
			trade, "nation_food_export", nation.id
		)
		var trade_net := imports - exports
		nation.last_food_estimated_production = int(round(
			float(half_year_produced[nation.id]) / 6.0
		))
		nation.last_food_estimated_consumption = nation.last_food_demand
		nation.last_food_estimated_balance = (
			nation.last_food_estimated_production
			- nation.last_food_estimated_consumption
			+ trade_net
		)
	_publish_granary_snapshot()


func _publish_initial_food_snapshot() -> void:
	# Cold-start snapshot: no state mutation (debt/army untouched).
	# Production: aggregate city_food_output over all valid owner cities
	# (half-year) then /6 rounding to monthly, mirroring _publish_food_snapshot.
	# Trade: pure _forecast_trade_and_gold_flows()["trade"] — read-only.
	# Demand: compute projected demand BEFORE forecast so trade settlement
	# sees the same new demand values. Preserve settled last_food_demand
	# if already authoritative (EMA > 0 on old saves); otherwise use
	# projected values for cold-start.
	var garrison_by_city: Dictionary = build_garrison_index(state)
	var half_year_produced: Array[int] = []
	half_year_produced.resize(state.nations.size())
	half_year_produced.fill(0)
	for city in state.cities:
		if (
			city.owner_nation < 0
			or city.owner_nation >= state.nations.size()
		):
			continue
		half_year_produced[city.owner_nation] += city_food_output(
			state,
			city,
			garrison_by_city
		)
	for nation in state.nations:
		var projected_demand: int = (
			TradeNetwork.projected_nation_monthly_food_demand(
				state, nation.id
			)
		)
		nation.last_food_demand = projected_demand
	var forecast: Dictionary = _forecast_trade_and_gold_flows()
	var trade: Dictionary = forecast.get("trade", {})
	_publish_trade_snapshot(trade)
	_publish_food_snapshot(trade, half_year_produced)


func _publish_granary_snapshot() -> void:
	state.refresh_derived()


func _publish_trade_snapshot(trade: Dictionary) -> void:
	var next_routes: Array[Dictionary] = []
	for route_value in trade.get("routes", []):
		next_routes.append((route_value as Dictionary).duplicate(true))
	var signature := int(trade.get("signature", 0))
	var previous_signature := int(state.get_meta(&"trade_signature", -1))
	if signature != previous_signature:
		state.trade_revision += 1
		state.set_meta(&"trade_signature", signature)
	state.trade_routes = next_routes
	for city in state.cities:
		city.trade_gold_bonus = _trade_array_value(
			trade, "city_gold_bonus", city.id
		)
		city.trade_route_count = 0
		city.trade_food_balance = 0
	var nation_route_counts: Array[int] = []
	nation_route_counts.resize(state.nations.size())
	nation_route_counts.fill(0)
	for route in state.trade_routes:
		if int(route.get("status", TradeNetwork.BLOCKED)) == TradeNetwork.BLOCKED:
			continue
		var nation_a := int(route.get("nation_a", -1))
		var nation_b := int(route.get("nation_b", -1))
		if nation_a >= 0 and nation_a < nation_route_counts.size():
			nation_route_counts[nation_a] += 1
		if (
			nation_b >= 0
			and nation_b < nation_route_counts.size()
			and nation_b != nation_a
		):
			nation_route_counts[nation_b] += 1
		var seen_cities := {}
		for city_value in route.get("city_path", []):
			var city_id := int(city_value)
			if (
				city_id < 0 or city_id >= state.cities.size()
				or seen_cities.has(city_id)
			):
				continue
			seen_cities[city_id] = true
			state.cities[city_id].trade_route_count += 1
		var food_amount := int(route.get("food_transfer", 0))
		var source_id := int(route.get("food_source_city", -1))
		var destination_id := int(route.get("food_destination_city", -1))
		if source_id >= 0 and source_id < state.cities.size():
			state.cities[source_id].trade_food_balance -= food_amount
		if destination_id >= 0 and destination_id < state.cities.size():
			state.cities[destination_id].trade_food_balance += food_amount
	for nation in state.nations:
		var gross := _trade_array_value(trade, "nation_trade_gold", nation.id)
		var cost := _trade_array_value(trade, "nation_food_cost", nation.id)
		var manpower_cost := _trade_array_value(
			trade, "nation_manpower_cost", nation.id
		)
		nation.last_trade_gold = gross - cost - manpower_cost
		nation.last_trade_food_import = _trade_array_value(
			trade, "nation_food_import", nation.id
		)
		nation.last_trade_food_export = _trade_array_value(
			trade, "nation_food_export", nation.id
		)
		nation.last_trade_manpower_import = _trade_array_value(
			trade, "nation_manpower_import", nation.id
		)
		nation.last_trade_route_count = nation_route_counts[nation.id]


## 简化版 EU4 贸易结算：把 TradeNetwork 规划的「凭空采购」落到库存与人力。
## 粮食直接存入国家粮池（不从任何他国抽调），人力直接加进 manpower_pool。
## 金钱支出已在 _monthly_gold_flows_from_trade 的 trade_net_income 里扣过，
## 这里只负责让资源到账，保持「钱→粮/人凭空产生」的单向语义。
func _resolve_trade_purchases(trade: Dictionary) -> void:
	for nation in state.nations:
		var imported := _trade_array_value(
			trade, "nation_food_import", nation.id
		)
		if imported > 0:
			state.deposit_food(nation.id, imported)
	for nation in state.nations:
		var manpower := _trade_array_value(
			trade, "nation_manpower_import", nation.id
		)
		if manpower > 0:
			nation.manpower_pool += manpower
	state.refresh_derived()


## 贡赋：每个藩王把当月金钱税收的 tribute_rate 比例上缴直接宗主（守恒转移）。
## 基数用当月产出而非国库存量，避免把藩王反复抽干；逐级上缴（各自只缴本国
## 城市产出的分成）天然支持多级宗藩，且与结算顺序无关。
func _resolve_tribute(gold_income: Array[int]) -> void:
	for subject_value in state.suzerainty:
		var subject_id := int(subject_value)
		var overlord_id := int(state.suzerainty[subject_id]["overlord_id"])
		if (
			subject_id < 0
			or subject_id >= state.nations.size()
			or subject_id >= gold_income.size()
			or overlord_id < 0
			or overlord_id >= state.nations.size()
		):
			continue
		var rate := effective_tribute_rate(
			state,
			subject_id
		)
		if rate <= 0.0:
			continue
		var subject_nation := state.nations[subject_id]
		var tribute := mini(
			int(floor(float(gold_income[subject_id]) * rate)),
			subject_nation.treasury_gold
		)
		if tribute <= 0:
			continue
		subject_nation.treasury_gold -= tribute
		state.nations[overlord_id].treasury_gold += tribute
## 城市产出的就近治理倍率（钱/粮共用）：实控 owner 是藩王则 ×VASSAL_GOVERNANCE_OUTPUT_MULTIPLIER，
## 否则 ×1。纯 owner 派生、无状态，与战乱减产正交相乘。是藩王产出加成的单一真源。
static func city_governance_output_multiplier(
	game_state: GameState,
	city: City
) -> float:
	if (
		city == null
		or city.owner_nation < 0
		or city.owner_nation >= game_state.nations.size()
		or not game_state.is_vassal(city.owner_nation)
	):
		return 1.0
	return VASSAL_GOVERNANCE_OUTPUT_MULTIPLIER


static func _apply_governance_multiplier(
	game_state: GameState,
	city: City,
	output: int
) -> int:
	var mult := city_governance_output_multiplier(game_state, city)
	if is_equal_approx(mult, 1.0):
		return output
	return maxi(int(floor(float(output) * mult)), 0)


static func city_food_output(
	game_state: GameState,
	city: City,
	garrison_by_city: Dictionary = {}
) -> int:
	var garrison_output := city_food_output_for_garrison(
		city,
		city_garrison_troops(game_state, city, garrison_by_city)
	)
	var output := _apply_governance_multiplier(
		game_state,
		city,
		_apply_city_war_disruption(
			game_state,
			city,
			garrison_output
		)
	)
	return _apply_ruler_output_multiplier(
		game_state, city, output, RulerProfile.KEY_FOOD_OUTPUT
	)


static func city_gold_output(
	game_state: GameState,
	city: City
) -> int:
	var output := _apply_governance_multiplier(
		game_state,
		city,
		city_gold_output_before_governance(
			game_state,
			city
		)
	)
	return _apply_ruler_output_multiplier(
		game_state, city, output, RulerProfile.KEY_GOLD_OUTPUT
	)


static func city_manpower_output(
	game_state: GameState,
	city: City
) -> int:
	return _apply_ruler_output_multiplier(
		game_state, city, maxi(city.manpower_per_month, 0),
		RulerProfile.KEY_MANPOWER_OUTPUT
	)


static func _apply_ruler_output_multiplier(
	game_state: GameState,
	city: City,
	output: int,
	modifier_key: String
) -> int:
	if (
		city == null
		or city.owner_nation < 0
		or city.owner_nation >= game_state.nations.size()
	):
		return maxi(output, 0)
	var modifiers := RulerProfile.modifiers(
		game_state.nations[city.owner_nation]
	)
	return maxi(int(floor(
		float(maxi(output, 0))
			* float(modifiers.get(modifier_key, 1.0))
	)), 0)


## 城市当月金产出在治理倍率生效前的值。用于所有权变化的反事实评估，避免通过
## 除以当前倍率逆推时被逐城 floor 舍入破坏精度。
static func city_gold_output_before_governance(
	game_state: GameState,
	city: City
) -> int:
	return _apply_city_war_disruption(
		game_state,
		city,
		city.gold_per_month
	)


static func city_war_disrupted(
	game_state: GameState,
	city: City
) -> bool:
	return game_state.day < city.war_disruption_until_day


static func _apply_city_war_disruption(
	game_state: GameState,
	city: City,
	output: int
) -> int:
	if not city_war_disrupted(game_state, city):
		return maxi(output, 0)
	return maxi(int(floor(
		float(output)
			* CITY_WAR_OUTPUT_MULTIPLIER
	)), 0)


static func city_food_output_for_garrison(
	city: City,
	garrison_troops: int
) -> int:
	var capacity := maxf(
		float(city.manpower_per_month)
			* CITY_GARRISON_CAPACITY_PER_MANPOWER,
		1.0
	)
	var penalty := minf(
		CITY_GARRISON_FOOD_PENALTY_MAX,
		float(maxi(garrison_troops, 0))
			/ capacity
			* CITY_GARRISON_FOOD_PENALTY_RATE
	)
	return maxi(int(floor(
		float(city.food_per_half_year)
			* (1.0 - penalty)
	)), 0)


static func city_garrison_troops(
	game_state: GameState,
	city: City,
	garrison_by_city: Dictionary = {}
) -> int:
	# 提供 garrison_by_city（city_id -> 驻城兵力）时走 O(1) 查桶；否则回退全表扫描。
	# 结算路径（经济/军粮报告）每 tick 对上百城反复取用，一次分桶 O(A) 消除 O(C×A)。
	if not garrison_by_city.is_empty():
		return int(garrison_by_city.get(city.id, 0))
	var result := 0
	for army in game_state.armies:
		if (
			army.size > 0
			and army.owner_nation == city.owner_nation
			and not army.on_edge
			and army.location_city == city.id
		):
			result += army.size
	return result


## 一次性构建「驻城兵力桶」：city_id -> 该城本国非在途守军兵力总和（O(A)）。
## 供经济/军粮结算共享，替代 city_garrison_troops 的逐城 O(A) 全表扫描。
static func build_garrison_index(game_state: GameState) -> Dictionary:
	var index := {}
	var city_count := game_state.cities.size()
	for army in game_state.armies:
		if (
			army.size <= 0
			or army.on_edge
			or army.location_city < 0
			or army.location_city >= city_count
		):
			continue
		if army.owner_nation != game_state.cities[army.location_city].owner_nation:
			continue
		index[army.location_city] = int(index.get(army.location_city, 0)) + army.size
	return index


static func city_garrison_food_loss(
	game_state: GameState,
	city: City,
	additional_troops: int = 0
) -> int:
	var current_troops := city_garrison_troops(
		game_state,
		city
	)
	return (
		_apply_city_war_disruption(
			game_state,
			city,
			city_food_output_for_garrison(
				city,
				current_troops
			)
		)
		- _apply_city_war_disruption(
			game_state,
			city,
			city_food_output_for_garrison(
				city,
				current_troops
					+ maxi(additional_troops, 0)
			)
		)
	)


func _resolve_military_finance(
	gold_flows: Array[Dictionary] = []
) -> void:
	for nation in state.nations:
		var upkeep := (
			int(gold_flows[nation.id].get("military_upkeep", 0))
			if nation.id >= 0 and nation.id < gold_flows.size()
			else effective_monthly_military_upkeep(state, nation.id)
		)
		var paid := mini(nation.treasury_gold, upkeep)
		nation.treasury_gold -= paid
		nation.last_military_upkeep = upkeep
		nation.unpaid_military_upkeep = upkeep - paid
		nation.military_payment_ratio = (
			1.0
			if upkeep <= 0
			else clampf(
				float(paid) / float(upkeep),
				0.0,
				1.0
			)
		)


# ------------------------------------------------------------------ 1b. 全国人口补员

func _resolve_reinforcements() -> void:
	# 同步驱动：一次性完成全国补员（测试与快进路径用）。运行时改走
	# _resolve_reinforcements_over_frames 把 40 国循环分摊到多帧。
	var armies_by_nation := _bucket_armies_by_nation()
	var food_cache := {}
	for nation in state.nations:
		_reinforce_nation(
			nation,
			armies_by_nation.get(nation.id, [] as Array[Army]) as Array[Army],
			food_cache
		)


## 运行时分帧驱动：与 _resolve_reinforcements 逐国等价，但在国与国之间按墙钟预算
## yield。各国只写自身 manpower_pool 与自身军队 size，彼此独立；食物评估共享的
## food_cache 只读且与结算顺序无关，故切帧不改变任何结果（由等价守卫覆盖）。
func _resolve_reinforcements_over_frames() -> void:
	var armies_by_nation := _bucket_armies_by_nation()
	var food_cache := {}
	var slice_started := Time.get_ticks_usec()
	for nation in state.nations:
		_reinforce_nation(
			nation,
			armies_by_nation.get(nation.id, [] as Array[Army]) as Array[Army],
			food_cache
		)
		if Time.get_ticks_usec() - slice_started >= AI_RUNTIME_SLICE_BUDGET_USEC:
			await get_tree().process_frame
			slice_started = Time.get_ticks_usec()


## 按国家给 state.armies 分桶（O(A)），桶内保持原序。避免每国全表扫描（原 O(N×A），
## 40 国 × 数百军是月结算主线程卡顿的根因）；桶序与旧实现一致，补员结果不变。
func _bucket_armies_by_nation() -> Dictionary:
	return ReinforcementRules.bucket_armies_by_nation(state)


## 单国当月补员（逐国独立：只读食物评估共享 food_cache，只写本国 manpower_pool
## 与本国军队 size）。food_cache 携带 war_food_report 链路的边表矩阵/tick 级评估，
## 40 国共享后从每国 O(N×A) 冷调降为一次构建。
func _reinforce_nation(
	nation: Nation,
	nation_armies: Array[Army],
	food_cache: Dictionary
) -> void:
	ReinforcementPhase.reinforce_nation(
		state,
		nation,
		nation_armies,
		food_cache,
		Callable(self, "_food_security_report"),
		Callable(self, "_food_growth_manpower_budget"),
		reinforcement_network_cache_disabled
	)


func _reinforcement_priority(army: Army) -> int:
	return ReinforcementRules.reinforcement_priority(state, army)


## 战时新建战团前必须预留的人力：等于把现役军队本月补满编所需的人力
## （每军至多一个月补员量），并以 WARTIME_MANPOWER_RESERVE 为下限。这样
## 暴兵不会把 manpower_pool 抽到 0，月度补员始终有燃料，现役军队得以维持
## 满编，从而满足攻势的集结与战力门槛。现役越缺编，预留越多、越优先补员。
func _wartime_manpower_reserve(armies: Array[Army]) -> int:
	return ReinforcementRules.wartime_manpower_reserve(armies)


func _can_reinforce_army(
	army: Army,
	manpower_hub_network: Dictionary = {}
) -> bool:
	return ReinforcementRules.can_reinforce_army(
		state,
		army,
		reinforcement_network_cache_disabled,
		manpower_hub_network
	)

# ------------------------------------------------------------------ 2. 粮食 + 饥饿

func _resolve_supply() -> void:
	# 同步驱动：一次性完成当日补给结算（测试与快进路径用，保持单帧确定性）。
	# 运行时改走 _resolve_supply_over_frames 把两段逐军循环分摊到多帧。
	var supply_profile_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_prepare_supply_network_caches()
	_record_tick_profile_stage(
		"supply_prepare",
		supply_profile_started
	)
	supply_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var plans: Array = []   # [{army, sources, demand}]
	var demand_by_nation := _new_food_demand_accumulator()
	for army in state.armies:
		var plan := _build_supply_plan_for_army(army, demand_by_nation)
		if not plan.is_empty():
			plans.append(plan)
	_finalize_food_demand(demand_by_nation)
	_record_tick_profile_stage(
		"supply_build_plans",
		supply_profile_started
	)
	supply_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_sort_supply_plans(plans)
	_record_tick_profile_stage(
		"supply_sort",
		supply_profile_started
	)
	supply_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	for p in plans:
		_withdraw_supply_for_plan(p)
	_record_tick_profile_stage(
		"supply_withdraw",
		supply_profile_started
	)


## 运行时分帧驱动：与 _resolve_supply 逐军等价，但在两段循环内按墙钟预算 yield，
## 把每天 ~35ms 的补给结算摊到多帧，消除单帧尖峰。切帧点只暂停/继续循环，不重排
## plan 顺序、不改变累加序，故与同步版逐字节等价（由 supply_network_cache 守卫覆盖）。
func _resolve_supply_over_frames() -> void:
	_set_runtime_profile_stage(&"supply_prepare")
	var active_nation_ids := _prepare_supply_network_caches()
	await _prebuild_supply_networks_over_frames(
		active_nation_ids
	)
	var plans: Array = []
	var demand_by_nation := _new_food_demand_accumulator()
	var slice_started := Time.get_ticks_usec()
	_set_runtime_profile_stage(&"supply_build_plans")
	for army in state.armies:
		var plan := _build_supply_plan_for_army(army, demand_by_nation)
		if not plan.is_empty():
			plans.append(plan)
		if Time.get_ticks_usec() - slice_started >= AI_RUNTIME_SLICE_BUDGET_USEC:
			await get_tree().process_frame
			slice_started = Time.get_ticks_usec()
	_finalize_food_demand(demand_by_nation)
	_set_runtime_profile_stage(&"supply_sort")
	_sort_supply_plans(plans)
	slice_started = Time.get_ticks_usec()
	_set_runtime_profile_stage(&"supply_withdraw")
	for p in plans:
		_withdraw_supply_for_plan(p)
		if Time.get_ticks_usec() - slice_started >= AI_RUNTIME_SLICE_BUDGET_USEC:
			await get_tree().process_frame
			slice_started = Time.get_ticks_usec()


## 每日重算前的补给缓存维护：行军位置查表每天失效；驻城位置仅在该国网络
## 或该城围城状态变化时失效。网络损耗场继续按依赖指纹选择性失效。
func _prepare_supply_network_caches() -> Array[int]:
	_daily_supply_source_cache.clear()
	# 一次性预算共享依赖：被围城集合（O(B)）与各粮仓可用性，供逐国指纹复用，
	# 避免在指纹里逐粮仓 city_under_siege 的 O(B) 扫描退化成 O(城×B)。
	var besieged := state.besieged_city_ids()
	_invalidate_supply_city_sources_for_siege_changes(besieged)
	var active_nations := {}
	var occupied_edges_by_owner := {}
	for army in state.armies:
		if army.size <= 0:
			continue
		active_nations[army.owner_nation] = true
		if not army.on_edge or army.move_to < 0:
			continue
		if not occupied_edges_by_owner.has(army.owner_nation):
			occupied_edges_by_owner[army.owner_nation] = {}
		(occupied_edges_by_owner[army.owner_nation] as Dictionary)[
			GameState.edge_key(army.move_from, army.move_to)
		] = true
	var active_ids: Array[int] = []
	for nation_id_value in active_nations:
		active_ids.append(int(nation_id_value))
	active_ids.sort()
	_prepared_supply_blocked_edges.clear()
	if supply_network_cache_disabled:
		# 等价性守卫用：强制每天全量重建，复现指纹缓存前的旧行为。
		_daily_supply_network_cache.clear()
		_stable_supply_city_source_cache.clear()
	var warehouse_state := (
		{}
		if supply_network_cache_disabled
		else _supply_warehouse_availability(besieged)
	)
	for nation_id_value in active_ids:
		var nation_id := int(nation_id_value)
		var enemy_edges := {}
		for owner_id_value in occupied_edges_by_owner:
			var owner_id := int(owner_id_value)
			if not state.is_enemy(nation_id, owner_id):
				continue
			for edge_key_value in (
				occupied_edges_by_owner[owner_id]
				as Dictionary
			):
				enemy_edges[int(edge_key_value)] = true
		_prepared_supply_blocked_edges[nation_id] = (
			enemy_edges
		)
		if supply_network_cache_disabled:
			continue
		var fp := _supply_network_fingerprint(
			nation_id,
			warehouse_state,
			enemy_edges,
			besieged
		)
		if _supply_network_fingerprints.get(nation_id, []) != fp:
			_daily_supply_network_cache.erase(nation_id)
			_stable_supply_city_source_cache.erase(nation_id)
			_supply_network_fingerprints[nation_id] = fp
	return active_ids


## 真实运行路径在逐军计划前后台预热失效的国家级补给网络。旧路径把网络冷启动
## 隐藏在第一支军队的计划内，单次不可分割计算可阻塞主线程数十毫秒。任务期间
## GameState 冻结，各 worker 只写预分配结果数组中的独占索引；主线程完成后按
## 国家 ID 顺序提交。并发数取国家数、逻辑核数减一与 4 路上限的最小值。
func _prebuild_supply_networks_over_frames(
	active_nation_ids: Array[int]
) -> void:
	var missing_ids: Array[int] = []
	for nation_id in active_nation_ids:
		if not _daily_supply_network_cache.has(nation_id):
			missing_ids.append(nation_id)
	if missing_ids.is_empty():
		return
	var networks: Array = []
	networks.resize(missing_ids.size())
	var payload := {
		"nation_ids": missing_ids,
		"networks": networks,
		"blocked_edges_by_nation":
			_prepared_supply_blocked_edges,
	}
	_set_runtime_profile_stage(&"supply_network_worker")
	if (
		supply_network_parallel_prebuild_disabled
		or missing_ids.size() == 1
	):
		var task_id := WorkerThreadPool.add_task(
			_build_supply_networks_serial.bind(payload),
			false,
			"WorldWar supply networks serial"
		)
		while not WorkerThreadPool.is_task_completed(task_id):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task_id)
	else:
		var worker_count := mini(
			missing_ids.size(),
			mini(
				maxi(OS.get_processor_count() - 1, 1),
				SUPPLY_NETWORK_MAX_WORKERS
			)
		)
		var task_ids: Array[int] = []
		for worker_index in range(worker_count):
			task_ids.append(WorkerThreadPool.add_task(
				_build_supply_network_partition.bind(
					worker_index,
					worker_count,
					payload
				),
				false,
				"WorldWar supply networks parallel"
			))
		var pending := true
		while pending:
			pending = false
			for task_id in task_ids:
				if not WorkerThreadPool.is_task_completed(
					task_id
				):
					pending = true
					break
			if pending:
				await get_tree().process_frame
		for task_id in task_ids:
			WorkerThreadPool.wait_for_task_completion(task_id)
	for index in range(missing_ids.size()):
		var nation_id := missing_ids[index]
		_daily_supply_network_cache[nation_id] = (
			networks[index]
		)


func _build_supply_networks_serial(payload: Dictionary) -> void:
	var nation_ids: Array[int] = payload["nation_ids"]
	for index in range(nation_ids.size()):
		_build_supply_network_at(index, payload)


func _build_supply_network_partition(
	worker_index: int,
	worker_count: int,
	payload: Dictionary
) -> void:
	var nation_ids: Array[int] = payload["nation_ids"]
	var index := worker_index
	while index < nation_ids.size():
		_build_supply_network_at(index, payload)
		index += worker_count


## nation_ids/networks 均已定长；每个索引只由一个 worker 写入，线程间不修改
## 容器大小，也不共享可变结果。
func _build_supply_network_at(
	index: int,
	payload: Dictionary
) -> void:
	var nation_ids: Array[int] = payload["nation_ids"]
	var networks: Array = payload["networks"]
	var blocked_edges_by_nation: Dictionary = (
		payload["blocked_edges_by_nation"]
	)
	var nation_id := nation_ids[index]
	networks[index] = Pathfinding.build_supply_network(
		state,
		nation_id,
		blocked_edges_by_nation.get(nation_id, {})
	)


## 围城只改变驻扎在该城市的“补给孤岛”判定，不必清空其他城市或整张补给网络。
func _invalidate_supply_city_sources_for_siege_changes(
	besieged: Dictionary
) -> void:
	var changed_city_ids := {}
	for city_id_value in _supply_source_besieged_cities:
		if not besieged.has(city_id_value):
			changed_city_ids[int(city_id_value)] = true
	for city_id_value in besieged:
		if not _supply_source_besieged_cities.has(city_id_value):
			changed_city_ids[int(city_id_value)] = true
	if not changed_city_ids.is_empty():
		for nation_cache_value in _stable_supply_city_source_cache.values():
			var nation_cache: Dictionary = nation_cache_value
			for city_id_value in changed_city_ids:
				nation_cache.erase(int(city_id_value))
	_supply_source_besieged_cities = besieged.duplicate()


func _new_food_demand_accumulator() -> Array[int]:
	var demand_by_nation: Array[int] = []
	demand_by_nation.resize(state.nations.size())
	demand_by_nation.fill(0)
	return demand_by_nation


## 单军当日粮食需求结算（逐军独立、无跨军依赖）：累加本国月需求、按 1/30 滚动
## 到整粮债务，返回 {army, sources, demand} 供随后的库存竞争；被围守军与无需求军
## 在此直接落定状态并返回空字典（不参与竞争）。
func _build_supply_plan_for_army(
	army: Army,
	demand_by_nation: Array[int]
) -> Dictionary:
	if army.size <= 0 or army.state == Army.State.RECOVERING:
		return {}
	var siege_garrison := _siege_garrison_battle_of(army)
	if siege_garrison != null and siege_garrison.city.food_storage > 0:
		# 被围守军的粮食消耗真源是每日围城时钟。
		army.starving = false
		army.supply_ratio = 1.0
		army.supply_food_debt = 0.0
		return {}
	var sources := _cached_supply_sources(
		army,
		_daily_supply_source_cache,
		_daily_supply_network_cache,
		_stable_supply_city_source_cache
	)
	var route_loss := _weighted_supply_loss(sources)
	var mult: float = MAX_SUPPLY_MULT
	if not sources.is_empty():
		mult = minf(1.0 + route_loss, MAX_SUPPLY_MULT)
	var base := int(ceil(army.size * FOOD_PER_CAPITA))
	base = maxi(base, 1)
	var monthly_demand := int(ceil(
		base * mult * _ruler_food_consumption_multiplier(
			state, army.owner_nation
		)
	))
	demand_by_nation[army.owner_nation] += monthly_demand
	army.supply_food_debt += (
		float(monthly_demand) / float(DAYS_PER_MONTH)
	)
	var demand := int(floor(army.supply_food_debt + 0.000001))
	if demand > 0:
		army.supply_food_debt -= float(demand)
	return { "army": army, "sources": sources, "demand": demand }


## 落定各国当日粮食需求，并在月初把需求滚入 EMA（供裁军/宣战粮草评估）。
func _finalize_food_demand(demand_by_nation: Array[int]) -> void:
	for nation in state.nations:
		nation.last_food_demand = demand_by_nation[nation.id]
		if state.day % DAYS_PER_MONTH == 0:
			nation.food_demand_ema = (
				float(nation.last_food_demand)
				if nation.food_demand_ema <= 0.0
				else lerpf(
					nation.food_demand_ema,
					float(nation.last_food_demand),
					0.5
				)
			)


## 按物理镜像序排序取粮计划，避免 state.armies 创建顺序决定谁先取粮（确定性）。
func _sort_supply_plans(plans: Array) -> void:
	if plans.size() < 2:
		return
	var armies: Array[Army] = []
	var plans_by_army := {}
	for plan in plans:
		var army: Army = plan["army"]
		armies.append(army)
		plans_by_army[army] = plan
	EquivariantOrder.sort_armies_by_mirror_orbit(armies, state)
	for index in range(plans.size()):
		plans[index] = plans_by_army[armies[index]]


## 单个取粮计划的共享库存竞争结算（按已排序序执行；逐 plan 独立写自身军队状态）。
func _withdraw_supply_for_plan(p: Dictionary) -> void:
	var a: Army = p["army"]
	var demand: int = p["demand"]
	if demand <= 0:
		var has_food := _supply_sources_have_food(p["sources"])
		a.starving = not has_food
		a.supply_ratio = 1.0 if has_food else 0.0
		return
	var supplied := _withdraw_weighted_supply(
		p["sources"],
		demand,
		a.owner_nation
	)
	var shortfall := demand - supplied
	if shortfall > 0:
		a.starving = true
		a.supply_ratio = 1.0 - float(shortfall) / float(demand)
	else:
		a.starving = false
		a.supply_ratio = 1.0


## 每日滚动施加刚完成的粮食分配结果：士气/减员按 1/DAYS_PER_MONTH 摊派，
## 线路、部分短缺、兵力变化和共享库存竞争都已在本日 _resolve_supply 中体现。
## 逐军独立、无跨军求和/无 id/无 RNG → 天然镜像等变，不引入公平风险。
func _apply_supply_pressure() -> void:
	var morale_broken: Array[Army] = []
	for army in state.armies:
		if army.size <= 0 or army.state == Army.State.RECOVERING:
			continue
		var siege_garrison := _siege_garrison_battle_of(army)
		if siege_garrison != null and siege_garrison.city.food_storage > 0:
			# 被围守军的粮食时钟是 _drain_siege_food；此处不重复施压（补给孤岛）。
			army.starving = false
			continue
		var shortage := 1.0 - army.supply_ratio
		if _accrue_supply_pressure(army, shortage):
			morale_broken.append(army)
	for army in morale_broken:
		_retreat(army)
	_purge_dead_armies()


## 对单支军队施加当日断粮后果（纯逐军逻辑，无状态依赖/无 id/无 RNG → 天然镜像等变）。
## shortage∈[0,1]：士气按 SUPPLY_MORALE_LOSS_MAX/30 摊派、减员按 debt 整人化累计。
## 返回是否在本日「士气自正值边沿跌至 0」→ 由调用方收集触发溃逃。
func _accrue_supply_pressure(army: Army, shortage: float) -> bool:
	army.starving = shortage > 0.0001
	if shortage <= 0.0001:
		return false
	var old_morale := army.morale
	army.morale = maxf(
		army.morale - SUPPLY_MORALE_LOSS_MAX * shortage / float(DAYS_PER_MONTH),
		Combat.MORALE_FLOOR
	)
	# 减员按日累计到 supply_debt，满整人才扣、余额留存——避免逐日 ceil 造成的取整放大。
	army.supply_debt += shortage * float(army.size) * STARVE_RATE / float(DAYS_PER_MONTH)
	var loss := int(floor(army.supply_debt))
	if loss > 0:
		army.size -= loss
		army.supply_debt -= float(loss)
	# 只在士气从正值跌至 0 的瞬间触发溃逃（与旧口径一致）；FIGHTING 由战斗自身处置。
	return (
		old_morale > Combat.MORALE_FLOOR
		and army.morale <= Combat.MORALE_FLOOR
		and army.state in [Army.State.IDLE, Army.State.MOVING, Army.State.HOLDING]
		and army.size > 0
	)


# ------------------------------------------------------------------ 2b. 士气恢复

## 普通非交战、有粮军队每日恢复；战败后 RECOVERING 军队只能驻城，
## 日粮耗通过 supply_food_debt 保持月需求量纲，直至士气回满或粮尽。
func _recover_morale() -> void:
	for army in state.armies:
		if army.size <= 0 or army.state in [Army.State.FIGHTING, Army.State.RETREATING]:
			continue
		if army.state == Army.State.RECOVERING:
			_recover_garrisoned_army(army)
			continue
		if army.starving:
			continue
		var recovery_multiplier := morale_recovery_payment_multiplier(
			state.nations[
				army.owner_nation
			].military_payment_ratio
		)
		recovery_multiplier *= _ruler_morale_multiplier(
			state, army.owner_nation
		)
		army.morale = minf(
			army.morale
				+ army.max_morale
					/ float(Combat.MORALE_RECOVERY_DAYS)
					* recovery_multiplier,
			army.max_morale
		)


static func morale_recovery_payment_multiplier(
	payment_ratio: float
) -> float:
	return SupplyRules.morale_recovery_payment_multiplier(payment_ratio)


static func _ruler_food_consumption_multiplier(
	game_state: GameState,
	nation_id: int
) -> float:
	if (
		game_state == null
		or nation_id < 0
		or nation_id >= game_state.nations.size()
	):
		return 1.0
	return maxf(
		RulerProfile.food_consumption_multiplier(
			game_state.nations[nation_id]
		),
		0.1
	)


static func _ruler_morale_multiplier(
	game_state: GameState,
	nation_id: int
) -> float:
	if (
		game_state == null
		or nation_id < 0
		or nation_id >= game_state.nations.size()
	):
		return 1.0
	return maxf(
		RulerProfile.morale_multiplier(game_state.nations[nation_id]),
		0.1
	)


func _recover_garrisoned_army(army: Army) -> void:
	var city_id := army.location_city
	if city_id < 0 or city_id >= state.cities.size():
		army.state = Army.State.IDLE
		army.forced_retreat = false
		return
	var city := state.cities[city_id]
	# 驻城期间若城市已失守，重新向首都纵深撤退，不能在敌城恢复。
	if not state.has_military_access(army.owner_nation, city.owner_nation):
		_start_morale_retreat_from_city(army, city_id, city_id)
		return
	var sources := _cached_supply_sources(
		army,
		_daily_supply_source_cache,
		_daily_supply_network_cache,
		_stable_supply_city_source_cache
	)
	var route_loss := _weighted_supply_loss(sources)
	var full_month_demand := maxi(int(ceil(float(army.size) * RECOVERY_FOOD_PER_CAPITA)), 1)
	var recovery_multiplier := morale_recovery_payment_multiplier(
		state.nations[
			army.owner_nation
		].military_payment_ratio
	)
	recovery_multiplier *= _ruler_morale_multiplier(
		state, army.owner_nation
	)
	var target_gain := minf(
		army.max_morale
			/ float(Combat.MORALE_RECOVERY_DAYS)
			* recovery_multiplier,
		army.max_morale - army.morale
	)
	var full_daily_gain := (
		army.max_morale
		/ float(Combat.MORALE_RECOVERY_DAYS)
	)
	var monthly_demand := float(full_month_demand) * (
		minf(1.0 + route_loss, MAX_SUPPLY_MULT)
		if not sources.is_empty()
		else 1.0
	) * _ruler_food_consumption_multiplier(
		state, army.owner_nation
	) * target_gain / maxf(full_daily_gain, 0.0001)
	army.supply_food_debt += (
		monthly_demand / float(DAYS_PER_MONTH)
	)
	var demand := int(floor(
		army.supply_food_debt + 0.000001
	))
	if demand > 0:
		army.supply_food_debt -= float(demand)
	var supplied := (
		_withdraw_weighted_supply(
			sources,
			demand,
			army.owner_nation
		)
		if demand > 0
		else 0
	)
	var has_food := _supply_sources_have_food(sources)
	var supply_ratio := (
		float(supplied) / float(demand)
		if demand > 0
		else (1.0 if has_food else 0.0)
	)
	army.starving = supply_ratio < 1.0
	army.supply_ratio = supply_ratio
	if supply_ratio > 0.0:
		army.morale = minf(
			army.morale + target_gain * supply_ratio,
			army.max_morale
		)
	if army.morale >= army.max_morale - 0.0001:
		army.morale = army.max_morale
		army.state = Army.State.IDLE
		army.forced_retreat = false
		army.starving = false
	elif not has_food:
		# 无可达粮仓或粮仓耗尽也是强制驻守的终止条件；保留当前未满士气。
		army.state = Army.State.IDLE
		army.forced_retreat = false


func _supply_sources_have_food(sources: Array[Dictionary]) -> bool:
	return SupplyRules.sources_have_food(state, sources)


## 逐国补给网络依赖指纹：捕获 build_supply_network 读取的全部动态量——可达
## 各方粮仓的可用性（存量>0 且未被围）、敌占边集合、归属/外交版本，以及各粮池持有者
## 的「藩王首都中继起点」集合及其被围态（中继节点被围会改变损耗场）。拓扑与 danger 系
## 静态量（运行期不改），无需纳入。指纹一致即可跨天复用网络。
func _supply_network_fingerprint(
	nation_id: int,
	warehouse_state: Dictionary,
	enemy_edges: Dictionary,
	besieged: Dictionary
) -> Array[int]:
	return SupplyRules.network_fingerprint(
		state, nation_id, warehouse_state, enemy_edges, besieged
	)


## 预算各国可用粮仓（存量>0 且未被围）为 owner_id -> Array[city_id]，供逐国
## 指纹复用，避免每国重复遍历全部粮仓与逐粮仓 city_under_siege。
func _supply_warehouse_availability(besieged: Dictionary) -> Dictionary:
	return SupplyRules.warehouse_availability(state, besieged)


func _cached_supply_sources(
	army: Army,
	cache: Dictionary,
	network_cache: Dictionary,
	stable_city_cache: Variant = null
) -> Array[Dictionary]:
	var on_edge := army.on_edge and army.move_to != -1
	var position_key := _supply_position_key(army)
	var source_cache := cache
	var key: Variant = "%d:%s" % [army.owner_nation, position_key]
	if not on_edge and stable_city_cache is Dictionary:
		var stable_cache: Dictionary = stable_city_cache
		if not stable_cache.has(army.owner_nation):
			stable_cache[army.owner_nation] = {}
		source_cache = stable_cache[army.owner_nation]
		key = army.location_city
	if not source_cache.has(key):
		if not network_cache.has(army.owner_nation):
			network_cache[army.owner_nation] = (
				Pathfinding.build_supply_network(
					state,
					army.owner_nation
				)
			)
		source_cache[key] = Pathfinding.supply_sources_from_network(
			state,
			army,
			network_cache[army.owner_nation]
		)
	return source_cache[key]


static func _supply_position_key(army: Army) -> String:
	return SupplyRules.position_key(army)


func _weighted_supply_loss(sources: Array[Dictionary]) -> float:
	return SupplyRules.weighted_loss(state, sources)


func _withdraw_weighted_supply(
	sources: Array[Dictionary],
	demand: int,
	order_nation: int
) -> int:
	return SupplyRules.withdraw_weighted(state, sources, demand, order_nation)


static func _supply_source_weight(stock: int, route_loss: float) -> float:
	return SupplyRules.source_weight(stock, route_loss)

# ------------------------------------------------------------------ 2c. 被围城粮草时钟（每日）

## 规格 R3：被围城每日消耗本城存粮（补给孤岛，无法外部补充）。
## 存粮耗尽（food_storage<=0）后，守军城防加成大幅衰减由 Combat 侧按 food_storage 判定，
## 叠加断粮士气加速崩溃 → 城市战斗力大幅下降。
func _drain_siege_food() -> void:
	for battle in state.battles:
		if battle.finished or battle.kind != Battle.Kind.SIEGE or battle.city == null:
			continue
		var city := battle.city
		state.change_city_food_storage(city.id, -SIEGE_CITY_FOOD_PER_DAY)
		if battle.has_garrison:
			var has_food := city.food_storage > 0
			for defender in battle.side_b:
				if defender.size <= 0:
					continue
				defender.starving = not has_food
				defender.supply_ratio = 1.0 if has_food else 0.0


func _siege_garrison_battle_of(army: Army) -> Battle:
	if army.state != Army.State.FIGHTING or army.battle_id == -1:
		return null
	var battle := state.battle_by_id(army.battle_id)
	if battle == null or battle.finished or battle.kind != Battle.Kind.SIEGE:
		return null
	if not battle.has_garrison or not battle.side_b.has(army):
		return null
	return battle


## 每日推进持久边境防区状态，不等待十日一次的正式地图 AI 决策。
## 同步驱动：一次性处理全国防区（测试与快进路径用）。运行时改走分帧版。
func _resolve_line_edge_assignment_emergencies() -> void:
	var army_by_id := _living_army_index()
	for nation in state.nations:
		_resolve_nation_line_edge_sectors(nation, army_by_id)


## 运行时分帧驱动：与同步版逐国等价，但在国与国之间按墙钟预算 yield。各国只处理
## 本国防区、只改本国军队状态，彼此独立；army_by_id 与 besieged 为只读快照，切帧
## 不改变任何结果（由等价守卫覆盖）。
func _resolve_line_edge_assignment_emergencies_over_frames() -> void:
	var army_by_id := _living_army_index()
	var slice_started := Time.get_ticks_usec()
	for nation in state.nations:
		_resolve_nation_line_edge_sectors(nation, army_by_id)
		if Time.get_ticks_usec() - slice_started >= AI_RUNTIME_SLICE_BUDGET_USEC:
			await get_tree().process_frame
			slice_started = Time.get_ticks_usec()


func _living_army_index() -> Dictionary:
	var army_by_id := {}
	for army in state.armies:
		if army.size > 0:
			army_by_id[army.id] = army
	return army_by_id


## 单国防区每日状态推进。LINE 防区不读取围城、敌军位置或临时压力；
## 唯一会改变既有防区的运行时事件是锚点控制权丢失。
func _resolve_nation_line_edge_sectors(
	nation: Nation,
	army_by_id: Dictionary
) -> void:
	var sectors: Dictionary = nation.frontier_defense_sectors
	for city_id_value in sectors.keys().duplicate():
		var city_id := int(city_id_value)
		var sector: FrontierDefenseSector = sectors[city_id]
		if (
			city_id < 0
			or city_id >= state.cities.size()
			or state.cities[city_id].owner_nation
				!= nation.id
		):
			sector.state = FrontierDefenseSector.State.RETREATING
			_retreat_lost_frontier_sector(
				sector,
				army_by_id
			)
			sectors.erase(city_id)
			continue
		sector.state = FrontierDefenseSector.State.NORMAL
	nation.frontier_defense_sectors = sectors


func _retreat_lost_frontier_sector(
	sector: FrontierDefenseSector,
	army_by_id: Dictionary
) -> void:
	for army_id in sector.assigned_army_ids:
		var army: Army = army_by_id.get(int(army_id))
		if army == null:
			continue
		army.clear_line_assignment()
		if (
			army.on_edge
			and sector.city_id in [army.move_from, army.move_to]
		):
			_retreat(army)
			if army.size > 0:
				var retreat_target := (
					army.path[-1]
					if not army.path.is_empty()
					else army.move_to
				)
				var retreat_order := ActionCandidate.make(
					ActionCandidate.Kind.RETREAT,
					2000.0,
					"填线防区：锚点城市%d失守，军%d协同撤退"
						% [sector.city_id, army.id],
					retreat_target
				)
				retreat_order.minimum_commit_days = (
					AI_DECISION_INTERVAL_DAYS
				)
				_record_ai_order(army, retreat_order)
		elif army.is_at_city_node(sector.city_id):
			_start_morale_retreat_from_city(
				army,
				sector.city_id,
				sector.city_id
			)


func _advance_holding_adaptation() -> void:
	for army in state.armies:
		if army.size <= 0 or army.state != Army.State.HOLDING:
			continue
		var held_edge := state.edge_of(
			army.move_from,
			army.move_to
		)
		if held_edge == null or not held_edge.allows_holding:
			_leave_holding(army)
			continue
		if army.supply_ratio >= 1.0 - 0.0001:
			army.holding_days += 1
		elif army.supply_ratio <= 0.0001:
			army.holding_days = maxi(army.holding_days - HOLDING_STARVE_DECAY, 0)
		# 部分补给：既不增长也不衰减。

# ------------------------------------------------------------------ 2.5 外交

func _resolve_diplomacy() -> void:
	if not diplomacy_enabled or state.day % DIPLOMACY_DECISION_INTERVAL_DAYS != 0:
		return
	var diplomacy_profile_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_normalize_alliance_wars()
	_record_tick_profile_stage(
		"diplomacy_normalize", diplomacy_profile_started
	)
	diplomacy_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var evaluation_cache := _seed_trade_forecast({})
	var frozen_gold_flows: Array[Dictionary] = (
		evaluation_cache["monthly_gold_flows"]
	)
	_record_tick_profile_stage(
		"diplomacy_trade_seed", diplomacy_profile_started
	)
	diplomacy_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_refresh_war_preparation_viability(evaluation_cache)
	_record_tick_profile_stage(
		"diplomacy_preparation_viability",
		diplomacy_profile_started
	)
	diplomacy_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	if tick_phase_profiling_enabled:
		var profile := {"enabled": true}
		var actions := DiplomacyAI.choose_actions(
			state,
			profile,
			not diplomacy_structure_cache_disabled,
			evaluation_cache
		)
		_record_tick_profile_stage(
			"diplomacy_choose", diplomacy_profile_started
		)
		for stage in profile:
			if stage != "enabled":
				tick_profile_last_usec[stage] = profile[stage]
		diplomacy_profile_started = Time.get_ticks_usec()
		_commit_diplomacy_actions(
			actions, evaluation_cache, frozen_gold_flows
		)
		_record_tick_profile_stage(
			"diplomacy_commit", diplomacy_profile_started
		)
	else:
		_commit_diplomacy_actions(
			DiplomacyAI.choose_actions(
				state, {},
				not diplomacy_structure_cache_disabled,
				evaluation_cache
			),
			evaluation_cache,
			frozen_gold_flows
		)


func _resolve_diplomacy_over_frames() -> void:
	if not diplomacy_enabled or state.day % DIPLOMACY_DECISION_INTERVAL_DAYS != 0:
		return
	_normalize_alliance_wars()
	_set_runtime_profile_stage(&"trade_forecast_worker")
	var evaluation_cache := await _seed_trade_forecast_over_frames()
	var frozen_gold_flows: Array[Dictionary] = (
		evaluation_cache["monthly_gold_flows"]
	)
	_refresh_war_preparation_viability(evaluation_cache)
	var job := {
		"actions": [] as Array[Dictionary],
		"evaluation_cache": evaluation_cache,
	}
	var task_id := WorkerThreadPool.add_task(
		_build_parallel_diplomacy_actions.bind(job),
		true,
		"WorldWar diplomacy"
	)
	_set_runtime_profile_stage(&"diplomacy_worker")
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	var actions: Array = job["actions"]
	_set_runtime_profile_stage(&"diplomacy_commit")
	await _commit_diplomacy_actions_over_frames(
		actions, evaluation_cache, frozen_gold_flows
	)


func _build_parallel_diplomacy_actions(job: Dictionary) -> void:
	job["actions"] = DiplomacyAI.choose_actions(
		state, {},
		not diplomacy_structure_cache_disabled,
		job["evaluation_cache"]
	)


func _seed_trade_forecast_over_frames() -> Dictionary:
	var job := {"cache": {}}
	var task_id := WorkerThreadPool.add_task(
		_build_trade_forecast_cache_job.bind(job),
		true,
		"WorldWar trade forecast"
	)
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	return job["cache"] as Dictionary


func _build_trade_forecast_cache_job(job: Dictionary) -> void:
	job["cache"] = _seed_trade_forecast({})


func _commit_diplomacy_actions_over_frames(
	actions: Array,
	evaluation_cache: Dictionary = {},
	frozen_gold_flows: Array[Dictionary] = []
) -> void:
	var runtime_slice_started := Time.get_ticks_usec()
	_defer_declaration_launches = true
	var action_cache := evaluation_cache
	for action in actions:
		# action 之间可能改变外交、国库或军队；缓存只在单个 action 内共享。
		_commit_diplomacy_action(
			action, action_cache, frozen_gold_flows
		)
		for mobilization in _pending_war_mobilizations:
			_start_war_mobilization(
				int(mobilization["nation_id"]),
				int(mobilization["requested_armies"]),
				action_cache
			)
			if (
				Time.get_ticks_usec() - runtime_slice_started
					>= AI_RUNTIME_SLICE_BUDGET_USEC
			):
				await get_tree().process_frame
				runtime_slice_started = Time.get_ticks_usec()
		_pending_war_mobilizations.clear()
		action_cache = _new_diplomacy_action_cache()
		if (
			Time.get_ticks_usec() - runtime_slice_started
				>= AI_RUNTIME_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
	_defer_declaration_launches = false


func _new_diplomacy_action_cache() -> Dictionary:
	if diplomacy_structure_cache_disabled:
		return {}
	return {
		"__diplomacy_topology_cache": _diplomacy_topology_cache,
	}


func _commit_diplomacy_actions(
	actions: Array,
	evaluation_cache: Dictionary = {},
	frozen_gold_flows: Array[Dictionary] = []
) -> void:
	var action_cache := evaluation_cache
	for action in actions:
		var action_started := (
			Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
		)
		# action 之间不复用：前一个提交可能改变后一个的贸易与资源输入。
		_commit_diplomacy_action(
			action, action_cache, frozen_gold_flows
		)
		var kind := int(action.get("kind", DiplomacyAI.Action.NONE))
		var stage := (
			"diplomacy_commit_declare_war"
			if kind == DiplomacyAI.Action.DECLARE_WAR
			else "diplomacy_commit_other"
		)
		_record_tick_profile_stage(stage, action_started)
		action_cache = _new_diplomacy_action_cache()


func _commit_diplomacy_action(
	action: Dictionary,
	evaluation_cache: Dictionary = {},
	frozen_gold_flows: Array[Dictionary] = []
) -> void:
	_execute_diplomatic_action(
		action, evaluation_cache, frozen_gold_flows
	)


## 失去全部城市的国家立即向所有交战国投降。该规则属于战争结算，
## 不经过和平意愿评分、不等待月度外交 tick，也不保留多国战争残余关系。
func _resolve_eliminated_nation_capitulations() -> void:
	for surrendering in range(state.nations.size()):
		# 所有领土事务都会 refresh_derived；直接读取唯一存续真源，避免
		# 每日为每个国家重新扫描全部城市。
		if state.nations[surrendering].alive:
			continue
		var opponents := _war_opponents_including_eliminated(
			surrendering
		)
		# 藩王没有独立议和权。其全境失守只让这个无城成员退出战斗，
		# 不能借 _make_coalition_peace 强迫整个宗主体系停战；法理归属留给
		# 宗主最终集团议和统一确认。
		if state.is_vassal(surrendering):
			for opponent in opponents:
				state.set_diplomatic_relation(
					surrendering,
					opponent,
					GameState.DiplomaticRelation.NEUTRAL,
					GameState.DEFAULT_TRUCE_DAYS
				)
				state.clear_war_objective(surrendering, opponent)
			_reconcile_battles_after_coalition_peace(
				[surrendering] as Array[int],
				opponents
			)
			_clear_finished_war_mobilization(surrendering)
			continue
		for victor in opponents:
			if not state.is_enemy(surrendering, victor):
				continue
			_execute_diplomatic_action({
				"kind": DiplomacyAI.Action.MAKE_PEACE,
				"a": victor,
				"b": surrendering,
				"surrendering_nation": surrendering,
				"reason": (
					"国%d全境失守，向交战国%d投降"
					% [surrendering, victor]
				),
			})


## 削藩内战的首都失陷通吃结算。仅当 old_owner 与 claimant 正处于削藩内战关系时生效，
## 返回 true 表示已按通吃处理（调用方不再走普通投降）。否则返回 false。
##   宗主占藩王首都 → 吞并藩王全境，宗藩记录移除。
##   藩王占宗主首都 → 藩王继承宗主全部领土；宗主的其余藩王转投胜利藩王；
##                    胜利藩王自身升为独立主权（继承整个宗藩体系顶点）。
func _is_civil_war_capital_capture(old_owner: int, claimant: int) -> bool:
	return (
		(
			state.overlord_of(old_owner) == claimant
			and state.is_in_civil_war(old_owner)
		)
		or (
			state.overlord_of(claimant) == old_owner
			and state.is_in_civil_war(claimant)
		)
	)


func _finalize_civil_war_capital_annexation(
	claimant: int,
	claimant_was_rebel_vassal: bool
) -> void:
	if claimant_was_rebel_vassal:
		WorldNaming.promote_vassal_to_sovereign(state, claimant)
	_synchronize_war_gold_income_snapshots()
	_ai_last_decision_day = -1


func _resolve_civil_war_capital_capture(old_owner: int, claimant: int) -> bool:
	if not _is_civil_war_capital_capture(old_owner, claimant):
		return false
	var claimant_was_rebel_vassal := (
		state.overlord_of(claimant) == old_owner
		and state.is_in_civil_war(claimant)
	)
	if not state.annex_nation(claimant, old_owner):
		return false
	_finalize_civil_war_capital_annexation(
		claimant, claimant_was_rebel_vassal
	)
	return true


const CAPITAL_CAPTURE_TRANSFER_HOPS: int = 2


## 首都失陷后，以首都为中心沿可通行道路两跳内、仍由战败国实控的城市
## 一并转为胜方实控与法理，然后战败国立即退出全部战争。范围转移使用
## 单笔领土事务，避免逐城迁都、粮仓与存亡状态在半成品之间反复变化。
func _resolve_capital_capture_capitulation(
	surrendering: int,
	victor: int,
	captured_capital_id: int
) -> Array[int]:
	if (
		surrendering < 0
		or victor < 0
		or surrendering >= state.nations.size()
		or victor >= state.nations.size()
		or surrendering == victor
	):
		return [] as Array[int]
	if (
		captured_capital_id < 0
		or captured_capital_id >= state.cities.size()
		or state.cities[captured_capital_id].owner_nation != surrendering
	):
		return [] as Array[int]
	var transfer_ids := _capital_capture_transfer_city_ids(
		surrendering, captured_capital_id
	)
	var operations: Array[Dictionary] = []
	for city_id in transfer_ids:
		operations.append({
			"city_id": city_id,
			"controller_id": victor,
			"legal_owner_id": victor,
			"sponsor_id": -1,
			"reset_political_target": true,
			"reason": "capital_capture_capitulation",
			"stock_policy": (
				GameState.TerritoryStockDisposition.CAPTURE_SPOILS
				if city_id == captured_capital_id
				else GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
			),
		})
	var confirmation := state.apply_territory_transaction(operations)
	if not bool(confirmation.get("ok", false)):
		return [] as Array[int]
	var confirmed: Array[int] = []
	for city_value in confirmation.get("changed_city_ids", []):
		confirmed.append(int(city_value))
	var opponents := _war_opponents_including_eliminated(
		surrendering
	)
	if opponents.has(victor):
		opponents.erase(victor)
		opponents.push_front(victor)
	for opponent in opponents:
		if not state.is_enemy(surrendering, opponent):
			continue
		_execute_diplomatic_action({
			"kind": DiplomacyAI.Action.MAKE_PEACE,
			"a": opponent,
			"b": surrendering,
			"surrendering_nation": surrendering,
			"reason": (
				"国%d首都失守，向交战国%d投降"
				% [surrendering, opponent]
			),
		})
	return confirmed


func _capital_capture_transfer_city_ids(
	surrendering: int,
	captured_capital_id: int
) -> Array[int]:
	var result: Array[int] = []
	if (
		captured_capital_id < 0
		or captured_capital_id >= state.cities.size()
	):
		return result
	var distances := {captured_capital_id: 0}
	var queue: Array[int] = [captured_capital_id]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		var distance := int(distances[current])
		if state.cities[current].owner_nation == surrendering:
			result.append(current)
		if distance >= CAPITAL_CAPTURE_TRANSFER_HOPS:
			continue
		var neighbors: Array[int] = state.neighbors(current).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if distances.has(neighbor):
				continue
			var edge := state.edge_of(current, neighbor)
			if (
				edge == null
				or edge.max_manpower <= 0
			):
				continue
			distances[neighbor] = distance + 1
			queue.append(neighbor)
	result.sort()
	return result


func _war_opponents_including_eliminated(nation_id: int) -> Array[int]:
	var opponents: Array[int] = []
	for other_id in range(state.nations.size()):
		if other_id != nation_id and state.is_enemy(nation_id, other_id):
			opponents.append(other_id)
	return opponents


func _refresh_war_preparation_viability(
	evaluation_cache: Dictionary = {}
) -> void:
	for nation in state.nations:
		if nation.war_preparation_target_nation < 0:
			nation.war_preparation_unready_since_day = -1
			continue
		var ready := DiplomacyAI.war_preparation_resources_ready(
			state,
			nation.id,
			evaluation_cache
		)
		if ready:
			nation.war_preparation_unready_since_day = -1
		elif nation.war_preparation_unready_since_day < 0:
			nation.war_preparation_unready_since_day = state.day


func _execute_diplomatic_action(
	action: Dictionary,
	evaluation_cache: Dictionary = {},
	frozen_gold_flows: Array[Dictionary] = []
) -> bool:
	var kind := int(action.get("kind", DiplomacyAI.Action.NONE))
	var nation_a := int(action.get("a", -1))
	var nation_b := int(action.get("b", -1))
	var reason := str(action.get("reason", ""))
	if (
		nation_a < 0
		or nation_b < 0
		or nation_a >= state.nations.size()
		or nation_b >= state.nations.size()
	):
		return false
	var changed := false
	var war_outcome_a := 0.0
	var war_outcome_b := 0.0
	var territories_transferred := 0
	var occupations_restored := 0
	var action_bloc_a: Array[int] = [nation_a]
	var action_bloc_b: Array[int] = [nation_b]
	match kind:
		DiplomacyAI.Action.MAKE_PEACE:
			if state.is_enemy(nation_a, nation_b):
				var peace_result := _make_coalition_peace(
					nation_a,
					nation_b
				)
				changed = bool(peace_result.get("changed", false))
				war_outcome_a = float(
					peace_result.get("war_outcome_a", 0.0)
				)
				war_outcome_b = float(
					peace_result.get("war_outcome_b", 0.0)
				)
				territories_transferred = int(
					peace_result.get("territories_transferred", 0)
				)
				occupations_restored = int(
					peace_result.get("occupations_restored", 0)
				)
				action_bloc_a.assign(
					peace_result.get("bloc_a", [nation_a])
				)
				action_bloc_b.assign(
					peace_result.get("bloc_b", [nation_b])
				)
				if territories_transferred > 0:
					reason += (
						"；联盟和平确认%d座城市的领土转移"
						% territories_transferred
					)
				if occupations_restored > 0:
					reason += (
						"；联盟和平恢复%d座断联的临时占领城市"
						% occupations_restored
					)
		DiplomacyAI.Action.DECLARE_WAR:
			if (
				DiplomacyAI.within_diplomatic_range(
					state, nation_a, nation_b, evaluation_cache
				)
				and state.can_alliance_declare_war(nation_a, nation_b)
			):
				var declaration_part_started := (
					Time.get_ticks_usec()
					if tick_phase_profiling_enabled else 0
				)
				var attackers := state.alliance_bloc(nation_a)
				var defenders := state.alliance_bloc(nation_b)
				action_bloc_a = attackers
				action_bloc_b = defenders
				_record_tick_profile_stage(
					"diplomacy_declare_blocs",
					declaration_part_started
				)
				declaration_part_started = (
					Time.get_ticks_usec()
					if tick_phase_profiling_enabled else 0
				)
				changed = _set_coalition_war(
					attackers,
					defenders,
					frozen_gold_flows
				)
				_record_tick_profile_stage(
					"diplomacy_declare_set_war",
					declaration_part_started
				)
				declaration_part_started = (
					Time.get_ticks_usec()
					if tick_phase_profiling_enabled else 0
				)
				var objective_city := int(action.get("objective_city", -1))
				if changed and objective_city >= 0:
					_set_coalition_war_objective(
						attackers,
						defenders,
						nation_a,
						objective_city,
						str(action.get("objective_reason", ""))
					)
				_record_tick_profile_stage(
					"diplomacy_declare_objective",
					declaration_part_started
				)
				declaration_part_started = (
					Time.get_ticks_usec()
					if tick_phase_profiling_enabled else 0
				)
				if changed:
					_prepare_diplomacy_mobilization_cache(
						evaluation_cache
					)
					_record_tick_profile_stage(
						"diplomacy_declare_cache_seed",
						declaration_part_started
					)
					declaration_part_started = (
						Time.get_ticks_usec()
						if tick_phase_profiling_enabled else 0
					)
					var preparation_days := 0
					var preparation_started := (
						state.nations[nation_a]
							.war_preparation_started_day
					)
					if preparation_started >= 0:
						preparation_days = maxi(
							state.day - preparation_started,
							0
						)
					var requested_armies := int(
						action.get("mobilization_armies", -1)
					)
					for attacker_id in attackers:
						_queue_or_start_war_mobilization(
							attacker_id,
							requested_armies
								if attacker_id == nation_a
								else -1,
							evaluation_cache
						)
					for defender_id in defenders:
						_clear_war_preparation(defender_id)
						_queue_or_start_war_mobilization(
							defender_id,
							-1,
							evaluation_cache
						)
					_record_tick_profile_stage(
						"diplomacy_declare_mobilization",
						declaration_part_started
					)
					declaration_part_started = (
						Time.get_ticks_usec()
						if tick_phase_profiling_enabled else 0
					)
					_clear_war_preparation(nation_a, false)
					if _defer_declaration_launches:
						_pending_declaration_launches[nation_a] = {
							"objective_city": objective_city,
							"preparation_days": preparation_days,
						}
					else:
						_launch_campaign_offensive(
							nation_a,
							objective_city,
							preparation_days
						)
					_record_tick_profile_stage(
						"diplomacy_declare_launch",
						declaration_part_started
					)
					# 宣战瞬间出现新前线：强制所有参战国（尤其被动防守方）
					# 下一天重算国境与防区，立即沿新边界铺开填线军。
					_ai_last_decision_day = -1
		DiplomacyAI.Action.FORM_ALLIANCE:
			if (
				state.relation_between(nation_a, nation_b)
				== GameState.DiplomaticRelation.NEUTRAL
				and DiplomacyAI.within_diplomatic_range(
					state, nation_a, nation_b, evaluation_cache
				)
			):
				changed = state.set_diplomatic_relation(
					nation_a,
					nation_b,
					GameState.DiplomaticRelation.ALLIED
				)
				if changed:
					_synchronize_alliance_wars(
						nation_a, nation_b, evaluation_cache,
						frozen_gold_flows
					)
		DiplomacyAI.Action.LEAVE_ALLIANCE:
			if state.is_allied(nation_a, nation_b) and nation_a != nation_b:
				changed = state.set_diplomatic_relation(
					nation_a,
					nation_b,
					GameState.DiplomaticRelation.NEUTRAL
				)
				if changed:
					_repatriate_after_access_revoked(nation_a, nation_b)
		DiplomacyAI.Action.PREPARE_WAR:
			if (
				DiplomacyAI.within_diplomatic_range(
					state, nation_a, nation_b, evaluation_cache
				)
				and state.can_alliance_declare_war(nation_a, nation_b)
			):
				changed = _start_war_preparation(nation_a, nation_b, action)
		DiplomacyAI.Action.CANCEL_WAR_PREPARATION:
			if state.nations[nation_a].war_preparation_target_nation >= 0:
				_clear_war_preparation(nation_a)
				# 盖取消冷却戳：杜绝取消后隔一个决策周期立即重开备战的横跳（仅显式取消路径盖戳，
				# 宣战成功清空备战不盖，成功不该被冷却惩罚）。
				state.nations[nation_a].war_preparation_cancelled_day = state.day
				changed = true
		DiplomacyAI.Action.RETARGET_WAR_PREPARATION:
			var nation := state.nations[nation_a]
			var objective_city := int(action.get("objective_city", -1))
			if (
				nation.war_preparation_target_nation == nation_b
				and objective_city >= 0
				and objective_city < state.cities.size()
				and state.cities[objective_city].owner_nation == nation_b
				and not DiplomacyAI.staging_cities_for_objective(
					state, nation_a, objective_city
				).is_empty()
			):
				nation.war_preparation_objective_city = objective_city
				nation.war_preparation_reason = str(
					action.get("objective_reason", "")
				)
				# 只清目标相关的军事 Assignment；战略备战开始日、资源
				# 宽限时钟和既有动员成果全部保留。
				_clear_campaign_preparation_plan(nation_a)
				changed = true
		DiplomacyAI.Action.ENFEOFF:
			if not enfeoff_enabled:
				return false
			var region_cities: Array[int] = []
			for city_value in action.get("region_cities", []):
				region_cities.append(int(city_value))
			var new_subject := state.enfeoff(nation_a, region_cities)
			if new_subject >= 0:
				changed = true
				action["subject_nation"] = new_subject
				# 新藩王出现，边境与防区拓扑改变：强制下一天全体重算。
				_ai_last_decision_day = -1
		DiplomacyAI.Action.CENTRALIZE:
			# 削藩：藩王反抗则开内战（占首都通吃留待领土结算），否则和平撤藩直辖。
			if state.overlord_of(nation_b) == nation_a and not state.is_in_civil_war(nation_b):
				if bool(action.get("resist", false)):
					_capture_war_gold_income_snapshots([
						nation_a, nation_b
					] as Array[int], frozen_gold_flows)
					changed = state.start_civil_war(nation_b)
				else:
					changed = state.revoke_vassal(nation_b)
				if changed:
					# 关系/领土拓扑改变：强制下一天全体重算。
					_ai_last_decision_day = -1
	if not changed:
		return false
	var event := {
		"day": state.day,
		"action": kind,
		"nation_a": nation_a,
		"nation_b": nation_b,
		"reason": reason,
	}
	if action.has("objective_city"):
		event["objective_city"] = int(action["objective_city"])
		event["objective_reason"] = str(action.get("objective_reason", ""))
	if action.has("mobilization_armies"):
		event["mobilization_armies"] = int(action["mobilization_armies"])
	if action.has("subject_nation"):
		event["subject_nation"] = int(action["subject_nation"])
	if action.has("surrendering_nation"):
		event["surrendering_nation"] = int(action["surrendering_nation"])
	if kind == DiplomacyAI.Action.MAKE_PEACE:
		event["war_outcome_a"] = war_outcome_a
		event["war_outcome_b"] = war_outcome_b
		event["territories_transferred"] = territories_transferred
		event["occupations_restored"] = occupations_restored
	if kind in [
		DiplomacyAI.Action.MAKE_PEACE,
		DiplomacyAI.Action.DECLARE_WAR,
	]:
		event["bloc_a"] = action_bloc_a.duplicate()
		event["bloc_b"] = action_bloc_b.duplicate()
	state.diplomatic_history.append(event)
	for member_a in action_bloc_a:
		_record_diplomatic_action(
			member_a,
			kind,
			action_bloc_b[0],
			reason
		)
	for member_b in action_bloc_b:
		_record_diplomatic_action(
			member_b,
			kind,
			action_bloc_a[0],
			reason
		)
	return true


func _queue_or_start_war_mobilization(
	nation_id: int,
	requested_armies: int,
	evaluation_cache: Dictionary = {}
) -> void:
	if _defer_declaration_launches:
		_pending_war_mobilizations.append({
			"nation_id": nation_id,
			"requested_armies": requested_armies,
		})
	else:
		_start_war_mobilization(
			nation_id, requested_armies, evaluation_cache
		)


func _set_coalition_war(
	attackers: Array[int],
	defenders: Array[int],
	frozen_gold_flows: Array[Dictionary] = []
) -> bool:
	var coalition_war_part_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_capture_war_gold_income_snapshots(
		attackers + defenders, frozen_gold_flows
	)
	_record_tick_profile_stage(
		"diplomacy_set_war_snapshot", coalition_war_part_started
	)
	coalition_war_part_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var changed := false
	for attacker in attackers:
		for defender in defenders:
			if (
				attacker == defender
				or state.is_allied(attacker, defender)
			):
				continue
			if state.is_enemy(attacker, defender):
				continue
			changed = (
				state.set_diplomatic_relation(
					attacker,
					defender,
					GameState.DiplomaticRelation.WAR
				)
				or changed
			)
	_record_tick_profile_stage(
		"diplomacy_set_war_relations", coalition_war_part_started
	)
	return changed


func _set_coalition_war_objective(
	attackers: Array[int],
	defenders: Array[int],
	initiator: int,
	objective_city: int,
	reason: String
) -> void:
	if (
		objective_city < 0
		or objective_city >= state.cities.size()
		or not defenders.has(
			state.cities[objective_city].owner_nation
		)
	):
		return
	for attacker in attackers:
		for defender in defenders:
			if not state.is_enemy(attacker, defender):
				continue
			state.set_war_objective(
				attacker,
				defender,
				objective_city,
				(
					reason
					if attacker == initiator
					else "响应盟国共同战争目标：%s" % reason
				)
			)


func _synchronize_alliance_wars(
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary = {},
	frozen_gold_flows: Array[Dictionary] = []
) -> void:
	var bloc := state.alliance_bloc(nation_a)
	if not bloc.has(nation_b):
		return
	var enemy_set := {}
	var shared_objective: Dictionary = {}
	for member in bloc:
		for enemy_id in state.wars_of(member):
			if bloc.has(enemy_id):
				continue
			for enemy_member in state.alliance_bloc(enemy_id):
				if not bloc.has(enemy_member):
					enemy_set[enemy_member] = true
			var objective := state.war_objective(member, enemy_id)
			if shared_objective.is_empty() and not objective.is_empty():
				shared_objective = objective
	var enemies: Array[int] = []
	enemies.assign(enemy_set.keys())
	enemies.sort()
	if enemies.is_empty():
		return
	var joined_war := _set_coalition_war(
		bloc, enemies, frozen_gold_flows
	)
	if not joined_war:
		return
	_prepare_diplomacy_mobilization_cache(evaluation_cache)
	var objective_city := int(shared_objective.get("city_id", -1))
	if objective_city >= 0:
		_set_coalition_war_objective(
			bloc,
			enemies,
			int(shared_objective.get("attacker", bloc[0])),
			objective_city,
			str(shared_objective.get(
				"reason",
				"联盟共同战争目标"
			))
		)
	for member in bloc:
		if state.nations[member].war_preparation_target_nation >= 0:
			_clear_war_preparation(member)
		_queue_or_start_war_mobilization(
			member, -1, evaluation_cache
		)
	_ai_last_decision_day = -1


func _normalize_alliance_wars() -> void:
	var processed := {}
	for nation in state.nations:
		if not nation.alive or processed.has(nation.id):
			continue
		# 单国集团没有需要同步的战争。先做 O(N) 邻接检查，避免为每个
		# 无盟友国家分别运行一次 O(N²) 的冲突感知 alliance_bloc。
		if state.allies_of(nation.id).is_empty():
			processed[nation.id] = true
			continue
		var bloc := state.alliance_bloc(nation.id)
		for member in bloc:
			processed[member] = true
		if bloc.size() < 2:
			continue
		_synchronize_alliance_wars(bloc[0], bloc[1])


func _make_coalition_peace(
	nation_a: int,
	nation_b: int
) -> Dictionary:
	var plan := _plan_coalition_peace(nation_a, nation_b)
	if not bool(plan.get("ok", false)):
		return {
			"changed": false,
			"error": str(plan.get("error", "无法规划集团和平。")),
		}
	if not bool(plan.get("changed", false)):
		return {"changed": false}
	return _commit_coalition_peace_plan(plan)


## 只读旧快照；保存两类 revision，并把全部和平效果合成到共享 draft。
func _plan_coalition_peace(
	nation_a: int,
	nation_b: int
) -> Dictionary:
	if state == null:
		return {"ok": false, "changed": false, "error": "游戏状态不存在。"}
	var expected_ownership_revision := state.ownership_revision
	var expected_diplomacy_revision := state.diplomacy_revision
	var bloc_a := state.alliance_bloc(nation_a, false)
	var bloc_b := state.alliance_bloc(nation_b, false)
	if bloc_a.is_empty() or bloc_b.is_empty():
		return {"ok": true, "changed": false}
	var war_outcome_a := DiplomacyAI.war_situation_score(
		state,
		nation_a,
		nation_b
	)
	var war_outcome_b := DiplomacyAI.war_situation_score(
		state,
		nation_b,
		nation_a
	)
	var settled_war_pairs := {}
	var settled_pairs: Array[Vector2i] = []
	var diplomatic_operations: Array[Dictionary] = []
	for member_a in bloc_a:
		for member_b in bloc_b:
			if not state.is_enemy(member_a, member_b):
				continue
			# 地方叛军与母国至少交战一年；集团其他战争仍可各自议和，
			# 但不得把这条受保护的战争边顺带结算掉。
			if state.regional_rebellion_peace_locked(member_a, member_b):
				continue
			# 宗藩对的关系态由宗藩机制独占管理，普通联盟议和不得触碰（与退盟/议和
			# 收集器层的 is_suzerainty_pair 门控同源）。内战宗藩对（civil_war=true →
			# 关系 WAR）尤其危险：宗主与内战藩王可能分属对立集团，bloc 展开会把这对
			# WAR 扫进来，若在此停战会抹掉 WAR 却留下 civil_war 标记，破坏宗藩不变量
			# 第2条。内战只能由占首都通吃终结，故整对跳过（关系与双边战斗都不动）。
			if (
				state.is_suzerainty_pair(member_a, member_b)
				and (
					state.is_in_civil_war(member_a)
					or state.is_in_civil_war(member_b)
				)
			):
				continue
			settled_war_pairs[
				GameState.edge_key(member_a, member_b)
			] = true
			settled_pairs.append(Vector2i(member_a, member_b))
			diplomatic_operations.append({
				"nation_a": member_a,
				"nation_b": member_b,
				"relation": GameState.DiplomaticRelation.NEUTRAL,
				"truce_days": GameState.DEFAULT_TRUCE_DAYS,
			})
	if diplomatic_operations.is_empty():
		return {"ok": true, "changed": false}

	# 关系提交后已无法反推 parent/rebel 原战争边，故同样冻结于议和前。
	var rebellion_peace_pairs: Array[Vector2i] = []
	var rebel_ids: Array[int] = []
	for rebel_value in state.rebellions:
		var rebel_id := int(rebel_value)
		var rebellion: Dictionary = state.rebellions[rebel_id]
		if bool(rebellion.get("active", false)):
			rebel_ids.append(rebel_id)
	rebel_ids.sort()
	for rebel_id in rebel_ids:
		var rebellion: Dictionary = state.rebellions[rebel_id]
		var parent_id := int(rebellion.get("parent_id", -1))
		if (
			parent_id >= 0
			and parent_id < state.nations.size()
			and rebel_id >= 0
			and rebel_id < state.nations.size()
			and settled_war_pairs.has(
				GameState.edge_key(parent_id, rebel_id)
			)
		):
			rebellion_peace_pairs.append(Vector2i(parent_id, rebel_id))

	var owners: Array[int] = []
	var legal: Array[int] = []
	var sponsors: Array[int] = []
	owners.resize(state.cities.size())
	legal.resize(state.cities.size())
	sponsors.resize(state.cities.size())
	for city in state.cities:
		owners[city.id] = city.owner_nation
		legal[city.id] = state.recognized_owner_of(city.id)
		sponsors[city.id] = city.occupation_sponsor_nation
	var draft := {
		"owners": owners,
		"legal": legal,
		"sponsors": sponsors,
		"operation_by_city": {},
		"proposed_suzerainty": state.suzerainty.duplicate(true),
	}
	_plan_disconnected_coalition_occupation_restoration(
		draft, bloc_a, bloc_b, settled_war_pairs
	)
	_plan_coalition_occupation_recognition(
		draft, bloc_a, bloc_b, settled_war_pairs
	)
	var rebellion_plan := _plan_coalition_rebellion_peace(
		draft, rebellion_peace_pairs
	)
	if not bool(rebellion_plan.get("ok", false)):
		return {
			"ok": false,
			"changed": false,
			"error": str(rebellion_plan.get(
				"error", "无法规划地方叛乱和平。"
			)),
		}
	_plan_peaceful_occupation_normalization(
		draft, settled_war_pairs
	)
	var territories_transferred := _coalition_plan_operation_count(
		draft, "coalition_territory_recognized"
	)
	var occupations_restored := _coalition_plan_operation_count(
		draft, "peace_occupation_restored"
	)
	var occupations_normalized := _coalition_plan_operation_count(
		draft, "peaceful_occupation_normalized"
	)
	# annex planner 可能替换 map；最终只从 operation_by_city 重建数组。
	var operation_ids: Array[int] = []
	var operation_by_city: Dictionary = draft["operation_by_city"]
	for city_value in operation_by_city:
		operation_ids.append(int(city_value))
	operation_ids.sort()
	var operations: Array[Dictionary] = []
	for city_id in operation_ids:
		operations.append(
			(operation_by_city[city_id] as Dictionary).duplicate(true)
		)
	return {
		"ok": true,
		"changed": true,
		"war_outcome_a": war_outcome_a,
		"war_outcome_b": war_outcome_b,
		"territories_transferred": territories_transferred,
		"occupations_restored": occupations_restored,
		"occupations_normalized": occupations_normalized,
		"bloc_a": bloc_a,
		"bloc_b": bloc_b,
		"settled_pairs": settled_pairs,
		"operations": operations,
		"diplomatic_operations": diplomatic_operations,
		"proposed_suzerainty": (
			(draft["proposed_suzerainty"] as Dictionary).duplicate(true)
		),
		"pre_suzerainty": state.suzerainty.duplicate(true),
		"rebellion_updates": rebellion_plan.get("updates", []),
		"annexations": rebellion_plan.get("annexations", []),
		"expected_ownership_revision": expected_ownership_revision,
		"expected_diplomacy_revision": expected_diplomacy_revision,
	}


## 唯一提交点。事务拒绝时不执行战斗、军队、叛乱、目标、动员或财政收尾；
## 成功后剩余动作只消费已提交结果，不再含可失败的状态转换。
func _commit_coalition_peace_plan(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)) or not bool(
		plan.get("changed", false)
	):
		return {
			"changed": false,
			"error": str(plan.get("error", "集团和平计划无效。")),
		}
	var operations: Array[Dictionary] = []
	for operation_value in plan.get("operations", []):
		operations.append(operation_value as Dictionary)
	var diplomatic_operations: Array[Dictionary] = []
	for operation_value in plan.get("diplomatic_operations", []):
		diplomatic_operations.append(operation_value as Dictionary)
	var transaction := state.apply_territory_transaction(
		operations,
		{},
		int(plan.get("expected_ownership_revision", -1)),
		plan.get("proposed_suzerainty", null),
		diplomatic_operations,
		int(plan.get("expected_diplomacy_revision", -1))
	)
	if not bool(transaction.get("ok", false)):
		return {
			"changed": false,
			"error": str(transaction.get("error", "集团和平提交失败。")),
		}
	if not bool(transaction.get("changed", false)):
		return {"changed": false}

	for annexation_value in plan.get("annexations", []):
		var annexation := Vector2i(annexation_value)
		state.finalize_annexation_after_territory_commit(
			annexation.x, annexation.y
		)
	for update_value in plan.get("rebellion_updates", []):
		var update: Dictionary = update_value
		var rebel_id := int(update.get("rebel_id", -1))
		if rebel_id < 0 or not state.rebellions.has(rebel_id):
			continue
		var record: Dictionary = state.rebellions[rebel_id]
		record["active"] = false
		record["recognized"] = bool(update.get("recognized", false))
		state.rebellions[rebel_id] = record
		if not bool(update.get("suppressed", false)):
			continue
		var parent_id := int(update.get("parent_id", -1))
		for city_value in update.get("core_city_ids", []):
			var city_id := int(city_value)
			if city_id < 0 or city_id >= state.cities.size():
				continue
			var city := state.cities[city_id]
			city.loyalty_target_nation = parent_id
			city.loyalty = 45.0
			city.unrest = 55.0
			city.rebellion_progress = 0
			city.rebellion_cooldown_until_day = (
				state.day + RebellionSystem.REBELLION_COOLDOWN_DAYS
			)

	# 事务自动清理死亡宗主时，存活而独立的旧藩王需要同步命名身份。
	var pre_suzerainty: Dictionary = plan.get("pre_suzerainty", {})
	for subject_value in pre_suzerainty:
		var subject_id := int(subject_value)
		if (
			subject_id >= 0
			and subject_id < state.nations.size()
			and state.nations[subject_id].alive
			and not state.suzerainty.has(subject_id)
		):
			WorldNaming.promote_vassal_to_sovereign(state, subject_id)

	_synchronize_war_gold_income_snapshots()
	var bloc_a: Array[int] = []
	bloc_a.assign(plan.get("bloc_a", []))
	var bloc_b: Array[int] = []
	bloc_b.assign(plan.get("bloc_b", []))
	_reconcile_battles_after_coalition_peace(bloc_a, bloc_b)
	var changed_city_ids: Array[int] = []
	for city_value in transaction.get("changed_city_ids", []):
		changed_city_ids.append(int(city_value))
	if not changed_city_ids.is_empty():
		_repatriate_after_territory_settlement(changed_city_ids)
	for pair_value in plan.get("settled_pairs", []):
		var pair := Vector2i(pair_value)
		state.clear_war_objective(pair.x, pair.y)
	for member in bloc_a + bloc_b:
		_clear_finished_war_mobilization(member)
	_ai_last_decision_day = -1
	return {
		"changed": true,
		"war_outcome_a": float(plan.get("war_outcome_a", 0.0)),
		"war_outcome_b": float(plan.get("war_outcome_b", 0.0)),
		"territories_transferred": int(plan.get(
			"territories_transferred", 0
		)),
		"occupations_restored": int(plan.get(
			"occupations_restored", 0
		)),
		"occupations_normalized": int(plan.get(
			"occupations_normalized", 0
		)),
		"bloc_a": bloc_a,
		"bloc_b": bloc_b,
	}


func _append_coalition_territory_operation(
	draft: Dictionary,
	city_id: int,
	controller_id: int,
	legal_owner_id: int,
	sponsor_id: int,
	reason: String,
	stock_policy: int
) -> void:
	var owners: Array = draft["owners"]
	var legal: Array = draft["legal"]
	var sponsors: Array = draft["sponsors"]
	var operation_by_city: Dictionary = draft["operation_by_city"]
	owners[city_id] = controller_id
	legal[city_id] = legal_owner_id
	sponsors[city_id] = sponsor_id
	operation_by_city[city_id] = {
		"city_id": city_id,
		"controller_id": controller_id,
		"legal_owner_id": legal_owner_id,
		"sponsor_id": sponsor_id,
		"reset_political_target": true,
		"reason": reason,
		"stock_policy": stock_policy,
	}


func _coalition_plan_operation_count(
	draft: Dictionary,
	reason: String
) -> int:
	var count := 0
	var operation_by_city: Dictionary = draft["operation_by_city"]
	for city_value in operation_by_city:
		var operation: Dictionary = operation_by_city[city_value]
		if str(operation.get("reason", "")) == reason:
			count += 1
	return count


func _plan_disconnected_coalition_occupation_restoration(
	draft: Dictionary,
	bloc_a: Array[int],
	bloc_b: Array[int],
	settled_war_pairs: Dictionary
) -> Array[int]:
	var side_a := {}
	var side_b := {}
	for nation_id in bloc_a:
		side_a[nation_id] = true
	for nation_id in bloc_b:
		side_b[nation_id] = true
	var connected_by_nation := {}
	for nation_id in bloc_a + bloc_b:
		if _coalition_plan_nation_has_city(draft, nation_id):
			connected_by_nation[nation_id] = (
				_planned_capital_connected_territory(nation_id, draft)
			)
	var restored: Array[int] = []
	var owners: Array = draft["owners"]
	var legal: Array = draft["legal"]
	var sponsors: Array = draft["sponsors"]
	for controller in bloc_a + bloc_b:
		if not connected_by_nation.has(controller):
			continue
		var current_side: Dictionary = side_a if side_a.has(controller) else side_b
		var opposing_side: Dictionary = side_b if side_a.has(controller) else side_a
		var connected: Dictionary = connected_by_nation[controller]
		for city_id in range(state.cities.size()):
			var recognized_owner := int(legal[city_id])
			if (
				int(owners[city_id]) != controller
				or recognized_owner == controller
				or not opposing_side.has(recognized_owner)
				or connected.has(city_id)
			):
				continue
			var sponsor := int(sponsors[city_id])
			var valid_sponsor := sponsor >= 0 and sponsor < state.nations.size()
			if valid_sponsor:
				if not current_side.has(sponsor):
					continue
				if not settled_war_pairs.has(
					GameState.edge_key(sponsor, recognized_owner)
				):
					continue
			_append_coalition_territory_operation(
				draft, city_id, recognized_owner, recognized_owner, -1,
				"peace_occupation_restored",
				GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
			)
			restored.append(city_id)
	return restored


func _plan_coalition_occupation_recognition(
	draft: Dictionary,
	bloc_a: Array[int],
	bloc_b: Array[int],
	settled_war_pairs: Dictionary
) -> Array[int]:
	var side_a := {}
	var side_b := {}
	for nation_id in bloc_a:
		side_a[nation_id] = true
	for nation_id in bloc_b:
		side_b[nation_id] = true
	var transferred: Array[int] = []
	var owners: Array = draft["owners"]
	var legal: Array = draft["legal"]
	var sponsors: Array = draft["sponsors"]
	for city_id in range(state.cities.size()):
		var controller := int(owners[city_id])
		var recognized_owner := int(legal[city_id])
		if controller == recognized_owner:
			continue
		var sponsor := int(sponsors[city_id])
		if (
			sponsor >= 0
			and sponsor < state.nations.size()
			and not settled_war_pairs.has(
				GameState.edge_key(sponsor, recognized_owner)
			)
		):
			continue
		var occupying_side := -1
		if side_a.has(sponsor):
			occupying_side = 0
		elif side_b.has(sponsor):
			occupying_side = 1
		elif side_a.has(controller):
			occupying_side = 0
		elif side_b.has(controller):
			occupying_side = 1
		var recognized_side := -1
		if side_a.has(recognized_owner):
			recognized_side = 0
		elif side_b.has(recognized_owner):
			recognized_side = 1
		if (
			occupying_side < 0
			or recognized_side < 0
			or occupying_side == recognized_side
		):
			continue
		# 占领控制权已经在军队跨入敌境时按实际出发领土冻结。和平
		# 只确认当前 controller 的法理，不再把藩王成果二次上收到宗主。
		var recipient := (
			controller
			if _coalition_plan_nation_has_city(draft, controller)
			else _planned_external_territory_recipient(controller, draft)
		)
		if recipient < 0:
			continue
		_append_coalition_territory_operation(
			draft, city_id, recipient, recipient, -1,
			"coalition_territory_recognized",
			GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
		)
		transferred.append(city_id)
	return transferred


func _plan_coalition_rebellion_peace(
	draft: Dictionary,
	rebellion_peace_pairs: Array[Vector2i]
) -> Dictionary:
	var updates: Array[Dictionary] = []
	var annexations: Array[Vector2i] = []
	var frozen_owners: Array = (draft["owners"] as Array).duplicate()
	var outcomes := {}
	var suppressed_parents := {}
	# 所有结果必须读取同一份 restore/recognize 后快照；前一场叛乱的
	# recognize/annex 计划不得改变后一场叛乱是承认还是镇压的判定。
	for rebellion_pair in rebellion_peace_pairs:
		var parent_id := rebellion_pair.x
		var rebel_id := rebellion_pair.y
		if not state.rebellions.has(rebel_id):
			continue
		var record: Dictionary = state.rebellions[rebel_id]
		var core_city_ids: Array[int] = []
		var controls_core := false
		for city_value in record.get("core_city_ids", []):
			var city_id := int(city_value)
			core_city_ids.append(city_id)
			if (
				city_id >= 0
				and city_id < state.cities.size()
				and int(frozen_owners[city_id]) == rebel_id
			):
				controls_core = true
		outcomes[rebel_id] = {
			"parent_id": parent_id,
			"core_city_ids": core_city_ids,
			"recognized": controls_core,
		}
		if not controls_core:
			suppressed_parents[rebel_id] = parent_id

	# 承认项先基于冻结分类落法理；这一步仍不改变任何后续 outcome。
	var outcome_ids: Array[int] = []
	for rebel_value in outcomes:
		outcome_ids.append(int(rebel_value))
	outcome_ids.sort()
	for rebel_id in outcome_ids:
		var outcome: Dictionary = outcomes[rebel_id]
		if not bool(outcome["recognized"]):
			continue
		var core_city_ids: Array[int] = []
		core_city_ids.assign(outcome["core_city_ids"])
		for city_id in core_city_ids:
			if (
				city_id < 0
				or city_id >= state.cities.size()
				or int(frozen_owners[city_id]) != rebel_id
			):
				continue
			_append_coalition_territory_operation(
				draft, city_id, rebel_id, rebel_id, -1,
				"regional_rebellion_recognized",
				GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL
			)
		updates.append({
			"rebel_id": rebel_id,
			"parent_id": int(outcome["parent_id"]),
			"recognized": true,
			"suppressed": false,
			"core_city_ids": core_city_ids,
		})

	# 镇压链统一解析到最终仍存活的 absorber。P<-R1、R1<-R2 必须规划为
	# P<-R1 与 P<-R2；否则先吞 R1 再让 R1 吞 R2 会把中间叛军复活。
	for rebel_id in outcome_ids:
		var outcome: Dictionary = outcomes[rebel_id]
		if bool(outcome["recognized"]):
			continue
		var final_absorber := int(outcome["parent_id"])
		var seen := {rebel_id: true}
		var guard := 0
		while suppressed_parents.has(final_absorber):
			if seen.has(final_absorber) or guard > state.nations.size():
				return {"ok": false, "error": "地方叛乱镇压链包含环。"}
			seen[final_absorber] = true
			final_absorber = int(suppressed_parents[final_absorber])
			guard += 1
		if (
			final_absorber < 0
			or final_absorber >= state.nations.size()
			or final_absorber == rebel_id
			or not _coalition_plan_nation_has_city(
				draft, final_absorber
			)
		):
			return {"ok": false, "error": "地方叛乱镇压链没有有效最终接收者。"}
		if not state.append_annexation_to_territory_plan(
			draft, final_absorber, rebel_id
		):
			return {
				"ok": false,
				"error": "无法把地方叛乱镇压合并进和平事务。",
			}
		var core_city_ids: Array[int] = []
		core_city_ids.assign(outcome["core_city_ids"])
		annexations.append(Vector2i(final_absorber, rebel_id))
		updates.append({
			"rebel_id": rebel_id,
			"parent_id": final_absorber,
			"recognized": false,
			"suppressed": true,
			"core_city_ids": core_city_ids,
		})
	return {
		"ok": true,
		"updates": updates,
		"annexations": annexations,
	}


func _plan_peaceful_occupation_normalization(
	draft: Dictionary,
	settled_war_pairs: Dictionary
) -> Array[int]:
	var normalized: Array[int] = []
	var owners: Array = draft["owners"]
	var legal: Array = draft["legal"]
	var sponsors: Array = draft["sponsors"]
	for city_id in range(state.cities.size()):
		var controller := int(owners[city_id])
		var legal_owner := int(legal[city_id])
		if controller == legal_owner:
			continue
		var sponsor := int(sponsors[city_id])
		var sponsor_at_war := (
			sponsor >= 0
			and sponsor < state.nations.size()
			and _planned_coalition_relation(
				sponsor, legal_owner, draft, settled_war_pairs
			) == GameState.DiplomaticRelation.WAR
		)
		if sponsor_at_war:
			continue
		_append_coalition_territory_operation(
			draft, city_id, legal_owner, legal_owner, -1,
			"peaceful_occupation_normalized",
			GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
		)
		normalized.append(city_id)
	return normalized


func _coalition_plan_nation_has_city(
	draft: Dictionary,
	nation_id: int
) -> bool:
	for owner_value in draft["owners"]:
		if int(owner_value) == nation_id:
			return true
	return false


func _planned_suzerainty_root(
	nation_id: int,
	proposed_suzerainty: Dictionary
) -> int:
	var current := nation_id
	var guard := 0
	while proposed_suzerainty.has(current) and guard <= state.nations.size():
		current = int(
			(proposed_suzerainty[current] as Dictionary).get(
				"overlord_id", current
			)
		)
		guard += 1
	return current


func _planned_external_territory_recipient(
	nation_id: int,
	draft: Dictionary
) -> int:
	if nation_id < 0 or nation_id >= state.nations.size():
		return -1
	var proposed_suzerainty: Dictionary = draft["proposed_suzerainty"]
	var current := nation_id
	var guard := 0
	while proposed_suzerainty.has(current) and guard <= state.nations.size():
		var record: Dictionary = proposed_suzerainty[current]
		if bool(record.get("civil_war", false)):
			break
		var overlord_id := int(record.get("overlord_id", -1))
		if (
			overlord_id < 0
			or overlord_id >= state.nations.size()
			or not _coalition_plan_nation_has_city(draft, overlord_id)
		):
			break
		current = overlord_id
		guard += 1
	return current


func _planned_coalition_relation(
	nation_a: int,
	nation_b: int,
	draft: Dictionary,
	settled_war_pairs: Dictionary
) -> int:
	if nation_a == nation_b:
		return GameState.DiplomaticRelation.ALLIED
	if settled_war_pairs.has(GameState.edge_key(nation_a, nation_b)):
		return GameState.DiplomaticRelation.NEUTRAL
	var proposed_suzerainty: Dictionary = draft["proposed_suzerainty"]
	for subject_id in [nation_a, nation_b]:
		if not proposed_suzerainty.has(subject_id):
			continue
		var record: Dictionary = proposed_suzerainty[subject_id]
		var other_id := nation_b if subject_id == nation_a else nation_a
		if int(record.get("overlord_id", -1)) == other_id:
			return (
				GameState.DiplomaticRelation.WAR
				if bool(record.get("civil_war", false))
				else GameState.DiplomaticRelation.ALLIED
			)
	return state.relation_between(nation_a, nation_b)


func _planned_capital_connected_territory(
	nation_id: int,
	draft: Dictionary
) -> Dictionary:
	var capital_id := state.nations[nation_id].capital_city_id
	var owners: Array = draft["owners"]
	if (
		capital_id < 0
		or capital_id >= state.cities.size()
		or int(owners[capital_id]) != nation_id
	):
		return {}
	var proposed_suzerainty: Dictionary = draft["proposed_suzerainty"]
	var root := _planned_suzerainty_root(nation_id, proposed_suzerainty)
	var connected := {capital_id: true}
	var queue: Array[int] = [capital_id]
	var cursor := 0
	while cursor < queue.size():
		var city_id := queue[cursor]
		cursor += 1
		for neighbor in state.neighbors(city_id):
			var edge := state.edge_of(city_id, neighbor)
			var neighbor_owner := int(owners[neighbor])
			if (
				connected.has(neighbor)
				or edge == null
				or edge.max_manpower <= 0
				or _planned_suzerainty_root(
					neighbor_owner, proposed_suzerainty
				) != root
				or _planned_coalition_relation(
					nation_id, neighbor_owner, draft, {}
				) != GameState.DiplomaticRelation.ALLIED
			):
				continue
			connected[neighbor] = true
			queue.append(neighbor)
	return connected


func _restore_disconnected_coalition_occupations(
	bloc_a: Array[int],
	bloc_b: Array[int],
	settled_war_pairs: Dictionary = {}
) -> Array[int]:
	var side_a := {}
	var side_b := {}
	for nation_id in bloc_a:
		side_a[nation_id] = true
	for nation_id in bloc_b:
		side_b[nation_id] = true
	var connected_by_nation := {}
	for nation_id in bloc_a + bloc_b:
		if not state.land_cities_of(nation_id).is_empty():
			connected_by_nation[nation_id] = (
				_capital_connected_territory(nation_id)
			)
	# 合法飞地不会仅因议和而割让。这里只撤销无法连接控制者首都、
	# 法理属于对方集团的临时占领；有效 sponsor 还必须来自控制方集团。
	var restorations: Array[Dictionary] = []
	for controller in bloc_a + bloc_b:
		if not connected_by_nation.has(controller):
			continue
		var current_side: Dictionary = side_a if side_a.has(controller) else side_b
		var opposing_side: Dictionary = side_b if side_a.has(controller) else side_a
		var connected: Dictionary = connected_by_nation[controller]
		for city in state.cities:
			var recognized_owner := state.recognized_owner_of(city.id)
			if (
				city.owner_nation != controller
				or recognized_owner == controller
				or not opposing_side.has(recognized_owner)
				or connected.has(city.id)
			):
				continue
			var sponsor := city.occupation_sponsor_nation
			var valid_sponsor := (
				sponsor >= 0 and sponsor < state.nations.size()
			)
			# 有效声明只随 sponsor 与法理方的这场战争结算；controller
			# 与法理方的另一场战争不能串案。无效声明视为脏状态并恢复法理。
			if valid_sponsor:
				if not current_side.has(sponsor):
					continue
				if (
					not settled_war_pairs.has(
						GameState.edge_key(sponsor, recognized_owner)
					)
				):
					continue
			restorations.append({
				"city_id": city.id,
				"controller_id": recognized_owner,
				"legal_owner_id": recognized_owner,
				"sponsor_id": -1,
				"reset_political_target": true,
				"reason": "peace_occupation_restored",
				"stock_policy": (
					GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
				),
			})
	if restorations.is_empty():
		return [] as Array[int]
	var restore_result := state.apply_territory_transaction(
		restorations
	)
	if not bool(restore_result.get("ok", false)):
		return [] as Array[int]
	var restored: Array[int] = []
	for city_value in restore_result.get(
		"changed_city_ids", []
	):
		restored.append(int(city_value))
	if restored.is_empty():
		return restored
	_ai_last_decision_day = -1
	_repatriate_after_territory_settlement(restored)
	return restored

## 返回 nation_id 所属和平宗藩体系内，从该国首都沿正容量道路可达的实控区。
## 仅用于集团议和识别断联临时占领；普通盟国不提供领土连续性。
func _capital_connected_territory(nation_id: int) -> Dictionary:
	var capital_id := state.nations[nation_id].capital_city_id
	if (
		capital_id < 0
		or capital_id >= state.cities.size()
		or state.cities[capital_id].owner_nation != nation_id
	):
		return {}
	var suzerainty_root := state.suzerainty_root(nation_id)
	var connected := {capital_id: true}
	var queue: Array[int] = [capital_id]
	var cursor := 0
	while cursor < queue.size():
		var city_id := queue[cursor]
		cursor += 1
		for neighbor in state.neighbors(city_id):
			var edge := state.edge_of(city_id, neighbor)
			var neighbor_owner := state.cities[
				neighbor
			].owner_nation
			var same_peaceful_suzerainty := (
				neighbor_owner >= 0
				and state.suzerainty_root(neighbor_owner)
					== suzerainty_root
				and state.has_military_access(
					nation_id,
					neighbor_owner
				)
			)
			if (
				connected.has(neighbor)
				or edge == null
				or edge.max_manpower <= 0
				or not same_peaceful_suzerainty
			):
				continue
			connected[neighbor] = true
			queue.append(neighbor)
	return connected


func _repatriate_after_territory_settlement(
	settled_cities: Array[int]
) -> void:
	var settled_set := {}
	for city_id in settled_cities:
		settled_set[city_id] = true
	for army in state.armies:
		if army.size <= 0:
			continue
		var affected := false
		for city_id in settled_cities:
			if (
				not state.has_military_access(
					army.owner_nation,
					state.cities[city_id].owner_nation
				)
				and (
					army.is_at_city_node(city_id)
					or army.move_from == city_id
					or army.move_to == city_id
					or army.path.has(city_id)
				)
			):
				affected = true
				break
		if not affected:
			continue
		army.path.clear()
		army.ai_target_city = -1
		army.ai_order_until_day = state.day
		var repatriated_manpower := army.size
		if army.on_edge and army.move_to != -1:
			army.diplomatic_repatriation = true
			_retreat(army)
		elif settled_set.has(army.location_city):
			_start_diplomatic_repatriation(
				army,
				army.location_city
			)
		else:
			_settle_idle(army, army.location_city)
		if army.size <= 0:
			state.nations[
				army.owner_nation
			].manpower_pool += repatriated_manpower
			army.ai_action = ActionCandidate.Kind.DISBAND_ARMY
			army.ai_order_reason = "和平领土结算，无陆路可撤时按协议复员"
	_purge_dead_armies()


func _start_war_preparation(
	nation_id: int,
	target_id: int,
	action: Dictionary
) -> bool:
	var objective_city := int(action.get("objective_city", -1))
	if (
		objective_city < 0
		or objective_city >= state.cities.size()
		or state.cities[objective_city].owner_nation != target_id
	):
		return false
	var nation := state.nations[nation_id]
	nation.war_preparation_target_nation = target_id
	nation.war_preparation_objective_city = objective_city
	nation.war_preparation_started_day = state.day
	nation.war_preparation_reason = str(action.get("objective_reason", ""))
	nation.war_preparation_unready_since_day = -1
	_clear_campaign_preparation_plan(nation_id)
	var requested_armies := int(action.get("mobilization_armies", 0))
	var current_troops := DiplomacyAI._troop_count(state, nation_id)
	nation.war_mobilization_target_troops = maxi(
		nation.war_mobilization_target_troops,
		current_troops + requested_armies * NEW_ARMY_SIZE
	)
	nation.war_mobilization_until_day = maxi(
		nation.war_mobilization_until_day,
		state.day + DiplomacyAI.WAR_PREPARATION_MAX_DAYS
	)
	nation.war_mobilization_reason = (
		"战前动员%d军，向城市%d方向集结"
		% [requested_armies, objective_city]
	)
	return true


func _clear_war_preparation(
	nation_id: int,
	clear_mobilization: bool = true
) -> void:
	var nation := state.nations[nation_id]
	nation.war_preparation_target_nation = -1
	nation.war_preparation_objective_city = -1
	nation.war_preparation_started_day = -1
	nation.war_preparation_reason = ""
	nation.war_preparation_unready_since_day = -1
	if clear_mobilization:
		_clear_campaign_preparation_plan(nation_id)
	if clear_mobilization and state.wars_of(nation_id).is_empty():
		nation.war_mobilization_target_troops = 0
		nation.war_mobilization_until_day = -1
		nation.war_mobilization_reason = ""


## 同一外交 action 内只创建一份评估上下文。宣战关系已原子提交后清空
## preflight 派生，保证联盟成员共享、且不把缓存带到下一个 action。贸易报告
## 保持惰性：有月度快照时无需因宣战重建整张路线图；无快照的外部调用仍由
## DiplomacyAI._trade_report 按当前战后状态构建一次，结果与旧路径相同。
func _prepare_diplomacy_mobilization_cache(
	evaluation_cache: Dictionary
) -> void:
	if diplomacy_mobilization_cache_disabled:
		return
	evaluation_cache.clear()
	evaluation_cache["__diplomacy_mobilization_cache_ready"] = true
	diplomacy_mobilization_evaluation_cache_total += 1


func _start_war_mobilization(
	nation_id: int,
	requested_armies: int = -1,
	evaluation_cache: Dictionary = {}
) -> void:
	var nation := state.nations[nation_id]
	var resource_cache := evaluation_cache
	if diplomacy_mobilization_cache_disabled:
		resource_cache = {}
		diplomacy_mobilization_evaluation_cache_total += 1
	elif not resource_cache.has(
		"__diplomacy_mobilization_cache_ready"
	):
		_prepare_diplomacy_mobilization_cache(resource_cache)
	var mobilization_part_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var posture := DiplomacyAI.food_posture(
		state, nation_id, resource_cache
	)
	# 战时动员的金币上限最终只读取冻结的战前收入；完整 resource_report
	# 其余字段不会参与 capacity。预聚合这两个实际输入，避免仅为随后被覆盖
	# 的当前贸易收入重建全图。异常旧档没有快照时仍走原始完整计算。
	if (
		not diplomacy_mobilization_cache_disabled
		and posture in [
			DiplomacyAI.FoodPosture.OFFENSIVE_WAR,
			DiplomacyAI.FoodPosture.DEFENSIVE_WAR,
		]
		and nation.war_gold_income_snapshot >= 0
	):
		resource_cache["resource:%d" % nation_id] = {
			"gold_reserve_target": (
				nation.war_gold_income_snapshot
				* WAR_GOLD_RESERVE_MONTHS
			),
			"gold_reserve_baseline_income": (
				nation.war_gold_income_snapshot
			),
		}
	_record_tick_profile_stage(
		"diplomacy_mobilization_posture",
		mobilization_part_started
	)
	mobilization_part_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var capacity := DiplomacyAI.mobilization_capacity(
		state,
		nation_id,
		posture,
		resource_cache
	)
	_record_tick_profile_stage(
		"diplomacy_mobilization_capacity",
		mobilization_part_started
	)
	mobilization_part_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	if requested_armies >= 0:
		capacity = mini(capacity, requested_armies)
	var current_troops := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			current_troops += army.size
	_record_tick_profile_stage(
		"diplomacy_mobilization_troops",
		mobilization_part_started
	)
	mobilization_part_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var target := current_troops + capacity * NEW_ARMY_SIZE
	var food_plan := DiplomacyAI.war_food_report(
		state,
		nation_id,
		target,
		posture,
		resource_cache
	)
	_record_tick_profile_stage(
		"diplomacy_mobilization_food",
		mobilization_part_started
	)
	nation.war_mobilization_target_troops = maxi(
		nation.war_mobilization_target_troops,
		target
	)
	nation.war_mobilization_until_day = maxi(
		nation.war_mobilization_until_day,
		state.day + WAR_MOBILIZATION_DAYS
	)
	nation.war_mobilization_reason = (
		"粮食储备支持额外动员%d军，目标总兵力%d；年结余%.0f，可支撑%.1f年"
		% [
			capacity,
			nation.war_mobilization_target_troops,
			food_plan["target_annual_balance"],
			food_plan["target_runway_years"],
		]
	)


func _clear_finished_war_mobilization(nation_id: int) -> void:
	if not state.wars_of(nation_id).is_empty():
		return
	var nation := state.nations[nation_id]
	nation.war_mobilization_target_troops = 0
	nation.war_mobilization_until_day = -1
	nation.war_mobilization_reason = ""
	nation.campaign_last_offensive_day = -1
	nation.campaign_next_offensive_day = -1
	nation.campaign_offensive_count = 0
	nation.campaign_theater_anchor_city = -1
	nation.campaign_theater_started_day = -1
	_clear_campaign_preparation_plan(nation_id)
	nation.campaign_post_capture_plans.clear()
	_clear_campaign_attack_plan(nation_id)


func _record_diplomatic_action(
	nation_id: int,
	action: int,
	target_id: int,
	reason: String
) -> void:
	var nation := state.nations[nation_id]
	nation.ai_last_diplomatic_action = action
	nation.ai_last_diplomatic_target = target_id
	nation.ai_last_diplomatic_day = state.day
	nation.ai_last_diplomatic_reason = reason


## 联盟议和先原子提交全部外交关系，再按当前敌对关系重建战斗参与者。
## 不能用 side_a[0]/side_b[0] 代表整侧：围城守方可以是多国共同体，且被普通
## 议和豁免的削藩内战仍可能在同一场围城中继续。
func _reconcile_battles_after_coalition_peace(
	bloc_a: Array[int],
	bloc_b: Array[int]
) -> void:
	for battle in state.battles:
		if battle.finished:
			continue
		if battle.kind == Battle.Kind.SIEGE:
			_reconcile_siege_after_coalition_peace(battle)
			continue
		if not _battle_sides_still_hostile(battle):
			_finish_battle_for_peace(battle)
	state.battles = state.battles.filter(func(b: Battle) -> bool: return not b.finished)
	var affected := {}
	for nation_id in bloc_a + bloc_b:
		affected[nation_id] = true
	for army in state.armies:
		if army.size <= 0 or not affected.has(army.owner_nation):
			continue
		var node_city := army.current_city_node()
		if (
			node_city >= 0
			and node_city < state.cities.size()
			and not state.has_military_access(
				army.owner_nation,
				state.cities[node_city].owner_nation
			)
		):
			_start_diplomatic_repatriation(
				army,
				node_city
			)
			continue
		if (
			army.ai_target_city >= 0
			and army.ai_target_city < state.cities.size()
		):
			var target_owner := state.cities[army.ai_target_city].owner_nation
			if not state.is_enemy(army.owner_nation, target_owner):
				army.path.clear()
				army.ai_target_city = -1
				army.ai_order_until_day = state.day


func _reconcile_siege_after_coalition_peace(
	battle: Battle
) -> void:
	if battle.city == null or battle.side_a.is_empty():
		_finish_battle_for_peace(battle)
		return
	var besieger_nation := battle.side_a[0].owner_nation
	if not state.is_enemy(
		besieger_nation,
		battle.city.owner_nation
	):
		if (
			not _siege_side_defends_city(
				battle,
				battle.side_b
			)
			and _siege_side_has_enemy_of_city(
				battle.side_b,
				battle.city
			)
		):
			for army in battle.side_a:
				_release_army_from_peace_battle(
					army,
					battle
				)
			battle.side_a.clear()
			_promote_challengers(battle)
			return
		_finish_battle_for_peace(battle)
		return
	var retained: Array[Army] = []
	for army in battle.side_b:
		if (
			army.size > 0
			and state.is_enemy(
				army.owner_nation,
				besieger_nation
			)
		):
			retained.append(army)
		else:
			_release_army_from_peace_battle(
				army,
				battle
			)
	battle.side_b = retained
	battle.reinforce_fresh_b = battle.reinforce_fresh_b.filter(
		func(army: Army) -> bool:
			return retained.has(army)
	)
	battle.routed_b = battle.routed_b.filter(
		func(army: Army) -> bool:
			return retained.has(army)
	)
	for army in battle.frontline_priority_b.keys():
		if not retained.has(army):
			battle.frontline_priority_b.erase(army)
	battle.has_garrison = _siege_side_defends_city(
		battle,
		retained
	)


func _siege_side_has_enemy_of_city(
	side: Array[Army],
	city: City
) -> bool:
	for army in side:
		if (
			army.size > 0
			and state.is_enemy(
				army.owner_nation,
				city.owner_nation
			)
		):
			return true
	return false


func _battle_sides_still_hostile(
	battle: Battle
) -> bool:
	for army_a in battle.side_a:
		if army_a.size <= 0:
			continue
		for army_b in battle.side_b:
			if (
				army_b.size > 0
				and state.is_enemy(
					army_a.owner_nation,
					army_b.owner_nation
				)
			):
				return true
	return false


func _finish_battle_for_peace(battle: Battle) -> void:
	for army in battle.side_a + battle.side_b:
		_release_army_from_peace_battle(
			army,
			battle
		)
	battle.finished = true
	battle.winner_side = 0


func _release_army_from_peace_battle(
	army: Army,
	battle: Battle
) -> void:
	if army.size <= 0:
		army.battle_id = -1
		return
	if (
		army.location_city >= 0
		and army.location_city < state.cities.size()
		and state.has_military_access(
			army.owner_nation,
			state.cities[army.location_city].owner_nation
		)
	):
		_settle_idle(army, army.location_city)
	elif (
		battle.city != null
		and state.has_military_access(
			army.owner_nation,
			battle.city.owner_nation
		)
	):
		_settle_idle(army, battle.city.id)
	elif army.on_edge and army.move_to != -1:
		army.state = Army.State.MOVING
		army.battle_id = -1
		army.path.clear()
	else:
		_retreat_to_friendly(army)


func _repatriate_after_access_revoked(
	nation_a: int,
	nation_b: int
) -> void:
	for army in state.armies:
		if army.size <= 0 or army.owner_nation not in [nation_a, nation_b]:
			continue
		var former_ally := nation_b if army.owner_nation == nation_a else nation_a
		var in_former_ally_territory := (
			army.location_city >= 0
			and army.location_city < state.cities.size()
			and state.cities[army.location_city].owner_nation == former_ally
		)
		var route_uses_former_ally := false
		for city_id in army.path:
			if state.cities[city_id].owner_nation == former_ally:
				route_uses_former_ally = true
				break
		if not in_former_ally_territory and not route_uses_former_ally:
			continue
		army.path.clear()
		army.ai_target_city = -1
		army.ai_order_until_day = state.day
		if army.on_edge and army.move_to != -1:
			army.diplomatic_repatriation = true
			_retreat(army)
		else:
			_start_diplomatic_repatriation(
				army,
				army.current_city_node()
			)
# ------------------------------------------------------------------ 3. AI 决策


func _build_parallel_ai_threat(job_index: int) -> void:
	var job: Dictionary = _parallel_ai_context_jobs[
		job_index
	]
	job["threat"] = ThreatField.build(
		job["view"],
		job["threat_cache"]
	)


func _build_parallel_ai_defense(job_index: int) -> void:
	var job: Dictionary = _parallel_ai_context_jobs[
		job_index
	]
	var defense_plan: CityDefensePlan = job["defense_plan"]
	defense_plan.evaluate_readonly(job["previous_defense_plan"])


func _build_ai_defense_partition(
	worker_index: int, worker_count: int, job_count: int
) -> void:
	var job_index := worker_index
	while job_index < job_count:
		_build_parallel_ai_defense(job_index)
		job_index += worker_count


func _record_defense_plan_cache_result(
	plan: CityDefensePlan
) -> void:
	if plan.topology_rebuilt:
		ai_defense_topology_rebuild_total += 1
	elif plan.topology_reused:
		ai_defense_topology_reuse_total += 1
	if plan.dynamic_plan_reused:
		ai_defense_dynamic_reuse_total += 1


func _build_ai_snapshot_context(
	job: Dictionary,
	diplomacy_cache: Dictionary = {}
) -> void:
	var snapshot_profile: Dictionary = (
		{"enabled": true} if ai_snapshot_substage_profiling_enabled
		else _empty_snapshot_profile_sink
	)
	job["snapshot"] = _strategy_snapshot_for(
		job["view"],
		diplomacy_cache,
		snapshot_profile
	)
	job["snapshot_profile"] = snapshot_profile


## 后台线程构建全部国家的只读 AI 上下文（view/snapshot/threat）。运行期把这
## ~67% 的重活移出主线程，主线程在等待期间继续渲染插值，消除十日一次的卡顿。
## 只读冻结的 GameState，写入各自 job 私有字段与本任务独占的行军/外交缓存；
## 期间主线程只做渲染（不触碰 EquivariantOrder/威胁缓存），故无需加锁。
## 防区规划因会改写 GameState，仍留在主线程串行提交。
func _build_ai_snapshots_serial(payload: Dictionary) -> void:
	var jobs: Array = payload["jobs"]
	var diplomacy_cache: Dictionary = payload["diplomacy_cache"]
	var substage_profile_enabled: bool = bool(
		payload.get("substage_profile_enabled", false)
	)
	for job in jobs:
		var snapshot_profile: Dictionary = (
			{"enabled": true} if substage_profile_enabled
			else _empty_snapshot_profile_sink
		)
		job["snapshot"] = _strategy_snapshot_for(
			job["view"],
			diplomacy_cache,
			snapshot_profile
		)
		job["snapshot_profile"] = snapshot_profile


func _build_ai_threat_partition(
	worker_index: int,
	worker_count: int,
	payload: Dictionary
) -> void:
	var jobs: Array = payload["jobs"]
	var base_cache: Dictionary = payload["threat_base_cache"]
	var worker_cache_deltas: Array = payload["worker_cache_deltas"]
	var local_cache: Dictionary = worker_cache_deltas[worker_index]
	var job_index := worker_index
	while job_index < jobs.size():
		var job: Dictionary = jobs[job_index]
		job["threat"] = ThreatField.build(
			job["view"], base_cache, local_cache, true
		)
		job_index += worker_count


func _build_ai_travel_partition(
	worker_index: int,
	worker_count: int,
	payload: Dictionary
) -> void:
	var requests: Array = payload["requests"]
	var worker_deltas: Array = payload["worker_deltas"]
	var output: Dictionary = worker_deltas[worker_index]
	var request_index := worker_index
	while request_index < requests.size():
		var request: Vector2i = requests[request_index]
		ThreatField.build_shared_travel_request(
			state, request.x, request.y, output
		)
		request_index += worker_count


func _ai_threat_travel_requests() -> Array[Vector2i]:
	var unique := {}
	for army in state.armies:
		if army.size <= 0:
			continue
		var starts: Array[int] = []
		if army.on_edge and army.move_to >= 0:
			starts = [army.move_from, army.move_to]
		elif army.location_city >= 0:
			starts = [army.location_city]
		for start in starts:
			if start < 0:
				continue
			unique["%d:%d" % [start, maxi(army.max_size, 1)]] = (
				Vector2i(start, maxi(army.max_size, 1))
			)
	var requests: Array[Vector2i] = []
	requests.assign(unique.values())
	requests.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	return requests


func _run_worker_tasks_over_frames(
	task_ids: Array[int]
) -> void:
	var pending := true
	while pending:
		pending = false
		for task_id in task_ids:
			if not WorkerThreadPool.is_task_completed(task_id):
				pending = true
				break
		if pending:
			await get_tree().process_frame
	for task_id in task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)


func _merge_parallel_threat_cache_deltas(
	worker_cache_deltas: Array
) -> void:
	# worker 索引固定；同 key 的计算结果确定性相同。固定顺序合并
	# 保持缓存内容与串行路径一致，也杜绝 worker 间 Dictionary 写竞争。
	for delta_value in worker_cache_deltas:
		var delta: Dictionary = delta_value
		var keys := delta.keys()
		keys.sort()
		for key in keys:
			if not _threat_travel_cache.has(key):
				_threat_travel_cache[key] = delta[key]


func _ai_assign_targets(spread_runtime_work: bool = false) -> void:
	if spread_runtime_work:
		await get_tree().process_frame
	_set_runtime_profile_stage(&"ai_view_setup")
	var runtime_slice_started := Time.get_ticks_usec()
	var ai_profile_stage_started := (
		runtime_slice_started if tick_phase_profiling_enabled else 0
	)
	var view_phase: Dictionary = await _prepare_ai_view_phase(
		spread_runtime_work,
		runtime_slice_started
	)
	var nation_order: Array[int] = view_phase["nation_order"]
	var managed_nations: Array[int] = view_phase["managed_nations"]
	var context_jobs: Array[Dictionary] = view_phase["context_jobs"]
	runtime_slice_started = int(view_phase["slice_started"])
	var force_contexts := {}
	_record_tick_profile_stage("ai_view_setup", ai_profile_stage_started)
	ai_profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var snapshot_cache_seed_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var snapshot_diplomacy_cache := (
		await _seed_trade_forecast_over_frames()
		if spread_runtime_work
		else _seed_trade_forecast({})
	)
	_record_tick_profile_stage(
		"ai_snapshot_cache_seed",
		snapshot_cache_seed_started
	)
	var snapshot_phase: Dictionary = await _build_ai_snapshot_threat_phase(
		context_jobs,
		snapshot_diplomacy_cache,
		spread_runtime_work,
		runtime_slice_started,
		ai_profile_stage_started
	)
	runtime_slice_started = int(snapshot_phase["slice_started"])
	ai_profile_stage_started = int(snapshot_phase["profile_stage_started"])
	var defense_phase: Dictionary = await _build_ai_defense_phase(
		context_jobs,
		force_contexts,
		spread_runtime_work,
		runtime_slice_started,
		ai_profile_stage_started
	)
	runtime_slice_started = int(defense_phase["slice_started"])
	ai_profile_stage_started = int(defense_phase["profile_stage_started"])
	# 宣战提交只落盘外交状态；同日 AI 上下文完成后复用其 ThreatField
	# 发动已准备攻势，避免在外交阶段重复构建整张威胁场。
	_set_runtime_profile_stage(&"ai_declaration_launches")
	var declaration_phase: Dictionary = await (
		_launch_pending_declaration_offensives(
			managed_nations,
			force_contexts,
			spread_runtime_work,
			runtime_slice_started
		)
	)
	var declaration_launched_nations: Dictionary = (
		declaration_phase["launched_nations"]
	)
	runtime_slice_started = int(declaration_phase["slice_started"])
	_record_tick_profile_stage(
		"ai_declaration_launches",
		ai_profile_stage_started
	)
	ai_profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	# 军制调整只消耗本国资源；所有国家先基于同一时刻的冻结上下文决策。
	_set_runtime_profile_stage(&"ai_force_structure")
	var force_phase: Dictionary = await _run_ai_force_structure_phase(
		managed_nations,
		force_contexts,
		snapshot_diplomacy_cache,
		spread_runtime_work,
		runtime_slice_started
	)
	var decision_contexts: Dictionary = force_phase["decision_contexts"]
	runtime_slice_started = int(force_phase["slice_started"])
	_record_tick_profile_stage("ai_force_structure", ai_profile_stage_started)
	ai_profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	# 军事规划复用 tick 开始时的冻结上下文；军制变化从下一次决策起生效。
	_set_runtime_profile_stage(&"ai_campaign_planning")
	var military_contexts := force_contexts
	var campaign_phase: Dictionary = await _run_ai_campaign_planning_phase(
		managed_nations,
		military_contexts,
		decision_contexts,
		declaration_launched_nations,
		spread_runtime_work,
		runtime_slice_started
	)
	var coordinators: Dictionary = campaign_phase["coordinators"]
	var defense_plans: Dictionary = campaign_phase["defense_plans"]
	runtime_slice_started = int(campaign_phase["slice_started"])
	_record_tick_profile_stage("ai_campaign_planning", ai_profile_stage_started)
	ai_profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"ai_army_decisions")
	runtime_slice_started = await _run_ai_army_decision_phase(
		managed_nations,
		military_contexts,
		coordinators,
		defense_plans,
		spread_runtime_work,
		runtime_slice_started
	)
	_record_tick_profile_stage("ai_army_decisions", ai_profile_stage_started)
	ai_profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"ai_commit")
	_commit_ai_command_collection(nation_order)
	_record_tick_profile_stage("ai_commit", ai_profile_stage_started)


func _prepare_ai_view_phase(
	spread_runtime_work: bool,
	runtime_slice_started: int
) -> Dictionary:
	_ai_supply_source_cache.clear()
	_ai_supply_network_cache.clear()
	# 全局外交变化强制全体重算；局部占领只把直接受影响国家并入当天错峰集合。
	var first_world_decision := (
		_ai_last_decision_day == -1
		and state.day <= 1
		and state.uses_heightmap
		and ai_staggered_decisions
		and state.nations.size() > AI_INITIAL_STAGGER_NATION_THRESHOLD
	)
	var force_all_nations := (
		_ai_last_decision_day == -1 and not first_world_decision
	)
	_ai_last_decision_day = state.day
	var decision_interval := (
		AI_DECISION_INTERVAL_DAYS
		if state.uses_heightmap
		else GRID_AI_DECISION_INTERVAL_DAYS
	)
	var nation_order := _ai_nation_ids_for_day(
		state.nations.size(),
		state.day,
		rotate_ai_nation_order,
		decision_interval,
		force_all_nations,
		ai_staggered_decisions
	)
	if not force_all_nations and not _ai_forced_nations.is_empty():
		nation_order = merge_forced_ai_nation_order(
			nation_order,
			_ai_forced_nations.keys(),
			state.nations.size(),
			state.day,
			rotate_ai_nation_order,
			decision_interval
		)
	for nation_id in nation_order:
		_ai_forced_nations.erase(nation_id)
	var managed_nations: Array[int] = []
	var context_jobs: Array[Dictionary] = []
	var ai_view_detail_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var shared_army_index := (
		AiWorldView.build_army_index(state)
		if ai_policy_overrides.is_empty()
		else {}
	)
	_record_tick_profile_stage(
		"ai_shared_army_index",
		ai_view_detail_started
	)
	for nation_id in nation_order:
		var nation := state.nations[nation_id]
		if not nation.alive:
			continue
		ai_view_detail_started = (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
		_reconcile_strategic_roles(
			nation_id,
			shared_army_index
		)
		_record_tick_profile_stage(
			"ai_reconcile_roles",
			ai_view_detail_started
		)
		if ai_policy_overrides.has(nation.id):
			var policy: Callable = ai_policy_overrides[nation.id]
			policy.call(state, nation.id, self)
			continue
		managed_nations.append(nation_id)
		ai_view_detail_started = (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
		var view := _build_ai_view(
			nation_id,
			shared_army_index
		)
		_record_tick_profile_stage(
			"ai_build_view",
			ai_view_detail_started
		)
		context_jobs.append({
			"nation_id": nation_id,
			"view": view,
			"snapshot": null,
			"threat_cache": _threat_travel_cache,
			"previous_defense_plan":
				_ai_defense_plan_cache.get(nation_id),
			"threat": null,
			"defense_plan": null,
		})
		if (
			spread_runtime_work
			and Time.get_ticks_usec() - runtime_slice_started
				>= AI_CONTEXT_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
	return {
		"nation_order": nation_order,
		"managed_nations": managed_nations,
		"context_jobs": context_jobs,
		"slice_started": runtime_slice_started,
	}


func _build_ai_snapshot_threat_phase(
	context_jobs: Array[Dictionary],
	snapshot_diplomacy_cache: Dictionary,
	spread_runtime_work: bool,
	runtime_slice_started: int,
	ai_profile_stage_started: int
) -> Dictionary:
	_parallel_ai_context_jobs = context_jobs
	# Read-only snapshot and threat construction dominates the decision cost.
	# Runtime mode keeps rendering while deterministic worker batches complete.
	if spread_runtime_work and not context_jobs.is_empty():
		var snapshot_payload := {
			"jobs": context_jobs,
			"diplomacy_cache": snapshot_diplomacy_cache,
			"substage_profile_enabled":
				ai_snapshot_substage_profiling_enabled,
		}
		var snapshot_task_id := WorkerThreadPool.add_task(
			_build_ai_snapshots_serial.bind(snapshot_payload),
			true, "WorldWar AI snapshots"
		)
		_set_runtime_profile_stage(&"ai_snapshot_worker")
		while not WorkerThreadPool.is_task_completed(snapshot_task_id):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(snapshot_task_id)
		if ai_snapshot_substage_profiling_enabled:
			for job in context_jobs:
				_merge_tick_profile_stage_values(
					job.get("snapshot_profile", {})
				)
		var worker_count := (
			1
			if ai_parallel_threat_disabled
			else mini(
				context_jobs.size(),
				mini(maxi(OS.get_processor_count() - 1, 1), AI_THREAT_MAX_WORKERS)
			)
		)
		var travel_requests := _ai_threat_travel_requests().filter(
			func(request: Vector2i) -> bool:
				return not _threat_travel_cache.has(
					"I:%d:%d" % [request.x, request.y]
				)
		)
		if not travel_requests.is_empty():
			var travel_worker_count := mini(
				worker_count, travel_requests.size()
			)
			var travel_worker_deltas: Array = []
			for _worker_index in range(travel_worker_count):
				travel_worker_deltas.append({})
			var travel_payload := {
				"requests": travel_requests,
				"worker_deltas": travel_worker_deltas,
			}
			var travel_task_ids: Array[int] = []
			for worker_index in range(travel_worker_count):
				travel_task_ids.append(WorkerThreadPool.add_task(
					_build_ai_travel_partition.bind(
						worker_index, travel_worker_count, travel_payload
					),
					true,
					"WorldWar AI travel fields"
				))
			_set_runtime_profile_stage(&"ai_travel_workers")
			await _run_worker_tasks_over_frames(travel_task_ids)
			_merge_parallel_threat_cache_deltas(travel_worker_deltas)
		var threat_payload := {
			"jobs": context_jobs,
			"threat_base_cache": _threat_travel_cache,
			"worker_cache_deltas": [],
		}
		var worker_cache_deltas: Array = threat_payload["worker_cache_deltas"]
		for _worker_index in range(worker_count):
			worker_cache_deltas.append({})
		var threat_task_ids: Array[int] = []
		var threat_started_usec := Time.get_ticks_usec()
		ai_threat_worker_count_last = worker_count
		for worker_index in range(worker_count):
			threat_task_ids.append(WorkerThreadPool.add_task(
				_build_ai_threat_partition.bind(
					worker_index, worker_count, threat_payload
				),
				true,
				"WorldWar AI threats"
			))
		_set_runtime_profile_stage(&"ai_threat_workers")
		await _run_worker_tasks_over_frames(threat_task_ids)
		ai_threat_worker_last_usec = (
			Time.get_ticks_usec() - threat_started_usec
		)
		ai_threat_worker_total_usec += ai_threat_worker_last_usec
		ai_threat_worker_runs += 1
		_merge_parallel_threat_cache_deltas(worker_cache_deltas)
		runtime_slice_started = Time.get_ticks_usec()
		_record_tick_profile_stage(
			"ai_snapshot_threat",
			ai_profile_stage_started
		)
		ai_profile_stage_started = (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
	else:
		for job in context_jobs:
			_build_ai_snapshot_context(job, snapshot_diplomacy_cache)
			if ai_snapshot_substage_profiling_enabled:
				_merge_tick_profile_stage_values(
					job.get("snapshot_profile", {})
				)
		_record_tick_profile_stage("ai_snapshot", ai_profile_stage_started)
		ai_profile_stage_started = (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
		for job_index in range(context_jobs.size()):
			_build_parallel_ai_threat(job_index)
		_record_tick_profile_stage("ai_threat", ai_profile_stage_started)
		ai_profile_stage_started = (
			Time.get_ticks_usec()
			if tick_phase_profiling_enabled else 0
		)
	return {
		"slice_started": runtime_slice_started,
		"profile_stage_started": ai_profile_stage_started,
	}


func _build_ai_defense_phase(
	context_jobs: Array[Dictionary],
	force_contexts: Dictionary,
	spread_runtime_work: bool,
	runtime_slice_started: int,
	ai_profile_stage_started: int
) -> Dictionary:
	_set_runtime_profile_stage(&"ai_defense")
	if spread_runtime_work and not context_jobs.is_empty():
		for job in context_jobs:
			job["defense_plan"] = CityDefensePlan.prepare_evaluation(
				job["view"], job["snapshot"], job["threat"]
			)
		var defense_worker_count := (
			1 if ai_parallel_defense_disabled else mini(
				context_jobs.size(),
				mini(maxi(OS.get_processor_count() - 1, 1), AI_DEFENSE_MAX_WORKERS)
			)
		)
		var defense_task_ids: Array[int] = []
		var defense_started_usec := Time.get_ticks_usec()
		ai_defense_worker_count_last = defense_worker_count
		for worker_index in range(defense_worker_count):
			defense_task_ids.append(WorkerThreadPool.add_task(
				_build_ai_defense_partition.bind(
					worker_index, defense_worker_count, context_jobs.size()
				),
				true, "WorldWar AI defense evaluation"
			))
		_set_runtime_profile_stage(&"ai_defense_workers")
		await _run_worker_tasks_over_frames(defense_task_ids)
		ai_defense_worker_last_usec = Time.get_ticks_usec() - defense_started_usec
		ai_defense_worker_total_usec += ai_defense_worker_last_usec
		ai_defense_worker_runs += 1
		_set_runtime_profile_stage(&"ai_defense_commit")
		# Commit in deterministic nation order while keeping frames responsive.
		runtime_slice_started = Time.get_ticks_usec()
		for job in context_jobs:
			var defense_plan: CityDefensePlan = job["defense_plan"]
			defense_plan.commit_assignments()
			_record_defense_plan_cache_result(defense_plan)
			if (
				spread_runtime_work
				and Time.get_ticks_usec() - runtime_slice_started
					>= AI_RUNTIME_SLICE_BUDGET_USEC
			):
				await get_tree().process_frame
				runtime_slice_started = Time.get_ticks_usec()
	else:
		for job in context_jobs:
			var defense_plan := CityDefensePlan.build(
				job["view"], job["snapshot"], job["threat"],
				job["previous_defense_plan"]
			)
			job["defense_plan"] = defense_plan
			_record_defense_plan_cache_result(defense_plan)
	_record_tick_profile_stage("ai_defense", ai_profile_stage_started)
	ai_profile_stage_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	for job in context_jobs:
		var nation_id := int(job["nation_id"])
		_ai_defense_plan_cache[nation_id] = job["defense_plan"]
		force_contexts[nation_id] = {
			"view": job["view"],
			"snapshot": job["snapshot"],
			"threat": job["threat"],
			"defense_plan": job["defense_plan"],
		}
	_parallel_ai_context_jobs.clear()
	return {
		"slice_started": runtime_slice_started,
		"profile_stage_started": ai_profile_stage_started,
	}


func _run_ai_army_decision_phase(
	managed_nations: Array[int],
	military_contexts: Dictionary,
	coordinators: Dictionary,
	defense_plans: Dictionary,
	spread_runtime_work: bool,
	runtime_slice_started: int
) -> int:
	for nation_id in managed_nations:
		var context: Dictionary = military_contexts[nation_id]
		var nation := state.nations[nation_id]
		var view: AiWorldView = context["view"]
		var snapshot: StrategicMapSnapshot = context["snapshot"]
		var threat: ThreatField = context["threat"]
		var coordinator: ArmyCoordinator = coordinators[nation_id]
		var defense_plan: CityDefensePlan = defense_plans[nation_id]
		var minimum_participant_ratio := float(
			ai_assault_participant_ratio_overrides.get(
				nation_id,
				UtilityAI.ASSAULT_PARTICIPANT_MIN_RATIO
			)
		)
		var strongest_first := bool(
			ai_tactical_decision_order_overrides.get(nation_id, true)
		)
		var decision_order := _sort_ai_decision_order(
			state,
			view.friendly_armies,
			snapshot,
			strongest_first
		)
		for army in decision_order:
			if (
				spread_runtime_work
				and Time.get_ticks_usec() - runtime_slice_started
					>= AI_RUNTIME_SLICE_BUDGET_USEC
			):
				await get_tree().process_frame
				runtime_slice_started = Time.get_ticks_usec()
			_decide_ai_army(
				nation_id,
				nation,
				army,
				view,
				snapshot,
				threat,
				coordinator,
				minimum_participant_ratio,
				defense_plan
			)
		if (
			spread_runtime_work
			and Time.get_ticks_usec() - runtime_slice_started
				>= AI_RUNTIME_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
	return runtime_slice_started


func _decide_ai_army(
	nation_id: int,
	nation: Nation,
	army: Army,
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	minimum_participant_ratio: float,
	defense_plan: CityDefensePlan
) -> void:
	var active_campaign_target := int(
		nation.campaign_attack_assignments.get(army.id, -1)
	)
	var preparation_target := int(
		nation.campaign_preparation_assignments.get(army.id, -1)
	)
	var campaign_target := (
		active_campaign_target
		if active_campaign_target >= 0
		else preparation_target
	)
	var campaign_locked := (
		campaign_target >= 0
		and (
			nation.war_preparation_target_nation >= 0
			or (
				campaign_target < state.cities.size()
				and state.is_enemy(
					nation_id,
					state.cities[campaign_target].owner_nation
				)
			)
		)
	)
	if campaign_locked:
		var defense_anchor := army.location_city
		if army.state == Army.State.HOLDING and army.move_to != -1:
			defense_anchor = _campaign_army_origin(army, nation_id)
		var actual_emergency := (
			state.city_under_siege(defense_anchor)
			if preparation_target >= 0
			else defense_plan.urgent_defense_at(defense_anchor)
		)
		if actual_emergency:
			campaign_locked = false
	if (
		campaign_locked
		and army.size > 0
		and not _ai_planned_armies.has(army.id)
	):
		if (
			active_campaign_target >= 0
			and state.is_enemy(
				nation_id,
				state.cities[campaign_target].owner_nation
			)
			and nation.campaign_launched_armies.has(army.id)
			and _army_ready_for_campaign_target(
				army,
				nation_id,
				campaign_target
			)
		):
			var continue_campaign := ActionCandidate.make(
				ActionCandidate.Kind.ATTACK,
				2000.0,
				("继续执行国家战役计划：" + "军%d攻击城市%d") % [
					army.id,
					campaign_target,
				],
				campaign_target
			)
			continue_campaign.minimum_commit_days = (
				CAMPAIGN_OFFENSIVE_COMMIT_DAYS
			)
			if _execute_ai_candidate(army, continue_campaign):
				coordinator.reserve(campaign_target, army)
	if (
		army.size <= 0
		or _ai_planned_armies.has(army.id)
		or campaign_locked
	):
		return
	if army.is_line_role():
		var line_candidate := defense_plan.candidate_for(army, coordinator)
		if (
			line_candidate != null
			and line_candidate.kind != ActionCandidate.Kind.NONE
			and _execute_ai_candidate(army, line_candidate)
		):
			if line_candidate.kind == ActionCandidate.Kind.HOLD:
				coordinator.reserve_edge(
					line_candidate.target_edge_a,
					line_candidate.target_edge_b,
					army
				)
			elif line_candidate.target_city != -1:
				coordinator.reserve(line_candidate.target_city, army)
		return
	var candidate := UtilityAI.choose(
		view,
		snapshot,
		threat,
		coordinator,
		army,
		minimum_participant_ratio,
		defense_plan
	)
	if candidate.kind == ActionCandidate.Kind.NONE:
		return
	if _execute_ai_candidate(army, candidate):
		if candidate.kind == ActionCandidate.Kind.HOLD:
			coordinator.reserve_edge(
				candidate.target_edge_a,
				candidate.target_edge_b,
				army
			)
		elif candidate.target_city != -1:
			coordinator.reserve(candidate.target_city, army)


func _launch_pending_declaration_offensives(
	managed_nations: Array[int],
	force_contexts: Dictionary,
	spread_runtime_work: bool,
	runtime_slice_started: int
) -> Dictionary:
	var launched_nations := {}
	for nation_id in managed_nations:
		if not _pending_declaration_launches.has(nation_id):
			continue
		if (
			spread_runtime_work
			and Time.get_ticks_usec() - runtime_slice_started
				>= AI_RUNTIME_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
		var pending_launch: Dictionary = _pending_declaration_launches[nation_id]
		_pending_declaration_launches.erase(nation_id)
		var objective := int(pending_launch.get("objective_city", -1))
		if (
			objective >= 0
			and objective < state.cities.size()
			and state.is_enemy(
				nation_id, state.cities[objective].owner_nation
			)
		):
			var context: Dictionary = force_contexts[nation_id]
			if _launch_campaign_offensive(
				nation_id,
				objective,
				int(pending_launch.get("preparation_days", 0)),
				[],
				context["threat"]
			):
				launched_nations[nation_id] = true
		if (
			spread_runtime_work
			and Time.get_ticks_usec() - runtime_slice_started
				>= AI_RUNTIME_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
	return {
		"launched_nations": launched_nations,
		"slice_started": runtime_slice_started,
	}


func _run_ai_force_structure_phase(
	managed_nations: Array[int],
	force_contexts: Dictionary,
	snapshot_diplomacy_cache: Dictionary,
	spread_runtime_work: bool,
	runtime_slice_started: int
) -> Dictionary:
	# Only stable diplomatic/topology primitives survive declaration launches;
	# dynamic resource and food reports are rebuilt against the current state.
	var resource_cache := (
		{}
		if ai_snapshot_resource_cache_reuse_disabled
		else _stable_force_resource_cache_from_snapshot(
			snapshot_diplomacy_cache
		)
	)
	_seed_trade_forecast(resource_cache)
	var decision_contexts := {}
	for nation_id in managed_nations:
		var context: Dictionary = force_contexts[nation_id]
		var decision_context := {}
		var context_started := (
			Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
		)
		_set_runtime_profile_stage(&"ai_force_context")
		if not ai_decision_context_disabled:
			_enrich_ai_decision_context(context, resource_cache)
			decision_context = context
		_record_tick_profile_stage("ai_force_context", context_started)
		decision_contexts[nation_id] = decision_context
		if (
			spread_runtime_work
			and Time.get_ticks_usec() - runtime_slice_started
				>= AI_RUNTIME_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
		var commit_started := (
			Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
		)
		_set_runtime_profile_stage(&"ai_force_commit")
		_ai_manage_force_structure(
			context["view"],
			context["snapshot"],
			context["threat"],
			context["defense_plan"],
			true,
			resource_cache,
			decision_context
		)
		_record_tick_profile_stage("ai_force_commit", commit_started)
		if (
			spread_runtime_work
			and Time.get_ticks_usec() - runtime_slice_started
				>= AI_RUNTIME_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
	return {
		"decision_contexts": decision_contexts,
		"slice_started": runtime_slice_started,
	}


func _run_ai_campaign_planning_phase(
	managed_nations: Array[int],
	military_contexts: Dictionary,
	decision_contexts: Dictionary,
	declaration_launched_nations: Dictionary,
	spread_runtime_work: bool,
	runtime_slice_started: int
) -> Dictionary:
	var snapshot_army_ids := {}
	for nation_id in managed_nations:
		var context: Dictionary = military_contexts[nation_id]
		var view: AiWorldView = context["view"]
		for army in view.friendly_armies:
			snapshot_army_ids[army.id] = true
	_begin_ai_command_collection(snapshot_army_ids)
	var coordinators := {}
	var defense_plans := {}
	for nation_id in managed_nations:
		var context: Dictionary = military_contexts[nation_id]
		var coordinator := ArmyCoordinator.from_view(context["view"])
		coordinators[nation_id] = coordinator
		defense_plans[nation_id] = context["defense_plan"]
	for nation_id in managed_nations:
		var context: Dictionary = military_contexts[nation_id]
		var decision_context: Dictionary = decision_contexts[nation_id]
		var nation := state.nations[nation_id]
		var defense_plan: CityDefensePlan = defense_plans[nation_id]
		var coordinator: ArmyCoordinator = coordinators[nation_id]
		# Peaceful subjects only manage their own internal defense and claims.
		if state.is_vassal(nation_id) and not state.is_in_civil_war(nation_id):
			pass
		elif (
			nation.war_preparation_target_nation >= 0
			and (
				(decision_context["wars"] as Array).is_empty()
				if decision_context.has("wars")
				else state.wars_of(nation_id).is_empty()
			)
		):
			_assign_offensive_staging_orders(
				nation_id,
				nation.war_preparation_objective_city,
				defense_plan,
				coordinator,
				true,
				false,
				true,
				decision_context
			)
		elif (
			not declaration_launched_nations.has(nation_id)
			and (
				not (decision_context["wars"] as Array).is_empty()
				if decision_context.has("wars")
				else not state.wars_of(nation_id).is_empty()
			)
		):
			_manage_campaign_offensive(
				nation_id,
				defense_plan,
				coordinator,
				context["threat"] as ThreatField,
				decision_context
			)
		if (
			spread_runtime_work
			and Time.get_ticks_usec() - runtime_slice_started
				>= AI_RUNTIME_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
	return {
		"coordinators": coordinators,
		"defense_plans": defense_plans,
		"slice_started": runtime_slice_started,
	}


func _stable_force_resource_cache_from_snapshot(
	snapshot_cache: Dictionary
) -> Dictionary:
	var result := {}
	for key_value in snapshot_cache:
		if key_value is not String:
			continue
		var key := key_value as String
		if (
			key in [
				"frontier_matrix_built",
				"frontier_matrix",
				"frontier_neighbors_by_observer",
				"__diplomacy_topology_cache",
				"monthly_gold_flows",
				"trade_network_result",
			]
			or key.begins_with("wars:")
			or key.begins_with("allies:")
			or key.begins_with("frontier:")
			or key.begins_with("borders:")
		):
			result[key] = snapshot_cache[key]
	return result


func _reconcile_strategic_roles(
	nation_id: int,
	shared_army_index: Dictionary = {}
) -> void:
	if nation_id < 0 or nation_id >= state.nations.size():
		return
	var nation := state.nations[nation_id]
	var valid_groups := {}
	for group in nation.battle_groups:
		valid_groups[group.id] = true
	var armies: Array[Army] = []
	if not shared_army_index.is_empty():
		var armies_by_nation: Dictionary = (
			shared_army_index["armies_by_nation"]
		)
		armies.assign(
			(armies_by_nation[nation_id] as Array[Army])
		)
	else:
		for army in state.armies:
			if army.owner_nation == nation_id and army.size > 0:
				armies.append(army)
	armies.sort_custom(func(a: Army, b: Army) -> bool:
		if a.max_size != b.max_size:
			return a.max_size > b.max_size
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a,
			b
		)
	)
	var light_by_group := {}
	var heavy_by_group := {}
	for army in armies:
		if (
			army.battle_group_id < 0
			or not valid_groups.has(army.battle_group_id)
		):
			army.battle_group_id = -1
			continue
		var group_id := army.battle_group_id
		if army.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE:
			var light_count := int(light_by_group.get(group_id, 0))
			if light_count >= BattleGroup.MAX_LIGHT_ARMIES:
				army.battle_group_id = -1
				continue
			light_by_group[group_id] = light_count + 1
		elif army.max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
			var heavy_count := int(heavy_by_group.get(group_id, 0))
			if heavy_count >= BattleGroup.MAX_HEAVY_ARMIES:
				army.battle_group_id = -1
				continue
			heavy_by_group[group_id] = heavy_count + 1
	for army in armies:
		if (
			army.max_size < GameState.INITIAL_HEAVY_ARMY_SIZE
			or army.battle_group_id >= 0
		):
			continue
		var destination := -1
		for group in nation.battle_groups:
			if int(heavy_by_group.get(group.id, 0)) == 0:
				destination = group.id
				break
		if destination < 0:
			var group := state.create_battle_group(nation_id)
			destination = group.id
			valid_groups[destination] = true
		if state.assign_army_to_battle_group(army, destination):
			heavy_by_group[destination] = 1
	for army in armies:
		if army.battle_group_id >= 0:
			army.strategic_role = Army.StrategicRole.MAIN
			army.clear_line_assignment()
		else:
			army.strategic_role = Army.StrategicRole.LINE
	var army_by_id := {}
	for army in armies:
		army_by_id[army.id] = army
	for army_id in (
		nation.campaign_preparation_assignments.keys().duplicate()
	):
		var target_city := int(
			nation.campaign_preparation_assignments[army_id]
		)
		var assigned_army: Army = army_by_id.get(army_id)
		if (
			assigned_army != null
			and assigned_army.battle_group_id >= 0
			and nation.campaign_preparation_plan != null
			and nation.campaign_preparation_plan.target_for_group(
				assigned_army.battle_group_id
			) == target_city
		):
			continue
		nation.campaign_preparation_assignments.erase(army_id)


func _build_ai_view(
	nation_id: int,
	shared_army_index: Dictionary = {}
) -> AiWorldView:
	if not _ai_path_field_cache_by_nation.has(nation_id):
		_ai_path_field_cache_by_nation[nation_id] = {}
	var view := AiWorldView.build(
		state,
		nation_id,
		_ai_path_field_cache_by_nation[nation_id],
		_ai_supply_network_cache,
		_ai_city_partition_cache,
		shared_army_index
	)
	view.strategic_planning_enabled = bool(
		ai_strategic_planning_overrides.get(nation_id, true)
	)
	view.adaptive_garrison_enabled = bool(
		ai_adaptive_garrison_overrides.get(nation_id, true)
	)
	view.supply_corridor_defense_enabled = bool(
		ai_supply_corridor_defense_overrides.get(nation_id, true)
	)
	view.executable_attack_paths_enabled = bool(
		ai_executable_attack_paths_overrides.get(nation_id, true)
	)
	view.legacy_id_personality_enabled = bool(
		ai_legacy_id_personality_overrides.get(nation_id, false)
	)
	return view


## 在单次 AI tick 内汇总军制与战役规划都会读取的资源和战争状态。
## 不跨日缓存；战役准备索引在计划落定后再按当前 assignment 刷新。
func _enrich_ai_decision_context(
	context: Dictionary,
	resource_evaluation_cache: Dictionary
) -> void:
	var view: AiWorldView = context["view"]
	var nation_id := view.nation_id
	var part_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"ai_force_wars")
	context["wars"] = state.wars_of(nation_id)
	_record_tick_profile_stage("ai_force_wars", part_started)
	var food_evaluation_cache := (
		{}
		if ai_force_resource_cache_disabled
		else resource_evaluation_cache
	)
	part_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"ai_force_food")
	context["food_report"] = _food_security_report(
		nation_id,
		view.friendly_armies,
		food_evaluation_cache
	)
	_record_tick_profile_stage("ai_force_food", part_started)
	const GOLD_FLOWS_CACHE_KEY := "monthly_gold_flows"
	if not resource_evaluation_cache.has(GOLD_FLOWS_CACHE_KEY):
		part_started = (
			Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
		)
		_set_runtime_profile_stage(&"ai_force_gold_flows")
		resource_evaluation_cache[GOLD_FLOWS_CACHE_KEY] = (
			_forecast_trade_and_gold_flows(true)["gold_flows"]
		)
		_record_tick_profile_stage(
			"ai_force_gold_flows", part_started
		)
	part_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	_set_runtime_profile_stage(&"ai_force_gold_report")
	context["gold_report"] = DiplomacyAI.resource_report(
		state,
		nation_id,
		resource_evaluation_cache
	)
	_record_tick_profile_stage("ai_force_gold_report", part_started)


## 战役准备分配可能在规划阶段变化，因此只在计划落定后刷新，并仅供本次规划读取。
func _refresh_ai_campaign_staging_context(
	context: Dictionary
) -> void:
	var view: AiWorldView = context["view"]
	var nation_id := view.nation_id
	var nation := state.nations[nation_id]
	var staged_armies_by_target := {}
	for army in view.friendly_armies:
		if army.size <= 0:
			continue
		var target_city := int(
			nation.campaign_preparation_assignments.get(
				army.id,
				-1
			)
		)
		if (
			target_city < 0
			or not _army_ready_for_campaign_target(
				army,
				nation_id,
				target_city
			)
		):
			continue
		if not staged_armies_by_target.has(target_city):
			staged_armies_by_target[target_city] = [] as Array[Army]
		(
			staged_armies_by_target[target_city]
				as Array[Army]
		).append(army)
	var staged_troops_by_target := {}
	for target_city_value in staged_armies_by_target:
		var target_city := int(target_city_value)
		var staged: Array[Army] = staged_armies_by_target[
			target_city
		]
		staged = _sort_campaign_priority(
			staged,
			nation_id,
			target_city
		)
		staged_armies_by_target[target_city] = staged
		var troops := 0
		for army in staged:
			troops += army.size
		staged_troops_by_target[target_city] = troops
	context["campaign_staged_armies_by_target"] = (
		staged_armies_by_target
	)
	context["campaign_staged_troops_by_target"] = (
		staged_troops_by_target
	)


func _cached_ai_path_field(
	cache_nation_id: int,
	start: int,
	allowed_nation: int = -1,
	block_contested_edges: bool = false,
	use_danger_weight: bool = true,
	allowed_goal: int = -1,
	required_manpower: int = 0
) -> Dictionary:
	if not _ai_path_field_cache_by_nation.has(cache_nation_id):
		_ai_path_field_cache_by_nation[cache_nation_id] = {}
	return AiWorldView.cached_path_field(
		state,
		state.day,
		_ai_path_field_cache_by_nation[cache_nation_id],
		start,
		allowed_nation,
		block_contested_edges,
		use_danger_weight,
		allowed_goal,
		required_manpower
	)


func _strategy_snapshot_for(
	view: AiWorldView,
	diplomacy_cache: Dictionary = {},
	build_profile: Dictionary = {}
) -> StrategicMapSnapshot:
	var snapshot_cache := diplomacy_cache
	var revision := [
		state.ownership_revision,
		state.diplomacy_revision,
		state.fortification_revision,
	]
	if (
		not _ai_strategy_cache.has(view.nation_id)
		or _ai_strategy_revision.get(view.nation_id, []) != revision
	):
		var city_values_revision: Array[int] = [
			state.day,
			state.ownership_revision,
			state.fortification_revision,
		]
		if _ai_base_city_values_revision != city_values_revision:
			_ai_base_city_values = (
				StrategicMapSnapshot.build_base_city_values(
					state
				)
			)
			_ai_base_city_values_revision = city_values_revision
		if _ai_base_edge_values.is_empty():
			_ai_base_edge_values = (
				StrategicMapSnapshot.build_base_edge_values(
					state
				)
			)
		_ai_strategy_cache[view.nation_id] = StrategicMapSnapshot.build(
			view,
			snapshot_cache,
			_ai_base_city_values,
			_ai_base_edge_values,
			build_profile
		)
		_ai_strategy_revision[view.nation_id] = revision
	return _ai_strategy_cache[view.nation_id]


## 返回「今天应决策的国家」及其决策顺序。
## 错峰：当国家数 > 决策周期时，把各国按相位 posmod(nation_id, interval) 均摊到
## 周期内的不同天，每天只决策相位匹配的子集——每国仍每 interval 天决策一次，但
## 计算量从「每周期一次性算全部」摊成「每天算一小批」，消除决策日的算力尖峰。
## force_all=true（议和/宣战后强制重算）或国家数 <= 周期（含 2 国镜像基准）时，
## 退化为「全体今天决策」，保持镜像对称与原有语义。
static func _ai_nation_ids_for_day(
	nation_count: int,
	day: int,
	rotate_order: bool = true,
	decision_interval_days: int = AI_DECISION_INTERVAL_DAYS,
	force_all: bool = false,
	stagger_enabled: bool = true
) -> Array[int]:
	var result: Array[int] = []
	if nation_count <= 0:
		return result
	var interval := maxi(decision_interval_days, 1)
	var stagger := stagger_enabled and nation_count > interval and not force_all
	var today_phase := posmod(day, interval)
	# 先按相位筛出今天到期的国家（错峰关闭时全部到期）。
	var due: Array[int] = []
	for nation_id in range(nation_count):
		if not stagger or posmod(nation_id, interval) == today_phase:
			due.append(nation_id)
	if due.is_empty():
		return result
	# 在到期集合内部轮转起点，保持决策先后顺序的长期公平性。
	var decision_round := day / interval
	var start := posmod(decision_round, due.size()) if rotate_order else 0
	for offset in range(due.size()):
		result.append(due[(start + offset) % due.size()])
	return result


## 把局部失效国家并入当天决策集合，同时保持“全体今天决策”时的既有轮转顺序。
## 这样城市易手不会把 40 国错峰退化成全量重算，也不会让被提前决策国家获得
## 固定靠前顺序。
static func merge_forced_ai_nation_order(
	due_nations: Array[int],
	forced_values: Array,
	nation_count: int,
	day: int,
	rotate_order: bool = true,
	decision_interval_days: int = AI_DECISION_INTERVAL_DAYS
) -> Array[int]:
	var included := {}
	for nation_id in due_nations:
		if nation_id >= 0 and nation_id < nation_count:
			included[nation_id] = true
	for nation_value in forced_values:
		var nation_id := int(nation_value)
		if nation_id >= 0 and nation_id < nation_count:
			included[nation_id] = true
	if included.is_empty():
		return [] as Array[int]
	var full_order := _ai_nation_ids_for_day(
		nation_count,
		day,
		rotate_order,
		decision_interval_days,
		true,
		true
	)
	var result: Array[int] = []
	for nation_id in full_order:
		if included.has(nation_id):
			result.append(nation_id)
	return result


## 满准备是日历截止而不是“恰好轮到本国 AI”时才检查的软提示。
## 错峰调度、占领强制重算或外交备战都可能改变下一次常规决策日；
## 到达120天的交战国必须在当天进入完整军事规划，不能再额外等待。
func _force_mature_campaign_evaluations() -> void:
	for nation in state.nations:
		if (
			not nation.alive
			or state.wars_of(nation.id).is_empty()
			or nation.campaign_preparation_started_day < 0
			or state.day - nation.campaign_preparation_started_day
				< OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
			or _campaign_active_wave_present(nation)
		):
			continue
		_ai_forced_nations[nation.id] = true


func _launch_mature_campaign_offensives() -> void:
	for nation in state.nations:
		if (
			not nation.alive
			or state.wars_of(nation.id).is_empty()
			or nation.campaign_preparation_plan == null
			or nation.campaign_preparation_started_day < 0
			or state.day - nation.campaign_preparation_started_day
				< OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
			or _campaign_active_wave_present(nation)
			or int(_campaign_evaluated_day_by_nation.get(
				nation.id, -1
			)) == state.day
			or (
				state.is_vassal(nation.id)
				and not state.is_in_civil_war(nation.id)
			)
		):
			continue
		var objective_city := nation.campaign_preparation_plan.primary_city
		if objective_city < 0:
			continue
		_manage_campaign_offensive(nation.id)


func _collect_capture_affected_nations(
	old_owner: int,
	claimant: int,
	city_id: int
) -> Array[int]:
	var affected := {}
	for nation_id in [old_owner, claimant]:
		if (
			nation_id >= 0
			and nation_id < state.nations.size()
			and state.nations[nation_id].alive
		):
			affected[nation_id] = true
	if city_id < 0 or city_id >= state.cities.size():
		var result: Array[int] = []
		result.assign(affected.keys())
		result.sort()
		return result
	for neighbor_id in state.neighbors(city_id):
		var neighbor_owner := state.cities[
			neighbor_id
		].owner_nation
		if (
			neighbor_owner >= 0
			and neighbor_owner < state.nations.size()
			and state.nations[neighbor_owner].alive
		):
			affected[neighbor_owner] = true
	var result: Array[int] = []
	result.assign(affected.keys())
	result.sort()
	return result


func _mark_capture_affected_nations(
	old_owner: int,
	claimant: int,
	city_id: int
) -> Array[int]:
	var affected := _collect_capture_affected_nations(
		old_owner,
		claimant,
		city_id
	)
	for nation_id in affected:
		_ai_forced_nations[nation_id] = true
		_frontline_dirty_nations[nation_id] = true
	return affected


func _force_ai_replan_for_capture(
	old_owner: int,
	claimant: int,
	city_id: int
) -> void:
	_mark_capture_affected_nations(
		old_owner,
		claimant,
		city_id
	)


func _flush_same_day_frontline_refresh() -> void:
	if _frontline_dirty_nations.is_empty():
		return
	var dirty_ids: Array[int] = []
	for nation_value in _frontline_dirty_nations.keys():
		var nation_id := int(nation_value)
		if (
			nation_id >= 0
			and nation_id < state.nations.size()
			and state.nations[nation_id].alive
		):
			dirty_ids.append(nation_id)
	_frontline_dirty_nations.clear()
	if dirty_ids.is_empty():
		return
	dirty_ids.sort()
	frontline_refresh_batch_total += 1
	var shared_army_index := (
		AiWorldView.build_army_index(state)
		if ai_policy_overrides.is_empty()
		else {}
	)
	var diplomacy_cache := _seed_trade_forecast({})
	var context_jobs: Array[Dictionary] = []
	var snapshot_army_ids := {}
	for nation_id in dirty_ids:
		if ai_policy_overrides.has(nation_id):
			continue
		var nation := state.nations[nation_id]
		if not nation.alive:
			continue
		var view := _build_ai_view(
			nation_id,
			shared_army_index
		)
		var job := {
			"nation_id": nation_id,
			"view": view,
			"snapshot": null,
			"threat_cache": _threat_travel_cache,
			"previous_defense_plan":
				_ai_defense_plan_cache.get(nation_id),
			"threat": null,
			"defense_plan": null,
		}
		_build_ai_snapshot_context(job, diplomacy_cache)
		job["threat"] = ThreatField.build(
			view,
			_threat_travel_cache
		)
		var defense_plan := CityDefensePlan.build(
			view,
			job["snapshot"],
			job["threat"],
			job["previous_defense_plan"]
		)
		_record_defense_plan_cache_result(defense_plan)
		_ai_defense_plan_cache[nation_id] = defense_plan
		job["defense_plan"] = defense_plan
		context_jobs.append(job)
		for army in view.friendly_armies:
			snapshot_army_ids[army.id] = true
		frontline_refresh_nation_total += 1
		frontline_refresh_build_total += 1
	if context_jobs.is_empty():
		return
	_begin_ai_command_collection(snapshot_army_ids)
	for job in context_jobs:
		var view: AiWorldView = job["view"]
		var snapshot: StrategicMapSnapshot = job["snapshot"]
		var coordinator := ArmyCoordinator.from_view(view)
		var defense_plan: CityDefensePlan = job["defense_plan"]
		var nation_id := int(job["nation_id"])
		var nation := state.nations[nation_id]
		for army in _sort_ai_decision_order(
			state,
			view.friendly_armies,
			snapshot,
			true
		):
			if (
				army.size <= 0
				or _ai_planned_armies.has(army.id)
				or not army.is_line_role()
			):
				continue
			var active_campaign_target := int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			)
			var preparation_target := int(
				nation.campaign_preparation_assignments.get(
					army.id,
					-1
				)
			)
			var campaign_target := (
				active_campaign_target
				if active_campaign_target >= 0
				else preparation_target
			)
			var campaign_locked := (
				campaign_target >= 0
				and (
					nation.war_preparation_target_nation >= 0
					or (
						campaign_target < state.cities.size()
						and state.is_enemy(
							nation_id,
							state.cities[
								campaign_target
							].owner_nation
						)
					)
				)
			)
			if campaign_locked:
				var defense_anchor := army.location_city
				if (
					army.state == Army.State.HOLDING
					and army.move_to != -1
				):
					defense_anchor = _campaign_army_origin(
						army,
						nation_id
					)
				var actual_emergency := (
					state.city_under_siege(defense_anchor)
					if preparation_target >= 0
					else defense_plan.urgent_defense_at(defense_anchor)
				)
				if actual_emergency:
					campaign_locked = false
			if campaign_locked:
				continue
			var line_candidate: ActionCandidate = defense_plan.candidate_for(
				army,
				coordinator
			)
			if (
				line_candidate == null
				or line_candidate.kind not in [
					ActionCandidate.Kind.HOLD,
					ActionCandidate.Kind.REINFORCE,
					ActionCandidate.Kind.RETREAT,
				]
				or not _execute_ai_candidate(
					army,
					line_candidate
				)
			):
				continue
			if (
				line_candidate.kind
					== ActionCandidate.Kind.HOLD
			):
				coordinator.reserve_edge(
					line_candidate.target_edge_a,
					line_candidate.target_edge_b,
					army
				)
			elif line_candidate.target_city != -1:
				coordinator.reserve(
					line_candidate.target_city,
					army
				)
	_commit_ai_command_collection(dirty_ids)


static func _sort_ai_decision_order(
	game_state: GameState,
	armies: Array[Army],
	snapshot: StrategicMapSnapshot,
	strongest_first: bool
) -> Array[Army]:
	var result: Array[Army] = armies.duplicate()
	result.sort_custom(func(a: Army, b: Army) -> bool:
		var a_front := (
			snapshot.frontier_cities.has(a.location_city)
			or snapshot.potential_frontier_cities.has(a.location_city)
		)
		var b_front := (
			snapshot.frontier_cities.has(b.location_city)
			or snapshot.potential_frontier_cities.has(b.location_city)
		)
		if a_front != b_front:
			return a_front and not b_front
		if (
			strongest_first
			and not is_equal_approx(
				ArmyPower.effective(a), ArmyPower.effective(b)
			)
		):
			return ArmyPower.effective(a) > ArmyPower.effective(b)
		return EquivariantOrder.army_less(
			game_state,
			snapshot.nation_id,
			a,
			b
		)
	)
	return result


func _ai_manage_force_structure(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	defense_plan: CityDefensePlan = null,
	roles_reconciled: bool = false,
	resource_evaluation_cache: Dictionary = {},
	decision_context: Dictionary = {}
) -> bool:
	if not state.uses_heightmap:
		# Road clearance is transport-footprint based in every map mode. A heavy
		# formation traverses a narrow route in batches and must not be split into
		# separate Army entities merely to satisfy road capacity.
		return false
	if not roles_reconciled:
		_reconcile_strategic_roles(view.nation_id)
	if defense_plan == null:
		defense_plan = CityDefensePlan.build(
			view,
			snapshot,
			threat
		)
	var nation := state.nations[view.nation_id]
	var assessment: ForceStructureAssessment = _build_force_structure_assessment(
		view,
		defense_plan,
		resource_evaluation_cache,
		decision_context
	)
	if _try_force_structure_demobilization(
		view,
		threat,
		nation,
		assessment
	):
		return true
	# 应急动员（小国最后城市保卫战 / 战争动员窗口）是生死存亡的最后一搏，
	# 允许把人力抽到底，不设战时预留；否则仅在常规战时扩军时预留补员燃料，
	# 使现役军队每月补满编，避免爆兵抽干 manpower_pool 后军团长期缺编。
	var protected_reserve := (
		PEACETIME_MANPOWER_RESERVE
		if assessment.wars.is_empty()
		else (
			0
			if assessment.emergency_recruitment
			else _wartime_manpower_reserve(view.friendly_armies)
		)
	)
	var available_manpower := (
		state.nations[view.nation_id].manpower_pool - protected_reserve
	)
	var recruitment := {}
	if assessment.line_armies < assessment.critical_city_line_target:
		recruitment = {
			"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
			"group_id": -1,
			"reason": "补充核心城市填线槽",
		}
	elif assessment.small_nation_survival:
		recruitment = _small_nation_force_recruitment(
			view.nation_id,
			nation,
			assessment.main_armies
		)
	elif (
		state.is_vassal(view.nation_id)
		and not state.is_in_civil_war(
			view.nation_id
		)
	):
		recruitment = _vassal_force_recruitment(
			view.nation_id,
			nation,
			defense_plan,
			assessment.total_line_target,
			assessment.line_armies,
			assessment.main_armies
		)
	else:
		recruitment = _regular_force_recruitment(
			view,
			snapshot,
			threat,
			defense_plan,
			decision_context,
			assessment.wars,
			assessment.total_line_target,
			assessment.line_armies,
			assessment.main_armies,
			assessment.active_war_mobilization
		)
	return _try_recruit_force_structure(
		view,
		defense_plan,
		nation,
		assessment,
		recruitment,
		available_manpower
	)


func _try_force_structure_demobilization(
	view: AiWorldView,
	threat: ThreatField,
	nation: Nation,
	assessment: ForceStructureAssessment
) -> bool:
	if (
		assessment.wars.is_empty()
		and nation.war_preparation_target_nation < 0
		and _demobilize_excess_peacetime_battle_group(
			view,
			threat,
			assessment.baseline_group_count
		)
	):
		return true
	if assessment.emergency_recruitment:
		return false
	if assessment.food_pressure and _demobilize_for_food_security(
		view,
		threat,
		assessment.food_report,
		assessment.force_structure_target
	):
		return true
	if assessment.gold_pressure and _demobilize_for_gold_security(
		view,
		threat,
		assessment.required_gold_savings,
		assessment.force_structure_target
	):
		return true
	return false


func _try_recruit_force_structure(
	view: AiWorldView,
	defense_plan: CityDefensePlan,
	nation: Nation,
	assessment: ForceStructureAssessment,
	recruitment: Dictionary,
	available_manpower: int
) -> bool:
	var missing_formation_size := int(recruitment.get("size", 0))
	# Defense orders and recruitment share deployment throughput. Do not keep
	# producing at a hub while an earlier assignment is blocked on the first edge.
	if (
		missing_formation_size > 0
		and (
			(
				bool(recruitment.get("create_group", false))
				and defense_plan.pending_deployment_army_count(1) > 0
			)
			or (
				int(recruitment.get("group_id", -1)) < 0
				and not bool(recruitment.get("create_group", false))
				and defense_plan.pending_deployment_army_count(0) > 0
			)
		)
	):
		return false
	var creation_cost := (
		GameState.formation_creation_gold_cost(missing_formation_size)
		if missing_formation_size > 0 else 0
	)
	var reserve_target := int(assessment.gold_reserve.get("reserve_target", 0))
	var gold_growth_allowed := (
		assessment.emergency_recruitment
		or (
			not assessment.gold_pressure
			and nation.treasury_gold - creation_cost >= reserve_target
		)
	)
	var food_recruitment_allowed := (
		not assessment.food_pressure
		and assessment.food_growth_budget >= missing_formation_size
	)
	if assessment.emergency_recruitment:
		food_recruitment_allowed = (
			int(assessment.food_report["stock"]) > 0
			and (
				float(assessment.food_report["monthly_surplus"]) >= 0.0
				or float(assessment.food_report["runway_years"])
					>= EMERGENCY_RECRUITMENT_MIN_RUNWAY_YEARS
			)
		)
	if (
		missing_formation_size > 0
		and available_manpower >= missing_formation_size
		and food_recruitment_allowed
		and gold_growth_allowed
	):
		return _try_create_force_recruitment(
			view.nation_id,
			nation,
			recruitment,
			missing_formation_size,
			assessment.emergency_recruitment,
			assessment.small_nation_survival
		)
	return false


func _build_force_structure_assessment(
	view: AiWorldView,
	defense_plan: CityDefensePlan,
	resource_evaluation_cache: Dictionary,
	decision_context: Dictionary
) -> ForceStructureAssessment:
	var assessment := ForceStructureAssessment.new()
	var nation := state.nations[view.nation_id]
	var current_troops := 0
	for army in view.friendly_armies:
		current_troops += army.size
		if army.is_line_role():
			assessment.line_armies += 1
		elif army.is_main_battle_role():
			assessment.main_armies += 1
	assessment.wars = (
		decision_context["wars"]
		if decision_context.has("wars")
		else state.wars_of(view.nation_id)
	)
	assessment.small_nation_survival = (
		not assessment.wars.is_empty()
		and state.land_cities_of(view.nation_id).size()
			<= SMALL_NATION_SURVIVAL_MAX_CITIES
	)
	assessment.active_war_mobilization = (
		not assessment.wars.is_empty()
		and state.day <= nation.war_mobilization_until_day
		and nation.war_mobilization_target_troops > current_troops
	)
	var city_line_target := defense_plan.line_city_slots
	assessment.critical_city_line_target = (
		defense_plan.line_critical_city_slots
	)
	assessment.total_line_target = (
		city_line_target + defense_plan.line_edge_slots
	)
	if assessment.small_nation_survival:
		# Small nations keep one LINE per city and one mobile MAIN reserve.
		city_line_target = state.land_cities_of(view.nation_id).size()
		assessment.critical_city_line_target = city_line_target
		assessment.total_line_target = city_line_target
	assessment.emergency_recruitment = (
		assessment.small_nation_survival
		or assessment.active_war_mobilization
	)
	assessment.food_report = (
		decision_context["food_report"]
		if decision_context.has("food_report")
		else _food_security_report(
			view.nation_id,
			view.friendly_armies,
			(
				{}
				if ai_force_resource_cache_disabled
				else resource_evaluation_cache
			)
		)
	)
	assessment.food_pressure = bool(
		assessment.food_report["needs_demobilization"]
	)
	var _gold_report: Dictionary = (
		decision_context["gold_report"]
		if decision_context.has("gold_report")
		else DiplomacyAI.resource_report(
			state,
			view.nation_id,
			resource_evaluation_cache
		)
	)
	var gold_flows: Array[Dictionary] = []
	if resource_evaluation_cache.has("monthly_gold_flows"):
		gold_flows = resource_evaluation_cache["monthly_gold_flows"]
	assessment.gold_reserve = gold_reserve_policy(
		state, view.nation_id, gold_flows
	)
	assessment.required_gold_savings = int(
		assessment.gold_reserve.get("required_upkeep_savings", 0)
	)
	var current_financial_month := state.day / DAYS_PER_MONTH
	assessment.gold_pressure = (
		assessment.required_gold_savings > 0
		and nation.last_gold_demobilization_month < current_financial_month
	)
	assessment.food_growth_budget = _food_growth_manpower_budget(
		assessment.food_report
	)
	# Historical wartime groups must not permanently raise the peacetime floor.
	assessment.baseline_group_count = (
		defense_plan.main_reserve_target_group_count()
		if assessment.wars.is_empty()
		else maxi(nation.battle_groups.size(), 1)
	)
	assessment.force_structure_target = (
		assessment.total_line_target
		+ assessment.baseline_group_count
			* (
				BattleGroup.MAX_LIGHT_ARMIES
				+ BattleGroup.MAX_HEAVY_ARMIES
			)
	)
	return assessment


func _try_create_force_recruitment(
	nation_id: int,
	nation: Nation,
	recruitment: Dictionary,
	formation_size: int,
	emergency_recruitment: bool,
	small_nation_survival: bool
) -> bool:
	var creation_site := -1
	var capital_id := nation.capital_city_id
	if _is_available_recruitment_hub(
		nation_id,
		capital_id,
		small_nation_survival
	):
		creation_site = capital_id
	else:
		for warehouse in state.warehouse_cities_of(nation_id):
			if _is_available_recruitment_hub(
				nation_id,
				warehouse.id,
				small_nation_survival
			):
				creation_site = warehouse.id
				break
	if creation_site == -1:
		return false
	var recruitment_reason := str(
		recruitment.get("reason", "资源结余扩军")
	)
	if emergency_recruitment:
		recruitment_reason = "战争生存动员%d编制" % formation_size
	var battle_group_id := int(recruitment.get("group_id", -1))
	var created_group: BattleGroup = null
	if bool(recruitment.get("create_group", false)):
		created_group = state.create_battle_group(nation_id)
		battle_group_id = created_group.id
		recruitment_reason = (
			"战争生存动员%d编制：创建战团%d并补充第一支轻军"
			% [formation_size, battle_group_id]
			if emergency_recruitment
			else "创建战团%d并补充第一支轻军" % battle_group_id
		)
	var created_army := _create_army_for_nation(
		nation_id,
		creation_site,
		formation_size,
		recruitment_reason,
		small_nation_survival,
		battle_group_id
	)
	if created_army == null and created_group != null:
		nation.battle_groups.erase(created_group)
	return created_army != null


func _regular_force_recruitment(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	defense_plan: CityDefensePlan,
	decision_context: Dictionary,
	wars: Array,
	total_line_target: int,
	line_armies: int,
	main_armies: int,
	active_war_mobilization: bool
) -> Dictionary:
	var nation := state.nations[view.nation_id]
	var demand := _campaign_force_recruitment_demand(
		view,
		snapshot,
		threat,
		defense_plan,
		decision_context,
		wars
	)
	var active_offense := bool(demand["active_offense"])
	var campaign_allocation: CampaignAllocationPlan = (
		demand["campaign_allocation"]
	)
	var required_group_count := int(demand["required_group_count"])
	var target_group_count := int(demand["target_group_count"])
	var target_main_armies := maxi(
		target_group_count * (
			BattleGroup.MAX_LIGHT_ARMIES
			+ BattleGroup.MAX_HEAVY_ARMIES
		),
		1
	)
	var main_deficit := maxi(target_main_armies - main_armies, 0)
	var line_deficit := maxi(total_line_target - line_armies, 0)
	var main_deficit_ratio := (
		float(main_deficit) / float(target_main_armies)
	)
	var line_deficit_ratio := (
		float(line_deficit) / float(maxi(total_line_target, 1))
	)
	var recruit_main := (
		main_deficit > 0
		and (
			# Once an offensive has a target, establish its minimum battle groups
			# before filling a potentially much larger set of line slots.
			nation.battle_groups.size() < required_group_count
			or line_deficit <= 0
			or main_deficit_ratio >= line_deficit_ratio
		)
	)
	if recruit_main:
		var needs_new_campaign_group := (
			active_offense
			and nation.battle_groups.size() < required_group_count
			and (
				campaign_allocation == null
				or campaign_allocation.unfilled_group_slots > 0
			)
		)
		return _next_battle_group_recruitment(
			view.nation_id,
			nation.battle_groups.size() < target_group_count,
			needs_new_campaign_group
		)
	if line_deficit > 0:
		return {
			"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
			"group_id": -1,
			"reason": "补充常规填线槽",
		}
	return _next_battle_group_recruitment(
		view.nation_id,
		active_war_mobilization
			or (
				active_offense
				and nation.battle_groups.size() < required_group_count
			)
	)


func _campaign_force_recruitment_demand(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	defense_plan: CityDefensePlan,
	decision_context: Dictionary,
	wars: Array
) -> Dictionary:
	var nation := state.nations[view.nation_id]
	var active_offense := (
		nation.war_preparation_target_nation >= 0
		or not wars.is_empty()
	)
	var force_demand_targets: Array[int] = []
	var campaign_allocation: CampaignAllocationPlan = null
	if active_offense:
		force_demand_targets = _campaign_force_demand_targets(
			view.nation_id,
			snapshot
		)
	var required_group_count := 1
	if (
		active_offense
		and state.uses_heightmap
		and not force_demand_targets.is_empty()
	):
		campaign_allocation = _plan_campaign_allocation(
			view.nation_id,
			force_demand_targets[0],
			force_demand_targets,
			defense_plan,
			ArmyCoordinator.from_view(view),
			view,
			nation.war_preparation_target_nation >= 0
				and wars.is_empty()
		)
		decision_context["campaign_allocation_plan"] = campaign_allocation
		required_group_count = maxi(
			campaign_allocation.required_group_count, 1
		)
		if campaign_allocation.assigned_group_count > 0:
			_apply_campaign_plan_atomic(view.nation_id, campaign_allocation)
	elif active_offense:
		required_group_count = _campaign_required_group_count(
			view.nation_id, force_demand_targets, threat
		)
	var target_group_count := (
		maxi(nation.battle_groups.size(), required_group_count)
		if active_offense
		else defense_plan.main_reserve_target_group_count()
	)
	return {
		"active_offense": active_offense,
		"campaign_allocation": campaign_allocation,
		"required_group_count": required_group_count,
		"target_group_count": target_group_count,
	}


func _small_nation_force_recruitment(
	nation_id: int,
	nation: Nation,
	main_armies: int
) -> Dictionary:
	# One light MAIN is the mobile reserve; existing wartime groups stay intact.
	if main_armies >= SMALL_NATION_MOBILE_RESERVE_ARMIES:
		return {}
	var reserve_group_id := -1
	for group in nation.battle_groups:
		if state.battle_group_members(nation_id, group.id).is_empty():
			reserve_group_id = group.id
			break
	return {
		"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
		"group_id": reserve_group_id,
		"create_group": reserve_group_id < 0,
		"reason": "小国补充机动预备队",
	}


func _vassal_force_recruitment(
	nation_id: int,
	nation: Nation,
	defense_plan: CityDefensePlan,
	total_line_target: int,
	line_armies: int,
	main_armies: int
) -> Dictionary:
	var line_deficit := maxi(total_line_target - line_armies, 0)
	# Each priority defense city demands a complete MAIN battle group.
	var target_group_count := defense_plan.main_reserve_target_group_count()
	var target_main_armies := (
		target_group_count
		* (BattleGroup.MAX_LIGHT_ARMIES + BattleGroup.MAX_HEAVY_ARMIES)
	)
	var main_deficit := maxi(target_main_armies - main_armies, 0)
	var main_deficit_ratio := (
		float(main_deficit) / float(target_main_armies)
	)
	var line_deficit_ratio := (
		float(line_deficit) / float(maxi(total_line_target, 1))
	)
	if (
		main_deficit > 0
		and (
			line_deficit <= 0
			or main_deficit_ratio >= line_deficit_ratio
		)
	):
		return _next_battle_group_recruitment(
			nation_id,
			nation.battle_groups.size() < target_group_count
		)
	if line_deficit > 0:
		return {
			"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
			"group_id": -1,
			"reason": "藩王补充填线槽",
		}
	return {}


## 和平时期战团数量由当前防区规模决定，而不是由历次战争动员的历史峰值决定。
## 一次撤销一个完整的、已回到安全本土的多余战团，并让该国下一日继续重算；
## 保持战团原子性，避免只裁重军后留下多个残缺战团继续挤在重点城市。
func _demobilize_excess_peacetime_battle_group(
	view: AiWorldView,
	threat: ThreatField,
	target_group_count: int
) -> bool:
	var nation := state.nations[view.nation_id]
	if nation.battle_groups.size() <= target_group_count:
		return false
	var groups: Array[BattleGroup] = (
		nation.battle_groups.duplicate()
	)
	# 后组建的战争动员战团优先复员；同日建立时组号仍是国家内部的
	# 持久编制序，不读取军队数组顺序。
	groups.sort_custom(func(a: BattleGroup, b: BattleGroup) -> bool:
		if a.created_day != b.created_day:
			return a.created_day > b.created_day
		return a.id > b.id
	)
	for group in groups:
		var members := state.battle_group_members(
			view.nation_id,
			group.id
		)
		if members.is_empty():
			nation.battle_groups.erase(group)
			_ai_forced_nations[view.nation_id] = true
			return true
		var safe_to_demobilize := true
		for army in members:
			if (
				army.state not in [
					Army.State.IDLE,
					Army.State.RECOVERING,
				]
				or army.location_city < 0
				or state.cities[army.location_city].owner_nation
					!= view.nation_id
				or state.city_under_siege(army.location_city)
				or threat.threat_at(army.location_city)
					>= ArmyPower.effective(army)
			):
				safe_to_demobilize = false
				break
		if not safe_to_demobilize:
			continue
		var returned := 0
		for army in members.duplicate():
			returned += army.size
			nation.campaign_preparation_assignments.erase(army.id)
			nation.campaign_attack_assignments.erase(army.id)
			nation.campaign_attack_echelons.erase(army.id)
			nation.campaign_launched_armies.erase(army.id)
			_disband_army(
				army,
				"和平防区复员：撤销多余战团%d" % group.id
			)
		nation.battle_groups.erase(group)
		nation.ai_last_force_action = (
			ActionCandidate.Kind.DISBAND_ARMY
		)
		nation.ai_last_force_day = state.day
		nation.ai_last_force_reason = (
			"和平防区复员：战团%d返还%d人，当前防区保留%d个战团"
			% [group.id, returned, target_group_count]
		)
		_ai_forced_nations[view.nation_id] = true
		return true
	return false


func _next_battle_group_recruitment(
	nation_id: int,
	allow_new_group: bool = true,
	prioritize_new_group: bool = false
) -> Dictionary:
	var nation := state.nations[nation_id]
	# 攻势明确需要多个独立方向/梯队时，先建立战团骨架，再逐团补齐。
	# 否则“补满第一团才建第二团”会让决定性战役等待数百天。
	if allow_new_group and prioritize_new_group:
		return {
			"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
			"group_id": -1,
			"create_group": true,
			"reason": "攻势扩编：创建新战团并补充第一支轻军",
		}
	for group in nation.battle_groups:
		var light_count := 0
		var heavy_count := 0
		for member in state.battle_group_members(
			nation_id,
			group.id
		):
			if member.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE:
				light_count += 1
			elif member.max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
				heavy_count += 1
		if light_count < BattleGroup.MAX_LIGHT_ARMIES:
			return {
				"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
				"group_id": group.id,
				"reason": "战团%d补充第%d支轻军" % [
					group.id,
					light_count + 1,
				],
			}
		if heavy_count < BattleGroup.MAX_HEAVY_ARMIES:
			return {
				"size": GameState.INITIAL_HEAVY_ARMY_SIZE,
				"group_id": group.id,
				"reason": "战团%d补充重军" % group.id,
			}
	if not allow_new_group:
		return {}
	return {
		"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
		"group_id": -1,
		"create_group": true,
		"reason": "创建新战团并补充第一支轻军",
	}


func _clear_campaign_attack_plan(nation_id: int) -> void:
	var nation := state.nations[nation_id]
	nation.campaign_attack_assignments.clear()
	nation.campaign_attack_echelons.clear()
	nation.campaign_active_echelons.clear()
	nation.campaign_launched_armies.clear()
	nation.campaign_echelon_started_days.clear()
	nation.campaign_post_capture_plans.clear()
	nation.campaign_launched_attack_multiplier = 1.0
	nation.campaign_launched_bonus_days = 0
	nation.campaign_plan_targets.clear()
	nation.campaign_plan_wave = -1
	nation.campaign_plan_primary_city = -1


func _reconcile_campaign_active_wave(nation_id: int) -> void:
	if nation_id < 0 or nation_id >= state.nations.size():
		return
	var nation := state.nations[nation_id]
	if nation.campaign_plan_targets.is_empty():
		if (
			not nation.campaign_attack_assignments.is_empty()
			or not nation.campaign_attack_echelons.is_empty()
			or not nation.campaign_active_echelons.is_empty()
			or not nation.campaign_launched_armies.is_empty()
			or not nation.campaign_echelon_started_days.is_empty()
			or not nation.campaign_post_capture_plans.is_empty()
			or nation.campaign_plan_wave >= 0
		):
			_clear_campaign_attack_plan(nation_id)
		return
	var active := false
	# 默认把快照中已无实体承载的 assignment 视为陈旧；扫描到仍合法的
	# 待发成员或仍执行原目标的已发成员时再从集合移除。
	var stale_assignment_ids := {}
	for army_id_value in nation.campaign_attack_assignments:
		stale_assignment_ids[int(army_id_value)] = true
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or not nation.campaign_attack_assignments.has(army.id)
		):
			continue
		var assigned_target := int(
			nation.campaign_attack_assignments.get(army.id, -1)
		)
		var target_still_enemy := (
			assigned_target >= 0
			and assigned_target < state.cities.size()
			and state.is_enemy(
				nation_id, state.cities[assigned_target].owner_nation
			)
		)
		var launched := nation.campaign_launched_armies.has(army.id)
		# launched 只是“曾经从本波发射”的历史集合；真正的执行态必须仍是
		# 对同一目标的 ATTACK。紧急防守或撤退会覆盖 Army 的 AI 命令，若仍仅
		# 凭 MOVING/FIGHTING 判活，旧波会把下一轮攻势永久挡住。
		if launched and not (
			target_still_enemy
			and army.state in [Army.State.MOVING, Army.State.FIGHTING]
			and army.ai_action == ActionCandidate.Kind.ATTACK
			and army.ai_target_city == assigned_target
		):
			continue
		if target_still_enemy:
			# 未发射梯队可能仍在去集结地的途中，因此只要实体和敌对目标
			# 有效就保留；它是否足以让整波继续存活由下面的 readiness 判定。
			stale_assignment_ids.erase(army.id)
		if (
			target_still_enemy
			and launched
		):
			active = true
			continue
		# 已冻结但尚未发射的后续梯队仍属于 active wave；只要它的
		# 目标有效且确实能从当前位置出发，就不能被下一波抢占。
		var target_city := assigned_target
		if (
			not nation.campaign_launched_armies.has(army.id)
			and target_city >= 0
			and target_city < state.cities.size()
			and state.is_enemy(
				nation_id, state.cities[target_city].owner_nation
			)
			and _army_ready_for_campaign_target(
				army, nation_id, target_city
			)
			and _campaign_army_can_attack_target(
				army, nation_id, target_city
			)
		):
			active = true
	for army_id in stale_assignment_ids:
		nation.campaign_attack_assignments.erase(army_id)
		nation.campaign_attack_echelons.erase(army_id)
		nation.campaign_launched_armies.erase(army_id)
	# 部分方向已无任何成员时立即释放其 target/echelon/后续计划；否则
	# 其他方向尚在执行会让空目标一直残留到整波结束。
	for target_value in nation.campaign_plan_targets.duplicate():
		var target_city := int(target_value)
		if not nation.campaign_attack_assignments.values().has(target_city):
			_remove_campaign_target(nation_id, target_city)
	if not active:
		_clear_campaign_attack_plan(nation_id)


func _ensure_campaign_attack_plan(
	nation_id: int,
	primary_city: int
) -> bool:
	var nation := state.nations[nation_id]
	var desired_wave := nation.campaign_offensive_count + 1
	if (
		nation.campaign_plan_wave == desired_wave
		and nation.campaign_plan_primary_city == primary_city
		and not nation.campaign_attack_assignments.is_empty()
		and _campaign_primary_assignment_ready(
			nation_id,
			primary_city
		)
	):
		return true
	if state.uses_heightmap:
		return false
	_clear_campaign_attack_plan(nation_id)
	if (
		primary_city < 0
		or primary_city >= state.cities.size()
	):
		return false
	var attackers := _campaign_staged_armies(
		nation_id,
		primary_city
	)
	var primary_required := DiplomacyAI.required_assault_troops(
		state,
		nation_id,
		primary_city
	)
	var primary_limit := int(ceil(
		float(primary_required)
			* CAMPAIGN_TARGET_COMMIT_RATIO
	))
	var primary_committed := 0
	var remaining: Array[Army] = []
	for army in attackers:
		if primary_committed < primary_limit:
			nation.campaign_attack_assignments[army.id] = (
				primary_city
			)
			primary_committed += army.size
		else:
			remaining.append(army)
	if primary_committed < primary_required:
		_clear_campaign_attack_plan(nation_id)
		return false
	nation.campaign_plan_targets.append(primary_city)

	if not remaining.is_empty():
		var target_nation := (
			state.cities[primary_city].owner_nation
		)
		var eligible_by_target := {}
		for army in remaining:
			var origin := _campaign_army_origin(
				army,
				nation_id
			)
			if origin < 0:
				continue
			for neighbor in state.neighbors(origin):
				var edge := state.edge_of(origin, neighbor)
				if (
					neighbor == primary_city
					or edge == null
					or edge.max_manpower <= 0
					or state.cities[neighbor].owner_nation
						!= target_nation
				):
					continue
				if not eligible_by_target.has(neighbor):
					eligible_by_target[neighbor] = (
						[] as Array[Army]
					)
				(
					eligible_by_target[neighbor]
					as Array[Army]
				).append(army)
		var view := _build_ai_view(nation_id)
		var snapshot := _strategy_snapshot_for(view)
		var target_ids := eligible_by_target.keys()
		target_ids.sort_custom(func(a_value: Variant, b_value: Variant) -> bool:
			var a := int(a_value)
			var b := int(b_value)
			var score_a := snapshot.value_of_city(a)
			var score_b := snapshot.value_of_city(b)
			if not is_equal_approx(score_a, score_b):
				return score_a > score_b
			return EquivariantOrder.city_id_less(
				state,
				nation_id,
				a,
				b,
				primary_city
			)
		)
		for target_id_value in target_ids:
			if nation.campaign_plan_targets.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS:
				break
			var target_id := int(target_id_value)
			var required := (
				DiplomacyAI.required_assault_troops(
					state,
					nation_id,
					target_id
				)
			)
			var target_armies: Array[Army] = []
			var target_available := 0
			for army in remaining:
				if not (
					eligible_by_target[target_id]
					as Array[Army]
				).has(army):
					continue
				target_armies.append(army)
				target_available += army.size
			if target_available < required:
				continue
			var target_limit := int(ceil(
				float(required)
					* CAMPAIGN_TARGET_COMMIT_RATIO
			))
			var target_committed := 0
			for army in target_armies:
				if target_committed >= target_limit:
					break
				nation.campaign_attack_assignments[army.id] = target_id
				target_committed += army.size
				remaining.erase(army)
			nation.campaign_plan_targets.append(target_id)
	# 已进入集结区但未承担独立方向的军队全部作为主目标后续梯队，
	# 避免首轮失败后重新等待 90 天国家级攻势周期。
	for army in remaining:
		if not nation.campaign_attack_assignments.has(army.id):
			nation.campaign_attack_assignments[army.id] = primary_city
	_build_campaign_echelons(nation_id)
	nation.campaign_plan_wave = desired_wave
	nation.campaign_plan_primary_city = primary_city
	return true


func _build_campaign_echelons(nation_id: int) -> void:
	var nation := state.nations[nation_id]
	nation.campaign_attack_echelons.clear()
	nation.campaign_active_echelons.clear()
	nation.campaign_launched_armies.clear()
	nation.campaign_echelon_started_days.clear()
	for target_city in nation.campaign_plan_targets:
		var assigned: Array[Army] = []
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and int(
					nation.campaign_attack_assignments.get(
						army.id,
						-1
					)
				) == target_city
			):
				assigned.append(army)
		var prioritized := _sort_campaign_priority(
			assigned, nation_id, target_city
		)
		assigned.clear()
		for army in prioritized:
			if _army_ready_for_campaign_target(
				army,
				nation_id,
				target_city
			):
				assigned.append(army)
		for army in prioritized:
			if not assigned.has(army):
				assigned.append(army)
		var required := DiplomacyAI.required_assault_troops(
			state,
			nation_id,
			target_city
		)
		var echelon := 0
		var echelon_troops := 0
		for army in assigned:
			nation.campaign_attack_echelons[army.id] = echelon
			echelon_troops += army.size
			if echelon_troops >= required:
				echelon += 1
				echelon_troops = 0
		nation.campaign_active_echelons[target_city] = -1


func _campaign_primary_assignment_ready(
	nation_id: int,
	primary_city: int
) -> bool:
	var nation := state.nations[nation_id]
	var ready_troops := 0
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) != primary_city
			or not _army_ready_for_campaign_target(
				army,
				nation_id,
				primary_city
			)
		):
			continue
		ready_troops += army.size
	if (
		state.uses_heightmap
		and nation.campaign_preparation_group_assignments.has(
			primary_city
		)
	):
		return ready_troops > 0
	return ready_troops >= (
		DiplomacyAI.required_assault_troops(
			state,
			nation_id,
			primary_city
		)
	)


func _campaign_staged_armies(
	nation_id: int,
	target_city: int
) -> Array[Army]:
	var result: Array[Army] = []
	var staging := DiplomacyAI.staging_cities_for_objective(
		state,
		nation_id,
		target_city
	)
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		if (
			army.state == Army.State.IDLE
			and staging.has(army.location_city)
		) or (
			army.state == Army.State.HOLDING
			and (
				(
					army.move_from == target_city
					and staging.has(army.move_to)
				)
				or (
					army.move_to == target_city
					and staging.has(army.move_from)
				)
			)
		):
			result.append(army)
	return _sort_campaign_priority(result, nation_id, target_city)


## 战役集结优先级：兵力多者优先，等兵力时按“距目标更近者优先”。
## 距离取整数边长最短路（求和精确、与松弛顺序无关），是镜像不变量，
## 因此镜像对称世界里左右两军会做出镜像一致的梯队编排；
## 相同兵力且等距时按势力局部物理位置收尾，保证镜像等变。
func _sort_campaign_priority(
	armies: Array[Army],
	nation_id: int,
	target_city: int
) -> Array[Army]:
	var field := _cached_ai_path_field(
		nation_id,
		target_city,
		nation_id,
		false,
		false,
		target_city
	)
	var dist: Dictionary = field["dist"]
	var distance_of := func(army: Army) -> float:
		return float(dist.get(
			_campaign_army_origin(army, nation_id),
			INF
		))
	var sorted: Array[Army] = armies.duplicate()
	sorted.sort_custom(func(a: Army, b: Army) -> bool:
		if a.size != b.size:
			return a.size > b.size
		var da: float = distance_of.call(a)
		var db: float = distance_of.call(b)
		if not is_equal_approx(da, db):
			return da < db
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a,
			b,
			target_city
		)
	)
	return sorted


func _campaign_army_origin(
	army: Army,
	nation_id: int
) -> int:
	if army.state == Army.State.IDLE:
		return army.location_city
	if army.state != Army.State.HOLDING:
		return -1
	var origin := army.move_from
	if not state.has_military_access(
		nation_id,
		state.cities[origin].owner_nation
	):
		origin = army.move_to
	return origin


func _can_use_army_for_offensive(
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator,
	army: Army,
	target_city: int
) -> bool:
	if defense_plan == null:
		return true
	if state.uses_heightmap:
		return defense_plan.can_join_offensive(
			army,
			target_city,
			true
		)
	return (
		coordinator == null
		or defense_plan.can_redeploy(army, coordinator)
	)


func _campaign_assignment_overrides_defensive_lock(
	nation_id: int,
	army: Army,
	target_city: int
) -> bool:
	return (
		state.uses_heightmap
		and army != null
		and army.is_main_battle_role()
		and int(
			state.nations[nation_id]
				.campaign_preparation_assignments.get(army.id, -1)
		) == target_city
	)


func _can_assign_campaign_preparation_army(
	nation_id: int,
	army: Army,
	target_city: int
) -> bool:
	var nation := state.nations[nation_id]
	if (
		state.uses_heightmap
		and army.battle_group_id >= 0
	):
		var group_target := (
			nation.campaign_preparation_plan.target_for_group(
				army.battle_group_id
			)
			if nation.campaign_preparation_plan != null
			else -1
		)
		if group_target >= 0 and group_target != target_city:
			return false
		if group_target == -2:
			return false
	var preparation_target := int(
		nation.campaign_preparation_assignments.get(
			army.id,
			-1
		)
	)
	if preparation_target >= 0:
		return preparation_target == target_city
	var attack_target := int(
		nation.campaign_attack_assignments.get(
			army.id,
			-1
		)
	)
	return (
		attack_target < 0
		or attack_target == target_city
		or (
			not state.uses_heightmap
			and nation.campaign_launched_armies.has(army.id)
		)
	)


func _assign_campaign_preparation_army(
	nation_id: int,
	army: Army,
	target_city: int
) -> void:
	var nation := state.nations[nation_id]
	# 准备态与 active wave 是两个互不相交的 write-set。上一波成员在
	# planner 中已整团排除，这里绝不能为了下一波删除执行态。
	if (
		state.uses_heightmap
		and nation.campaign_attack_assignments.has(army.id)
	):
		return
	if not state.uses_heightmap:
		var attack_target := int(
			nation.campaign_attack_assignments.get(army.id, -1)
		)
		if attack_target >= 0 and attack_target != target_city:
			nation.campaign_attack_assignments.erase(army.id)
			nation.campaign_attack_echelons.erase(army.id)
			nation.campaign_launched_armies.erase(army.id)
	if army.is_line_role():
		army.clear_line_assignment()
	nation.campaign_preparation_assignments[army.id] = target_city


func _campaign_theater_required_manpower(
	nation_id: int
) -> int:
	# Theater reachability uses the largest formation's travel time. Dijkstra
	# converts this to the common 5000 clearance footprint while charging extra
	# batches on narrow roads, so heavy formations remain mobile but not free.
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
		):
			return GameState.INITIAL_HEAVY_ARMY_SIZE
	return GameState.INITIAL_LIGHT_ARMY_SIZE


func _campaign_force_demand_targets(
	nation_id: int,
	snapshot: StrategicMapSnapshot = null
) -> Array[int]:
	var nation := state.nations[nation_id]
	var candidates: Array[int] = []
	if nation.campaign_preparation_plan != null:
		for target_city in (
			nation.campaign_preparation_plan.candidate_target_ids
		):
			if not candidates.has(target_city):
				candidates.append(target_city)
	else:
		for target_city in nation.campaign_preparation_targets:
			if not candidates.has(target_city):
				candidates.append(target_city)
	if candidates.is_empty():
		for target_city in nation.campaign_plan_targets:
			if not candidates.has(target_city):
				candidates.append(target_city)
	if (
		candidates.is_empty()
		and nation.war_preparation_objective_city >= 0
	):
		candidates.append(nation.war_preparation_objective_city)
	if candidates.is_empty():
		for enemy_id in state.wars_of(nation_id):
			var objective := state.war_objective(
				nation_id,
				enemy_id
			)
			if (
				not objective.is_empty()
				and int(objective.get("attacker", -1))
					== nation_id
			):
				var objective_city := int(
					objective.get("city_id", -1)
				)
				if (
					objective_city >= 0
					and not candidates.has(objective_city)
				):
					candidates.append(objective_city)
	if (
		candidates.is_empty()
		and snapshot != null
		and snapshot.campaign_target >= 0
	):
		candidates.append(snapshot.campaign_target)
	# 战时扩军不能只看首次建立的计划；把当前所有合法前线按战略
	# 优先级补入需求，新的主战团建成后动态计划才能扩宽到这些方向。
	if snapshot != null and not state.wars_of(nation_id).is_empty():
		for target_city in snapshot.priority_enemy_cities:
			if candidates.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS:
				break
			if not candidates.has(target_city):
				candidates.append(target_city)
	var result: Array[int] = []
	for target_city in candidates:
		if result.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS:
			break
		if (
			not _campaign_force_demand_target_valid(
				nation_id,
				target_city
			)
			or result.has(target_city)
		):
			continue
		if DiplomacyAI.staging_cities_for_objective(
			state,
			nation_id,
			target_city
		).is_empty():
			continue
		result.append(target_city)
	return result


func _campaign_force_demand_target_valid(
	nation_id: int,
	target_city: int
) -> bool:
	if (
		target_city < 0
		or target_city >= state.cities.size()
	):
		return false
	var owner := state.cities[target_city].owner_nation
	return (
		state.is_enemy(nation_id, owner)
		or owner
			== state.nations[
				nation_id
			].war_preparation_target_nation
	)


func _campaign_required_group_count(
	nation_id: int,
	targets: Array[int],
	threat: ThreatField = null
) -> int:
	var required_groups := 0
	for target_city in targets:
		var demand := _campaign_target_group_demand(
			nation_id,
			target_city,
			threat
		)
		required_groups += int(demand.get("groups", 0))
	return clampi(required_groups, 1, CAMPAIGN_MAX_WARTIME_GROUPS)


func _campaign_target_group_demand(
	nation_id: int,
	target_city: int,
	threat: ThreatField = null
) -> Dictionary:
	if not _campaign_force_demand_target_valid(
		nation_id,
		target_city
	):
		return {}
	var staging := DiplomacyAI.staging_cities_for_objective(
		state,
		nation_id,
		target_city
	)
	if staging.is_empty():
		return {}
	var route_capacity := _campaign_route_group_capacity(
		target_city,
		staging
	)
	var route_manpower := int(
		route_capacity.get("manpower", 0)
	)
	var route_power := float(route_capacity.get("power", 0.0))
	if route_manpower <= 0 or route_power <= 0.0:
		return {}
	var required_manpower := (
		DiplomacyAI.objective_assault_troops(
			state,
			nation_id,
			target_city
		)
	)
	var required_power := (
		_campaign_objective_defense_power(
			nation_id,
			target_city,
			threat
		)
		* _campaign_attack_ratio_threshold(nation_id)
		/ OFFENSIVE_BONUS_MAX_MULTIPLIER
	)
	var groups_by_manpower := int(ceil(
		float(required_manpower) / float(route_manpower)
	))
	var groups_by_power := int(ceil(
		required_power / route_power
	))
	var defender_owner := state.cities[target_city].owner_nation
	var decisive_minimum := (
		CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS
		if defender_owner >= 0
			and state.land_cities_of(defender_owner).size() <= 1
		else 1
	)
	var assault_groups := maxi(
		maxi(groups_by_manpower, groups_by_power), decisive_minimum
	)
	return {
		# 每个方向不仅形成第一批接敌兵力，还冻结一个独立战团梯队。
		# 八路目标因此自然对应最多十六团，而非靠发射阶段临时加码。
		"groups": assault_groups * CAMPAIGN_PREPARED_ECHELONS,
		"assault_groups": assault_groups,
		"is_decisive": decisive_minimum
			>= CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS,
		"required_manpower": required_manpower,
		"required_power": required_power,
		"route_group_manpower": route_manpower,
		"route_group_power": route_power,
	}


func _campaign_route_group_capacity(
	target_city: int,
	staging: Array[int]
) -> Dictionary:
	var entry_capacity := 0
	for staging_city in staging:
		var edge := state.edge_of(staging_city, target_city)
		if edge != null:
			entry_capacity = maxi(
				entry_capacity,
				edge.max_manpower
			)
	var manpower := 0
	var power := 0.0
	if entry_capacity >= GameState.INITIAL_LIGHT_ARMY_SIZE:
		manpower += (
			BattleGroup.MAX_LIGHT_ARMIES
			* GameState.INITIAL_LIGHT_ARMY_SIZE
		)
		power += float(
			BattleGroup.MAX_LIGHT_ARMIES
			* GameState.INITIAL_LIGHT_ARMY_SIZE
		)
	# Demand uses effective first-contact capacity, not eventual transport
	# reachability. A heavy formation can traverse a narrow route in packets,
	# but only contributes its full 15000 here when the entry road can deploy it
	# without serial delay; this keeps narrow-front assault sizing conservative.
	if entry_capacity >= GameState.INITIAL_HEAVY_ARMY_SIZE:
		manpower += (
			BattleGroup.MAX_HEAVY_ARMIES
			* GameState.INITIAL_HEAVY_ARMY_SIZE
		)
		power += float(
			BattleGroup.MAX_HEAVY_ARMIES
			* GameState.INITIAL_HEAVY_ARMY_SIZE
		)
	return {
		"entry_capacity": entry_capacity,
		"manpower": manpower,
		"power": power,
	}


func _campaign_objective_in_current_theater(
	nation_id: int,
	proposed_city: int,
	context_view: AiWorldView = null,
	context_snapshot: StrategicMapSnapshot = null
) -> int:
	var nation := state.nations[nation_id]
	var anchor := nation.campaign_theater_anchor_city
	if (
		anchor < 0
		or anchor >= state.cities.size()
		or proposed_city < 0
		or proposed_city >= state.cities.size()
	):
		return proposed_city
	if (
		state.is_enemy(
			nation_id,
			state.cities[anchor].owner_nation
		)
		and not DiplomacyAI.staging_cities_for_objective(
			state,
			nation_id,
			anchor
		).is_empty()
	):
		return anchor
	var view := (
		context_view
		if context_view != null
		else _build_ai_view(nation_id)
	)
	var snapshot := (
		context_snapshot
		if context_snapshot != null
		else _strategy_snapshot_for(view)
	)
	var field := view.path_field(
		anchor,
		-1,
		false,
		false,
		-1,
		_campaign_theater_required_manpower(nation_id)
	)
	var distances: Dictionary = field["dist"]
	var proposed_distance := float(
		distances.get(proposed_city, INF)
	)
	if (
		proposed_distance
			<= CAMPAIGN_THEATER_MAX_TRANSFER_COST
		and not DiplomacyAI.staging_cities_for_objective(
			state,
			nation_id,
			proposed_city
		).is_empty()
	):
		return proposed_city
	var best_city := -1
	var best_score := -INF
	for city_id in snapshot.priority_enemy_cities:
		var city := state.cities[city_id]
		if (
			not state.is_enemy(
				nation_id,
				city.owner_nation
			)
			or DiplomacyAI.staging_cities_for_objective(
				state,
				nation_id,
				city.id
			).is_empty()
		):
			continue
		var distance := float(
			distances.get(city.id, INF)
		)
		if distance > CAMPAIGN_THEATER_MAX_TRANSFER_COST:
			continue
		var score := (
			snapshot.value_of_offense(city.id)
			- distance * 0.15
		)
		if (
			score > best_score
			or (
				is_equal_approx(score, best_score)
				and EquivariantOrder.city_id_less(
					state,
					nation_id,
					city.id,
					best_city,
					anchor
				)
			)
		):
			best_city = city.id
			best_score = score
	return best_city if best_city >= 0 else proposed_city


func _ensure_campaign_preparation_plan(
	nation_id: int,
	primary_city: int,
	defense_plan: CityDefensePlan = null,
	coordinator: ArmyCoordinator = null,
	roles_reconciled: bool = false,
	decision_context: Dictionary = {}
) -> bool:
	if state.uses_heightmap:
		# attack_* 只表示上一支已冻结/已发射波次。先终结已经没有在途、
		# 作战或待发梯队的旧波，随后 planner 才能安全复用这些战团。
		_reconcile_campaign_active_wave(nation_id)
		return _ensure_group_campaign_preparation_plan(
			nation_id, primary_city, defense_plan, coordinator,
			roles_reconciled, decision_context
		)
	var nation := state.nations[nation_id]
	var plan_valid := (
		not nation.campaign_preparation_targets.is_empty()
		and nation.campaign_preparation_targets.has(primary_city)
	)
	if plan_valid:
		for target_city in nation.campaign_preparation_targets:
			if (
				target_city < 0
				or target_city >= state.cities.size()
				or not state.is_enemy(
					nation_id,
					state.cities[target_city].owner_nation
				)
			):
				plan_valid = false
				break
	if plan_valid:
		return true

	_clear_campaign_preparation_plan(nation_id)
	if (
		primary_city < 0
		or primary_city >= state.cities.size()
		or not state.is_enemy(
			nation_id,
			state.cities[primary_city].owner_nation
		)
	):
		return false
	var view := (
		defense_plan.view
		if (
			defense_plan != null
			and defense_plan.view != null
		)
		else _build_ai_view(nation_id)
	)
	var snapshot := (
		defense_plan.snapshot
		if (
			defense_plan != null
			and defense_plan.snapshot != null
		)
		else _strategy_snapshot_for(view)
	)
	var target_candidates: Array[int] = [primary_city]
	for target_city in snapshot.priority_enemy_cities:
		if target_candidates.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS:
			break
		if (
			target_city == primary_city
			or not state.is_enemy(
				nation_id,
				state.cities[target_city].owner_nation
			)
			or DiplomacyAI.staging_cities_for_objective(
				state,
				nation_id,
				target_city
			).is_empty()
		):
			continue
		target_candidates.append(target_city)
	var threat := (
		defense_plan.threat
		if (
			defense_plan != null
			and defense_plan.threat != null
		)
		else ThreatField.build(
			view,
			_threat_travel_cache
		)
	)

	var readiness := _campaign_preparation_readiness(
		nation_id,
		primary_city,
		view
	)
	var available: Array[Army] = readiness["available"]
	var parallel_capacity := int(readiness["parallel_capacity"])
	var defense_assigned_armies := 0
	for target_index in range(target_candidates.size()):
		var target_city := target_candidates[target_index]
		var staging := DiplomacyAI.staging_cities_for_objective(
			state,
			nation_id,
			target_city
		)
		if staging.is_empty():
			continue
		var ranked: Array[Dictionary] = _rank_campaign_preparation_armies(
			nation_id,
			target_city,
			staging,
			available,
			view,
			defense_plan,
			coordinator
		)
		var future_target_slots := mini(
			mini(
				target_candidates.size(),
				parallel_capacity
			) - target_index - 1,
			maxi(available.size() - 1, 0)
		)
		var selection_limit := maxi(
			available.size() - maxi(future_target_slots, 0),
			1
		)
		if not state.uses_heightmap:
			_assign_grid_campaign_target(
				nation_id,
				target_city,
				ranked,
				selection_limit,
				threat,
				nation,
				available
			)
			continue
		var selection := _select_campaign_preparation_armies(
			nation_id,
			target_city,
			ranked,
			selection_limit,
			defense_plan,
			defense_assigned_armies
		)
		var selected: Array[Army] = selection["armies"]
		var selected_troops := int(selection["troops"])
		defense_assigned_armies = int(selection["defense_assigned"])
		if (
			selected_troops <= 0
			or (
				target_city != primary_city
				and target_index >= parallel_capacity
			)
		):
			continue
		nation.campaign_preparation_targets.append(
			target_city
		)
		for army in selected:
			_assign_campaign_preparation_army(
				nation_id,
				army,
				target_city
			)
			available.erase(army)
	if nation.campaign_preparation_targets.is_empty():
		return false
	nation.campaign_preparation_started_day = (
		nation.campaign_last_offensive_day
		if nation.campaign_last_offensive_day >= 0
		else state.day
	)
	return true


func _select_campaign_preparation_armies(
	nation_id: int,
	target_city: int,
	ranked: Array[Dictionary],
	selection_limit: int,
	defense_plan: CityDefensePlan,
	defense_assigned_armies: int
) -> Dictionary:
	var ranked_heavy: Array[Dictionary] = []
	var ranked_light: Array[Dictionary] = []
	for entry in ranked:
		var ranked_army: Army = entry["army"]
		if ranked_army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE:
			ranked_heavy.append(entry)
		elif ranked_army.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE:
			ranked_light.append(entry)
	var selected: Array[Army] = []
	var selected_troops := 0
	var rank_equivalent := func(a: Dictionary, b: Dictionary) -> bool:
		var army_a: Army = a["army"]
		var army_b: Army = b["army"]
		return (
			is_equal_approx(float(a["distance"]), float(b["distance"]))
			and army_a.size == army_b.size
			and not EquivariantOrder.army_less(
				state, nation_id, army_a, army_b, target_city
			)
			and not EquivariantOrder.army_less(
				state, nation_id, army_b, army_a, target_city
			)
		)
	if ranked_heavy.is_empty():
		var fallback_limit := mini(
			LIGHT_ONLY_OFFENSIVE_MAX_ARMIES,
			mini(ranked_light.size(), selection_limit)
		)
		for fallback_entry in ranked_light:
			if selected.size() >= fallback_limit:
				break
			var fallback_army: Army = fallback_entry["army"]
			var has_defense_assignment := (
				defense_plan != null
				and defense_plan.assigned_city_for(fallback_army) >= 0
			)
			if (
				has_defense_assignment
				and defense_assigned_armies >= CAMPAIGN_DEFENSE_ASSIGNED_MAX_ARMIES
			):
				continue
			selected.append(fallback_army)
			selected_troops += fallback_army.size
			if has_defense_assignment:
				defense_assigned_armies += 1
	else:
		for heavy_entry in ranked_heavy:
			var spearhead: Army = heavy_entry["army"]
			selected.append(spearhead)
			selected_troops += spearhead.size
	if not ranked_heavy.is_empty() and not ranked_light.is_empty():
		var support_candidates: Array[Dictionary] = []
		for light_entry in ranked_light:
			var light_army: Army = light_entry["army"]
			var has_defense_assignment := (
				defense_plan != null
				and defense_plan.assigned_city_for(light_army) >= 0
			)
			if (
				has_defense_assignment
				and defense_assigned_armies >= CAMPAIGN_DEFENSE_ASSIGNED_MAX_ARMIES
			):
				continue
			support_candidates.append(light_entry)
		var support_is_unique: bool = (
			support_candidates.size() == 1
			or not rank_equivalent.call(
				support_candidates[0], support_candidates[1]
			)
		) if not support_candidates.is_empty() else false
		if support_is_unique and not support_candidates.is_empty():
			var support: Army = support_candidates[0]["army"]
			selected.append(support)
			selected_troops += support.size
			if (
				defense_plan != null
				and defense_plan.assigned_city_for(support) >= 0
			):
				defense_assigned_armies += 1
	return {
		"armies": selected,
		"troops": selected_troops,
		"defense_assigned": defense_assigned_armies,
	}


## 正式地图的攻势只有这一条规划入口：纯规划器一次决定目标预算和战团归属，
## 原子应用器再投影到兼容字段。扩军、集结、发射只能消费这份计划。
func _rank_campaign_preparation_armies(
	nation_id: int,
	target_city: int,
	staging: Array,
	available: Array[Army],
	view: AiWorldView,
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator
) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for army in available:
		if not _can_assign_campaign_preparation_army(
			nation_id,
			army,
			target_city
		):
			continue
		if not _can_use_army_for_offensive(
			defense_plan,
			coordinator,
			army,
			target_city
		):
			continue
		var origin := _campaign_army_origin(army, nation_id)
		if origin < 0:
			continue
		var field := view.path_field(
			origin,
			nation_id,
			false,
			true,
			-1,
			army.max_size
		)
		var best_distance := INF
		for staging_city in staging:
			best_distance = minf(
				best_distance,
				float(field["dist"].get(staging_city, INF))
			)
		if best_distance == INF:
			continue
		ranked.append({
			"army": army,
			"distance": best_distance,
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var army_a: Army = a["army"]
		var army_b: Army = b["army"]
		if state.uses_heightmap and army_a.max_size != army_b.max_size:
			return army_a.max_size > army_b.max_size
		if army_a.is_main_battle_role() != army_b.is_main_battle_role():
			return army_a.is_main_battle_role()
		var distance_a := float(a["distance"])
		var distance_b := float(b["distance"])
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		if army_a.size != army_b.size:
			return army_a.size > army_b.size
		return EquivariantOrder.army_less(
			state,
			nation_id,
			army_a,
			army_b,
			target_city
		)
	)
	return ranked


func _campaign_preparation_readiness(
	nation_id: int,
	primary_city: int,
	view: AiWorldView
) -> Dictionary:
	var available: Array[Army] = []
	for army in view.friendly_armies:
		var origin := _campaign_army_origin(army, nation_id)
		if (
			army.size <= 0
			or origin < 0
			or army.state not in [Army.State.IDLE, Army.State.HOLDING]
			or state.day < army.defensive_deployment_until_day
		):
			continue
		available.append(army)
	var available_troops := 0
	for army in available:
		available_troops += army.size
	var primary_staged_required := _campaign_minimum_staged_troops(
		nation_id,
		primary_city
	)
	var primary_surplus := maxi(
		available_troops - primary_staged_required,
		0
	)
	var parallel_capacity := maxi(
		1 + int(floor(
			float(primary_surplus)
			/ (
				float(maxi(primary_staged_required, 1))
				* CAMPAIGN_PARALLEL_SURPLUS_STEP_RATIO
			)
		)),
		1
	)
	return {
		"available": available,
		"parallel_capacity": parallel_capacity,
	}


func _assign_grid_campaign_target(
	nation_id: int,
	target_city: int,
	ranked: Array[Dictionary],
	selection_limit: int,
	threat: ThreatField,
	nation: Nation,
	available: Array[Army]
) -> void:
	var grid_target_limit := int(ceil(
		float(_campaign_minimum_staged_troops(
			nation_id,
			target_city
		)) * CAMPAIGN_TARGET_COMMIT_RATIO
	))
	var grid_direct_defense := 0.0
	for defender in state.armies_at_city(target_city):
		if state.is_enemy(nation_id, defender.owner_nation):
			grid_direct_defense += ArmyPower.effective(defender)
	var grid_target_defense := maxf(
		grid_direct_defense,
		threat.threat_at(target_city)
	)
	if state.recognized_owner_of(target_city) != nation_id:
		grid_target_defense += ArmyPower.city_defense(
			state.cities[target_city]
		)
	var grid_preparation_days := (
		_campaign_offensive_interval(nation_id)
		if nation.campaign_last_offensive_day >= 0
		else 0
	)
	var grid_target_power := (
		grid_target_defense
		* _campaign_attack_ratio_threshold(nation_id)
		/ offensive_preparation_multiplier(grid_preparation_days)
	)
	var selected: Array[Army] = []
	var selected_troops := 0
	var grid_selected_power := 0.0
	for entry in ranked:
		if (
			selected.size() >= selection_limit
			or (
				selected_troops >= grid_target_limit
				and grid_selected_power >= grid_target_power
			)
		):
			break
		var grid_army: Army = entry["army"]
		selected.append(grid_army)
		selected_troops += grid_army.size
		grid_selected_power += ArmyPower.effective(grid_army)
	if selected_troops <= 0:
		return
	nation.campaign_preparation_targets.append(target_city)
	for grid_army in selected:
		_assign_campaign_preparation_army(
			nation_id,
			grid_army,
			target_city
		)
		available.erase(grid_army)


func _ensure_group_campaign_preparation_plan(
	nation_id: int,
	primary_city: int,
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator,
	roles_reconciled: bool,
	decision_context: Dictionary = {}
) -> bool:
	if (
		primary_city < 0
		or primary_city >= state.cities.size()
		or not _campaign_force_demand_target_valid(
			nation_id, primary_city
		)
	):
		return false
	if not roles_reconciled:
		_reconcile_strategic_roles(nation_id)
	var view := (
		defense_plan.view
		if defense_plan != null and defense_plan.view != null
		else _build_ai_view(nation_id)
	)
	var snapshot := (
		defense_plan.snapshot
		if defense_plan != null and defense_plan.snapshot != null
		else _strategy_snapshot_for(view)
	)
	var targets := _campaign_allocation_target_candidates(
		nation_id, primary_city, snapshot
	)
	var strict_readiness := (
		state.nations[nation_id].war_preparation_target_nation >= 0
		and state.wars_of(nation_id).is_empty()
	)
	var plan: CampaignAllocationPlan = decision_context.get(
		"campaign_allocation_plan"
	)
	if (
		plan == null
		or plan.nation_id != nation_id
		or not plan.candidate_target_ids.has(primary_city)
	):
		plan = _plan_campaign_allocation(
			nation_id, primary_city, targets, defense_plan, coordinator, view,
			strict_readiness
		)
		if not decision_context.is_empty():
			decision_context["campaign_allocation_plan"] = plan
	if plan == null or plan.assigned_group_count <= 0:
		return false
	return _apply_campaign_plan_atomic(nation_id, plan)


func _campaign_allocation_target_candidates(
	nation_id: int,
	primary_city: int,
	snapshot: StrategicMapSnapshot
) -> Array[int]:
	var nation := state.nations[nation_id]
	var result: Array[int] = []
	var append_valid := func(target_city: int) -> void:
		if (
			result.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS
			or result.has(target_city)
			or not _campaign_force_demand_target_valid(
				nation_id, target_city
			)
			or DiplomacyAI.staging_cities_for_objective(
				state, nation_id, target_city
			).is_empty()
		):
			return
		result.append(target_city)
	append_valid.call(primary_city)
	var previous := nation.campaign_preparation_plan
	if previous != null:
		# 一次准备期内冻结目标集合。不能每十天把最新动态评分目标插到
		# 第一位，否则既有战团会持续改派、永远无法在同一集结线会合。
		result.clear()
		for target_city in previous.candidate_target_ids:
			append_valid.call(target_city)
		if result.is_empty():
			for target_city in previous.assigned_target_ids:
				append_valid.call(target_city)
		return result
	else:
		for target_city in nation.campaign_preparation_targets:
			append_valid.call(target_city)
	if snapshot != null:
		for target_city in snapshot.priority_enemy_cities:
			append_valid.call(target_city)
	return result


## 只读当前世界快照并返回完整结果。除 AiWorldView 自身的路径缓存外，不修改
## Nation、Army 或任何攻势字段；相同输入必然产生相同分配。
func _plan_campaign_allocation(
	nation_id: int,
	primary_city: int,
	target_candidates: Array[int],
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator,
	view: AiWorldView,
	strict_group_readiness: bool = false
) -> CampaignAllocationPlan:
	var plan := CampaignAllocationPlan.new()
	plan.nation_id = nation_id
	plan.generated_day = state.day
	plan.strict_group_readiness = strict_group_readiness
	plan.requested_primary_city = primary_city
	if (
		nation_id < 0
		or nation_id >= state.nations.size()
		or view == null
	):
		return plan
	var nation := state.nations[nation_id]
	var previous_plan: CampaignAllocationPlan = (
		nation.campaign_preparation_plan
	)
	if previous_plan != null:
		plan.requested_primary_city = (
			previous_plan.requested_primary_city
		)
	var previous_group_targets := {}
	if previous_plan != null:
		previous_group_targets = (
			previous_plan.group_to_target.duplicate()
		)
	else:
		# 旧运行态只在首次迁移时读取一次，之后不再反向推断规划。
		for army in view.friendly_armies:
			var legacy_target := int(
				nation.campaign_preparation_assignments.get(army.id, -1)
			)
			if army.battle_group_id >= 0 and legacy_target >= 0:
				previous_group_targets[army.battle_group_id] = legacy_target
	var active_reserved_groups := {}
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and army.battle_group_id >= 0
			and nation.campaign_attack_assignments.has(army.id)
		):
			active_reserved_groups[army.battle_group_id] = true
	var group_members_by_id := {}
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.battle_group_id < 0
		):
			continue
		if not group_members_by_id.has(army.battle_group_id):
			group_members_by_id[army.battle_group_id] = [] as Array[Army]
		(group_members_by_id[army.battle_group_id] as Array[Army]).append(army)
	for group_id_value in group_members_by_id:
		var members: Array[Army] = group_members_by_id[group_id_value]
		members.sort_custom(func(a: Army, b: Army) -> bool:
			return EquivariantOrder.army_less(state, nation_id, a, b)
		)

	# 目标预算严格分三轮：广度覆盖、决定性三团、按需求补强。
	var target_staging := {}
	for target_value in target_candidates:
		if plan.candidate_target_ids.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS:
			break
		var target_city := int(target_value)
		if plan.candidate_target_ids.has(target_city):
			continue
		var demand := (
			(previous_plan.target_demands[target_city] as Dictionary)
				.duplicate(true)
			if (
				previous_plan != null
				and previous_plan.target_demands.has(target_city)
			)
			else _campaign_target_group_demand(
				nation_id, target_city,
				defense_plan.threat if defense_plan != null else null
			)
		)
		if demand.is_empty():
			continue
		var staging := DiplomacyAI.staging_cities_for_objective(
			state, nation_id, target_city
		)
		if staging.is_empty():
			continue
		plan.candidate_target_ids.append(target_city)
		plan.target_demands[target_city] = demand.duplicate(true)
		plan.target_group_budget[target_city] = (
			maxi(int(previous_plan.target_group_budget.get(
				target_city, 1
			)), 1)
			if previous_plan != null else 1
		)
		target_staging[target_city] = staging
	if plan.candidate_target_ids.is_empty():
		return plan
	plan.primary_city = (
		previous_plan.primary_city
		if (
			previous_plan != null
			and plan.candidate_target_ids.has(previous_plan.primary_city)
		)
		else primary_city
		if plan.candidate_target_ids.has(primary_city)
		else plan.candidate_target_ids[0]
	)
	var budget_used := 0
	for target_city in plan.candidate_target_ids:
		budget_used += int(plan.target_group_budget[target_city])
	plan.desired_group_count = 0
	for target_city in plan.candidate_target_ids:
		plan.desired_group_count += maxi(
			int(plan.target_demands[target_city].get("groups", 1)), 1
		)
	for target_city in plan.candidate_target_ids:
		var desired := int(plan.target_demands[target_city].get("groups", 1))
		var decisive := bool(
			plan.target_demands[target_city].get("is_decisive", false)
		)
		if not decisive:
			continue
		while (
			int(plan.target_group_budget[target_city])
				< CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS
					* CAMPAIGN_PREPARED_ECHELONS
			and budget_used < CAMPAIGN_MAX_WARTIME_GROUPS
		):
			plan.target_group_budget[target_city] = (
				int(plan.target_group_budget[target_city]) + 1
			)
			budget_used += 1
	var budget_progress := true
	while budget_progress and budget_used < CAMPAIGN_MAX_WARTIME_GROUPS:
		budget_progress = false
		for target_city in plan.candidate_target_ids:
			var desired := int(
				plan.target_demands[target_city].get("groups", 1)
			)
			if int(plan.target_group_budget[target_city]) >= desired:
				continue
			plan.target_group_budget[target_city] = (
				int(plan.target_group_budget[target_city]) + 1
			)
			budget_used += 1
			budget_progress = true
			if budget_used >= CAMPAIGN_MAX_WARTIME_GROUPS:
				break
	plan.required_group_count = budget_used

	var evaluations := {}
	for target_city in plan.candidate_target_ids:
		for group in nation.battle_groups:
			if active_reserved_groups.has(group.id):
				continue
			var members: Array[Army] = group_members_by_id.get(
				group.id, [] as Array[Army]
			)
			if members.is_empty():
				continue
			var retained_ids: Array[int] = []
			if (
				previous_plan != null
				and previous_plan.target_for_group(group.id) == target_city
			):
				retained_ids = previous_plan.member_ids_for_group(group.id)
			var evaluation := _evaluate_campaign_group_for_target(
				nation_id, target_city, members, target_staging[target_city],
				view, defense_plan, coordinator, strict_group_readiness,
				retained_ids
			)
			if not evaluation.is_empty():
				evaluations["%d:%d" % [target_city, group.id]] = evaluation
	var used_groups := {}
	var assigned_manpower := {}
	var assigned_power := {}
	# 决定性主目标先拿到首轮所需三团，再做广度覆盖。旧顺序先给八路
	# 各一团，现有战团不足时主目标的第三团只能等待后续逐次扩军。
	var slots: Array[int] = []
	if (
		plan.target_demands.has(plan.primary_city)
		and bool(plan.target_demands[plan.primary_city].get(
			"is_decisive", false
		))
	):
		for _slot in range(mini(
			CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS,
			int(plan.target_group_budget[plan.primary_city])
		)):
			slots.append(plan.primary_city)
	for target_city in plan.candidate_target_ids:
		if not slots.has(target_city):
			slots.append(target_city)
	for target_city in plan.candidate_target_ids:
		var decisive := bool(
			plan.target_demands[target_city].get("is_decisive", false)
		)
		if not decisive:
			continue
		var already_reserved := slots.count(target_city)
		for unused in range(already_reserved, mini(
			int(plan.target_demands[target_city].get("groups", 1)),
			CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS
				* CAMPAIGN_PREPARED_ECHELONS
		)):
			slots.append(target_city)
	var already_slotted := {}
	for target_city in slots:
		already_slotted[target_city] = int(
			already_slotted.get(target_city, 0)
		) + 1
	var add_slots := true
	while add_slots and slots.size() < plan.required_group_count:
		add_slots = false
		for target_city in plan.candidate_target_ids:
			if int(already_slotted.get(target_city, 0)) >= int(
				plan.target_group_budget[target_city]
			):
				continue
			slots.append(target_city)
			already_slotted[target_city] = int(
				already_slotted.get(target_city, 0)
			) + 1
			add_slots = true
			if slots.size() >= plan.required_group_count:
				break
	for target_city in slots:
		var best := _best_planned_campaign_group(
			target_city, used_groups, nation.battle_groups, evaluations,
			previous_group_targets
		)
		if best.is_empty():
			continue
		var group_id := int(best["group_id"])
		used_groups[group_id] = true
		plan.group_to_target[group_id] = target_city
		if not plan.target_to_groups.has(target_city):
			plan.target_to_groups[target_city] = [] as Array[int]
		(plan.target_to_groups[target_city] as Array[int]).append(group_id)
		var all_ids: Array[int] = []
		for member in group_members_by_id[group_id] as Array[Army]:
			all_ids.append(member.id)
		plan.all_member_ids[group_id] = all_ids
		plan.eligible_member_ids[group_id] = (
			best["eligible_member_ids"] as Array[int]
		).duplicate()
		plan.excluded_member_reasons[group_id] = (
			best.get("excluded_member_reasons", {}) as Dictionary
		).duplicate(true)
		assigned_manpower[target_city] = int(
			assigned_manpower.get(target_city, 0)
		) + int(best["manpower"])
		assigned_power[target_city] = float(
			assigned_power.get(target_city, 0.0)
		) + float(best["power"])
	# 理论团槽只是扩军预算；实际分配还必须填平当前兵力和战力缺口。
	# 残缺战团可以占一个方向，但不能冒充满编团阻止后续补强。
	var reinforcement_progress := true
	while (
		reinforcement_progress
		and used_groups.size() < CAMPAIGN_MAX_WARTIME_GROUPS
	):
		reinforcement_progress = false
		for target_city in plan.candidate_target_ids:
			var demand: Dictionary = plan.target_demands[target_city]
			var assigned_groups := (
				(plan.target_to_groups[target_city] as Array).size()
				if plan.target_to_groups.has(target_city) else 0
			)
			if (
				assigned_groups >= int(plan.target_group_budget[target_city])
				and int(assigned_manpower.get(target_city, 0))
					>= int(demand["required_manpower"])
				and float(assigned_power.get(target_city, 0.0))
					>= float(demand["required_power"])
			):
				continue
			var best := _best_planned_campaign_group(
				target_city, used_groups, nation.battle_groups, evaluations,
				previous_group_targets
			)
			if best.is_empty():
				continue
			var group_id := int(best["group_id"])
			if assigned_groups >= int(plan.target_group_budget[target_city]):
				plan.target_group_budget[target_city] = assigned_groups + 1
			used_groups[group_id] = true
			plan.group_to_target[group_id] = target_city
			if not plan.target_to_groups.has(target_city):
				plan.target_to_groups[target_city] = [] as Array[int]
			(plan.target_to_groups[target_city] as Array[int]).append(group_id)
			var all_ids: Array[int] = []
			for member in group_members_by_id[group_id] as Array[Army]:
				all_ids.append(member.id)
			plan.all_member_ids[group_id] = all_ids
			plan.eligible_member_ids[group_id] = (
				best["eligible_member_ids"] as Array[int]
			).duplicate()
			plan.excluded_member_reasons[group_id] = (
				best.get("excluded_member_reasons", {}) as Dictionary
			).duplicate(true)
			assigned_manpower[target_city] = int(
				assigned_manpower.get(target_city, 0)
			) + int(best["manpower"])
			assigned_power[target_city] = float(
				assigned_power.get(target_city, 0.0)
			) + float(best["power"])
			reinforcement_progress = true
			if used_groups.size() >= CAMPAIGN_MAX_WARTIME_GROUPS:
				break
	for target_city in plan.candidate_target_ids:
		if (
			plan.target_to_groups.has(target_city)
			and not (plan.target_to_groups[target_city] as Array).is_empty()
		):
			plan.assigned_target_ids.append(target_city)
	plan.assigned_group_count = plan.group_to_target.size()
	plan.required_group_count = maxi(
		plan.required_group_count, plan.assigned_group_count
	)
	plan.target_assigned_manpower = assigned_manpower.duplicate(true)
	plan.target_assigned_power = assigned_power.duplicate(true)
	plan.unfilled_group_slots = maxi(
		plan.required_group_count - plan.assigned_group_count, 0
	)
	return plan


func _evaluate_campaign_group_for_target(
	nation_id: int,
	target_city: int,
	group_members: Array[Army],
	staging: Array[int],
	view: AiWorldView,
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator,
	strict_group_readiness: bool,
	retained_member_ids: Array[int] = []
) -> Dictionary:
	var eligible_members: Array[Army] = []
	var eligible_ids: Array[int] = []
	var excluded := {}
	var power := 0.0
	var manpower := 0
	var distance := 0.0
	for army in group_members:
		var entry_staging: Array[int] = []
		for staging_city in staging:
			var edge := state.edge_of(staging_city, target_city)
			if edge != null and edge.max_manpower >= army.road_footprint():
				entry_staging.append(staging_city)
		if entry_staging.is_empty():
			excluded[army.id] = "entry_capacity"
			continue
		var origin := _campaign_army_origin(army, nation_id)
		var retained_in_plan := retained_member_ids.has(army.id)
		var staging_in_transit := (
			retained_in_plan
			and army.state == Army.State.MOVING
			and army.ai_action in [
				ActionCandidate.Kind.REINFORCE,
				ActionCandidate.Kind.RETREAT,
			]
			and staging.has(army.ai_target_city)
		)
		if (
			origin < 0
			or army.state not in [Army.State.IDLE, Army.State.HOLDING]
			or not _can_use_army_for_offensive(
				defense_plan, coordinator, army, target_city
			)
		):
			# 只保留确实正在前往本目标集结城的旧成员。FIGHTING、
			# RECOVERING 或执行其他目标的军队不能伪装成“在途第三团”，
			# 否则 planner 会一直占着团槽而实际永不到位。
			if staging_in_transit:
				eligible_members.append(army)
				eligible_ids.append(army.id)
				power += ArmyPower.effective(army)
				manpower += army.size
				excluded[army.id] = "staging_in_transit"
				continue
			excluded[army.id] = "temporarily_unavailable"
			continue
		var field := view.path_field(
			origin, nation_id, false, true, -1, army.max_size
		)
		var member_distance := INF
		for staging_city in entry_staging:
			member_distance = minf(
				member_distance,
				float(field["dist"].get(staging_city, INF))
			)
		if member_distance == INF:
			excluded[army.id] = "unreachable"
			continue
		eligible_members.append(army)
		eligible_ids.append(army.id)
		power += ArmyPower.effective(army)
		manpower += army.size
		distance = maxf(distance, member_distance)
	if eligible_members.is_empty():
		return {}
	if strict_group_readiness:
		for reason in excluded.values():
			if str(reason) not in ["entry_capacity", "staging_in_transit"]:
				return {}
	return {
		"members": eligible_members,
		"eligible_member_ids": eligible_ids,
		"excluded_member_reasons": excluded,
		"power": power,
		"manpower": manpower,
		"distance": distance,
	}


func _best_planned_campaign_group(
	target_city: int,
	used_groups: Dictionary,
	groups: Array[BattleGroup],
	evaluations: Dictionary,
	previous_group_targets: Dictionary
) -> Dictionary:
	var best := {}
	for group in groups:
		if used_groups.has(group.id):
			continue
		var key := "%d:%d" % [target_city, group.id]
		if not evaluations.has(key):
			continue
		var evaluation: Dictionary = evaluations[key]
		var stable := int(previous_group_targets.get(group.id, -1)) == target_city
		if (
			best.is_empty()
			or stable and not bool(best["stable"])
			or stable == bool(best["stable"]) and (
				float(evaluation["power"]) > float(best["power"])
				or is_equal_approx(
					float(evaluation["power"]), float(best["power"])
				) and (
					float(evaluation["distance"]) < float(best["distance"])
					or is_equal_approx(
						float(evaluation["distance"]), float(best["distance"])
					) and group.id < int(best["group_id"])
				)
			)
		):
			best = evaluation.duplicate(true)
			best["group_id"] = group.id
			best["stable"] = stable
	return best


func _apply_campaign_plan_atomic(
	nation_id: int,
	plan: CampaignAllocationPlan
) -> bool:
	if (
		plan == null
		or nation_id < 0
		or nation_id >= state.nations.size()
		or plan.nation_id != nation_id
		or plan.assigned_target_ids.is_empty()
		or plan.assigned_target_ids.size() > CAMPAIGN_MAX_PARALLEL_TARGETS
		or plan.group_to_target.size() > CAMPAIGN_MAX_WARTIME_GROUPS
		or plan.assigned_group_count != plan.group_to_target.size()
		or plan.required_group_count < plan.assigned_group_count
		or plan.required_group_count > CAMPAIGN_MAX_WARTIME_GROUPS
		or plan.unfilled_group_slots != maxi(
			plan.required_group_count - plan.assigned_group_count, 0
		)
	):
		return false
	var nation := state.nations[nation_id]
	var new_targets: Array[int] = []
	var new_assignments := {}
	var new_representatives := {}
	var seen_groups := {}
	for target_city in plan.assigned_target_ids:
		if (
			new_targets.has(target_city)
			or not _campaign_force_demand_target_valid(nation_id, target_city)
			or not plan.target_to_groups.has(target_city)
		):
			return false
		var target_groups: Array[int] = []
		target_groups.assign(plan.target_to_groups[target_city])
		if target_groups.is_empty():
			return false
		if target_groups.size() > int(
			plan.target_group_budget.get(target_city, 0)
		):
			return false
		target_groups.sort()
		new_targets.append(target_city)
		new_representatives[target_city] = target_groups[0]
		for group_id in target_groups:
			if (
				seen_groups.has(group_id)
				or int(plan.group_to_target.get(group_id, -1)) != target_city
				or state.battle_group_by_id(nation_id, group_id) == null
			):
				return false
			seen_groups[group_id] = true
			var eligible_ids: Array[int] = []
			eligible_ids.assign(plan.eligible_member_ids.get(group_id, []))
			if eligible_ids.is_empty():
				return false
			var member_by_id := {}
			var current_member_ids: Array[int] = []
			for member in state.battle_group_members(nation_id, group_id):
				member_by_id[member.id] = member
				current_member_ids.append(member.id)
				if nation.campaign_attack_assignments.has(member.id):
					return false
			current_member_ids.sort()
			var planned_member_ids: Array[int] = []
			planned_member_ids.assign(plan.all_member_ids.get(group_id, []))
			planned_member_ids.sort()
			if planned_member_ids != current_member_ids:
				return false
			for army_id in eligible_ids:
				if (
					not member_by_id.has(army_id)
				):
					return false
				new_assignments[army_id] = target_city
	if seen_groups.size() != plan.group_to_target.size():
		return false
	for group_id_value in plan.group_to_target:
		var group_id := int(group_id_value)
		var target_city := int(plan.group_to_target[group_id_value])
		if (
			not seen_groups.has(group_id)
			or not plan.target_to_groups.has(target_city)
			or not (plan.target_to_groups[target_city] as Array).has(group_id)
		):
			return false
	var new_full_targets: Array[int] = []
	for target_city in nation.campaign_full_preparation_targets:
		if new_targets.has(target_city):
			new_full_targets.append(target_city)
	var started_day := nation.campaign_preparation_started_day
	if started_day < 0:
		started_day = (
			nation.campaign_last_offensive_day
			if nation.campaign_last_offensive_day >= 0
			else state.day
		)
	# 从这里开始才提交；上方任一校验失败时旧状态逐字段不变。
	nation.campaign_preparation_plan = plan.duplicate_plan()
	nation.campaign_preparation_targets = new_targets
	nation.campaign_preparation_assignments = new_assignments
	nation.campaign_preparation_group_assignments = new_representatives
	nation.campaign_full_preparation_targets = new_full_targets
	nation.campaign_preparation_started_day = started_day
	return true


## 网格地图逐军计划的兼容预算裁剪；正式高度图只消费 CampaignAllocationPlan，
## 不会进入此函数。
func _trim_campaign_preparation_budget(
	nation_id: int,
	target_candidates: Array[int]
) -> Array[int]:
	var nation := state.nations[nation_id]
	var bounded_targets: Array[int] = []
	for target_city in target_candidates:
		if bounded_targets.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS:
			break
		if not bounded_targets.has(target_city):
			bounded_targets.append(target_city)
	# 旧存档可能带有超过八路的准备状态；先移除超额目标及其 Assignment。
	for target_value in nation.campaign_preparation_targets.duplicate():
		var target_city := int(target_value)
		if not bounded_targets.has(target_city):
			_remove_campaign_preparation_target(nation_id, target_city)
	var ordered_groups: Array[int] = []
	var reserved_group_slots := 0
	var existing_assigned_groups := {}
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and army.battle_group_id >= 0
			and nation.campaign_preparation_assignments.has(army.id)
		):
			existing_assigned_groups[army.battle_group_id] = true
	# 每个方向的代表战团优先保留，避免裁剪把某一路整个清空。
	for target_city in bounded_targets:
		var representative := int(
			nation.campaign_preparation_group_assignments.get(
				target_city, -1
			)
		)
		var representative_valid := false
		if (
			representative >= 0
			and state.battle_group_by_id(nation_id, representative) != null
		):
			for member in state.battle_group_members(
				nation_id, representative
			):
				if int(nation.campaign_preparation_assignments.get(
					member.id, -1
				)) == target_city:
					representative_valid = true
					break
		if representative_valid:
			if not ordered_groups.has(representative):
				ordered_groups.append(representative)
		else:
			nation.campaign_preparation_group_assignments.erase(
				target_city
			)
		var valid_group_count := 0
		var counted_groups := {}
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and army.battle_group_id >= 0
				and int(nation.campaign_preparation_assignments.get(
					army.id, -1
				)) == target_city
				and not counted_groups.has(army.battle_group_id)
			):
				counted_groups[army.battle_group_id] = true
				valid_group_count += 1
		var defender_owner := state.cities[target_city].owner_nation
		var required_floor := (
			CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS
			if defender_owner >= 0
				and state.land_cities_of(defender_owner).size() <= 1
			else 1
		)
		reserved_group_slots += maxi(
			required_floor - valid_group_count, 0
		)
	# 为尚未覆盖的新方向预留战团预算；若16团已全部堆在旧方向，
	# 从额外增援团中释放相同数量，下一阶段即可重平衡到新前线。
	var retained_existing_limit := maxi(
		mini(
			CAMPAIGN_MAX_WARTIME_GROUPS - reserved_group_slots,
			maxi(
				existing_assigned_groups.size() - reserved_group_slots,
				0
			)
		),
		ordered_groups.size()
	)
	# 其余增援战团按目标优先级、团号稳定收进预算。
	for target_city in bounded_targets:
		var target_groups: Array[int] = []
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and army.battle_group_id >= 0
				and int(nation.campaign_preparation_assignments.get(
					army.id, -1
				)) == target_city
				and not target_groups.has(army.battle_group_id)
			):
				target_groups.append(army.battle_group_id)
		target_groups.sort()
		for group_id in target_groups:
			if ordered_groups.size() >= retained_existing_limit:
				break
			if not ordered_groups.has(group_id):
				ordered_groups.append(group_id)
	var allowed_groups := {}
	for group_id in ordered_groups.slice(
		0, CAMPAIGN_MAX_WARTIME_GROUPS
	):
		allowed_groups[int(group_id)] = true
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.battle_group_id >= 0
			and nation.campaign_preparation_assignments.has(army.id)
			and not allowed_groups.has(army.battle_group_id)
		):
			nation.campaign_preparation_assignments.erase(army.id)
	# 若代表团本身已无有效成员，删掉映射；第一阶段会重新绑定，
	# 没有可用战团的目标则暂时退出，待下一轮恢复后重新加入。
	for target_city in bounded_targets.duplicate():
		var has_member := false
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and int(nation.campaign_preparation_assignments.get(
					army.id, -1
				)) == target_city
			):
				has_member = true
				break
		if not has_member and nation.campaign_preparation_targets.has(target_city):
			nation.campaign_preparation_group_assignments.erase(target_city)
	return bounded_targets


func _campaign_preparation_staged_armies(
	nation_id: int,
	target_city: int
) -> Array[Army]:
	var nation := state.nations[nation_id]
	var result: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and int(
				nation.campaign_preparation_assignments.get(
					army.id,
					-1
				)
			) == target_city
			and _army_ready_for_campaign_target(
				army,
				nation_id,
				target_city
			)
		):
			result.append(army)
	return _sort_campaign_priority(
		result,
		nation_id,
		target_city
	)


func _campaign_preparation_staged_troops(
	nation_id: int,
	target_city: int
) -> int:
	var total := 0
	for army in _campaign_preparation_staged_armies(
		nation_id,
		target_city
	):
		total += army.size
	return total


func _assign_offensive_staging_orders(
	nation_id: int,
	objective_city: int,
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator,
	build_campaign_plan: bool,
	assigned_only: bool,
	roles_reconciled: bool = false,
	decision_context: Dictionary = {}
) -> bool:
	var staging := DiplomacyAI.staging_cities_for_objective(
		state, nation_id, objective_city
	)
	if staging.is_empty():
		return false
	var path_view: AiWorldView = (
		defense_plan.view
		if defense_plan != null
		else _build_ai_view(nation_id)
	)
	if state.uses_heightmap:
		var nation := state.nations[nation_id]
		if (
			nation.campaign_preparation_plan == null
			or not nation.campaign_preparation_plan
				.assigned_target_ids.has(objective_city)
		):
			return false
		assigned_only = true
	var committed_heavy := 0
	var committed_light := 0
	if not assigned_only:
		var objective_token := "目标城市%d" % objective_city
		for committed_army in path_view.friendly_armies:
			if (
				committed_army.size <= 0
				or not committed_army.ai_order_reason.contains(
					objective_token
				)
				or (
					committed_army.state == Army.State.IDLE
					and not staging.has(
						committed_army.location_city
					)
				)
			):
				continue
			if (
				committed_army.max_size
					== GameState.INITIAL_HEAVY_ARMY_SIZE
			):
				committed_heavy += 1
			elif (
				committed_army.max_size
					== GameState.INITIAL_LIGHT_ARMY_SIZE
			):
				committed_light += 1
	var changed := false
	var orders := 0
	for staging_city in staging:
		if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
			break
		if _edge_has_friendly_holder_or_order(
			nation_id, staging_city, objective_city
		):
			continue
		var staging_armies: Array[Army] = []
		var armies_at_staging: Array[Army] = (
			path_view.armies_by_city.get(
				staging_city,
				[] as Array[Army]
			) as Array[Army]
		)
		for army in armies_at_staging:
			if (
				army.size <= 0
				or army.owner_nation != nation_id
				or army.state != Army.State.IDLE
				or army.location_city != staging_city
				or (
					assigned_only
						and not _can_assign_campaign_preparation_army(
							nation_id,
							army,
							objective_city
						)
				)
				or (
					state.day < army.defensive_deployment_until_day
					and not _campaign_assignment_overrides_defensive_lock(
						nation_id, army, objective_city
					)
				)
				or not _can_use_army_for_offensive(
					defense_plan,
					coordinator,
					army,
					objective_city
				)
			):
				continue
			staging_armies.append(army)
		staging_armies.sort_custom(
			func(a: Army, b: Army) -> bool:
				if a.max_size != b.max_size:
					return a.max_size > b.max_size
				return EquivariantOrder.army_less(
					state,
					nation_id,
					a,
					b,
					objective_city
				)
		)
		for army in staging_armies:
			if (
				not assigned_only
				and army.max_size
					== GameState.INITIAL_LIGHT_ARMY_SIZE
				and committed_light >= committed_heavy
			):
				continue
			var hold := ActionCandidate.make(
				ActionCandidate.Kind.HOLD,
				1000.0,
				"战前集结：在己方侧监视目标城市%d" % objective_city,
				objective_city
			)
			hold.target_edge_a = staging_city
			hold.target_edge_b = objective_city
			hold.minimum_commit_days = DiplomacyAI.WAR_PREPARATION_MIN_DAYS
			if _execute_ai_candidate(army, hold):
				changed = true
				orders += 1
				if not assigned_only:
					if (
						army.max_size
							== GameState.INITIAL_HEAVY_ARMY_SIZE
					):
						committed_heavy += 1
					elif (
						army.max_size
							== GameState.INITIAL_LIGHT_ARMY_SIZE
					):
						committed_light += 1
			break
	var staged := (
		_campaign_preparation_staged_troops(
			nation_id,
			objective_city
		)
		if assigned_only
		else DiplomacyAI.staged_troops_for_objective(
			state,
			nation_id,
			objective_city
		)
	)
	var required := DiplomacyAI.required_assault_troops(
		state,
		nation_id,
		objective_city
	)
	if assigned_only:
		var nation := state.nations[nation_id]
		if (
			state.uses_heightmap
			and nation.campaign_preparation_plan != null
			and nation.campaign_preparation_plan
				.assigned_target_ids.has(objective_city)
		):
			required = _campaign_planned_staging_troops(
				nation_id, objective_city
			)
		else:
			required = _campaign_minimum_staged_troops(
				nation_id,
				objective_city
			)
	var sustained_required := (
		required
		if assigned_only
		else required * CAMPAIGN_PREPARED_ECHELONS
	)
	if staged >= sustained_required:
		if build_campaign_plan:
			_ensure_campaign_attack_plan(
				nation_id,
				objective_city
			)
		return changed
	if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
		return changed
	var candidates: Array[Dictionary] = []
	for army in path_view.friendly_armies:
		if (
			army.size <= 0
			or army.state != Army.State.IDLE
			or staging.has(army.location_city)
			or (
				assigned_only
					and not _can_assign_campaign_preparation_army(
						nation_id,
						army,
						objective_city
					)
			)
			or (
				state.day < army.defensive_deployment_until_day
				and not _campaign_assignment_overrides_defensive_lock(
					nation_id, army, objective_city
				)
			)
			or not _can_use_army_for_offensive(
				defense_plan,
				coordinator,
				army,
				objective_city
			)
		):
			continue
		var field: Dictionary = path_view.path_field(
			army.location_city,
			nation_id,
			false,
			true,
			-1,
			army.max_size
		)
		var best_city := -1
		var best_distance := INF
		for staging_city in staging:
			var distance := float(field["dist"][staging_city])
			if distance < best_distance:
				best_distance = distance
				best_city = staging_city
		if best_city == -1 or best_distance == INF:
			continue
		candidates.append({
			"army": army,
			"best_city": best_city,
			"best_distance": best_distance,
		})
	# 距集结出发地更近者优先增援：距离取自镜像对称的静态最短路
	# （Dijkstra 的 dist 与松弛顺序无关，镜像世界左右严格相等），
	# 消除“先创建者（低 id）先动”的偏置，保证左右选出互为镜像的援军。
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var army_a: Army = a["army"]
		var army_b: Army = b["army"]
		if army_a.max_size != army_b.max_size:
			return army_a.max_size > army_b.max_size
		var da: float = a["best_distance"]
		var db: float = b["best_distance"]
		if not is_equal_approx(da, db):
			return da < db
		return EquivariantOrder.army_less(
			state,
			nation_id,
			army_a,
			army_b,
			objective_city
		)
	)
	for entry in candidates:
		if (
			orders >= PREPARATION_MAX_ORDERS_PER_CYCLE
			or staged >= sustained_required
		):
			break
		var army: Army = entry["army"]
		var best_city: int = entry["best_city"]
		if (
			not assigned_only
			and army.max_size
				== GameState.INITIAL_LIGHT_ARMY_SIZE
			and committed_light >= committed_heavy
		):
			continue
		var reinforce := ActionCandidate.make(
			ActionCandidate.Kind.REINFORCE,
			900.0,
			"战前集结：向目标城市%d的进攻出发地%d调兵"
				% [objective_city, best_city],
			best_city
		)
		reinforce.minimum_commit_days = DiplomacyAI.WAR_PREPARATION_MIN_DAYS
		if _execute_ai_candidate(army, reinforce):
			changed = true
			orders += 1
			staged += army.size
			if not assigned_only:
				if (
					army.max_size
						== GameState.INITIAL_HEAVY_ARMY_SIZE
				):
					committed_heavy += 1
				elif (
					army.max_size
						== GameState.INITIAL_LIGHT_ARMY_SIZE
				):
					committed_light += 1
	var actual_staged := (
		_campaign_preparation_staged_troops(
			nation_id,
			objective_city
		)
		if assigned_only
		else DiplomacyAI.staged_troops_for_objective(
			state,
			nation_id,
			objective_city
		)
	)
	if actual_staged >= sustained_required:
		if build_campaign_plan:
			_ensure_campaign_attack_plan(
				nation_id,
				objective_city
			)
		return changed
	if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
		return changed
	var holders: Array[Army] = []
	for army in path_view.friendly_armies:
		if (
			army.size <= 0
			or army.state != Army.State.HOLDING
			or (
				assigned_only
					and not _can_assign_campaign_preparation_army(
						nation_id,
						army,
						objective_city
					)
			)
			or (
				state.day < army.defensive_deployment_until_day
				and not _campaign_assignment_overrides_defensive_lock(
					nation_id, army, objective_city
				)
			)
			or _army_ready_for_campaign_target(
				army,
				nation_id,
				objective_city
			)
			or not _can_use_army_for_offensive(
				defense_plan,
				coordinator,
				army,
				objective_city
			)
		):
			continue
		var friendly_endpoint: int = army.move_from
		if not state.has_military_access(
			nation_id, state.cities[friendly_endpoint].owner_nation
		):
			friendly_endpoint = army.move_to
		holders.append(army)
	holders.sort_custom(func(a: Army, b: Army) -> bool:
			if a.size != b.size:
				return a.size > b.size
			return EquivariantOrder.army_less(
				state,
				nation_id,
				a,
				b,
				objective_city
			)
	)
	for army in holders:
		if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
			break
		if (
			not assigned_only
			and army.max_size
				== GameState.INITIAL_LIGHT_ARMY_SIZE
			and committed_light >= committed_heavy
		):
			continue
		var friendly_endpoint := army.move_from
		if not state.has_military_access(
			nation_id, state.cities[friendly_endpoint].owner_nation
		):
			friendly_endpoint = army.move_to
		var withdraw := ActionCandidate.make(
			ActionCandidate.Kind.RETREAT,
			850.0,
			"战前重部署：从次要边境撤回，转向目标城市%d集结"
				% objective_city,
			friendly_endpoint
		)
		withdraw.minimum_commit_days = AI_DECISION_INTERVAL_DAYS
		if _execute_ai_candidate(army, withdraw):
			changed = true
			orders += 1
			if not assigned_only:
				if (
					army.max_size
						== GameState.INITIAL_HEAVY_ARMY_SIZE
				):
					committed_heavy += 1
				elif (
					army.max_size
						== GameState.INITIAL_LIGHT_ARMY_SIZE
				):
					committed_light += 1
	return changed


func _build_campaign_attack_plan_from_preparation(
	nation_id: int,
	targets: Array[int]
) -> bool:
	var nation := state.nations[nation_id]
	_clear_campaign_attack_plan(nation_id)
	# 外部调用或旧存档可能直接传入超额准备列表；发射入口自身必须
	# 裁到8路/16团，不能依赖调用方预先经过正常规划流水线。
	var ordered_targets := _trim_campaign_preparation_budget(
		nation_id, targets
	)
	EquivariantOrder.sort_city_ids(
		ordered_targets,
		state,
		nation_id
	)
	for target_city in ordered_targets:
		if nation.campaign_plan_targets.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS:
			break
		var staged_troops := (
			_campaign_preparation_staged_troops(
				nation_id,
				target_city
			)
		)
		var persistent_group := (
			state.uses_heightmap
			and nation.campaign_preparation_group_assignments.has(
				target_city
			)
		)
		if (
			target_city < 0
			or target_city >= state.cities.size()
			or not state.is_enemy(
				nation_id,
				state.cities[target_city].owner_nation
			)
			or staged_troops <= 0
			or (
				not persistent_group
				and staged_troops
					< _campaign_minimum_staged_troops(
						nation_id,
						target_city
					)
			)
		):
			continue
		nation.campaign_plan_targets.append(target_city)
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and int(
					nation.campaign_preparation_assignments.get(
						army.id,
						-1
					)
				) == target_city
			):
				nation.campaign_attack_assignments[army.id] = (
					target_city
				)
	if nation.campaign_plan_targets.is_empty():
		return false
	_build_campaign_echelons(nation_id)
	nation.campaign_plan_wave = (
		nation.campaign_offensive_count + 1
	)
	nation.campaign_plan_primary_city = (
		nation.campaign_plan_targets[0]
	)
	return true


func _launch_campaign_offensive(
	nation_id: int,
	objective_city: int,
	preparation_days: int = -1,
	prepared_targets: Array[int] = [],
	route_threat_override: ThreatField = null
) -> bool:
	if (
		nation_id < 0
		or nation_id >= state.nations.size()
		or not _ruler_allows_campaign_target(
			nation_id, objective_city
		)
		or
		objective_city < 0
		or objective_city >= state.cities.size()
		or not state.is_enemy(
			nation_id, state.cities[objective_city].owner_nation
		)
	):
		return false
	if state.uses_heightmap:
		return _launch_group_campaign_offensive(
			nation_id, objective_city, preparation_days, prepared_targets,
			route_threat_override
		)
	if prepared_targets.is_empty():
		var required := DiplomacyAI.required_assault_troops(
			state, nation_id, objective_city
		)
		var staged := DiplomacyAI.staged_troops_for_objective(
			state, nation_id, objective_city
		)
		if staged < required:
			return false
		if not _ensure_campaign_attack_plan(
			nation_id,
			objective_city
		):
			return false
	elif not _build_campaign_attack_plan_from_preparation(
		nation_id,
		prepared_targets
	):
		return false
	var nation := state.nations[nation_id]
	if preparation_days < 0:
		preparation_days = _campaign_preparation_days(
			nation_id
		)
	var offensive_multiplier := offensive_preparation_multiplier(
		preparation_days
	)
	var offensive_bonus_days := offensive_bonus_duration_days(
		preparation_days
	)
	nation.campaign_preparation_multiplier = offensive_multiplier
	var launched := false
	var launched_origins := {}
	var route_threat := route_threat_override
	if route_threat == null:
		route_threat = ThreatField.build(
			_build_ai_view(nation_id),
			_threat_travel_cache
		)
	var plan_targets := nation.campaign_plan_targets.duplicate()
	EquivariantOrder.sort_city_ids(
		plan_targets,
		state,
		nation_id,
		objective_city
	)
	var launchable_targets: Array[int] = []
	var route_plans := {}
	for target_city in plan_targets:
		if launchable_targets.size() >= CAMPAIGN_MAX_PARALLEL_TARGETS:
			break
		if not state.is_enemy(
			nation_id,
			state.cities[target_city].owner_nation
		):
			continue
		var target_required := (
			_campaign_minimum_staged_troops(
				nation_id,
				target_city
			)
		)
		var target_attackers := _campaign_initial_attackers(
			nation_id,
			target_city
		)
		var target_size := 0
		for army in target_attackers:
			target_size += army.size
		if target_size < target_required:
			continue
		var route_plan := _campaign_two_step_route_plan(
			nation_id,
			target_city,
			target_attackers,
			route_threat
		)
		# 两步路线是破城后的续攻优化，不是首攻合法性。局部战力已经满足时，
		# 死胡同或暂无第二步的边境城仍可作为一步攻势目标。
		launchable_targets.append(target_city)
		route_plans[target_city] = route_plan
	if launchable_targets.is_empty():
		return false
	var base_organization_cost := _campaign_offensive_gold_cost(
		nation_id,
		launchable_targets
	)
	var organization_cost := int(ceil(
		float(base_organization_cost)
			* (1.0 - DiplomacyAI.unification_era_factor(state))
	))
	if (
		base_organization_cost <= 0
		or nation.treasury_gold < organization_cost
	):
		return false
	for target_city in launchable_targets:
		var target_required := (
			_campaign_minimum_staged_troops(
				nation_id,
				target_city
			)
		)
		var target_attackers := _campaign_initial_attackers(
			nation_id,
			target_city
		)
		# 首批必须同步投入整个第0梯队。正式地图用“1”表示持久战团
		# 已完成资格校验，不能把这个资格哨兵误当成实际提交兵力，
		# 否则一个完整战团首日只会冲出第一支军，形成低烈度添油。
		var initial_commit_target := 0
		for attacker in target_attackers:
			initial_commit_target += attacker.size
		var route_plan: Dictionary = route_plans[target_city]
		var target_committed := 0
		var origin_cities: Array[int] = []
		for army in target_attackers:
			var origin_city := _campaign_army_origin(
				army,
				nation_id
			)
			var attack := ActionCandidate.make(
				ActionCandidate.Kind.ATTACK,
				2000.0,
				(
					"国家战役第%d波：军%d按计划准备%d天，"
					+ "以%.2f倍攻击城市%d"
				) % [
					nation.campaign_offensive_count + 1,
					army.id,
					preparation_days,
					offensive_multiplier,
					target_city,
				],
				target_city
			)
			attack.minimum_commit_days = (
				CAMPAIGN_OFFENSIVE_COMMIT_DAYS
			)
			attack.offensive_attack_multiplier = (
				offensive_multiplier
			)
			attack.offensive_bonus_days = (
				offensive_bonus_days
			)
			if _execute_ai_candidate(army, attack):
				target_committed += army.size
				launched = true
				nation.campaign_launched_armies[army.id] = true
				if (
					origin_city >= 0
					and not origin_cities.has(
						origin_city
					)
				):
					origin_cities.append(origin_city)
			if target_committed >= initial_commit_target:
				break
		if not origin_cities.is_empty():
			launched_origins[target_city] = origin_cities
			nation.campaign_active_echelons[target_city] = 0
			nation.campaign_echelon_started_days[target_city] = (
				state.day
			)
			if not route_plan.is_empty():
				nation.campaign_post_capture_plans[target_city] = (
					route_plan
				)
			else:
				nation.campaign_post_capture_plans.erase(
					target_city
				)
	if launched:
		nation.treasury_gold -= organization_cost
		nation.last_offensive_gold_cost = organization_cost
		nation.last_offensive_gold_day = state.day
		nation.campaign_launched_attack_multiplier = (
			offensive_multiplier
		)
		nation.campaign_launched_bonus_days = (
			offensive_bonus_days
		)
		nation.campaign_last_offensive_day = state.day
		nation.campaign_theater_anchor_city = objective_city
		nation.campaign_theater_started_day = state.day
		_clear_campaign_preparation_plan(nation_id)
		nation.campaign_next_offensive_day = (
			state.day + _campaign_offensive_interval(nation_id)
		)
		nation.campaign_offensive_count += 1
		var launched_targets := launched_origins.keys()
		EquivariantOrder.sort_city_ids(
			launched_targets,
			state,
			nation_id,
			objective_city
		)
		for target_city_value in launched_targets:
			var target_city := int(target_city_value)
			state.add_campaign_visual_event(
				nation_id,
				target_city,
				launched_origins[target_city],
				nation.campaign_offensive_count,
				CAMPAIGN_ARROW_DURATION_DAYS
			)
	return launched


## 正式地图从 CampaignAllocationPlan 一次冻结并发射。所有 payload 先在
## 局部变量中完成校验，旧 active wave、国库和准备态在提交前均保持不变。
func _launch_group_campaign_offensive(
	nation_id: int,
	objective_city: int,
	preparation_days: int,
	prepared_targets: Array[int],
	route_threat_override: ThreatField
) -> bool:
	var nation := state.nations[nation_id]
	_reconcile_campaign_active_wave(nation_id)
	# 当前模型只有一个 active-wave 容器；允许并行准备下一波，但不能
	# 在上一波仍执行时覆盖它。若未来要求多波同时在途，应按 wave_id 建模。
	if not nation.campaign_plan_targets.is_empty():
		return false
	var plan := nation.campaign_preparation_plan
	if plan == null or plan.nation_id != nation_id:
		return false
	var requested_targets: Array[int] = []
	if prepared_targets.is_empty():
		requested_targets.append(objective_city)
	else:
		for target_value in prepared_targets:
			var target_city := int(target_value)
			if not requested_targets.has(target_city):
				requested_targets.append(target_city)
	var army_by_id := {}
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			army_by_id[army.id] = army
	var wave_targets: Array[int] = []
	var wave_assignments := {}
	var wave_echelons := {}
	var initial_attackers_by_target := {}
	for target_city in plan.assigned_target_ids:
		if (
			not requested_targets.has(target_city)
			or target_city < 0
			or target_city >= state.cities.size()
			or not state.is_enemy(
				nation_id, state.cities[target_city].owner_nation
			)
		):
			continue
		var members_by_group := {}
		var staging := DiplomacyAI.staging_cities_for_objective(
			state, nation_id, target_city
		)
		var planned_group_ids := plan.groups_for_target(target_city)
		for group_id in planned_group_ids:
			if state.battle_group_by_id(nation_id, group_id) == null:
				return false
			for army_id in plan.member_ids_for_group(group_id):
				var army: Army = army_by_id.get(army_id)
				if (
					army == null
					or army.battle_group_id != group_id
					or int(nation.campaign_preparation_assignments.get(
						army.id, -1
					)) != target_city
				):
					return false
				var ready := _army_ready_for_campaign_target(
					army, nation_id, target_city
				)
				var staging_in_transit := (
					army.state == Army.State.MOVING
					and army.ai_action in [
						ActionCandidate.Kind.REINFORCE,
						ActionCandidate.Kind.RETREAT,
					]
					and staging.has(army.ai_target_city)
				)
				if not ready and not staging_in_transit:
					continue
				if (
					ready
					and not _campaign_army_can_attack_target(
						army, nation_id, target_city
					)
				):
					return false
				if not members_by_group.has(group_id):
					members_by_group[group_id] = [] as Array[Army]
				(members_by_group[group_id] as Array[Army]).append(army)
		if members_by_group.is_empty():
			continue
		# 梯队以战团为原子。先按“团内至少一员已到集结线”稳定分区，
		# 再保持 planner 的团序；同团成员绝不拆到不同 echelon。
		var ordered_groups: Array[int] = []
		for ready_pass in [true, false]:
			for group_id in planned_group_ids:
				if not members_by_group.has(group_id):
					continue
				var group_ready := false
				for army in members_by_group[group_id] as Array[Army]:
					if _army_ready_for_campaign_target(
						army, nation_id, target_city
					):
						group_ready = true
						break
				if group_ready == ready_pass:
					ordered_groups.append(group_id)
		var demand: Dictionary = plan.target_demands.get(target_city, {})
		var assault_group_count := maxi(
			int(demand.get("assault_groups", 1)), 1
		)
		var initial_attackers: Array[Army] = []
		for group_index in range(ordered_groups.size()):
			var group_id := ordered_groups[group_index]
			var echelon := int(group_index / assault_group_count)
			var group_members: Array[Army] = members_by_group[group_id]
			group_members = _sort_campaign_priority(
				group_members, nation_id, target_city
			)
			for army in group_members:
				wave_assignments[army.id] = target_city
				wave_echelons[army.id] = echelon
				if (
					echelon == 0
					and _army_ready_for_campaign_target(
						army, nation_id, target_city
					)
				):
					initial_attackers.append(army)
		if initial_attackers.is_empty():
			continue
		wave_targets.append(target_city)
		initial_attackers_by_target[target_city] = initial_attackers
	if wave_targets.is_empty() or not wave_targets.has(objective_city):
		return false
	# 只为真正进入本波的目标计费；未就绪目标不会把其成员带入费用。
	for army_id_value in wave_assignments.keys().duplicate():
		var army_id := int(army_id_value)
		if not wave_targets.has(int(wave_assignments[army_id])):
			wave_assignments.erase(army_id)
			wave_echelons.erase(army_id)
	var participants: Array[Army] = []
	for army_id in wave_assignments:
		var participant: Army = army_by_id.get(int(army_id))
		if participant != null:
			participants.append(participant)
	var base_organization_cost := offensive_organization_gold_cost(
		participants
	)
	var organization_cost := int(ceil(
		float(base_organization_cost)
			* (1.0 - DiplomacyAI.unification_era_factor(state))
	))
	if (
		base_organization_cost <= 0
		or nation.treasury_gold < organization_cost
	):
		return false
	if preparation_days < 0:
		preparation_days = _campaign_preparation_days(nation_id)
	var multiplier := offensive_preparation_multiplier(preparation_days)
	var bonus_days := offensive_bonus_duration_days(preparation_days)
	var route_threat := route_threat_override
	if route_threat == null:
		route_threat = ThreatField.build(
			_build_ai_view(nation_id), _threat_travel_cache
		)
	var route_plans := {}
	for target_city in wave_targets:
		route_plans[target_city] = _campaign_two_step_route_plan_for_group(
			nation_id, target_city,
			initial_attackers_by_target[target_city], route_threat, plan
		)

	# 构造不可变提交 payload。命令收集模式下，只有统一提交阶段确认
	# 同一 transaction 的全部命令实际成功后，才消费准备态并扣费。
	var launched_origins := {}
	var initial_army_ids := {}
	var transaction_id := -1
	var transaction_buffer_start := _ai_command_buffer.size()
	var immediate_intents: Array[AiCommandIntent] = []
	if _collect_ai_commands:
		transaction_id = _next_ai_command_transaction_id
		_next_ai_command_transaction_id += 1
		_ai_queue_transaction_id = transaction_id
	var queued_or_executed := 0
	for target_city in wave_targets:
		var origin_cities: Array[int] = []
		for army in initial_attackers_by_target[target_city] as Array[Army]:
			var origin_city := _campaign_army_origin(army, nation_id)
			var attack := ActionCandidate.make(
				ActionCandidate.Kind.ATTACK, 2000.0,
				"国家战役第%d波：军%d按统一计划准备%d天，以%.2f倍攻击城市%d"
					% [nation.campaign_offensive_count + 1, army.id,
						preparation_days, multiplier, target_city],
				target_city
			)
			attack.minimum_commit_days = CAMPAIGN_OFFENSIVE_COMMIT_DAYS
			attack.offensive_attack_multiplier = multiplier
			attack.offensive_bonus_days = bonus_days
			if _collect_ai_commands:
				if not _execute_ai_candidate(army, attack):
					continue
			else:
				var immediate_intent := _build_campaign_attack_intent(
					army, attack
				)
				if immediate_intent == null:
					continue
				immediate_intents.append(immediate_intent)
			queued_or_executed += 1
			initial_army_ids[army.id] = true
			if origin_city >= 0 and not origin_cities.has(origin_city):
				origin_cities.append(origin_city)
		if not origin_cities.is_empty():
			launched_origins[target_city] = origin_cities
	if _collect_ai_commands:
		_ai_queue_transaction_id = -1
	if queued_or_executed <= 0:
		return false
	var expected_initial_commands := 0
	for target_city in wave_targets:
		expected_initial_commands += (
			initial_attackers_by_target[target_city] as Array
		).size()
	if queued_or_executed != expected_initial_commands:
		if _collect_ai_commands:
			# 一笔战役事务必须整批入队；释放本批预留并重建此前普通
			# intent 的首段容量，不能留下半批游离攻击命令。
			_ai_command_buffer.resize(transaction_buffer_start)
			_rebuild_ai_command_reservations()
		return false
	var payload := {
		"created_day": state.day,
		"nation_id": nation_id,
		"expected_offensive_count": nation.campaign_offensive_count,
		"expected_plan": plan.duplicate_plan(),
		"expected_preparation_targets": (
			nation.campaign_preparation_targets.duplicate()
		),
		"expected_preparation_assignments": (
			nation.campaign_preparation_assignments.duplicate(true)
		),
		"expected_preparation_group_assignments": (
			nation.campaign_preparation_group_assignments.duplicate(true)
		),
		"expected_full_preparation_targets": (
			nation.campaign_full_preparation_targets.duplicate()
		),
		"expected_preparation_started_day": (
			nation.campaign_preparation_started_day
		),
		"expected_intent_count": initial_army_ids.size(),
		"objective_city": objective_city,
		"wave_assignments": wave_assignments.duplicate(true),
		"wave_echelons": wave_echelons.duplicate(true),
		"wave_targets": wave_targets.duplicate(),
		"initial_army_ids": initial_army_ids.duplicate(true),
		"launched_origins": launched_origins.duplicate(true),
		"route_plans": route_plans.duplicate(true),
		"organization_cost": organization_cost,
		"multiplier": multiplier,
		"bonus_days": bonus_days,
	}
	var participant_fingerprints := {}
	for army_id in wave_assignments:
		var participant: Army = army_by_id.get(int(army_id))
		if participant == null:
			return false
		participant_fingerprints[int(army_id)] = (
			_campaign_transaction_army_fingerprint(participant)
		)
	payload["participant_fingerprints"] = participant_fingerprints
	if _collect_ai_commands:
		_pending_campaign_launch_transactions[transaction_id] = payload
		for army_id in wave_assignments:
			_ai_transaction_reserved_armies[int(army_id)] = transaction_id
		return true
	if not _validate_campaign_launch_payload(payload, immediate_intents):
		return false
	for intent in immediate_intents:
		_apply_prevalidated_campaign_intent(intent)
	_apply_campaign_launch_payload_unchecked(payload)
	return true


func _rebuild_ai_command_reservations() -> void:
	_ai_planned_armies.clear()
	_ai_planned_first_legs.clear()
	_ai_command_sequence.clear()
	_ai_transaction_reserved_armies.clear()
	for transaction_id_value in _pending_campaign_launch_transactions:
		var transaction_id := int(transaction_id_value)
		var payload: Dictionary = (
			_pending_campaign_launch_transactions[transaction_id_value]
		)
		for army_id in (payload.get("wave_assignments", {}) as Dictionary):
			_ai_transaction_reserved_armies[int(army_id)] = transaction_id
	for intent in _ai_command_buffer:
		_ai_planned_armies[intent.army.id] = true
		_ai_command_sequence[intent.nation_id] = maxi(
			int(_ai_command_sequence.get(intent.nation_id, 0)),
			intent.sequence + 1
		)
		if intent.prepared_path.is_empty() or intent.army.state != Army.State.IDLE:
			continue
		var first_leg := intent.prepared_path[0]
		var first_edge := state.edge_of(
			intent.army.location_city, first_leg
		)
		if first_edge == null or first_edge.max_manpower <= 0:
			continue
		var key := _ai_first_leg_key(
			intent.nation_id, intent.army.location_city, first_leg
		)
		_ai_planned_first_legs[key] = int(
			_ai_planned_first_legs.get(key, 0)
		) + intent.army.road_capacity_load(
			first_edge.max_manpower
		)


func _build_campaign_attack_intent(
	army: Army,
	candidate: ActionCandidate,
	transaction_id: int = -1
) -> AiCommandIntent:
	if (
		army == null or army.size <= 0
		or candidate == null
		or candidate.kind != ActionCandidate.Kind.ATTACK
		or not _can_queue_ai_candidate(army, candidate)
	):
		return null
	var prepared_path: Array[int] = []
	var path_prevalidated := false
	if army.state == Army.State.IDLE:
		var field := _cached_ai_path_field(
			army.owner_nation, army.location_city, army.owner_nation,
			false, false, candidate.target_city, army.max_size
		)
		prepared_path = Pathfinding.reconstruct(
			field["prev"], army.location_city, candidate.target_city
		)
		if prepared_path.is_empty():
			return null
		path_prevalidated = true
	return AiCommandIntent.make(
		army, candidate, 0, prepared_path, path_prevalidated, transaction_id
	)


func _campaign_transaction_army_fingerprint(army: Army) -> Array:
	return [
		army.owner_nation, army.size, army.max_size, army.battle_group_id,
		army.state, army.location_city, army.move_from, army.move_to,
		army.on_edge, army.battle_id,
	]


func _campaign_active_wave_present(nation: Nation) -> bool:
	return (
		not nation.campaign_plan_targets.is_empty()
		or not nation.campaign_attack_assignments.is_empty()
		or not nation.campaign_attack_echelons.is_empty()
		or not nation.campaign_active_echelons.is_empty()
		or not nation.campaign_launched_armies.is_empty()
		or not nation.campaign_echelon_started_days.is_empty()
		or not nation.campaign_post_capture_plans.is_empty()
		or nation.campaign_plan_wave >= 0
	)


func _validate_campaign_launch_payload(
	payload: Dictionary,
	intents: Array[AiCommandIntent]
) -> bool:
	var nation_id := int(payload.get("nation_id", -1))
	if nation_id < 0 or nation_id >= state.nations.size():
		return false
	var nation := state.nations[nation_id]
	var organization_cost := int(payload.get("organization_cost", 0))
	if (
		int(payload.get("created_day", -1)) != state.day
		or int(payload.get("expected_offensive_count", -1))
			!= nation.campaign_offensive_count
		or organization_cost < 0
		or nation.treasury_gold < organization_cost
		or _campaign_active_wave_present(nation)
		or nation.campaign_preparation_plan == null
	):
		return false
	var expected_plan: CampaignAllocationPlan = payload.get("expected_plan")
	if (
		expected_plan == null
		or not nation.campaign_preparation_plan.same_allocation(expected_plan)
		or nation.campaign_preparation_targets
			!= payload.get("expected_preparation_targets", [])
		or nation.campaign_preparation_assignments
			!= payload.get("expected_preparation_assignments", {})
		or nation.campaign_preparation_group_assignments
			!= payload.get("expected_preparation_group_assignments", {})
		or nation.campaign_full_preparation_targets
			!= payload.get("expected_full_preparation_targets", [])
		or nation.campaign_preparation_started_day
			!= int(payload.get("expected_preparation_started_day", -1))
		or intents.size() != int(payload.get("expected_intent_count", -1))
	):
		return false
	var initial_ids: Dictionary = payload.get("initial_army_ids", {})
	var wave_assignments: Dictionary = payload.get("wave_assignments", {})
	var wave_echelons: Dictionary = payload.get("wave_echelons", {})
	for target_value in payload.get("wave_targets", []):
		var target_city := int(target_value)
		if (
			target_city < 0 or target_city >= state.cities.size()
			or not state.is_enemy(
				nation_id, state.cities[target_city].owner_nation
			)
		):
			return false
	if wave_assignments.keys().size() != wave_echelons.keys().size():
		return false
	var participant_armies: Array[Army] = []
	var expected_fingerprints: Dictionary = payload.get(
		"participant_fingerprints", {}
	)
	for army_id_value in wave_assignments:
		var army_id := int(army_id_value)
		var participant: Army = null
		for candidate_army in state.armies:
			if candidate_army.id == army_id:
				participant = candidate_army
				break
		var target_city := int(wave_assignments[army_id_value])
		if (
			participant == null or participant.size <= 0
			or participant.owner_nation != nation_id
			or not wave_echelons.has(army_id_value)
			or expected_plan.target_for_group(participant.battle_group_id)
				!= target_city
			or _campaign_transaction_army_fingerprint(participant)
				!= expected_fingerprints.get(army_id, [])
		):
			return false
		participant_armies.append(participant)
	var current_base_cost := offensive_organization_gold_cost(
		participant_armies
	)
	var current_cost := int(ceil(
		float(current_base_cost)
			* (1.0 - DiplomacyAI.unification_era_factor(state))
	))
	if current_cost != organization_cost:
		return false
	var seen_ids := {}
	for intent in intents:
		if (
			intent == null or intent.army == null
			or intent.nation_id != nation_id
			or intent.candidate.kind != ActionCandidate.Kind.ATTACK
			or seen_ids.has(intent.army.id)
			or not initial_ids.has(intent.army.id)
			or intent.army.size <= 0
			or intent.army.owner_nation != nation_id
			or int(wave_assignments.get(intent.army.id, -1))
				!= intent.candidate.target_city
			or int(wave_echelons.get(intent.army.id, -1)) != 0
		):
			return false
		seen_ids[intent.army.id] = true
		if intent.army.state == Army.State.HOLDING:
			if intent.candidate.target_city not in [
				intent.army.move_from, intent.army.move_to
			]:
				return false
			continue
		if (
			intent.army.state != Army.State.IDLE
			or intent.prepared_path.is_empty()
			or intent.prepared_path[-1] != intent.candidate.target_city
		):
			return false
		var from_city := intent.army.location_city
		for to_city in intent.prepared_path:
			var edge := state.edge_of(from_city, to_city)
			if (
				edge == null
				or edge.max_manpower < intent.army.road_footprint()
			):
				return false
			from_city = to_city
		# 同批多军可共享首段并排队；_begin_next_leg 对暂时满载的边
		# 保留完整路径和 move_to=-1，待后续日容量释放，不是事务失败。
	if seen_ids.size() != initial_ids.size():
		return false
	return true


func _apply_prevalidated_campaign_intent(intent: AiCommandIntent) -> void:
	var army := intent.army
	var candidate := intent.candidate
	if army.state == Army.State.HOLDING:
		if candidate.target_city == army.move_from:
			var old_from := army.move_from
			army.move_from = army.move_to
			army.move_to = old_from
			army.move_progress = 1.0 - army.move_progress
		_set_occupation_claimant_for_crossing(
			army, army.move_from, army.move_to
		)
		army.state = Army.State.MOVING
		army.holding_days = 0
		army.hold_target_progress = -1.0
		army.path.clear()
		_record_ai_order(army, candidate)
		return
	army.path = intent.prepared_path.duplicate()
	army.hold_target_progress = -1.0
	army.state = Army.State.MOVING
	army.move_from = army.location_city
	army.move_to = -1
	army.move_progress = 0.0
	_begin_next_leg(army)
	_record_ai_order(army, candidate)


func _apply_campaign_launch_payload_unchecked(payload: Dictionary) -> void:
	var nation_id := int(payload["nation_id"])
	var nation := state.nations[nation_id]
	var organization_cost := int(payload["organization_cost"])
	var wave_targets: Array[int] = []
	wave_targets.assign(payload["wave_targets"])
	var initial_army_ids: Dictionary = payload["initial_army_ids"]
	var route_plans: Dictionary = payload["route_plans"]
	nation.campaign_attack_assignments = (
		(payload["wave_assignments"] as Dictionary).duplicate(true)
	)
	nation.campaign_attack_echelons = (
		(payload["wave_echelons"] as Dictionary).duplicate(true)
	)
	nation.campaign_plan_targets = wave_targets
	nation.campaign_plan_wave = int(payload["expected_offensive_count"]) + 1
	nation.campaign_plan_primary_city = int(payload["objective_city"])
	nation.campaign_active_echelons.clear()
	nation.campaign_launched_armies = initial_army_ids.duplicate(true)
	nation.campaign_echelon_started_days.clear()
	for target_city in wave_targets:
		var target_launched := false
		for army_id in initial_army_ids:
			if int(nation.campaign_attack_assignments.get(army_id, -1)) == target_city:
				target_launched = true
				break
		if not target_launched:
			continue
		nation.campaign_active_echelons[target_city] = 0
		nation.campaign_echelon_started_days[target_city] = state.day
		var route_plan: Dictionary = route_plans.get(target_city, {})
		if route_plan.is_empty():
			nation.campaign_post_capture_plans.erase(target_city)
		else:
			nation.campaign_post_capture_plans[target_city] = route_plan
	nation.treasury_gold -= organization_cost
	nation.last_offensive_gold_cost = organization_cost
	nation.last_offensive_gold_day = state.day
	nation.campaign_launched_attack_multiplier = float(payload["multiplier"])
	nation.campaign_launched_bonus_days = int(payload["bonus_days"])
	nation.campaign_last_offensive_day = state.day
	nation.campaign_theater_anchor_city = int(payload["objective_city"])
	nation.campaign_theater_started_day = state.day
	_clear_campaign_preparation_plan(nation_id)
	nation.campaign_next_offensive_day = (
		state.day + _campaign_offensive_interval(nation_id)
	)
	nation.campaign_offensive_count += 1
	var launched_origins: Dictionary = payload["launched_origins"]
	for target_city in launched_origins:
		state.add_campaign_visual_event(
			nation_id, int(target_city), launched_origins[target_city],
			nation.campaign_offensive_count, CAMPAIGN_ARROW_DURATION_DAYS
		)


func _campaign_initial_attackers(
	nation_id: int,
	target_city: int
) -> Array[Army]:
	var nation := state.nations[nation_id]
	var result: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) != target_city
			or int(
				nation.campaign_attack_echelons.get(
					army.id,
					0
				)
			) != 0
			or not _army_ready_for_campaign_target(
				army,
				nation_id,
				target_city
			)
			or not _campaign_army_can_attack_target(
				army,
				nation_id,
				target_city
			)
		):
			continue
		result.append(army)
	result.sort_custom(
		func(a: Army, b: Army) -> bool:
			if a.size != b.size:
				return a.size > b.size
			return EquivariantOrder.army_less(
				state,
				nation_id,
				a,
				b,
				target_city
			)
	)
	return result


func _campaign_army_can_attack_target(
	army: Army,
	nation_id: int,
	target_city: int
) -> bool:
	var origin := _campaign_army_origin(army, nation_id)
	if origin < 0:
		return false
	var field := _cached_ai_path_field(
		nation_id,
		origin,
		nation_id,
		false,
		true,
		target_city,
		army.max_size
	)
	return float(field["dist"].get(target_city, INF)) < INF


func _campaign_two_step_route_plan(
	nation_id: int,
	target_city: int,
	target_attackers: Array[Army],
	threat: ThreatField
) -> Dictionary:
	if target_attackers.is_empty():
		return {}
	var nation := state.nations[nation_id]
	var route_army: Army = target_attackers[0]
	var heavy_army_id := -1
	for candidate in target_attackers:
		if (
			candidate.max_size
				>= GameState.INITIAL_HEAVY_ARMY_SIZE
		):
			route_army = candidate
			heavy_army_id = candidate.id
			break
	var defender_nation := state.cities[
		target_city
	].owner_nation
	var next_step := _campaign_post_capture_target(
		route_army,
		state.cities[target_city],
		threat,
		defender_nation
	)
	if next_step.is_empty():
		return {}
	return {
		"next_city": int(next_step["city_id"]),
		"group_id": int(
			nation.campaign_preparation_group_assignments.get(
				target_city,
				-1
			)
		),
		"heavy_army_id": heavy_army_id,
		"execution_army_id": route_army.id,
		"enemy_nation": defender_nation,
		"created_day": state.day,
		"steps": CAMPAIGN_REQUIRED_ATTACK_STEPS,
	}


func _campaign_two_step_route_plan_for_group(
	nation_id: int,
	target_city: int,
	target_attackers: Array[Army],
	threat: ThreatField,
	plan: CampaignAllocationPlan
) -> Dictionary:
	if target_attackers.is_empty() or plan == null:
		return {}
	var route_army: Army = target_attackers[0]
	var heavy_army_id := -1
	for candidate in target_attackers:
		if candidate.max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
			route_army = candidate
			heavy_army_id = candidate.id
			break
	var defender_nation := state.cities[target_city].owner_nation
	var next_step := _campaign_post_capture_target(
		route_army, state.cities[target_city], threat, defender_nation
	)
	if next_step.is_empty():
		return {}
	var groups := plan.groups_for_target(target_city)
	return {
		"next_city": int(next_step["city_id"]),
		"group_id": groups[0] if not groups.is_empty() else -1,
		"heavy_army_id": heavy_army_id,
		"execution_army_id": route_army.id,
		"enemy_nation": defender_nation,
		"created_day": state.day,
		"steps": CAMPAIGN_REQUIRED_ATTACK_STEPS,
	}


static func offensive_organization_gold_cost(
	participants: Array[Army]
) -> int:
	var total := 0
	for army in participants:
		if army != null and army.size > 0:
			total += GameState.offensive_army_gold_cost(
				army.size
			)
	return total


func _campaign_offensive_gold_cost(
	nation_id: int,
	target_filter: Array[int] = []
) -> int:
	var nation := state.nations[nation_id]
	var participants: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or not nation.campaign_attack_assignments.has(
				army.id
			)
		):
			continue
		var target_city := int(
			nation.campaign_attack_assignments.get(
				army.id,
				-1
			)
		)
		if (
			not nation.campaign_plan_targets.has(target_city)
			or target_city < 0
			or target_city >= state.cities.size()
			or not state.is_enemy(
				nation_id,
				state.cities[target_city].owner_nation
			)
			or (
				not target_filter.is_empty()
				and not target_filter.has(target_city)
			)
		):
			continue
		participants.append(army)
	return offensive_organization_gold_cost(participants)


## 既有战役计划的执行续接。前梯队进入目标城市后即开放下一梯队，让道路容量
## 自然形成连续纵队；若前梯队提前失去作战能力，仍沿用次日接替规则。
func _advance_campaign_echelons() -> void:
	var armies_by_nation := {}
	for nation in state.nations:
		if nation.alive and not nation.campaign_plan_targets.is_empty():
			armies_by_nation[nation.id] = [] as Array[Army]
	if armies_by_nation.is_empty():
		return
	# 每日只扫描一次全军。旧实现会为每个有战役计划的国家再扫一遍，
	# 多国并行战争时退化为 O(活跃战役国×全军数)。保留 state.armies
	# 原顺序，后续梯队判定与发令结果不变。
	for army in state.armies:
		if (
			army.size > 0
			and armies_by_nation.has(army.owner_nation)
		):
			(armies_by_nation[army.owner_nation] as Array[Army]).append(army)
	for nation in state.nations:
		if not nation.alive or nation.campaign_plan_targets.is_empty():
			continue
		var nation_armies: Array[Army] = armies_by_nation[nation.id]
		var targets := nation.campaign_plan_targets.duplicate()
		EquivariantOrder.sort_city_ids(
			targets,
			state,
			nation.id
		)
		for target_city_value in targets:
			var target_city := int(target_city_value)
			if (
				target_city < 0
				or target_city >= state.cities.size()
				or not state.is_enemy(
					nation.id,
					state.cities[target_city].owner_nation
				)
			):
				_remove_campaign_target(nation.id, target_city)
				continue
			var active_echelon := int(
				nation.campaign_active_echelons.get(
					target_city,
					-1
				)
			)
			if active_echelon < 0:
				continue
			# 首批成员可能受道路容量限制而稍后抵达集结位，也可能已有
			# 成员在途中阵亡。每日至少先补发当前梯队的就绪成员；否则
			# operational=false 时直接跳到下一梯队，会把当前梯队遗留成员
			# 永久锁在 active wave 中。
			_launch_campaign_echelon_members(
				nation.id,
				target_city,
				active_echelon,
				false,
				false,
				nation_armies
			)
			if _campaign_echelon_operational(
				nation.id,
				target_city,
				active_echelon,
				nation_armies
			):
				if _campaign_echelon_engaged_at_target(
					nation.id,
					target_city,
					active_echelon,
					nation_armies
				):
					_launch_campaign_echelon_members(
						nation.id,
						target_city,
						active_echelon + 1,
						true,
						false,
						nation_armies
					)
				continue
			_launch_campaign_echelon_members(
				nation.id,
				target_city,
				active_echelon + 1,
				true,
				true,
				nation_armies
			)


func _campaign_echelon_engaged_at_target(
	nation_id: int,
	target_city: int,
	echelon: int,
	nation_armies: Array[Army]
) -> bool:
	var nation := state.nations[nation_id]
	for army in nation_armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.state != Army.State.FIGHTING
			or not nation.campaign_launched_armies.has(army.id)
			or int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) != target_city
			or int(
				nation.campaign_attack_echelons.get(
					army.id,
					-1
				)
			) != echelon
		):
			continue
		var battle := state.battle_by_id(army.battle_id)
		if (
			battle != null
			and not battle.finished
			and battle.kind == Battle.Kind.SIEGE
			and battle.city != null
			and battle.city.id == target_city
		):
			return true
	return false


func _campaign_echelon_operational(
	nation_id: int,
	target_city: int,
	echelon: int,
	nation_armies: Array[Army]
) -> bool:
	var nation := state.nations[nation_id]
	for army in nation_armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and nation.campaign_launched_armies.has(army.id)
			and int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) == target_city
			and int(
				nation.campaign_attack_echelons.get(
					army.id,
					-1
				)
			) == echelon
			and army.state in [
				Army.State.MOVING,
				Army.State.FIGHTING,
			]
		):
			return true
	return false


func _launch_campaign_echelon_members(
	nation_id: int,
	target_city: int,
	echelon: int,
	followup: bool,
	require_sufficient: bool,
	nation_armies: Array[Army]
) -> bool:
	var nation := state.nations[nation_id]
	var attackers: Array[Army] = []
	var ready_troops := 0
	for army in nation_armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or nation.campaign_launched_armies.has(army.id)
			or int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) != target_city
			or int(
				nation.campaign_attack_echelons.get(
					army.id,
					-1
				)
			) != echelon
			or not _army_ready_for_campaign_target(
				army,
				nation_id,
				target_city
			)
		):
			continue
		attackers.append(army)
		ready_troops += army.size
	if attackers.is_empty():
		return false
	var required := _campaign_minimum_staged_troops(
		nation_id,
		target_city
	)
	if require_sufficient and ready_troops < required:
		return false
	attackers.sort_custom(func(a: Army, b: Army) -> bool:
		if a.size != b.size:
			return a.size > b.size
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a,
			b,
			target_city
		)
	)
	var launched := false
	var origin_cities: Array[int] = []
	for army in attackers:
		var origin_city := _campaign_army_origin(
			army,
			nation_id
		)
		var attack := ActionCandidate.make(
			ActionCandidate.Kind.ATTACK,
			2000.0,
			(
				"持续攻势第%d梯队：军%d接替前梯队攻击城市%d"
				% [echelon + 1, army.id, target_city]
				if followup
				else "国家战役第%d梯队：军%d继续攻击城市%d"
					% [echelon + 1, army.id, target_city]
			),
			target_city
		)
		attack.minimum_commit_days = CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		attack.offensive_attack_multiplier = (
			nation.campaign_launched_attack_multiplier
		)
		attack.offensive_bonus_days = (
			nation.campaign_launched_bonus_days
		)
		if not _execute_ai_candidate(army, attack):
			continue
		nation.campaign_launched_armies[army.id] = true
		launched = true
		if origin_city >= 0 and not origin_cities.has(origin_city):
			origin_cities.append(origin_city)
	if not launched:
		return false
	nation.campaign_active_echelons[target_city] = echelon
	nation.campaign_echelon_started_days[target_city] = state.day
	state.add_campaign_visual_event(
		nation_id,
		target_city,
		origin_cities,
		nation.campaign_offensive_count,
		CAMPAIGN_ARROW_DURATION_DAYS
	)
	return true


## 对正在围攻的重点城市持续派遣纵深预备队。这里不保存平行的防御任务表：
## Army.ai_target_city 是在途任务真源，战斗与道路占用则直接从 GameState 派生。
func _advance_priority_city_defense_echelons(
	spread_runtime_work: bool = false
) -> void:
	_set_runtime_profile_stage(&"priority_defense_scan")
	var sieges: Array[Battle] = []
	var context_by_nation := {}
	var diplomacy_cache := {}
	for battle in state.battles:
		if (
			not battle.finished
			and battle.kind == Battle.Kind.SIEGE
			and battle.city != null
			and not battle.side_a.is_empty()
		):
			sieges.append(battle)
	var defense_gap_by_city := {}
	for siege in sieges:
		defense_gap_by_city[siege.city.id] = (
			_siege_local_defense_gap(siege)
		)
	sieges.sort_custom(func(a: Battle, b: Battle) -> bool:
		var gap_a := float(defense_gap_by_city[a.city.id])
		var gap_b := float(defense_gap_by_city[b.city.id])
		if not is_equal_approx(gap_a, gap_b):
			return gap_a > gap_b
		return EquivariantOrder.mirror_orbit_city_less(
			state,
			a.city.id,
			b.city.id
		)
	)
	var runtime_slice_started := Time.get_ticks_usec()
	for siege in sieges:
		if (
			spread_runtime_work
			and Time.get_ticks_usec() - runtime_slice_started
				>= AI_RUNTIME_SLICE_BUDGET_USEC
		):
			await get_tree().process_frame
			runtime_slice_started = Time.get_ticks_usec()
		var city_id := siege.city.id
		var nation_id := siege.city.owner_nation
		if (
			nation_id < 0
			or nation_id >= state.nations.size()
			or not state.nations[nation_id].alive
		):
			continue
		if not context_by_nation.has(nation_id):
			var revision := [
				state.ownership_revision,
				state.diplomacy_revision,
				state.fortification_revision,
			]
			var cached_snapshot: StrategicMapSnapshot = null
			if (
				_ai_strategy_cache.has(nation_id)
				and _ai_strategy_revision.get(
					nation_id,
					[]
				) == revision
			):
				cached_snapshot = _ai_strategy_cache[nation_id]
			context_by_nation[nation_id] = {
				"view": null,
				"snapshot": cached_snapshot,
				"threat": null,
			}
		var context: Dictionary = context_by_nation[nation_id]
		var snapshot: StrategicMapSnapshot = context["snapshot"]
		if snapshot == null:
			var initial_view := _build_ai_view(nation_id)
			# 同一日的所有重点城解围共享一份贸易/财政预测。旧路径给每个
			# 受围国家传空缓存，StrategicMapSnapshot._find_frontier() 会经
			# threat_from_nation 重复构建整张贸易网，500 城多围城时成为主热点。
			if diplomacy_cache.is_empty():
				_seed_trade_forecast(diplomacy_cache)
			snapshot = _strategy_snapshot_for(
				initial_view, diplomacy_cache
			)
			context["view"] = initial_view
			context["snapshot"] = snapshot
		var priority_defense := _is_priority_defense_city(
			nation_id,
			city_id,
			snapshot
		)
		if not priority_defense:
			continue
		var attack_power := 0.0
		for army in siege.side_a:
			if army.size > 0:
				attack_power += ArmyPower.effective(army)
		var committed_power := ArmyPower.city_defense(siege.city)
		for army in siege.side_b:
			if army.size > 0 and army.owner_nation == nation_id:
				committed_power += ArmyPower.effective(army)
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and army.state == Army.State.MOVING
				and army.ai_action in [
					ActionCandidate.Kind.REINFORCE,
					ActionCandidate.Kind.RETREAT,
				]
				and army.ai_target_city == city_id
			):
				committed_power += ArmyPower.effective(army)
		# 已在途的梯队足以填平当前战斗缺口时，无需重建完整国家防区。
		if committed_power >= attack_power:
			continue
		var view: AiWorldView = context["view"]
		if view == null:
			view = _build_ai_view(nation_id)
			context["view"] = view
		var threat: ThreatField = context["threat"]
		if threat == null:
			threat = ThreatField.build(
				view,
				_threat_travel_cache
			)
			context["threat"] = threat
		var defense_plan := CityDefensePlan.build(
			view,
			snapshot,
			threat,
			_ai_defense_plan_cache.get(nation_id)
		)
		_record_defense_plan_cache_result(defense_plan)
		_ai_defense_plan_cache[nation_id] = defense_plan
		_advance_priority_city_defense(
			siege,
			defense_plan
		)


func _siege_local_defense_gap(siege: Battle) -> float:
	if siege == null or siege.city == null:
		return 0.0
	var nation_id := siege.city.owner_nation
	var attack_power := 0.0
	for army in siege.side_a:
		if army.size > 0:
			attack_power += ArmyPower.effective(army)
	var committed_power := ArmyPower.city_defense(siege.city)
	for army in siege.side_b:
		if army.size > 0 and army.owner_nation == nation_id:
			committed_power += ArmyPower.effective(army)
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and army.state == Army.State.MOVING
			and army.ai_target_city == siege.city.id
			and army.ai_action in [
				ActionCandidate.Kind.REINFORCE,
				ActionCandidate.Kind.RETREAT,
			]
		):
			committed_power += ArmyPower.effective(army)
	return maxf(attack_power - committed_power, 0.0)


func _is_priority_defense_city(
	nation_id: int,
	city_id: int,
	snapshot: StrategicMapSnapshot
) -> bool:
	var city := state.cities[city_id]
	return (
		city_id == state.nations[nation_id].capital_city_id
		or city.has_warehouse
		or city.is_food_hub
		or city.is_manpower_hub
		or snapshot.critical_supply_cities.has(city_id)
		or snapshot.value_of_city(city_id)
			>= CityDefensePlan.MUST_HOLD_CITY_VALUE_FLOOR
	)


func _advance_priority_city_defense(
	siege: Battle,
	defense_plan: CityDefensePlan
) -> void:
	var city_id := siege.city.id
	var nation_id := siege.city.owner_nation
	var coordinator := ArmyCoordinator.from_view(
		defense_plan.view
	)
	var attack_power := 0.0
	for army in siege.side_a:
		if army.size > 0:
			attack_power += ArmyPower.effective(army)
	var committed_power := ArmyPower.city_defense(siege.city)
	for army in siege.side_b:
		if army.size > 0 and army.owner_nation == nation_id:
			committed_power += ArmyPower.effective(army)
	# 在途与既有战斗任务已由统一 coordinator 计入；排除本城战斗军，
	# 因为它们刚刚由 siege.side_b 统计过。
	for army_id in coordinator.city_defense_army_ids(city_id):
		var reserved_army: Army = null
		for candidate_army in defense_plan.view.friendly_armies:
			if candidate_army.id == int(army_id):
				reserved_army = candidate_army
				break
		if reserved_army == null or reserved_army.battle_id == siege.id:
			continue
		committed_power += ArmyPower.effective(reserved_army)
	var required_power := maxf(
		attack_power,
		defense_plan.requirement_at(city_id)
	)
	if committed_power >= required_power:
		return
	# 城市已处于本地均势而其他前线仍未形成最低屏障时，不再为其叠加
	# 纵深预备队。若本城仍实际劣势，则保留紧急解围权。
	if (
		committed_power >= attack_power
		and defense_plan.has_uncovered_frontline_minimum(
			coordinator,
			city_id
		)
	):
		return
	var candidates: Array[Dictionary] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.state != Army.State.IDLE
			or army.location_city == city_id
			or not defense_plan.can_redeploy(army, coordinator)
		):
			continue
		var field := defense_plan.view.path_field(
			army.location_city,
			nation_id,
			false,
			true,
			-1,
			army.max_size
		)
		var distance := float(field["dist"].get(city_id, INF))
		if distance == INF:
			continue
		candidates.append({
			"army": army,
			"distance": distance,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var distance_a := float(a["distance"])
		var distance_b := float(b["distance"])
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a["army"] as Army,
			b["army"] as Army,
			city_id
		)
	)
	for entry in candidates:
		if committed_power >= required_power:
			break
		var army: Army = entry["army"]
		var reinforce := ActionCandidate.make(
			ActionCandidate.Kind.REINFORCE,
			2000.0,
			"重点城市%d大会战：纵深预备队军%d流水增援"
				% [city_id, army.id],
			city_id
		)
		reinforce.minimum_commit_days = CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		reinforce.defensive_deployment = true
		if not _execute_ai_candidate(army, reinforce):
			continue
		var nation := state.nations[nation_id]
		nation.campaign_attack_assignments.erase(army.id)
		nation.campaign_attack_echelons.erase(army.id)
		nation.campaign_launched_armies.erase(army.id)
		coordinator.reserve(city_id, army)
		committed_power += ArmyPower.effective(army)


func _remove_campaign_target(
	nation_id: int,
	target_city: int
) -> void:
	var nation := state.nations[nation_id]
	nation.campaign_plan_targets.erase(target_city)
	nation.campaign_active_echelons.erase(target_city)
	nation.campaign_echelon_started_days.erase(target_city)
	nation.campaign_post_capture_plans.erase(target_city)
	var army_ids := nation.campaign_attack_assignments.keys()
	for army_id_value in army_ids:
		var army_id := int(army_id_value)
		if int(
			nation.campaign_attack_assignments.get(
				army_id,
				-1
			)
		) != target_city:
			continue
		nation.campaign_attack_assignments.erase(army_id)
		nation.campaign_attack_echelons.erase(army_id)
		nation.campaign_launched_armies.erase(army_id)


func _army_ready_for_campaign_target(
	army: Army,
	nation_id: int,
	target_city: int
) -> bool:
	var staging := DiplomacyAI.staging_cities_for_objective(
		state,
		nation_id,
		target_city
	)
	if (
		army.state == Army.State.IDLE
		and staging.has(army.location_city)
	):
		return true
	return (
		army.state == Army.State.HOLDING
		and (
			(
				army.move_from == target_city
				and staging.has(army.move_to)
			)
			or (
				army.move_to == target_city
				and staging.has(army.move_from)
			)
		)
	)


func _grant_offensive_bonus(
	army: Army,
	multiplier: float,
	duration_days: int
) -> void:
	army.offensive_attack_multiplier = clampf(
		multiplier,
		1.0,
		OFFENSIVE_BONUS_MAX_MULTIPLIER
	)
	army.offensive_bonus_until_day = (
		state.day + maxi(duration_days, 0)
	)


func _cached_campaign_objective(
	nation_id: int,
	target_id: int,
	cache: Dictionary
) -> Dictionary:
	if not cache.has(target_id):
		cache[target_id] = DiplomacyAI.select_war_objective(
			state,
			nation_id,
			target_id
		)
	return cache[target_id]


func _enemy_holds_recent_legal_reclamation(
	nation_id: int,
	enemy_id: int
) -> bool:
	for city in state.cities_of(enemy_id):
		if (
			state.recognized_owner_of(city.id) == nation_id
			and Simulation.city_fort_vulnerability(
				city,
				state.day
			) > 0.0
		):
			return true
	return false


## 攻势目标合法性只看城市本身有效即可。君主的好战/温和差异统一由外交层
## 的开战欲望（KEY_AGGRESSION 连续乘子）体现，而不是在战役执行层硬门控——
## 否则温和君主宣了战却永远打不出攻势，是终局僵持的根因之一。
func _ruler_allows_campaign_target(
	nation_id: int,
	target_city: int
) -> bool:
	return (
		nation_id >= 0 and nation_id < state.nations.size()
		and target_city >= 0 and target_city < state.cities.size()
	)


## 当前主目标无法形成可执行计划时，在所有敌国中找守军最少的可达城市。
## 守军是第一判据，集结入口数是第二判据，最终用镜像等变城市序稳定决胜。
func _weak_garrison_campaign_fallback(
	nation_id: int,
	enemy_ids: Array,
	excluded_city: int
) -> Dictionary:
	var best := {}
	for enemy_value in enemy_ids:
		var enemy_id := int(enemy_value)
		var candidate := (
			DiplomacyAI.replacement_war_preparation_objective(
				state, nation_id, enemy_id, excluded_city
			)
		)
		if candidate.is_empty():
			continue
		if (
			best.is_empty()
			or int(candidate["defender_troops"])
				< int(best["defender_troops"])
			or (
				int(candidate["defender_troops"])
					== int(best["defender_troops"])
				and int(candidate["staging_links"])
					> int(best["staging_links"])
			)
			or (
				int(candidate["defender_troops"])
					== int(best["defender_troops"])
				and int(candidate["staging_links"])
					== int(best["staging_links"])
				and EquivariantOrder.city_id_less(
					state, nation_id, int(candidate["city_id"]),
					int(best["city_id"])
				)
			)
		):
			best = candidate
	return best


func _manage_campaign_offensive(
	nation_id: int,
	defense_plan: CityDefensePlan = null,
	coordinator: ArmyCoordinator = null,
	threat: ThreatField = null,
	decision_context: Dictionary = {}
) -> bool:
	_campaign_evaluated_day_by_nation[nation_id] = state.day
	var campaign_profile_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var nation := state.nations[nation_id]
	var can_launch := not (
		nation.campaign_next_offensive_day >= 0
		and state.day < nation.campaign_next_offensive_day
	)
	var objective: Dictionary = {}
	var defender_id := -1
	var owns_diplomatic_objective := false
	var enemy_ids: Array = (
		(decision_context["wars"] as Array).duplicate()
		if decision_context.has("wars")
		else state.wars_of(nation_id)
	)
	var objective_cache := {}
	enemy_ids.sort_custom(func(a: int, b: int) -> bool:
		return EquivariantOrder.nation_less(
			state,
			nation_id,
			a,
			b
		)
	)
	# 君主好战差异已在外交层用连续侵略欲望体现；一旦真的进入战争，任何君主都
	# 会主动组织攻势去实现其战争目标，不再在执行层区分“能否侵略”。
	# 仍在修复窗口内的本国法理失地优先于原进攻目标，形成真实反复争夺。
	for enemy_id in enemy_ids:
		if not _enemy_holds_recent_legal_reclamation(
			nation_id,
			enemy_id
		):
			continue
		var reclamation := _cached_campaign_objective(
			nation_id,
			enemy_id,
			objective_cache
		)
		if reclamation.is_empty():
			continue
		var reclamation_city := int(reclamation["city_id"])
		if (
			state.recognized_owner_of(reclamation_city)
				== nation_id
			and Simulation.city_fort_vulnerability(
				state.cities[reclamation_city],
				state.day
			) > 0.0
		):
			objective = reclamation
			defender_id = enemy_id
			break
	if objective.is_empty():
		for enemy_id in enemy_ids:
			var candidate := state.war_objective(
				nation_id,
				enemy_id
			)
			if (
				not candidate.is_empty()
				and int(candidate.get("attacker", -1))
					== nation_id
			):
				objective = candidate
				defender_id = enemy_id
				owns_diplomatic_objective = true
				break
	# 防御战争没有本国发起的外交目标，但仍必须主动选择敌城组织反攻。
	if objective.is_empty():
		for enemy_id in enemy_ids:
			var counteroffensive := (
				_cached_campaign_objective(
					nation_id,
					enemy_id,
					objective_cache
				)
			)
			if counteroffensive.is_empty():
				continue
			objective = counteroffensive
			defender_id = enemy_id
			break
	if objective.is_empty():
		return false
	var objective_city := int(objective["city_id"])
	if (
		objective_city < 0
		or objective_city >= state.cities.size()
		or not state.is_enemy(
			nation_id, state.cities[objective_city].owner_nation
		)
	):
		var next := _cached_campaign_objective(
			nation_id,
			defender_id,
			objective_cache
		)
		if next.is_empty():
			return false
		objective_city = int(next["city_id"])
		if owns_diplomatic_objective:
				_set_coalition_war_objective(
					state.alliance_bloc(nation_id),
					state.alliance_bloc(defender_id),
				nation_id,
				objective_city,
				str(next["reason"])
			)
	var theater_objective := (
		_campaign_objective_in_current_theater(
			nation_id,
			objective_city,
			(
				defense_plan.view
				if (
					defense_plan != null
					and defense_plan.view != null
				)
				else null
			),
			(
				defense_plan.snapshot
				if (
					defense_plan != null
					and defense_plan.snapshot != null
				)
				else null
			)
		)
	)
	if theater_objective != objective_city:
		objective_city = theater_objective
		defender_id = state.cities[
			objective_city
		].owner_nation
		owns_diplomatic_objective = false
	if not _ruler_allows_campaign_target(nation_id, objective_city):
		return false
	_record_tick_profile_stage(
		"campaign_objective",
		campaign_profile_started
	)
	campaign_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var plan_ready := _ensure_campaign_preparation_plan(
		nation_id,
		objective_city,
		defense_plan,
		coordinator,
		true,
		decision_context
	)
	if not plan_ready:
		var fallback := _weak_garrison_campaign_fallback(
			nation_id, enemy_ids, objective_city
		)
		if not fallback.is_empty():
			objective_city = int(fallback["city_id"])
			defender_id = state.cities[objective_city].owner_nation
			plan_ready = _ensure_campaign_preparation_plan(
				nation_id,
				objective_city,
				defense_plan,
				coordinator,
				true,
				decision_context
			)
			if plan_ready:
				# 在下一轮外交/战役评估前固定当前战区方向，避免又被
				# 已不可执行的旧目标拉回。
				nation.campaign_theater_anchor_city = objective_city
	_record_tick_profile_stage(
		"campaign_ensure_plan",
		campaign_profile_started
	)
	if not plan_ready:
		return false
	if decision_context.has("view"):
		_refresh_ai_campaign_staging_context(
			decision_context
		)
	campaign_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var preparation_days := _campaign_preparation_days(nation_id)
	nation.campaign_preparation_multiplier = (
		offensive_preparation_multiplier(preparation_days)
	)
	var preparation_targets := (
		nation.campaign_preparation_targets.duplicate()
	)
	EquivariantOrder.sort_city_ids(
		preparation_targets,
		state,
		nation_id,
		objective_city
	)
	var launch_targets: Array[int] = []
	if can_launch:
		if threat == null:
			threat = ThreatField.build(
				_build_ai_view(nation_id),
				_threat_travel_cache
			)
	for target_city in preparation_targets:
		var recent_legal_reclamation := (
			state.recognized_owner_of(target_city) == nation_id
			and Simulation.city_fort_vulnerability(
				state.cities[target_city],
				state.day
			) > 0.0
		)
		if not can_launch and not recent_legal_reclamation:
			continue
		var required := _campaign_minimum_staged_troops(
			nation_id, target_city
		)
		var staged_armies: Array[Army] = (
			decision_context[
				"campaign_staged_armies_by_target"
			].get(
				target_city,
				[] as Array[Army]
			)
			if decision_context.has(
				"campaign_staged_armies_by_target"
			)
			else _campaign_preparation_staged_armies(
				nation_id,
				target_city
			)
		)
		var staged_troops := int(
			decision_context[
				"campaign_staged_troops_by_target"
			].get(target_city, 0)
			if decision_context.has(
				"campaign_staged_troops_by_target"
			)
			else 0
		)
		if not decision_context.has(
			"campaign_staged_troops_by_target"
		):
			for army in staged_armies:
				staged_troops += army.size
		var planned_groups_ready := true
		if state.uses_heightmap and nation.campaign_preparation_plan != null:
			var planned_groups := (
				nation.campaign_preparation_plan.groups_for_target(
					target_city
				)
			)
			var demand: Dictionary = (
				nation.campaign_preparation_plan.target_demands.get(
					target_city, {}
				)
			)
			var minimum_groups := (
				CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS
				if bool(demand.get("is_decisive", false))
				else 1
			)
			var staged_group_ids := {}
			for staged_army in staged_armies:
				if staged_army.battle_group_id >= 0:
					staged_group_ids[staged_army.battle_group_id] = true
			planned_groups_ready = (
				planned_groups.size() >= minimum_groups
				and staged_group_ids.size() >= minimum_groups
			)
		var preparation_deadline_reached := (
			preparation_days
				>= OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
		)
		# 决定性方向平时要求足额战团同步集结；120天是硬发动截止，
		# 到期后只要求至少一个已分配战团真正到位。旧逻辑在这里先用
		# planned_groups_ready continue，导致后面的满准备分支永远不可达。
		if (
			staged_troops < required
			or (
				not planned_groups_ready
				and not preparation_deadline_reached
			)
		):
			continue
		if threat == null:
			threat = ThreatField.build(
				_build_ai_view(nation_id),
				_threat_travel_cache
			)
		var projected_ratio := _campaign_projected_assault_ratio(
			nation_id,
			target_city,
			preparation_days,
			threat,
			true,
			staged_armies
		)
		var full_preparation_active := (
			nation.campaign_full_preparation_targets.has(
				target_city
			)
		)
		# 满准备（120 天）是给“常规兵力打不动”的僵局目标兜底的发动截止期，
		# 而不是一旦标记就必须空等满期的锁。若本方兵力已恢复到无需集结加成、
		# 仅凭常规集结窗口的基准倍率即可跨过进攻阈值，说明僵局已解除，应立即
		# 发动，杜绝“明明能打却拖很久不触发”的情况。基准窗口与均势夹具判据
		# 同源（CAMPAIGN_OFFENSIVE_INTERVAL_DAYS），真正的僵局目标基准比值仍
		# 低于阈值，因此不会被提前触发。
		var attack_ratio_threshold := _campaign_attack_ratio_threshold(
			nation_id
		)
		var force_ready_without_bonus := (
			full_preparation_active
			and _campaign_projected_assault_ratio(
				nation_id,
				target_city,
				mini(
					preparation_days,
					CAMPAIGN_OFFENSIVE_INTERVAL_DAYS
				),
				threat,
				true,
				staged_armies
			) >= attack_ratio_threshold
		)
		if (
			recent_legal_reclamation
			or force_ready_without_bonus
			or preparation_deadline_reached
			or (
				not full_preparation_active
				and projected_ratio
					>= attack_ratio_threshold
			)
		):
			launch_targets.append(target_city)
		elif not nation.campaign_full_preparation_targets.has(
			target_city
		):
			nation.campaign_full_preparation_targets.append(
				target_city
			)
	if not launch_targets.is_empty():
		var launch_objective := (
			objective_city
			if launch_targets.has(objective_city)
			else launch_targets[0]
		)
		var launched := _launch_campaign_offensive(
				nation_id,
				launch_objective,
				preparation_days,
				launch_targets,
				threat
		)
		if launched:
			_record_tick_profile_stage(
				"campaign_launch_eval",
				campaign_profile_started
			)
			return true
	_record_tick_profile_stage(
		"campaign_launch_eval",
		campaign_profile_started
	)
	campaign_profile_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	# 重整期不是空窗期：持续集结，但不覆盖仍在执行的当前梯队计划。
	var changed := false
	for target_city in preparation_targets:
		changed = (
			_assign_offensive_staging_orders(
				nation_id,
				target_city,
				defense_plan,
				coordinator,
				false,
				true,
				true,
				decision_context
			)
			or changed
		)
	_record_tick_profile_stage(
		"campaign_staging",
		campaign_profile_started
	)
	return changed


func _food_security_report(
	nation_id: int,
	nation_armies: Array[Army] = [],
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	var food_part_started := (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var war_food := DiplomacyAI.war_food_report(
		state,
		nation_id,
		-1,
		-1,
		evaluation_cache
	)
	_record_tick_profile_stage(
		"ai_force_food_plan", food_part_started
	)
	food_part_started = (
		Time.get_ticks_usec() if tick_phase_profiling_enabled else 0
	)
	var monthly_production := float(war_food["monthly_food_production"])
	var monthly_demand := 0.0
	var nation := state.nations[nation_id]
	var armies_to_scan: Array[Army] = (
		nation_armies
		if not nation_armies.is_empty()
		else state.armies
	)
	for army in armies_to_scan:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		monthly_demand += _projected_army_food_demand(army)
	_record_tick_profile_stage(
		"ai_force_food_armies", food_part_started
	)
	monthly_demand = maxf(
		monthly_demand,
		nation.food_demand_ema
	)
	var stock := int(war_food["food_stock"])
	var reserve_target := int(war_food["stock_target"])
	var sustainable_demand := float(war_food["monthly_food_budget"])
	return {
		"posture": war_food["posture"],
		"monthly_production": monthly_production,
		"monthly_demand": monthly_demand,
		"monthly_surplus": monthly_production - monthly_demand,
		"annual_production": war_food["annual_food_production"],
		"annual_demand": monthly_demand * 12.0,
		"annual_surplus": (
			float(war_food["annual_food_production"])
			- monthly_demand * 12.0
		),
		"runway_years": war_food["current_runway_years"],
		"required_campaign_years": war_food["required_campaign_years"],
		"full_strength_annual_demand": war_food["full_strength_annual_demand"],
		"full_strength_annual_balance": war_food["full_strength_annual_balance"],
		"full_strength_runway_years": war_food["full_strength_runway_years"],
		"affordable_troops": war_food["affordable_troops"],
		"stock": stock,
		"reserve_target": reserve_target,
		"sustainable_demand": sustainable_demand,
		"required_savings": maxf(monthly_demand - sustainable_demand, 0.0),
		"needs_demobilization": monthly_demand > sustainable_demand + 0.01,
	}


func _food_growth_manpower_budget(food_report: Dictionary) -> int:
	var food_headroom := maxf(
		float(food_report["sustainable_demand"])
			- float(food_report["monthly_demand"])
			- 1.0,
		0.0
	)
	return int(floor(
		food_headroom / (FOOD_PER_CAPITA * MAX_SUPPLY_MULT)
	))


func _projected_army_food_demand(army: Army) -> float:
	var sources := _cached_supply_sources(
		army,
		_daily_supply_source_cache,
		_daily_supply_network_cache,
		_stable_supply_city_source_cache
	)
	var supply := (
		[
			int(sources[0]["city_id"]),
			float(sources[0]["loss"]),
		]
		if not sources.is_empty()
		else [-1, INF]
	)
	var route_loss := float(supply[1])
	var multiplier := MAX_SUPPLY_MULT
	if int(supply[0]) != -1:
		multiplier = minf(1.0 + route_loss, MAX_SUPPLY_MULT)
	var base := maxi(int(ceil(float(army.size) * FOOD_PER_CAPITA)), 1)
	return ceil(
		float(base)
			* multiplier
			* _ruler_food_consumption_multiplier(
				state, army.owner_nation
			)
	)


func _demobilize_for_food_security(
	view: AiWorldView,
	threat: ThreatField,
	food_report: Dictionary,
	target_count: int
) -> bool:
	var candidates: Array[Army] = []
	for army in view.friendly_armies:
		if (
			army.state != Army.State.IDLE
			or army.location_city < 0
			or threat.threat_at(army.location_city) >= ArmyPower.effective(army)
		):
			continue
		candidates.append(army)
	candidates.sort_custom(func(a: Army, b: Army) -> bool:
		if a.size != b.size:
			return a.size > b.size
		return EquivariantOrder.army_less(
			state,
			view.nation_id,
			a,
			b
		)
	)
	if candidates.is_empty():
		return false
	var remaining_savings := float(food_report["required_savings"])
	var total_returned := 0
	var total_saved := 0.0
	var changed := false
	for army in candidates:
		if remaining_savings <= 0.01:
			break
		var minimum_size := int(ceil(
			float(army.max_size) * PEACETIME_STRENGTH_RATIO
		))
		var reducible := army.size - minimum_size
		if reducible <= 0:
			continue
		var demand := _projected_army_food_demand(army)
		var food_per_person := demand / float(maxi(army.size, 1))
		var requested := maxi(
			int(ceil(remaining_savings / maxf(food_per_person, 0.0001))),
			DEMOBILIZATION_STEP_MIN
		)
		var returned := mini(requested, reducible)
		if returned <= 0:
			continue
		var saved := food_per_person * float(returned)
		army.size -= returned
		state.nations[army.owner_nation].manpower_pool += returned
		army.ai_action = ActionCandidate.Kind.DISBAND_ARMY
		army.ai_order_created_day = state.day
		total_returned += returned
		total_saved += saved
		remaining_savings = maxf(remaining_savings - saved, 0.0)
		changed = true
	if not changed:
		return false
	var nation := state.nations[view.nation_id]
	nation.food_demand_ema = maxf(
		nation.food_demand_ema - total_saved,
		0.0
	)
	var reason := (
		(
			"军粮预算缩编：返还%d人，年结余%.0f，库存可撑%.1f年，"
			+ "态度%d要求%.1f年，目标保留%d军"
		) % [
			total_returned,
			food_report["annual_surplus"],
			food_report["runway_years"],
			food_report["posture"],
			food_report["required_campaign_years"],
			target_count,
		]
	)
	nation.ai_last_force_action = ActionCandidate.Kind.DISBAND_ARMY
	nation.ai_last_force_day = state.day
	nation.ai_last_force_reason = reason
	return true


func _demobilize_for_gold_security(
	view: AiWorldView,
	threat: ThreatField,
	required_savings: int,
	target_count: int
) -> bool:
	if required_savings <= 0:
		return false
	var upkeep_multiplier := RulerProfile.upkeep_multiplier(
		state.nations[view.nation_id]
	)
	var current_base_upkeep := 0
	for active_army in state.armies:
		if active_army.owner_nation == view.nation_id and active_army.size > 0:
			current_base_upkeep += GameState.army_monthly_upkeep(
				active_army.size
			)
	var current_effective_upkeep := _ruler_adjusted_upkeep(
		current_base_upkeep, upkeep_multiplier
	)
	var candidates: Array[Army] = []
	for army in view.friendly_armies:
		if (
			army.state != Army.State.IDLE
			or army.location_city < 0
			or state.cities[
				army.location_city
			].owner_nation != view.nation_id
			or threat.threat_at(army.location_city)
				>= ArmyPower.effective(army)
		):
			continue
		candidates.append(army)
	candidates.sort_custom(func(a: Army, b: Army) -> bool:
		var base_a := GameState.army_monthly_upkeep(a.size)
		var base_b := GameState.army_monthly_upkeep(b.size)
		var savings_a := current_effective_upkeep - _ruler_adjusted_upkeep(
			current_base_upkeep - base_a, upkeep_multiplier
		)
		var savings_b := current_effective_upkeep - _ruler_adjusted_upkeep(
			current_base_upkeep - base_b, upkeep_multiplier
		)
		if savings_a != savings_b:
			return savings_a > savings_b
		return EquivariantOrder.army_less(
			state,
			view.nation_id,
			a,
			b
		)
	)
	if candidates.is_empty():
		return false
	var remaining_savings := required_savings
	var total_saved := 0
	var total_returned := 0
	var total_food_saved := 0.0
	var active_count := view.friendly_armies.size()
	for army in candidates:
		if remaining_savings <= 0:
			break
		var current_army_base_upkeep := (
			GameState.army_monthly_upkeep(army.size)
		)
		var minimum_size := int(ceil(
			float(army.max_size)
			* PEACETIME_STRENGTH_RATIO
		))
		if active_count > target_count:
			minimum_size = 0
		var minimum_base_upkeep := (
			GameState.army_monthly_upkeep(minimum_size)
		)
		var possible_savings := (
			current_effective_upkeep
			- _ruler_adjusted_upkeep(
				current_base_upkeep
					- current_army_base_upkeep
					+ minimum_base_upkeep,
				upkeep_multiplier
			)
		)
		if possible_savings <= 0:
			continue
		var requested_savings := mini(
			remaining_savings,
			possible_savings
		)
		var target_nation_upkeep := (
			current_effective_upkeep - requested_savings
		)
		var target_size := army.size
		while (
			target_size > minimum_size
			and _ruler_adjusted_upkeep(
				current_base_upkeep
					- current_army_base_upkeep
					+ GameState.army_monthly_upkeep(target_size),
				upkeep_multiplier
			) > target_nation_upkeep
		):
			target_size = maxi(
				target_size - GameState.WAR_GOLD_TROOPS_PER_UNIT,
				minimum_size
			)
		target_size = mini(target_size, army.size)
		var demand_before := _projected_army_food_demand(
			army
		)
		var returned := army.size - target_size
		if returned <= 0:
			continue
		if (
			target_size <= DISBAND_SIZE_MAX
			and active_count > target_count
		):
			var disbanded_size := army.size
			if not _disband_army(
				army,
				"军费赤字缩编：撤销无法维持的编制"
			):
				continue
			returned = disbanded_size
			active_count -= 1
			total_food_saved += demand_before
			target_size = 0
		else:
			army.size = target_size
			state.nations[
				army.owner_nation
			].manpower_pool += returned
			army.ai_action = (
				ActionCandidate.Kind.DISBAND_ARMY
			)
			army.ai_order_created_day = state.day
			total_food_saved += maxf(
				demand_before
					- _projected_army_food_demand(army),
				0.0
			)
		var next_base_upkeep := (
			current_base_upkeep
			- current_army_base_upkeep
			+ GameState.army_monthly_upkeep(target_size)
		)
		var next_effective_upkeep := _ruler_adjusted_upkeep(
		next_base_upkeep, upkeep_multiplier
	)
		var saved := current_effective_upkeep - next_effective_upkeep
		current_base_upkeep = next_base_upkeep
		current_effective_upkeep = next_effective_upkeep
		total_returned += returned
		total_saved += saved
		remaining_savings = maxi(
			remaining_savings - saved,
			0
		)
	if total_saved <= 0:
		return false
	var nation := state.nations[view.nation_id]
	nation.food_demand_ema = maxf(
		nation.food_demand_ema - total_food_saved,
		0.0
	)
	nation.ai_last_force_action = (
		ActionCandidate.Kind.DISBAND_ARMY
	)
	nation.ai_last_force_day = state.day
	nation.last_gold_demobilization_month = (
		state.day / DAYS_PER_MONTH
	)
	nation.ai_last_force_reason = (
		"财政储备缩编：返还%d人，月省%d金，储备月度缺口%d金，目标保留%d军"
		% [
			total_returned,
			total_saved,
			required_savings,
			target_count,
		]
	)
	return true


func _is_available_recruitment_hub(
	nation_id: int,
	city_id: int,
	allow_besieged: bool = false
) -> bool:
	if (
		nation_id < 0
		or nation_id >= state.nations.size()
		or city_id < 0
		or city_id >= state.cities.size()
		or state.cities[city_id].owner_nation
			!= nation_id
	):
		return false
	var city := state.cities[city_id]
	var is_vassal_capital_relay := (
		state.is_vassal(nation_id)
		and state.nations[nation_id].capital_city_id
			== city_id
	)
	return (
		(city.has_warehouse or is_vassal_capital_relay)
		and (
			allow_besieged
			or not state.city_under_siege(city_id)
		)
	)


func _create_army_for_nation(
	nation_id: int,
	city_id: int,
	formation_size: int = GameState.INITIAL_LIGHT_ARMY_SIZE,
	reason: String = "",
	allow_besieged_hub: bool = false,
	battle_group_id: int = -1
) -> Army:
	if nation_id < 0 or nation_id >= state.nations.size():
		return null
	if formation_size not in [
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
	]:
		return null
	var nation := state.nations[nation_id]
	if (
		formation_size == GameState.INITIAL_HEAVY_ARMY_SIZE
		and state.battle_group_by_id(
			nation_id,
			battle_group_id
		) == null
	):
		return null
	var creation_cost := (
		GameState.formation_creation_gold_cost(
			formation_size
		)
	)
	if (
		nation.manpower_pool < formation_size
		or nation.treasury_gold < creation_cost
		or state.active_army_count(nation_id)
			>= state.max_army_count(nation_id)
		or not _is_available_recruitment_hub(
			nation_id,
			city_id,
			allow_besieged_hub
		)
	):
		return null
	nation.manpower_pool -= formation_size
	nation.treasury_gold -= creation_cost
	var army := state.create_army(
		nation_id,
		city_id,
		formation_size,
		formation_size
	)
	if army == null:
		nation.manpower_pool += formation_size
		nation.treasury_gold += creation_cost
		return null
	if (
		battle_group_id >= 0
		and not state.assign_army_to_battle_group(
			army,
			battle_group_id
		)
	):
		state.armies.erase(army)
		nation.manpower_pool += formation_size
		nation.treasury_gold += creation_cost
		return null
	army.ai_action = ActionCandidate.Kind.CREATE_ARMY
	army.ai_order_created_day = state.day
	army.ai_order_reason = (
		"%s；支付建制费%d金" % [
			reason,
			creation_cost,
		]
	)
	# 当前国家计划基于建军前的冻结军队快照；让该国下一日立即重建防区，
	# 新编制就会先获得展开命令，而不是在枢纽等待完整 AI 周期。
	_ai_forced_nations[nation_id] = true
	nation.ai_last_force_action = ActionCandidate.Kind.CREATE_ARMY
	nation.ai_last_force_day = state.day
	nation.ai_last_force_reason = army.ai_order_reason
	_reconcile_strategic_roles(nation_id)
	return army


func _disband_army(army: Army, reason: String = "") -> bool:
	if (
		army == null
		or army.size <= 0
		or army.state not in [
			Army.State.IDLE,
			Army.State.RECOVERING,
		]
		or army.location_city < 0 or army.location_city >= state.cities.size()
		or state.cities[army.location_city].owner_nation != army.owner_nation
	):
		return false
	var nation := state.nations[army.owner_nation]
	var returned := army.size
	nation.manpower_pool += returned
	army.ai_action = ActionCandidate.Kind.DISBAND_ARMY
	nation.ai_last_force_action = ActionCandidate.Kind.DISBAND_ARMY
	nation.ai_last_force_day = state.day
	nation.ai_last_force_reason = reason
	army.size = 0
	state.armies.erase(army)
	return true


func _begin_ai_command_collection(
	snapshot_army_ids: Dictionary = {}
) -> void:
	_clear_ai_command_collection()
	if snapshot_army_ids.is_empty():
		for army in state.armies:
			if army.size > 0:
				_ai_snapshot_armies[army.id] = true
	else:
		_ai_snapshot_armies = snapshot_army_ids.duplicate()
	_collect_ai_commands = true


func _clear_ai_command_collection() -> void:
	_collect_ai_commands = false
	_ai_command_buffer.clear()
	_ai_planned_armies.clear()
	_ai_planned_first_legs.clear()
	_ai_command_sequence.clear()
	_ai_snapshot_armies.clear()
	_ai_queue_transaction_id = -1
	_pending_campaign_launch_transactions.clear()
	_ai_transaction_reserved_armies.clear()


func _queue_ai_candidate(army: Army, candidate: ActionCandidate) -> bool:
	var reserved_transaction := int(
		_ai_transaction_reserved_armies.get(army.id, -1)
	) if army != null else -1
	var campaign_staging_queue := (
		army != null
		and army.is_main_battle_role()
		and army.owner_nation >= 0
		and army.owner_nation < state.nations.size()
		and state.nations[army.owner_nation]
			.campaign_preparation_assignments.has(army.id)
		and candidate != null
		and candidate.kind in [
			ActionCandidate.Kind.REINFORCE,
			ActionCandidate.Kind.RETREAT,
		]
		and candidate.reason.begins_with("战前")
	)
	if (
		army == null
		or army.size <= 0
		or (
			reserved_transaction >= 0
			and reserved_transaction != _ai_queue_transaction_id
		)
		or not _ai_snapshot_armies.has(army.id)
		or _ai_planned_armies.has(army.id)
		or not _can_queue_ai_candidate(army, candidate)
	):
		return false
	var prepared_path: Array[int] = []
	var path_prevalidated := false
	if (
		army.state == Army.State.IDLE
		and candidate.kind in [
			ActionCandidate.Kind.ATTACK,
			ActionCandidate.Kind.REINFORCE,
			ActionCandidate.Kind.MERGE,
			ActionCandidate.Kind.RETREAT,
		]
	):
		var field := _cached_ai_path_field(
			army.owner_nation,
			army.location_city,
			army.owner_nation,
			false,
			candidate.kind != ActionCandidate.Kind.ATTACK,
			candidate.target_city
				if candidate.kind == ActionCandidate.Kind.ATTACK
				else -1,
			army.max_size
		)
		prepared_path = Pathfinding.reconstruct(
			field["prev"],
			army.location_city,
			candidate.target_city
		)
		if prepared_path.is_empty():
			return false
		path_prevalidated = true
	var first_leg := -1
	if army.state == Army.State.IDLE:
		if candidate.kind == ActionCandidate.Kind.HOLD:
			first_leg = candidate.target_city
		elif path_prevalidated:
			first_leg = prepared_path[0]
	if first_leg != -1:
		var first_edge := state.edge_of(army.location_city, first_leg)
		if (
			first_edge == null
			or first_edge.max_manpower < army.road_footprint()
		):
			return false
		if (
			candidate.kind == ActionCandidate.Kind.HOLD
			and not first_edge.allows_holding
		):
			return false
		var leg_key := _ai_first_leg_key(
			army.owner_nation,
			army.location_city,
			first_leg
		)
		var occupied_manpower := _friendly_same_direction_manpower(
			army.owner_nation,
			army.location_city,
			first_leg
		)
		var reserved_manpower := int(
			_ai_planned_first_legs.get(leg_key, 0)
		)
		var transport_load := army.road_capacity_load(
			first_edge.max_manpower
		)
		if (
			occupied_manpower
			+ reserved_manpower
			+ transport_load
			> first_edge.max_manpower
			and _ai_queue_transaction_id < 0
			and not campaign_staging_queue
		):
			return false
		_ai_planned_first_legs[leg_key] = (
			reserved_manpower + transport_load
		)
	var sequence := int(
		_ai_command_sequence.get(army.owner_nation, 0)
	)
	_ai_command_sequence[army.owner_nation] = sequence + 1
	_ai_command_buffer.append(AiCommandIntent.make(
		army,
		candidate,
		sequence,
		prepared_path,
		path_prevalidated,
		_ai_queue_transaction_id
	))
	_ai_planned_armies[army.id] = true
	return true


func _can_queue_ai_candidate(
	army: Army,
	candidate: ActionCandidate
) -> bool:
	if candidate == null or candidate.kind == ActionCandidate.Kind.NONE:
		return false
	if candidate.kind == ActionCandidate.Kind.HOLD:
		if army.state == Army.State.HOLDING:
			var held_edge := state.edge_of(
				army.move_from,
				army.move_to
			)
			return held_edge != null and held_edge.allows_holding
		if army.state != Army.State.IDLE or candidate.target_city == -1:
			return false
		var target_edge := state.edge_of(
			army.location_city,
			candidate.target_city
		)
		return target_edge != null and target_edge.allows_holding
	if candidate.kind in [
		ActionCandidate.Kind.ATTACK,
		ActionCandidate.Kind.REINFORCE,
		ActionCandidate.Kind.MERGE,
	]:
		if candidate.kind == ActionCandidate.Kind.ATTACK and army.state == Army.State.HOLDING:
			return (
				candidate.target_city == army.move_from
				or candidate.target_city == army.move_to
			)
		return (
			army.state == Army.State.IDLE
			and candidate.target_city >= 0
			and candidate.target_city < state.cities.size()
			and candidate.target_city != army.location_city
		)
	if candidate.kind == ActionCandidate.Kind.RETREAT:
		if army.state == Army.State.HOLDING:
			return (
				candidate.target_city == army.move_from
				or candidate.target_city == army.move_to
			)
		return (
			army.state == Army.State.IDLE
			and candidate.target_city >= 0
			and candidate.target_city < state.cities.size()
			and candidate.target_city != army.location_city
		)
	return false


func _commit_ai_command_collection(
	nation_order: Array[int]
) -> void:
	_collect_ai_commands = false
	ai_last_command_commit_failures = 0
	var nation_rank := {}
	for index in range(nation_order.size()):
		nation_rank[nation_order[index]] = index
	_ai_command_buffer.sort_custom(
		func(a: AiCommandIntent, b: AiCommandIntent) -> bool:
			if a.sequence != b.sequence:
				return a.sequence < b.sequence
			return (
				int(nation_rank.get(a.nation_id, 999999))
				< int(nation_rank.get(b.nation_id, 999999))
			)
	)
	var processed_transactions := {}
	for intent in _ai_command_buffer:
		if intent.transaction_id >= 0:
			var transaction_id := intent.transaction_id
			if processed_transactions.has(transaction_id):
				continue
			processed_transactions[transaction_id] = true
			var transaction_intents: Array[AiCommandIntent] = []
			for candidate_intent in _ai_command_buffer:
				if candidate_intent.transaction_id == transaction_id:
					transaction_intents.append(candidate_intent)
			var payload: Dictionary = (
				_pending_campaign_launch_transactions.get(
					transaction_id, {}
				)
			)
			if not _validate_campaign_launch_payload(
				payload, transaction_intents
			):
				_pending_campaign_launch_transactions.erase(transaction_id)
				_release_ai_transaction_armies(transaction_id)
				_record_ai_command_commit_failure(
					intent, "campaign_transaction_preflight"
				)
				continue
			_pending_campaign_launch_transactions.erase(transaction_id)
			_release_ai_transaction_armies(transaction_id)
			for transaction_intent in transaction_intents:
				_apply_prevalidated_campaign_intent(transaction_intent)
			_apply_campaign_launch_payload_unchecked(payload)
			continue
		if not _execute_ai_candidate(
			intent.army, intent.candidate, intent.prepared_path,
			intent.path_prevalidated
		):
			_record_ai_command_commit_failure(intent, "ordinary_intent")
	_clear_ai_command_collection()


func _release_ai_transaction_armies(transaction_id: int) -> void:
	for army_id in _ai_transaction_reserved_armies.keys().duplicate():
		if int(_ai_transaction_reserved_armies[army_id]) == transaction_id:
			_ai_transaction_reserved_armies.erase(army_id)


func _record_ai_command_commit_failure(
	intent: AiCommandIntent,
	stage: String
) -> void:
	ai_last_command_commit_failures += 1
	ai_command_commit_failure_total += 1
	if ai_command_commit_failure_log.size() < 20:
		ai_command_commit_failure_log.append(
			(
				"day=%d army=%d nation=%d state=%d kind=%d target=%d "
				+ "stage=%s reason=%s"
			) % [
				state.day, intent.army.id, intent.army.owner_nation,
				intent.army.state, intent.candidate.kind,
				intent.candidate.target_city, stage, intent.candidate.reason,
			]
		)


static func _ai_first_leg_key(
	nation_id: int,
	from_city: int,
	to_city: int
) -> String:
	return "%d:%d:%d" % [nation_id, from_city, to_city]


func _execute_ai_candidate(
	army: Army,
	candidate: ActionCandidate,
	prepared_path: Array[int] = [],
	path_prevalidated: bool = false
) -> bool:
	if _collect_ai_commands:
		return _queue_ai_candidate(army, candidate)
	if candidate.kind == ActionCandidate.Kind.HOLD:
		if army.state == Army.State.HOLDING:
			var held_edge := state.edge_of(
				army.move_from,
				army.move_to
			)
			if held_edge == null or not held_edge.allows_holding:
				return false
			_record_ai_order(army, candidate)
			return true
		if army.state != Army.State.IDLE or candidate.target_city == -1:
			return false
		var target_edge := state.edge_of(
			army.location_city,
			candidate.target_city
		)
		if target_edge == null or not target_edge.allows_holding:
			return false
		army.path = [candidate.target_city] as Array[int]
		army.hold_target_progress = HOLDING_TARGET_PROGRESS
	elif candidate.kind in [
		ActionCandidate.Kind.ATTACK,
		ActionCandidate.Kind.REINFORCE,
		ActionCandidate.Kind.MERGE,
	]:
		if candidate.kind == ActionCandidate.Kind.ATTACK and army.state == Army.State.HOLDING:
			if candidate.target_city == army.move_from:
				var old_from := army.move_from
				army.move_from = army.move_to
				army.move_to = old_from
				army.move_progress = 1.0 - army.move_progress
			elif candidate.target_city != army.move_to:
				return false
				_set_occupation_claimant_for_crossing(
					army,
					army.move_from,
					army.move_to
				)
			army.state = Army.State.MOVING
			army.holding_days = 0
			army.hold_target_progress = -1.0
			army.path.clear()
			_record_ai_order(army, candidate)
			return true
		if army.state != Army.State.IDLE or candidate.target_city == -1:
			return false
		if path_prevalidated:
			army.path = prepared_path.duplicate()
		else:
			var field := _cached_ai_path_field(
				army.owner_nation,
				army.location_city,
				army.owner_nation,
				false,
				candidate.kind != ActionCandidate.Kind.ATTACK,
				candidate.target_city
					if candidate.kind == ActionCandidate.Kind.ATTACK
					else -1,
				army.max_size
			)
			army.path = Pathfinding.reconstruct(
				field["prev"], army.location_city, candidate.target_city
			)
		if army.path.is_empty():
			return false
		army.hold_target_progress = -1.0
	elif candidate.kind == ActionCandidate.Kind.RETREAT:
		if army.state == Army.State.HOLDING:
			if candidate.target_city == army.move_from:
				var old_from := army.move_from
				army.move_from = army.move_to
				army.move_to = old_from
				army.move_progress = 1.0 - army.move_progress
			elif candidate.target_city != army.move_to:
				return false
			army.state = Army.State.MOVING
			army.holding_days = 0
			army.hold_target_progress = -1.0
			army.path.clear()
			_record_ai_order(army, candidate)
			return true
		if army.state != Army.State.IDLE:
			return false
		if path_prevalidated:
			army.path = prepared_path.duplicate()
		else:
			var retreat_field := _cached_ai_path_field(
				army.owner_nation,
				army.location_city,
				army.owner_nation,
				false,
				true,
				-1,
				army.max_size
			)
			army.path = Pathfinding.reconstruct(
				retreat_field["prev"],
				army.location_city,
				candidate.target_city
			)
		if army.path.is_empty():
			return false
		army.hold_target_progress = -1.0
	else:
		return false
	army.state = Army.State.MOVING
	army.move_from = army.location_city
	army.move_to = -1
	army.move_progress = 0.0
	_begin_next_leg(army)
	if army.move_to == -1:
		if path_prevalidated and not army.path.is_empty():
			# 冻结快照收集后，边上友军可能在统一提交阶段调头，
			# 使首段容量暂时满载。保留有效路径，沿用每日行军重试。
			_record_ai_order(army, candidate)
			return true
		army.state = Army.State.IDLE
		army.path.clear()
		return false
	_record_ai_order(army, candidate)
	return true


func _record_ai_order(army: Army, candidate: ActionCandidate) -> void:
	army.encounter_blocked = false
	army.ai_action = candidate.kind
	army.ai_target_city = candidate.target_city
	army.ai_order_created_day = state.day
	army.ai_order_until_day = state.day + candidate.minimum_commit_days
	army.ai_order_score = candidate.score
	army.ai_order_reason = candidate.reason
	if candidate.defensive_deployment:
		army.defensive_deployment_until_day = (
			state.day + DEFENSIVE_DEPLOYMENT_LOCK_DAYS
		)
		if (
			candidate.kind == ActionCandidate.Kind.RETREAT
			and candidate.target_edge_a >= 0
			and candidate.target_edge_b >= 0
		):
			army.defensive_blocked_edge_a = mini(
				candidate.target_edge_a,
				candidate.target_edge_b
			)
			army.defensive_blocked_edge_b = maxi(
				candidate.target_edge_a,
				candidate.target_edge_b
			)
		elif candidate.kind in [
			ActionCandidate.Kind.HOLD,
			ActionCandidate.Kind.REINFORCE,
		]:
			army.defensive_blocked_edge_a = -1
			army.defensive_blocked_edge_b = -1
	if candidate.offensive_bonus_days > 0:
		_grant_offensive_bonus(
			army,
			candidate.offensive_attack_multiplier,
			candidate.offensive_bonus_days
		)


func _edge_has_friendly_holder_or_order(nation_id: int, from_city: int, to_city: int) -> bool:
	var key := _edge_key_of(from_city, to_city)
	for army in state.armies:
		if army.size <= 0 or army.owner_nation != nation_id or army.move_to == -1:
			continue
		if _edge_key_of(army.move_from, army.move_to) != key:
			continue
		if army.state == Army.State.HOLDING or army.hold_target_progress >= 0.0:
			return true
	return false

# ------------------------------------------------------------------ 4. 行军 + 遭遇战

## 陆路基础行军时长；特殊边通过 edge_travel_days() 应用边级倍率。
## distance=1 为 10 天，此后每个真实距离单位增加 5 天，不设长距离上限。
static func march_days(distance: int) -> float:
	return (
		MARCH_DAYS_MIN
		+ float(maxi(distance, 1) - 1)
			* MARCH_DAYS_PER_DISTANCE_STEP
	)


static func edge_travel_days(edge: Edge, formation_size: int = 0) -> float:
	if edge == null:
		return MISSING_EDGE_TRAVEL_DAYS
	return maxf(
		march_days(edge.distance)
			* maxf(edge.travel_time_multiplier, 0.05),
		1.0
	) * float(Army.road_transport_batches_for_formation(
		formation_size, edge.max_manpower
	))


func _advance_movement() -> void:
	_prepare_movement_capacity_index()
	# 1. 先推进所有 MOVING / RETREATING 军队（本步骤不处理"到达节点"）。
	#    关键时序：若在此就地 _arrive_at_node，先走到敌城的一方会在遭遇检测前离边进入攻城，
	#    导致相向而行的两军错身穿过、永不野战交火。故推进与到达必须分离。
	var holding_arrivals: Array[Army] = []
	for army in state.armies:
		if not _is_travelling(army) or army.size <= 0:
			continue   # FIGHTING 军队冻结在原地，不推进
		var was_encounter_blocked := army.encounter_blocked
		army.encounter_blocked = false
		if was_encounter_blocked:
			continue
		if army.move_to == -1:
			# 等待进入下一段（上月被 capacity 卡住）
			_begin_next_leg(army)
			if army.move_to == -1:
				continue
		var edge := state.edge_of(army.move_from, army.move_to)
		var travel_days := edge_travel_days(edge, army.max_size)
		army.move_progress += 1.0 / travel_days   # 可能 >= 1.0（走到边末端），稍后统一判定到达
		if army.state == Army.State.MOVING and army.hold_target_progress >= 0.0:
			if army.move_progress >= army.hold_target_progress:
				army.move_progress = army.hold_target_progress
				holding_arrivals.append(army)

	# 2. 已到道路终点的溃退军先完成节点落位。否则它会在下一次遭遇检测中
	#    反复拦截刚击败自己的胜方，使双方永久卡在城市端点而无法触发攻城。
	for army in state.armies:
		if (
			army.state == Army.State.RETREATING
			and army.size > 0
			and army.move_to != -1
			and army.move_progress >= 1.0
		):
			_arrive_at_node(army)

	# 3. 遭遇检测（普通行军到达节点之前）：同边敌军按物理位置接触即交火。
	#    走到边末端（norm→1.0）的一方与任何相向敌军必接触 → 优先野战，杜绝错身。
	_detect_encounters()
	_block_passthrough()   # 敌占交战点卡位：禁止敌军不战穿过
	# 驻防转换必须晚于遭遇检测：两支敌军同日抵达同一驻防点时仍应先开战，不能同时变 HOLDING 后互相无视。
	for army in holding_arrivals:
		if army.state == Army.State.MOVING and army.battle_id == -1:
			_start_holding(army)

	# 4. 到达节点：处理普通行军；未到终点或重新寻路的撤退军保持在道路上。
	for army in state.armies:
		if _is_travelling(army) and army.size > 0 and army.move_to != -1 and army.move_progress >= 1.0:
			_arrive_at_node(army)

	# 5. 推进所有进行中的战斗各打一回合
	_resolve_battles()
	_purge_dead_armies()
	_finish_movement_capacity_index()


## 构建本次行军阶段的同国同向负载。遍历顺序仍完全由 state.armies 决定；
## 索引只替代后续容量求和，不参与军队排序或批量准入。
func _prepare_movement_capacity_index() -> void:
	_movement_capacity_load_by_direction.clear()
	_movement_capacity_entry_by_army.clear()
	_movement_capacity_index_active = not movement_capacity_index_disabled
	if not _movement_capacity_index_active:
		return
	for army in state.armies:
		_track_movement_capacity(army)


func _finish_movement_capacity_index() -> void:
	_movement_capacity_index_active = false
	_movement_capacity_load_by_direction.clear()
	_movement_capacity_entry_by_army.clear()


func _movement_capacity_key(
	nation_id: int,
	from_city: int,
	to_city: int
) -> Vector3i:
	return Vector3i(nation_id, from_city, to_city)


func _track_movement_capacity(army: Army) -> void:
	if (
		not _movement_capacity_index_active
		or army == null
		or army.size <= 0
		or not army.on_edge
		or army.move_to == -1
	):
		return
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge == null:
		return
	var load := army.road_capacity_load(edge.max_manpower)
	if load <= 0:
		return
	var instance_id := army.get_instance_id()
	if _movement_capacity_entry_by_army.has(instance_id):
		_untrack_movement_capacity(army)
	var key := _movement_capacity_key(
		army.owner_nation, army.move_from, army.move_to
	)
	_movement_capacity_load_by_direction[key] = (
		int(_movement_capacity_load_by_direction.get(key, 0)) + load
	)
	_movement_capacity_entry_by_army[instance_id] = [key, load]


func _untrack_movement_capacity(army: Army) -> void:
	if not _movement_capacity_index_active or army == null:
		return
	var instance_id := army.get_instance_id()
	if not _movement_capacity_entry_by_army.has(instance_id):
		return
	var entry: Array = _movement_capacity_entry_by_army[instance_id]
	var key: Vector3i = entry[0]
	var remaining := maxi(
		int(_movement_capacity_load_by_direction.get(key, 0))
			- int(entry[1]),
		0
	)
	if remaining == 0:
		_movement_capacity_load_by_direction.erase(key)
	else:
		_movement_capacity_load_by_direction[key] = remaining
	_movement_capacity_entry_by_army.erase(instance_id)


## 尝试进入 path 的下一段边。capacity 仅限制同国同方向运输负载；
## 反向与敌军独立。重军可分批通过窄路，不拆成多个 Army。
## 前置约定：调用前 army.move_from 已锚定为当前所在城。
func _begin_next_leg(army: Army) -> void:
	var from_city := army.move_from
	if army.path.is_empty():
		if army.state == Army.State.RETREATING:
			_start_recovering(army, from_city)
		else:
			_settle_idle(army, from_city)
		return
	var next_city: int = army.path[0]
	var edge := state.edge_of(from_city, next_city)
	if edge == null or edge.max_manpower < army.road_footprint():
		# 路径失效或道路连一个运输包都无法承载：普通军等待 AI 重规划，
		# 撤退军立即改走合法路线。
		army.path.clear()
		if army.state == Army.State.RETREATING:
			if (
				from_city >= 0
				and from_city < state.cities.size()
				and state.has_military_access(
					army.owner_nation,
					state.cities[from_city].owner_nation
				)
				and not state.city_under_siege(from_city)
			):
				_start_recovering(army, from_city)
				return
				army.path = (
					Pathfinding.nearest_home_city_for_repatriation(
						state,
						army
					)
					if army.diplomatic_repatriation
					else Pathfinding.strategic_retreat_city(
						state,
						army
					)
				)
			if army.path.is_empty():
				army.size = 0
			else:
				_begin_next_leg(army)
		else:
			_settle_idle(army, from_city)
		return
	var occupied_manpower := _friendly_same_direction_manpower(
		army.owner_nation,
		from_city,
		next_city
	)
	var forced_evacuation := (
		army.state == Army.State.RETREATING
		and from_city >= 0
		and from_city < state.cities.size()
		and not state.has_military_access(
			army.owner_nation,
			state.cities[from_city].owner_nation
		)
	)
	if (
		not forced_evacuation
		and occupied_manpower + army.road_capacity_load(edge.max_manpower)
			> edge.max_manpower
	):
		# 只累计同国同方向的运输负载；反向友军和敌军不占本方向容量。
		army.move_to = -1
		return
	_set_occupation_claimant_for_crossing(
		army,
		from_city,
		next_city
	)
	army.path.pop_front()
	army.move_to = next_city
	army.move_progress = 0.0
	army.holding_days = 0
	army.resume_holding_after_battle = false
	edge.passing_count += 1
	edge.occupied = true
	army.on_edge = true
	_track_movement_capacity(army)


func _friendly_same_direction_manpower(
	nation_id: int,
	from_city: int,
	to_city: int
) -> int:
	if _movement_capacity_index_active:
		return int(_movement_capacity_load_by_direction.get(
			_movement_capacity_key(nation_id, from_city, to_city),
			0
		))
	var manpower := 0
	for other in state.armies:
		if other.size <= 0 or other.owner_nation != nation_id:
			continue
		if not other.on_edge or other.move_to == -1:
			continue
		if other.move_from == from_city and other.move_to == to_city:
			var edge := state.edge_of(from_city, to_city)
			if edge != null:
				manpower += other.road_capacity_load(edge.max_manpower)
	return manpower


func _set_occupation_claimant_for_crossing(
	army: Army,
	from_city: int,
	to_city: int
) -> void:
	if (
		from_city < 0
		or from_city >= state.cities.size()
		or to_city < 0
		or to_city >= state.cities.size()
		or not state.is_enemy(
			army.owner_nation,
			state.cities[to_city].owner_nation
		)
	):
		return
	var origin_owner := state.cities[from_city].owner_nation
	if (
		origin_owner == army.owner_nation
		or state.is_allied(
			army.owner_nation,
			origin_owner
		)
	):
		army.occupation_claimant_nation = origin_owner
	else:
		army.occupation_claimant_nation = army.owner_nation


## 到达 move_to 节点：释放当前边，触发/加入围城或继续下一段。
func _arrive_at_node(army: Army) -> void:
	var arrived := army.move_to
	var edge := state.edge_of(army.move_from, arrived)
	_release_edge(army)   # 离开边：释放通行槽

	if army.state == Army.State.RETREATING:
		army.move_from = arrived
		army.move_to = -1
		army.move_progress = 0.0
		army.location_city = arrived
		if army.path.is_empty():
			if (
				state.has_military_access(
					army.owner_nation,
					state.cities[arrived].owner_nation
				)
				and not state.city_under_siege(arrived)
			):
				_start_recovering(army, arrived)
			else:
				# 目的地在途中失守或被围：继续向首都纵深重算。
				_start_morale_retreat_from_city(army, arrived, arrived)
		else:
			_begin_next_leg(army)
		return

	var city := state.cities[arrived]
	# 该城正被围攻：任何抵达者都必须与围城战斗互动（敌对方→攻/守，城主援军→帮守/解围），
	# 不得旁观穿过。城被围时 owner 尚未易主，故不能只凭 is_enemy(owner) 判定。
	if _siege_battle_of(city) != null:
		_start_or_join_siege(army, city, edge)
		return
	if state.is_enemy(army.owner_nation, city.owner_nation):
		_start_or_join_siege(army, city, edge)
		return

	# 中立国不提供通行权；盟国允许穿越和临时驻留。
	if not state.has_military_access(army.owner_nation, city.owner_nation):
		army.move_from = arrived
		army.move_to = -1
		army.location_city = arrived
		army.path.clear()
		_retreat_to_friendly(army)
		return

	# 本国/盟国城市且无围城：继续下一段或驻扎。
	army.move_from = arrived
	army.move_to = -1
	army.location_city = arrived
	if army.path.is_empty():
		_settle_idle(army, arrived)
	else:
		_begin_next_leg(army)


func _is_travelling(army: Army) -> bool:
	return army.state in [Army.State.MOVING, Army.State.RETREATING]


func _is_edge_unit(army: Army) -> bool:
	return army.state in [Army.State.MOVING, Army.State.RETREATING, Army.State.HOLDING]


## 检测新遭遇（位置驱动的两两交战）：同边上的敌对军队，按物理位置判断是否接触。
##  - 相向：正向者推进到与反向者接近/交错才触发；相距远则不触发（边内可能不开战）。
##  - 同向：后军追上前军（位置差 <= CONTACT_EPS）才触发（修复"追逐永不开战"）。
## 一条边先选归一化位置差最小的敌对国家对，再把同国抵达者聚合进对应侧；
## 真正无法二分的完全同构多国接触统一脱离，第三方不与敌对方并肩。
func _detect_encounters() -> void:
	# 索引进行中的 FIELD 战斗（按边）
	var field_by_edge: Dictionary = {}
	for b in state.battles:
		if not b.finished and b.kind == Battle.Kind.FIELD and b.edge != null:
			field_by_edge[_edge_key_of(b.edge.city_a, b.edge.city_b)] = b

	# 按边聚合普通行军、溃逃军与驻防军。只有 MOVING 可主动发起接战。
	var by_edge: Dictionary = {}
	for army in state.armies:
		if not _is_edge_unit(army) or army.size <= 0 or army.move_to == -1:
			continue
		var key := _edge_key_of(army.move_from, army.move_to)
		if not by_edge.has(key):
			by_edge[key] = []
		by_edge[key].append(army)

	var keys := by_edge.keys()
	keys.sort_custom(func(a, b) -> bool:
		var group_a: Array = by_edge[a]
		var group_b: Array = by_edge[b]
		var edge_a := state.edge_of(
			(group_a[0] as Army).move_from,
			(group_a[0] as Army).move_to
		)
		var edge_b := state.edge_of(
			(group_b[0] as Army).move_from,
			(group_b[0] as Army).move_to
		)
		return EquivariantOrder.mirror_orbit_edge_less(
			state,
			edge_a,
			edge_b
		)
	)
	for key in keys:
		var group: Array = by_edge[key]
		group.sort_custom(func(x: Army, y: Army) -> bool:
			return EquivariantOrder.mirror_orbit_army_less(
				state,
				x,
				y
			)
		)
		var edge := state.edge_of(group[0].move_from, group[0].move_to)
		if edge == null:
			continue

		# 已有战斗：先按回合开始时冻结的战线位置筛出全部抵达者，再统一加入。
		# 逐支边判边加会让先加入者移动 contact_dist，进而改变后续军队资格，
		# 把 group 遍历顺序泄漏成同日“级联增援”。
		if field_by_edge.has(key):
			var existing: Battle = field_by_edge[key]
			var arrivals: Array[Army] = []
			for army in group:
				if (
					not existing.has_army(army)
					and _can_join_field_contact(
						army,
						existing,
						edge
					)
				):
					arrivals.append(army)
			for army in arrivals:
				_join_field_battle(existing, army, edge)
			continue

		if group.size() < 2:
			continue

		# 在所有「敌对且已接触」的对中选交战国家对。主判据=归一化位置差 gap 最小（物理逼近程度）。
		# gap 相等时按纯物理/稳定身份判据裁决，绝不依赖 army.id 或遍历顺序（item 11 验收）：
		#   次判据=双方合计兵力更大者优先（更决定性的对撞先形成核心，镜像不变量）；
		#   再相等=镜像轨道上的实体物理键较小者优先。
		var best_x: Army = null
		var best_y: Army = null
		var best_gap := INF
		var best_size := -1
		var best_ambiguous := false
		var best_equivalent_contacts := {}
		var best_equivalent_nation_pairs := {}
		for i in range(group.size()):
			for j in range(i + 1, group.size()):
				var x: Army = group[i]
				var y: Army = group[j]
				if x.state == Army.State.RETREATING and y.state == Army.State.RETREATING:
					continue   # 仅两支溃逃军都无主动交战意图；驻防军可截击溃逃军
				if not state.is_enemy(x.owner_nation, y.owner_nation):
					continue
				if not _edge_contact(x, y, edge):
					continue
				var gap := absf(_norm_pos(x, edge) - _norm_pos(y, edge))
				var psize := x.size + y.size
				# 词典序 argmin：gap 升 → 合计兵力降 → 镜像轨道实体键升。
				var better := false
				if best_x == null:
					better = true
				elif not is_equal_approx(gap, best_gap):
					better = gap < best_gap
				elif psize != best_size:
					better = psize > best_size
				else:
					better = EquivariantOrder.encounter_pair_less(
						state,
						x,
						y,
						best_x,
						best_y
					)
					if (
						not better
						and EquivariantOrder.encounter_pair_equivalent(
							state,
							x,
							y,
							best_x,
							best_y
						)
					):
						best_ambiguous = true
						best_equivalent_nation_pairs[Vector2i(
							mini(x.owner_nation, y.owner_nation),
							maxi(x.owner_nation, y.owner_nation)
						)] = true
						var equivalent_contact := (
							_norm_pos(x, edge)
							+ _norm_pos(y, edge)
						) * 0.5
						for equivalent_army in [x, y]:
							if not best_equivalent_contacts.has(
								equivalent_army
							):
								best_equivalent_contacts[
									equivalent_army
								] = []
							best_equivalent_contacts[
								equivalent_army
							].append(equivalent_contact)
				if better:
					best_gap = gap
					best_size = psize
					best_x = x
					best_y = y
					best_ambiguous = false
					var best_contact := (
						_norm_pos(x, edge)
						+ _norm_pos(y, edge)
					) * 0.5
					best_equivalent_contacts = {
						x: [best_contact],
						y: [best_contact],
					}
					best_equivalent_nation_pairs = {
						Vector2i(
							mini(x.owner_nation, y.owner_nation),
							maxi(x.owner_nation, y.owner_nation)
						): true,
					}
		if best_x == null:
			continue   # 本边无满足接触的敌对对 → 不开战（"边内可能不触发"）
		if best_ambiguous and best_equivalent_nation_pairs.size() > 1:
			# Battle 目前是严格两方模型。三个以上互相敌对、且全部物理键
			# 完全同构时，没有镜像等变的国家对可被指定为首战双方。让全部
			# 等价接触者沿各自战略退路脱离，保证有限收敛；绝不能冻结等待
			# 一个不会出现的外部破缺。只有一个国家对时则以任一等价军为
			# 核心继续建战，随后把
			# 同国等价军全部聚合进同一侧（典型 2v1 / NvM）。
			for army in best_equivalent_contacts:
				army.encounter_blocked = false
				_retreat(army)
			continue

		var length := float(maxi(edge.distance, 1))
		var battle := state.new_battle(Battle.Kind.FIELD)
		battle.edge = edge
		battle.contact_dist_a = _norm_pos(best_x, edge) * length
		battle.contact_dist_b = _norm_pos(best_y, edge) * length
		if best_x.state == Army.State.HOLDING:
			battle.holding_side = 1
			battle.holding_days = float(best_x.holding_days)
		elif best_y.state == Army.State.HOLDING:
			battle.holding_side = 2
			battle.holding_days = float(best_y.holding_days)
		_enter_battle(battle, best_x, 1)
		_enter_battle(battle, best_y, 2)
		# 首日其余军队也必须按核心对刚建立时的冻结战线批量判定，
		# 不能让先加入者改变后续军队的抵达资格。
		var initial_arrivals: Array[Army] = []
		for army in group:
			if (
				not battle.has_army(army)
				and _can_join_field_contact(
					army,
					battle,
					edge
				)
			):
				initial_arrivals.append(army)
		for army in initial_arrivals:
			_join_field_battle(battle, army, edge)


## 增援抵达判定（item 4）：任何军队（含 MOVING）加入一场进行中的战斗，都必须已行进到
## 距「己方战线」归一化距离 <= REINFORCEMENT_RADIUS 才算抵达战场；否则继续行军（eta 未到）。
## 归侧战线：与本军同 nation 的一侧的 contact_dist（同国增援从己方后方接近己方战线）。
## 若无法判定同侧（第三国/两侧皆异族），取两战线中较近者兜底（一般由 _block_passthrough 拦截）。
func _can_join_field_contact(army: Army, battle: Battle, edge: Edge) -> bool:
	var length := float(maxi(edge.distance, 1))
	var my_norm := _norm_pos(army, edge)
	var line_a := clampf(battle.contact_dist_a / length, 0.0, 1.0)
	var line_b := clampf(battle.contact_dist_b / length, 0.0, 1.0)
	var na := battle.side_a[0].owner_nation if not battle.side_a.is_empty() else -1
	var nb := battle.side_b[0].owner_nation if not battle.side_b.is_empty() else -1
	var my_line := -1.0
	if army.owner_nation == na:
		my_line = line_a
	elif army.owner_nation == nb:
		my_line = line_b
	if my_line >= 0.0:
		return absf(my_norm - my_line) <= REINFORCEMENT_RADIUS
	return minf(absf(my_norm - line_a), absf(my_norm - line_b)) <= REINFORCEMENT_RADIUS


## 军队在边上「以 city_a 为原点」的归一化位置 ∈ [0,1]。
func _norm_pos(army: Army, edge: Edge) -> float:
	if army.move_from == edge.city_a:
		return clampf(army.move_progress, 0.0, 1.0)
	return clampf(1.0 - army.move_progress, 0.0, 1.0)


## 军队在边上的行进方向（+1: city_a→city_b；-1: 反向）。
func _edge_dir(army: Army, edge: Edge) -> int:
	return 1 if army.move_from == edge.city_a else -1


## 两军是否已在边上接触（可触发战斗）。
##  - 相向（方向相异）：正向者位置 >= 反向者位置 - EPS（接近或已交错）。
##  - 同向（方向相同）：位置差 <= EPS（后军追上前军）。
func _edge_contact(x: Army, y: Army, edge: Edge) -> bool:
	var px := _norm_pos(x, edge)
	var py := _norm_pos(y, edge)
	if _edge_dir(x, edge) == _edge_dir(y, edge):
		return absf(px - py) <= CONTACT_EPS
	var plus_pos := px if _edge_dir(x, edge) > 0 else py
	var minus_pos := py if _edge_dir(x, edge) > 0 else px
	return plus_pos >= minus_pos - CONTACT_EPS


## 敌占交战点卡位：任何 MOVING 军队若逼近同边上一场进行中 FIELD 战斗的交战线、
## 且与该战斗任一方敌对，则被冻结在交战线位置待机（不得穿过）。待该战斗结束后，
## 下一 tick 由 _detect_encounters 让其与幸存者开战——实现「同点必战、串行化」。
## （同 nation 军队不卡位——它们由 _join_field_battle 直接并入本侧。）
func _block_passthrough() -> void:
	for battle in state.battles:
		if battle.finished or battle.kind != Battle.Kind.FIELD or battle.edge == null:
			continue
		var edge := battle.edge
		var length := float(maxi(edge.distance, 1))
		var line_norm := clampf(maxf(battle.contact_dist_a, battle.contact_dist_b) / length, 0.0, 1.0)
		var na := battle.side_a[0].owner_nation if not battle.side_a.is_empty() else -1
		var nb := battle.side_b[0].owner_nation if not battle.side_b.is_empty() else -1
		for army in state.armies:
			if not _is_travelling(army) or army.size <= 0 or army.move_to == -1:
				continue
			if battle.has_army(army):
				continue
			if _edge_key_of(army.move_from, army.move_to) != _edge_key_of(edge.city_a, edge.city_b):
				continue
			# 同 nation 交给 _join_field_battle 处理；此处只卡「敌对且未并入」的第三国
			if army.owner_nation == na or army.owner_nation == nb:
				continue
			if not (state.is_enemy(army.owner_nation, na) or state.is_enemy(army.owner_nation, nb)):
				continue
			var my_norm := _norm_pos(army, edge)
			if absf(my_norm - line_norm) > CONTACT_EPS:
				continue
			# 卡位：夹到交战线前沿，冻结推进（保持 MOVING，下一 tick 待幸存者再战）。
			# 夹取用 min(现值) 避免把尚未抵达的军队「前拉」，只阻止越过、不瞬移。
			if army.move_from == edge.city_a:
				army.move_progress = clampf(line_norm, 0.0, army.move_progress)
			else:
				army.move_progress = clampf(1.0 - line_norm, 0.0, army.move_progress)


## 围城角色统一入口：
## - side_a 仍是单一 nation 的围城方；
## - side_b 若与城市控制者有军事通行权，则是可含盟军的城市防卫共同体；
## - side_b 否则是单一 nation 的敌对挑战者；
## - 与当前围城无敌对关系的无关方撤回。
func _start_or_join_siege(attacker: Army, city: City, edge: Edge) -> void:
	var siege := _siege_battle_of(city)
	if siege == null and not state.is_enemy(attacker.owner_nation, city.owner_nation):
		_retreat_to_friendly(attacker)
		return
	if siege == null:
		var defenders := _siege_city_defenders(city)
		# item 7：不再设机制层「弱攻自动撤离」硬门槛——兵力不足时围城进度会按连续曲线
		# 停滞/倒退（见 _advance_siege），是否撤离交 AI 战略层裁量，避免攻/撤无限循环。
		siege = state.new_battle(Battle.Kind.SIEGE)
		siege.edge = edge
		siege.city = city
		_mark_city_war_disruption(city)
		var length := float(maxi(edge.distance, 1))
		siege.contact_dist_a = length   # 围城方在城墙 dist=L（端点，无地形惩罚）
		siege.contact_dist_b = 0.0      # 守军城中 dist=0（端点，无地形惩罚）
		if not defenders.is_empty():
			for defender in defenders:
					_enter_battle(siege, defender, 2)
			siege.has_garrison = true
		# 破城所需兵力仅由工事强度换算（item 6：不含守军人数，守军是城下决斗阶段的对手）。
		# 有无守军该值一致，消除数量级跳变；守军被歼后此值不变（城防来自 fort_strength）。
		siege.siege_required = Combat.siege_required_manpower(city.fort_strength)
		_enter_battle(siege, attacker, 1)
		return

	match _siege_role_for_nation(siege, attacker.owner_nation):
		SiegeRole.BESIEGER:
			_enter_battle(siege, attacker, 1)
		SiegeRole.CITY_DEFENDER:
			if (
				not siege.side_b.is_empty()
				and not _siege_side_defends_city(
					siege,
					siege.side_b
				)
			):
				# side_b 已被敌对挑战者占据，防卫共同体下一日接续，避免三方混侧。
				_retreat_to_friendly(attacker)
				return
			_enter_battle(siege, attacker, 2)
			siege.has_garrison = true
		SiegeRole.CHALLENGER:
			if (
				siege.has_garrison
				or (
					not siege.side_b.is_empty()
					and siege.side_b[0].owner_nation
						!= attacker.owner_nation
				)
			):
				_retreat_to_friendly(attacker)
				return
			_enter_battle(siege, attacker, 2)
		_:
			_retreat_to_friendly(attacker)


func _siege_role_for_nation(
	siege: Battle,
	nation_id: int
) -> int:
	if (
		siege == null
		or siege.city == null
		or nation_id < 0
		or nation_id >= state.nations.size()
		or siege.side_a.is_empty()
	):
		return SiegeRole.REJECTED
	var besieger_nation := siege.side_a[0].owner_nation
	if nation_id == besieger_nation:
		return SiegeRole.BESIEGER
	if (
		_nation_defends_city(nation_id, siege.city)
		and state.is_enemy(nation_id, besieger_nation)
	):
		return SiegeRole.CITY_DEFENDER
	if (
		not siege.side_b.is_empty()
		and siege.side_b[0].owner_nation == nation_id
	):
		return SiegeRole.CHALLENGER
	if state.is_enemy(nation_id, besieger_nation):
		return SiegeRole.CHALLENGER
	return SiegeRole.REJECTED


func _nation_defends_city(
	nation_id: int,
	city: City
) -> bool:
	return (
		city != null
		and nation_id >= 0
		and nation_id < state.nations.size()
		and state.has_military_access(
			nation_id,
			city.owner_nation
		)
	)


func _siege_side_defends_city(
	siege: Battle,
	side: Array[Army]
) -> bool:
	if siege == null or siege.city == null:
		return false
	var living_count := 0
	for army in side:
		if army.size <= 0:
			continue
		living_count += 1
		if not _nation_defends_city(
			army.owner_nation,
			siege.city
		):
			return false
	return living_count > 0


func _siege_city_defenders(city: City) -> Array[Army]:
	var result: Array[Army] = []
	for army in state.armies:
		if (
			army.size <= 0
			or not _nation_defends_city(
				army.owner_nation,
				city
			)
			or not army.is_at_city_node(city.id)
		):
			continue
		if army.state == Army.State.FIGHTING:
			var active_battle := state.battle_by_id(
				army.battle_id
			)
			if (
				active_battle != null
				and not active_battle.finished
				and active_battle.kind == Battle.Kind.SIEGE
				and active_battle.city == city
				and active_battle.has_army(army)
			):
				continue
		result.append(army)
	EquivariantOrder.sort_armies(
		result,
		state,
		city.owner_nation,
		city.id
	)
	return result


## 对每场进行中的战斗推进一个 tick：FIELD 打一回合；SIEGE 走专用状态机（守军歼灭≠破城）。
func _resolve_battles() -> void:
	# item 8：每 tick 只消费一次共享战场骰与一次战术熵。各战斗/各侧修正由物理指纹纯函数派生，
	# 不依赖 battle 数组顺序，也不会因军队拆分增加随机消费次数。
	var shared_roll := state.rng.randi_range(Combat.DICE_MIN, Combat.DICE_MAX)
	var tactical_entropy := int(state.rng.randi())
	for battle in state.battles:
		if battle.finished:
			continue
		if battle.kind == Battle.Kind.SIEGE:
			_advance_siege(
				battle,
				shared_roll,
				tactical_entropy
			)
		else:
			_resolve_combat_round(
				battle,
				shared_roll,
				tactical_entropy
			)
			if battle.finished:
				_finish_field_battle(battle)
	state.battles = state.battles.filter(func(b: Battle) -> bool: return not b.finished)


func _resolve_combat_round(
	battle: Battle,
	shared_roll: int,
	tactical_entropy: int
) -> void:
	_sync_battle_ruler_modifiers(battle)
	_refresh_battle_frontline_priorities(battle)
	Combat.resolve_round(
		battle,
		state.rng,
		shared_roll,
		tactical_entropy,
		state.day
	)
	# 战斗伤亡可能把仍标记 on_edge 的军队直接减至 0；旧扫描会立即排除它们，
	# 局部索引也须在任何随后撤退军尝试入边前同步移除。
	for side in [
		battle.side_a, battle.side_b,
		battle.routed_a, battle.routed_b,
	]:
		for participant in side:
			if participant.size <= 0:
				_untrack_movement_capacity(participant)
	# Combat 只负责判定单军溃退并从战斗侧移出；Simulation 拥有路径与边占用，
	# 因此在同一回合立即从真实战场位置启动撤退。
	for army in battle.routed_a:
		if army.size > 0:
			_retreat(army)
		else:
			army.battle_id = -1
	for army in battle.routed_b:
		if army.size <= 0:
			army.battle_id = -1
		elif (
			battle.kind == Battle.Kind.SIEGE
			and battle.has_garrison
			and battle.city != null
			and _nation_defends_city(
				army.owner_nation,
				battle.city
			)
		):
			_retreat_defender(army, battle.city)
		else:
			_retreat(army)


func _sync_battle_ruler_modifiers(battle: Battle) -> void:
	if battle == null:
		return
	if battle.city != null:
		var base_city_defense := Combat.city_defense_modifier(
			battle.city
		)
		battle.city.ruler_city_defense_multiplier = (
			float(state.effective_city_defense(battle.city))
				/ float(base_city_defense)
			if base_city_defense > 0
			else 1.0
		)
	for side in [battle.side_a, battle.side_b]:
		for army_value in side:
			var army: Army = army_value
			if (
				army.owner_nation < 0
				or army.owner_nation >= state.nations.size()
			):
				army.ruler_defense_multiplier = 1.0
				army.ruler_morale_multiplier = 1.0
				continue
			var ruler := state.nations[army.owner_nation]
			army.ruler_defense_multiplier = maxf(
				RulerProfile.defense_multiplier(ruler), 0.1
			)
			army.ruler_morale_multiplier = maxf(
				RulerProfile.morale_multiplier(ruler), 0.1
			)


func _refresh_battle_frontline_priorities(battle: Battle) -> void:
	var anchor_city := (
		battle.city.id
		if battle.city != null
		else -1
	)
	_fill_battle_frontline_priority(
		battle.side_a,
		battle.frontline_priority_a,
		anchor_city
	)
	_fill_battle_frontline_priority(
		battle.side_b,
		battle.frontline_priority_b,
		anchor_city
	)


func _fill_battle_frontline_priority(
	side: Array[Army],
	priority: Dictionary,
	anchor_city: int
) -> void:
	priority.clear()
	if side.is_empty():
		return
	var nation_id := side[0].owner_nation
	if (
		anchor_city >= 0
		and anchor_city < state.cities.size()
	):
		var anchor := state.cities[anchor_city]
		var defense_coalition := true
		for army in side:
			if not _nation_defends_city(
				army.owner_nation,
				anchor
			):
				defense_coalition = false
				break
		if defense_coalition:
			nation_id = anchor.owner_nation
	var ordered: Array[Army] = side.duplicate()
	ordered.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a,
			b,
			anchor_city
		)
	)
	for index in range(ordered.size()):
		priority[ordered[index]] = index


func _mark_city_war_disruption(city: City) -> void:
	city.war_disruption_until_day = maxi(
		city.war_disruption_until_day,
		state.day + CITY_WAR_DISRUPTION_DAYS
	)


## SIEGE 状态机（每天一 tick）。三阶段：
##  1) 守军抵抗：resolve_round 削守军。守军歼灭≠破城——转纯围城；攻方溃则围城失败。
##  2) 城下决斗：side_b 为敌对挑战者（无城防加成），分胜负后胜方独占围城。
##  3) 纯围城：无对抗，掷骰累积 siege_progress，达阈值破城易主。
func _advance_siege(
	battle: Battle,
	shared_roll: int = -1,
	tactical_entropy: int = -1
) -> void:
	if battle.city != null:
		_mark_city_war_disruption(battle.city)
	battle.prune_dead()
	# 纯围城阶段也必须执行单军溃败阈值；不能因没有正面守军而让失去组织的
	# 围城军无限停留并贡献（哪怕为 0 的）封锁兵力。
	battle.side_a = _withdraw_broken_armies(battle.side_a)
	_reconcile_siege_city_defenders(battle)
	_refresh_battle_frontline_priorities(battle)
	var atk_alive := battle.side_size(battle.side_a) > 0

	# 阶段 1：守军抵抗
	if battle.has_garrison and battle.side_size(battle.side_b) > 0:
		if not atk_alive:
			# 围城方尽墨（多因断粮）→ 防卫共同体统一结算解围。
			_resolve_siege_side_b_victory(battle)
			return
		_decay_interrupted_siege_progress(battle)
		_resolve_combat_round(
			battle,
			shared_roll,
			tactical_entropy
		)
		if not battle.finished:
			return
		if battle.winner_side != 1:
			# 攻方被守军击退，或双方同时崩溃判平局：进攻方未攻下→守方保城，攻方撤退。
			for a in battle.side_a:
				if a.size > 0:
					_retreat(a)
				else:
					a.battle_id = -1
			for d in battle.side_b:
				d.battle_id = -1
				if d.size > 0:
					_settle_or_recover_after_battle(d, battle.city.id)
			return
		# 守军溃散（winner_side==1）：不占领，清走守军，转纯围城
		for d in battle.side_b:
			if d.size > 0:
				_retreat_defender(d, battle.city)
			else:
				d.battle_id = -1
		battle.side_b.clear()
		battle.has_garrison = false
		battle.side_a = _withdraw_broken_armies(battle.side_a)
		if battle.side_a.is_empty():
			battle.finished = true
			battle.winner_side = 0
			return
		battle.finished = false
		battle.winner_side = 0
		return

	# 阶段 2：城下决斗（side_b 为敌对挑战者，无城防加成）
	if battle.side_size(battle.side_b) > 0:
		if not atk_alive:
			# 围城方尽墨：城主/盟军解围则解除围城，敌对第三国才接管围城。
			_resolve_siege_side_b_victory(battle)
			return
		_decay_interrupted_siege_progress(battle)
		_resolve_combat_round(
			battle,
			shared_roll,
			tactical_entropy
		)
		if not battle.finished:
			return
		if battle.winner_side == 1:
			# 围城方胜：挑战者撤退，围城继续
			for c in battle.side_b:
				if c.size > 0:
					_retreat(c)
				else:
					c.battle_id = -1
			_reset_empty_battle_side_b(battle)
			battle.side_a = _withdraw_broken_armies(battle.side_a)
			if battle.side_a.is_empty():
				battle.finished = true
				battle.winner_side = 0
				return
			battle.finished = false
			battle.winner_side = 0
		elif battle.winner_side == 0:
			# 平局（双方同时崩溃、续战能力相等）：城下双方都撤退，围城彻底解除，无人占城。
			for c in battle.side_b:
				if c.size > 0:
					_retreat(c)
				else:
					c.battle_id = -1
			for a in battle.side_a:
				if a.size > 0:
					_retreat(a)
				else:
					a.battle_id = -1
			battle.side_a.clear()
			battle.side_b.clear()
			battle.finished = true
			battle.winner_side = 0
		else:
			# 挑战者胜：原围城方撤退
			for a in battle.side_a:
				if a.size > 0:
					_retreat(a)
				else:
					a.battle_id = -1
			battle.side_a.clear()
			_resolve_siege_side_b_victory(battle)
		return

	# 阶段 3：纯围城，连续曲线累积破城（item 7：无 5× 硬门槛、无跳变）。
	if not atk_alive:
		battle.finished = true
		battle.winner_side = 0   # 围城方尽墨，无人占领
		return
	# 连续曲线：ratio≥1 正常推进、0.5~1 极慢（部分封锁）、<0.5 缓慢倒退。
	# 不再机制性强制撤离——兵力不足时保持围城/等待援军，去留由 AI 战略层按补给与威胁决策，
	# 避免「机制撤离 ↔ AI 再派」的攻/撤无限循环（item 7 验收）。进度夹在 [0, REQUIRED]。
	var daily_progress := Combat.siege_daily_progress(
		Combat.effective_siege_strength(
			battle.side_a,
			battle.frontline_priority_a
		),
		battle.siege_required
	)
	battle.siege_progress = clampf(
		battle.siege_progress + daily_progress,
		0.0,
		Combat.SIEGE_PROGRESS_REQUIRED
	)
	if battle.siege_progress >= Combat.SIEGE_PROGRESS_REQUIRED:
		var captor := _strongest_alive(battle.side_a)
		if captor != null:
			_capture_city(captor, battle.city, -1, false)
		for a in battle.side_a:
			a.battle_id = -1
			if (
				a != captor
				and a.size > 0
				and state.has_military_access(
					a.owner_nation,
					battle.city.owner_nation
				)
			):
				_settle_idle(a, battle.city.id)
			if (
				captor != null
				and state.has_military_access(
					captor.owner_nation,
					battle.city.owner_nation
				)
			):
				_execute_campaign_post_capture_plan(
					captor,
					battle.city
				)
		battle.finished = true
		battle.winner_side = 1


## 围城建立后仍可能有撤退军抵达、恢复军落位等状态转换。每个围城日都重新收集
## 目标城内未参战的防卫共同体军队，确保城主与盟军使用同一入场规则。
func _reconcile_siege_city_defenders(battle: Battle) -> void:
	if (
		battle.city == null
		or battle.city.id < 0
		or battle.city.id >= state.cities.size()
		or state.cities[battle.city.id] != battle.city
	):
		return
	var defenders := _siege_city_defenders(battle.city)
	if defenders.is_empty():
		return
	if (
		not battle.side_b.is_empty()
		and not _siege_side_defends_city(
			battle,
			battle.side_b
		)
	):
		# 第三方已在城下挑战围城方；守军下一日再接续，避免三国混入同一战斗侧。
		return
	for defender in defenders:
		if battle.has_army(defender):
			continue
		_enter_battle(battle, defender, 2)
	if _siege_side_defends_city(battle, battle.side_b):
		# 后到防卫共同体入城帮守：加入城下决斗消耗攻方，但封锁需求仅由工事决定
		# （item 6：守军不抬高破城门槛），此处无需改动 battle.siege_required。
		battle.has_garrison = true


func _decay_interrupted_siege_progress(battle: Battle) -> void:
	battle.siege_progress = Combat.siege_progress_after_interruption(
		battle.siege_progress
	)


## side_b 获胜后的唯一结算：城市防卫共同体解围并驻城；
## 对城主无通行权的敌对挑战者才晋升为新围城方。
func _resolve_siege_side_b_victory(
	battle: Battle
) -> void:
	if not _siege_side_defends_city(
		battle,
		battle.side_b
	):
		_promote_challengers(battle)
		return
	battle.side_a.clear()
	for challenger in battle.side_b:
		challenger.battle_id = -1
		if challenger.size > 0:
			_settle_or_recover_after_battle(
				challenger,
				battle.city.id
			)
	_reset_empty_battle_side_b(battle)
	battle.has_garrison = false
	battle.finished = true
	battle.winner_side = 2


## 挑战者（side_b）接管围城：晋升为围城方（移入 side_a、置城墙位置），围城继续。
func _promote_challengers(battle: Battle) -> void:
	var new_besiegers: Array[Army] = []
	for c in battle.side_b:
		if (
			c.size > 0
				and c.combat_morale() > Combat.ARMY_ROUT_THRESHOLD
		):
			new_besiegers.append(c)
		elif c.size > 0:
			_retreat(c)
		else:
			c.battle_id = -1
	battle.side_a = new_besiegers
	battle.tactical_key_a = battle.tactical_key_b
	battle.reinforcement_morale_gained_a = (
		battle.reinforcement_morale_gained_b
	)
	battle.reinforce_fresh_a = battle.reinforce_fresh_b.duplicate()
	battle.frontline_priority_a = (
		battle.frontline_priority_b.duplicate()
	)
	_reset_empty_battle_side_b(battle)
	battle.contact_dist_a = float(maxi(battle.edge.distance, 1)) if battle.edge != null else 0.0
	# 挑战者接管的是纯围城；封锁需求仅由工事决定（item 6，与守军无关），显式重申以自证。
	battle.siege_required = (
		Combat.siege_required_manpower(battle.city.fort_strength)
		if battle.city != null
		else battle.siege_required
	)
	battle.has_garrison = false
	battle.finished = new_besiegers.is_empty()
	battle.winner_side = 0


func _reset_empty_battle_side_b(battle: Battle) -> void:
	battle.side_b.clear()
	battle.reinforce_fresh_b.clear()
	battle.routed_b.clear()
	battle.frontline_priority_b.clear()
	battle.reinforcement_morale_gained_b = 0.0
	battle.tactical_key_b = 0


func _withdraw_broken_armies(side: Array[Army]) -> Array[Army]:
	var active: Array[Army] = []
	for army in side:
		if army.size <= 0:
			army.battle_id = -1
		elif army.combat_morale() <= Combat.ARMY_ROUT_THRESHOLD:
			_retreat(army)              # 军队级溃退阈值：彻底失去组织者撤离
		else:
			active.append(army)
	return active


func _settle_or_recover_after_battle(army: Army, city_id: int) -> void:
	if army.morale <= Combat.MORALE_FLOOR:
		_start_morale_retreat_from_city(
			army,
			city_id
		)
	else:
		_settle_idle(army, city_id)


func _finish_field_battle(battle: Battle) -> void:
	# 平局（winner_side==0，双方同时失败且续战能力相等）：双方都脱离战斗撤退，无人占领/追击。
	if battle.winner_side == 0:
		_finish_field([], battle.side_a + battle.side_b)
		return
	var winners: Array[Army] = battle.side_a if battle.winner_side == 1 else battle.side_b
	var losers: Array[Army] = battle.side_b if battle.winner_side == 1 else battle.side_a
	_finish_field(winners, losers)


func _finish_field(winners: Array[Army], losers: Array[Army]) -> void:
	for a in losers:
		if a.size > 0:
			_retreat(a)              # 败方带残兵向首都纵深撤退
		else:
			a.battle_id = -1
	for a in winners:
		if a.size > 0:
			if a.combat_morale() <= Combat.SIDE_ROUT_THRESHOLD:
				_retreat(a)          # 双方同时崩溃时，低士气胜方也不能继续追击
			else:
				_resume_after_battle(a)
		else:
			a.battle_id = -1


## 胜方继续行军：解除 FIGHTING，恢复 MOVING，沿原方向推进（仍占该边）。
func _resume_after_battle(army: Army) -> void:
	if army.forced_retreat:
		army.state = Army.State.RETREATING
	elif army.resume_holding_after_battle:
		var edge := state.edge_of(army.move_from, army.move_to)
		army.state = (
			Army.State.HOLDING
			if edge != null and edge.allows_holding
			else Army.State.MOVING
		)
	else:
		army.state = Army.State.MOVING
	army.resume_holding_after_battle = false
	army.battle_id = -1


## 归侧加入既有 FIELD 战斗（两方制 + 可靠同国聚合）。
## 因 is_enemy 等价「异 nation」：同 side_a 的 nation → 并入 side_a；同 side_b 的 nation → 并入 side_b；
## 与两侧皆异族的第三国不介入（待当前这对分胜负后，下一 tick 再与幸存者接触）。
## 初始「是否开战」由核心对的 _edge_contact 位置判定把关；此处只处理「已开战后同国增援的归并」，
## 故不再要求近邻（修复：同边靠后的同国友军被 CONTACT_EPS 漏掉而无法聚合）。
func _join_field_battle(battle: Battle, army: Army, edge: Edge) -> void:
	if battle.side_a.is_empty() or battle.side_b.is_empty():
		return
	var na := battle.side_a[0].owner_nation
	var nb := battle.side_b[0].owner_nation
	var target := 0
	if army.owner_nation == na:
		target = 1
	elif army.owner_nation == nb:
		target = 2
	else:
		return
	if battle.holding_side == target:
		var side_before: Array[Army] = battle.side_a if target == 1 else battle.side_b
		var old_size := 0
		for member in side_before:
			if member.size > 0:
				old_size += member.size
		var new_total := old_size + maxi(army.size, 0)
		if new_total > 0:
			var newcomer_days := float(army.holding_days) if army.state == Army.State.HOLDING else 0.0
			battle.holding_days = (
				battle.holding_days * float(old_size)
				+ newcomer_days * float(maxi(army.size, 0))
			) / float(new_total)
	var my_norm := _norm_pos(army, edge)
	var length := float(maxi(edge.distance, 1))
	var my_distance := my_norm * length
	var own_line := (
		battle.contact_dist_a
		if target == 1
		else battle.contact_dist_b
	)
	var enemy_line := (
		battle.contact_dist_b
		if target == 1
		else battle.contact_dist_a
	)
	var advances_front := (
		absf(my_distance - enemy_line)
		< absf(own_line - enemy_line)
	)
	_enter_battle(battle, army, target)
	if target == 1:
		if advances_front:
			battle.contact_dist_a = my_distance
		battle.reinforce_fresh_a.append(army)
	else:
		if advances_front:
			battle.contact_dist_b = my_distance
		battle.reinforce_fresh_b.append(army)
	# 增援集结：登记为本 tick 新援军，士气提振在下一次 resolve_round 统一结算（防拆分套利 item 12）。


func _enter_battle(battle: Battle, army: Army, side: int) -> void:
	if battle.kind == Battle.Kind.FIELD and army.state == Army.State.HOLDING:
		army.resume_holding_after_battle = true
	army.state = Army.State.FIGHTING
	army.encounter_blocked = false
	army.battle_id = battle.id
	if side == 1:
		if battle.side_a.is_empty():
			battle.tactical_key_a = (
				EquivariantOrder.tactical_side_key(state, army)
			)
		battle.side_a.append(army)
	else:
		if battle.side_b.is_empty():
			battle.tactical_key_b = (
				EquivariantOrder.tactical_side_key(state, army)
			)
		battle.side_b.append(army)


func _strongest_alive(arr: Array[Army]) -> Army:
	var best: Army = null
	for a in arr:
		if a.size > 0 and (best == null or a.size > best.size):
			best = a
	return best


func _siege_battle_of(city: City) -> Battle:
	for b in state.battles:
		if not b.finished and b.kind == Battle.Kind.SIEGE and b.city == city:
			return b
	return null


## 守军战败后排除正在失守的城市，撤向距离最近的其他友方城市。
func _retreat_defender(defender: Army, city: City) -> void:
	_start_morale_retreat_from_city(defender, city.id, city.id)

# ------------------------------------------------------------------ 5. 占领

func _capture_city(
	army: Army,
	city: City,
	owner_override: int = -1,
	execute_post_capture_plan: bool = true
) -> void:
	# 领土只能通过 GameState 中的权威 City 实体变更；拒绝脱离状态树的
	# 值对象，防止画面对象已变而领土真源未变。
	if (
		city == null
		or city.id < 0
		or city.id >= state.cities.size()
		or state.cities[city.id] != city
	):
		return
	var old_owner := city.owner_nation
	var claimant := _occupation_claimant_for_army(army, city)
	if owner_override >= 0:
		claimant = owner_override
	var old_owner_valid := old_owner >= 0 and old_owner < state.nations.size()
	var captured_capital := old_owner_valid and state.nations[old_owner].capital_city_id == city.id
	var civil_war_capital_capture := (
		captured_capital
		and claimant != old_owner
		and _is_civil_war_capital_capture(old_owner, claimant)
	)
	var claimant_was_rebel_vassal := (
		civil_war_capital_capture
		and state.overlord_of(claimant) == old_owner
		and state.is_in_civil_war(claimant)
	)
	var occupation_sponsor := (
		-1
		if state.recognized_owner_of(city.id) == claimant
		else army.owner_nation
	)
	# 首都身份和 revision 都冻结在攻城前快照。削藩内战的首都通吃必须把
	# 正在失守的首都与败方其余领土放进同一笔兼并事务；一旦兼并被拒绝，
	# 不得降级成普通占领或普通投降。
	var expected_ownership_revision := state.ownership_revision
	var territory_changed := false
	var captured_city_ids: Array[int] = [city.id]
	if civil_war_capital_capture:
		if not state.annex_nation(
			claimant,
			old_owner,
			expected_ownership_revision,
			{
				city.id: (
					GameState.TerritoryStockDisposition.CAPTURE_SPOILS
				),
			}
		):
			return
		_finalize_civil_war_capital_annexation(
			claimant, claimant_was_rebel_vassal
		)
		territory_changed = true
	elif captured_capital and not state.is_vassal(old_owner):
		var capital_transfers := _resolve_capital_capture_capitulation(
			old_owner, claimant, city.id
		)
		if capital_transfers.is_empty():
			return
		captured_city_ids = capital_transfers
		territory_changed = true
	else:
		var capture_result := state.transfer_city_control(
			city.id,
			claimant,
			occupation_sponsor,
			GameState.TerritoryStockDisposition.CAPTURE_SPOILS,
			"city_capture"
		)
		if not bool(capture_result.get("ok", false)):
			return
		territory_changed = bool(capture_result.get("changed", false))
	# 占领只重塑局部边境：旧主、占领者和每座易主城的相邻势力下一日
	# 提前重算。首都两跳批量转移必须逐城标脏，不能只刷新首都邻域。
	# 全局外交/宗藩重构仍使用 _ai_last_decision_day=-1。
	if territory_changed:
		for captured_city_id in captured_city_ids:
			_force_ai_replan_for_capture(
				old_owner, claimant, captured_city_id
			)
	if territory_changed and claimant != old_owner:
		city.fort_strength_max = maxi(
			city.fort_strength_max,
			city.fort_strength
		)
		city.fort_last_capture_day = state.day
		city.fort_strength = city_fort_strength_after_capture(
			city.fort_strength_max,
			0
		)
	# 城市易主后，所有不再拥有通行权且尚未离开城市节点的军队都必须撤退。
	# 覆盖 IDLE/RECOVERING、容量阻塞的 MOVING/RETREATING 以及残留 FIGHTING 状态。
	var captured_city_set := {}
	for captured_city_id in captured_city_ids:
		captured_city_set[captured_city_id] = true
	for displaced in state.armies:
		if displaced == army or displaced.size <= 0:
			continue
		var displaced_city_id := displaced.current_city_node()
		if not captured_city_set.has(displaced_city_id):
			continue
		if state.has_military_access(
			displaced.owner_nation,
			claimant
		):
			continue
		_start_morale_retreat_from_city(
			displaced,
			displaced_city_id,
			displaced_city_id
		)
	var captor_can_remain := state.has_military_access(
		army.owner_nation,
		claimant
	)
	army.occupation_claimant_nation = -1
	if captor_can_remain:
		army.state = Army.State.IDLE
		army.forced_retreat = false
		army.battle_id = -1
		army.location_city = city.id
		army.move_from = city.id
		army.move_to = -1
		army.move_progress = 0.0
		army.path.clear()
	else:
		_start_diplomatic_repatriation(
			army,
			city.id
		)
	if captured_capital and claimant != old_owner:
		# 削藩内战：占领对方首都即通吃。宗主占藩王首都→吞并藩王全境；
		# 藩王占宗主首都→藩王继承宗主全部领土与其余藩王（继承宗藩体系）。
		if civil_war_capital_capture:
			pass
		# 普通主权国的两跳领土转移与投降已在上面的原子占领分支完成。
		# 和平藩王不整国投降；原子领土事务已同步处理迁都、共享粮仓
		# 与派生状态。若已经失去最后一城，日末再清理其宗藩记录。
	if execute_post_capture_plan and captor_can_remain:
		_execute_campaign_post_capture_plan(army, city)


func _execute_campaign_post_capture_plan(
	army: Army,
	city: City
) -> void:
	if (
		army.owner_nation < 0
		or army.owner_nation >= state.nations.size()
		or city == null
	):
		return
	var nation := state.nations[army.owner_nation]
	if not nation.campaign_post_capture_plans.has(city.id):
		return
	var plan: Dictionary = (
		nation.campaign_post_capture_plans[city.id]
	)
	nation.campaign_post_capture_plans.erase(city.id)
	_remove_campaign_target(army.owner_nation, city.id)
	var next_city := int(plan.get("next_city", -1))
	var route_valid := (
		next_city >= 0
		and next_city < state.cities.size()
		and _ruler_allows_campaign_target(
			army.owner_nation, next_city
		)
		and state.is_enemy(
			army.owner_nation,
			state.cities[next_city].owner_nation
		)
	)
	var route_edge := (
		state.edge_of(city.id, next_city)
		if route_valid
		else null
	)
	route_valid = (
		route_valid
		and route_edge != null
		and route_edge.max_manpower >= army.road_footprint()
	)
	var heavy_army_id := int(
		plan.get("heavy_army_id", -1)
	)
	var execution_army_id := int(
		plan.get("execution_army_id", army.id)
	)
	var execution_army: Army = null
	var heavy_operational := heavy_army_id < 0
	for member in state.armies:
		if member.id == execution_army_id:
			execution_army = member
		if member.id == heavy_army_id:
			heavy_operational = (
				member.size > 0
				and member.morale > Combat.MORALE_FLOOR
			)
	if execution_army == null and execution_army_id == army.id:
		execution_army = army
	var execution_ready := (
		execution_army != null
		and execution_army.size > 0
		and execution_army.morale > Combat.MORALE_FLOOR
		and execution_army.is_at_city_node(city.id)
	)
	if route_valid and execution_army != null:
		route_valid = (
			route_edge.max_manpower
				>= execution_army.road_footprint()
		)
	if (
		route_valid
		and heavy_operational
		and execution_ready
	):
		var attack := ActionCandidate.make(
			ActionCandidate.Kind.ATTACK,
			2500.0,
			(
				"两步攻势第二步：城市%d已占领，"
				+ "按预定路线继续攻击城市%d"
			) % [
				city.id,
				next_city,
			],
			next_city
		)
		attack.minimum_commit_days = (
			CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		)
		var remaining_bonus_days := maxi(
			execution_army.offensive_bonus_until_day
				- state.day,
			0
		)
		if remaining_bonus_days > 0:
			attack.offensive_attack_multiplier = (
				execution_army.offensive_attack_multiplier
			)
			attack.offensive_bonus_days = remaining_bonus_days
		if _execute_ai_candidate(execution_army, attack):
			nation.campaign_attack_assignments[
				execution_army.id
			] = next_city
			nation.campaign_launched_armies[
				execution_army.id
			] = true
			if (
				not nation.campaign_plan_targets.has(next_city)
				and nation.campaign_plan_targets.size()
					< CAMPAIGN_MAX_PARALLEL_TARGETS
			):
				nation.campaign_plan_targets.append(next_city)
			state.add_campaign_visual_event(
				execution_army.owner_nation,
				next_city,
				[city.id] as Array[int],
				nation.campaign_offensive_count,
				CAMPAIGN_ARROW_DURATION_DAYS
			)
			return
	var stop_reason := (
		"执行重军士气归零"
		if not heavy_operational
		else (
			"执行军士气归零"
			if not execution_ready
			else "预定第二步目标或道路失效"
		)
	)
	var garrison := ActionCandidate.make(
		ActionCandidate.Kind.HOLD,
		2000.0,
		(
			"两步攻势终止：城市%d占领后%s，主力就地驻扎"
		) % [city.id, stop_reason],
		city.id
	)
	garrison.minimum_commit_days = DEFENSIVE_DEPLOYMENT_LOCK_DAYS
	garrison.defensive_deployment = true
	_record_ai_order(army, garrison)


func _campaign_post_capture_target(
	army: Army,
	city: City,
	threat: ThreatField,
	target_nation: int = -1
) -> Dictionary:
	var best: Dictionary = {}
	var neighbors := state.neighbors(city.id).duplicate()
	EquivariantOrder.sort_city_ids(
		neighbors,
		state,
		army.owner_nation,
		city.id
	)
	for target_id in neighbors:
		var edge := state.edge_of(city.id, target_id)
		if (
			edge == null
			or edge.max_manpower < army.road_footprint()
			or not state.is_enemy(
				army.owner_nation,
				state.cities[target_id].owner_nation
			)
			or (
				target_nation >= 0
				and state.cities[target_id].owner_nation
					!= target_nation
			)
		):
			continue
		var target := state.cities[target_id]
		var defense_power := (
			threat.threat_at(target_id)
			+ ArmyPower.city_defense(target)
		)
		var attack_ratio := (
			ArmyPower.effective(army)
			/ maxf(defense_power, 1.0)
		)
		var strategic_value := (
			float(target.gold_per_month) * 0.10
			+ float(target.food_per_half_year) * 0.002
			+ float(target.manpower_per_month) * 0.10
			+ (5.0 if target.is_capital else 0.0)
			+ (3.0 if target.has_warehouse else 0.0)
			+ (2.0 if target.is_food_hub else 0.0)
			+ (2.0 if target.is_manpower_hub else 0.0)
		)
		var score := attack_ratio * 4.0 + strategic_value
		if (
			best.is_empty()
			or score > float(best["score"])
			or (
				is_equal_approx(score, float(best["score"]))
				and EquivariantOrder.city_id_less(
					state,
					army.owner_nation,
					target_id,
					int(best["city_id"]),
					city.id
				)
			)
		):
			best = {
				"city_id": target_id,
				"attack_ratio": attack_ratio,
				"defense_power": defense_power,
				"score": score,
			}
	return best


func _occupation_claimant_for_army(
	army: Army,
	target_city: City = null
) -> int:
	# 此函数只在真正破城后决定控制权接收者，与围城阶段的 CITY_DEFENDER/
	# CHALLENGER 角色正交：战斗阵营按当前控制与军事通行权，控制权则优先归还
	# 仍存活且与攻方结盟的法理所有者。
	if target_city != null:
		var recognized_owner := state.recognized_owner_of(
			target_city.id
		)
		if (
			recognized_owner >= 0
			and recognized_owner < state.nations.size()
			and not state.land_cities_of(recognized_owner).is_empty()
			and state.is_enemy(
				recognized_owner,
				target_city.owner_nation
			)
			and (
				recognized_owner == army.owner_nation
				or state.is_allied(
					army.owner_nation,
					recognized_owner
				)
			)
		):
			return recognized_owner
	if (
		army.occupation_claimant_nation >= 0
		and army.occupation_claimant_nation
			< state.nations.size()
		and state.nations[army.occupation_claimant_nation].alive
	):
		return army.occupation_claimant_nation
	var origin_city := army.move_from
	if origin_city < 0 or origin_city >= state.cities.size():
		origin_city = army.location_city
	if origin_city >= 0 and origin_city < state.cities.size():
		var origin_owner := state.cities[origin_city].owner_nation
		if (
			origin_owner == army.owner_nation
			or state.is_allied(
				army.owner_nation,
				origin_owner
			)
		):
			return origin_owner
	return army.owner_nation

# ------------------------------------------------------------------ 6. 战争状态刷新

func _refresh_war_flags() -> void:
	# 边 occupied 由 passing_count 决定
	for e in state.edges:
		e.occupied = e.passing_count > 0
	# 城 at_war：与任一相邻敌国城市接壤。
	for city in state.cities:
		var war := false
		for nb in state.neighbors(city.id):
			if state.is_enemy(
				city.owner_nation,
				state.cities[nb].owner_nation
			):
				war = true
				break
		city.at_war = war

# ------------------------------------------------------------------ 7. 胜负

func _check_victory() -> void:
	var has_land_city := PackedByteArray()
	has_land_city.resize(state.nations.size())
	has_land_city.fill(0)
	for city in state.cities:
		if (
			not city.is_dock
			and city.owner_nation >= 0
			and city.owner_nation < has_land_city.size()
		):
			has_land_city[city.owner_nation] = 1
	var alive_nations: Array[int] = []
	for n in state.nations:
		var has_city := has_land_city[n.id] != 0
		n.alive = has_city
		if has_city:
			alive_nations.append(n.id)
	if alive_nations.size() == 1:
		state.winner = alive_nations[0]
	elif alive_nations.size() > 1:
		state.winner = -1

# ================================================================== 工具

func _settle_idle(army: Army, city_id: int) -> void:
	if (
		city_id >= 0
		and city_id < state.cities.size()
		and not state.has_military_access(
			army.owner_nation,
			state.cities[city_id].owner_nation
		)
	):
		_start_morale_retreat_from_city(
			army,
			city_id,
			city_id
		)
		return
	_release_edge(army)   # 无条件释放：仅当 on_edge 为真才实际减计数
	army.state = Army.State.IDLE
	army.forced_retreat = false
	army.diplomatic_repatriation = false
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.battle_id = -1
	army.location_city = city_id
	army.move_from = city_id
	army.move_to = -1
	army.move_progress = 0.0
	army.path.clear()


## 士气崩溃撤退：从真实交战位置避开围城，优先向本国首都纵深撤离。
func _retreat(army: Army) -> void:
	army.battle_id = -1
	army.state = Army.State.RETREATING
	army.forced_retreat = true
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.path.clear()
	if army.on_edge and army.move_to != -1:
		var route := (
			Pathfinding.nearest_home_route_from_edge_for_repatriation(
				state,
				army
			)
			if army.diplomatic_repatriation
			else Pathfinding.strategic_retreat_route_from_edge(
				state,
				army
			)
		)
		if route.is_empty():
			_release_edge(army)
			army.size = 0
			return
		var endpoint: int = route["endpoint"]
		var old_from := army.move_from
		var old_to := army.move_to
		var old_progress := clampf(army.move_progress, 0.0, 1.0)
		if endpoint == old_from:
			# 原地掉头：交换边方向并反转 progress，像素位置保持不变。
			_untrack_movement_capacity(army)
			army.move_from = old_to
			army.move_to = old_from
			army.move_progress = 1.0 - old_progress
			_track_movement_capacity(army)
		else:
			army.move_from = old_from
			army.move_to = old_to
			army.move_progress = old_progress
		army.location_city = endpoint
		army.path = route["path"]
		return
	var current_city := army.move_to if army.move_to != -1 else army.move_from
	if current_city == -1:
		current_city = army.location_city
	_start_morale_retreat_from_city(army, current_city)


## 每日兜底清理：驱离「已定居（非在途、非交战）在无军事通行权敌城节点」的己方军队。
## 覆盖占领驱逐漏网（如占领瞬间军队在途、抵达后城已易主）与填线锚点易主后滞留等所有入口，
## 使这类军队立即向首都纵深撤离，杜绝 LINE 军在敌城 IDLE 永久卡死。
## 只处理静止态（IDLE/RECOVERING/HOLDING 且不在边上、不在战斗），不打断行军/撤退/战斗。
func _evict_stranded_hostile_armies() -> void:
	for army in state.armies:
		if army.size <= 0 or army.on_edge or army.battle_id >= 0:
			continue
		if army.state not in [
			Army.State.IDLE,
			Army.State.RECOVERING,
			Army.State.HOLDING,
		]:
			continue
		var node := army.current_city_node()
		if node < 0 or node >= state.cities.size():
			continue
		if state.has_military_access(
			army.owner_nation,
			state.cities[node].owner_nation
		):
			continue
		_start_morale_retreat_from_city(army, node, node)


## 从城市节点开始撤退。excluded_city_id 常用于排除正在失守/被围的当前城。
func _start_morale_retreat_from_city(
	army: Army,
	current_city: int,
	excluded_city_id: int = -1
) -> void:
	_release_edge(army)
	army.battle_id = -1
	army.state = Army.State.RETREATING
	army.forced_retreat = true
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.location_city = current_city
	army.move_from = current_city
	army.move_to = -1
	army.move_progress = 0.0
	army.path.clear()
	if current_city < 0 or current_city >= state.cities.size():
		army.size = 0
		return
	if (
		not army.diplomatic_repatriation
		and _annihilate_encircled_zero_morale_army(
		army,
		current_city
		)
	):
		return
	if (
		current_city != excluded_city_id
		and state.has_military_access(
			army.owner_nation,
			state.cities[current_city].owner_nation
		)
		and not state.city_under_siege(current_city)
	):
		_start_recovering(army, current_city)
		return
	var path := (
		Pathfinding.nearest_home_city_for_repatriation(
			state,
			army,
			excluded_city_id
		)
		if army.diplomatic_repatriation
		else Pathfinding.strategic_retreat_city(
			state,
			army,
			excluded_city_id
		)
	)
	if path.is_empty():
		army.size = 0   # 已无可达友城：溃散
		return
	army.path = path
	_begin_next_leg(army)


func _start_recovering(army: Army, city_id: int) -> void:
	if (
		city_id >= 0
		and city_id < state.cities.size()
		and (
			not state.has_military_access(
				army.owner_nation,
				state.cities[city_id].owner_nation
			)
			or state.city_under_siege(city_id)
		)
	):
		_start_morale_retreat_from_city(
			army,
			city_id,
			city_id
		)
		return
	_release_edge(army)
	army.state = Army.State.RECOVERING
	army.forced_retreat = true
	army.diplomatic_repatriation = false
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.battle_id = -1
	army.location_city = city_id
	army.move_from = city_id
	army.move_to = -1
	army.move_progress = 0.0
	army.path.clear()


func _annihilate_encircled_zero_morale_army(
	army: Army,
	city_id: int
) -> bool:
	if (
		army == null
		or army.size <= 0
		or army.morale > Combat.MORALE_FLOOR
		or Pathfinding.has_friendly_retreat_route_from_city(
			state,
			army.owner_nation,
			city_id,
			army.max_size
		)
	):
		return false
	_release_edge(army)
	army.battle_id = -1
	army.path.clear()
	army.size = 0
	return true


func _start_holding(army: Army) -> void:
	if not army.on_edge or army.move_to == -1:
		return
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge == null or not edge.allows_holding:
		army.state = Army.State.MOVING
		army.hold_target_progress = -1.0
		army.holding_days = 0
		army.resume_holding_after_battle = false
		return
	army.state = Army.State.HOLDING
	army.forced_retreat = false
	army.diplomatic_repatriation = false
	army.hold_target_progress = -1.0
	army.holding_days = 0
	army.path.clear()


func _leave_holding(army: Army) -> void:
	if army.state != Army.State.HOLDING:
		return
	army.state = Army.State.MOVING
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false


## 从无法加入的围城节点向首都纵深强制撤离。army 已抵达目标城且当前边已释放；
## RETREATING 保证它不受 AI 改写，并可立即离开敌城而不受友方方向容量阻塞。
func _retreat_to_friendly(army: Army) -> void:
	var arrived := army.move_to
	army.battle_id = -1
	army.move_from = arrived if arrived != -1 else army.move_from
	army.move_to = -1
	army.move_progress = 0.0
	army.state = Army.State.RETREATING
	army.forced_retreat = true
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.location_city = army.move_from
	var path := (
		Pathfinding.nearest_home_city_for_repatriation(
			state,
			army
		)
		if army.diplomatic_repatriation
		else Pathfinding.strategic_retreat_city(
			state,
			army
		)
	)
	if path.is_empty():
		# 无合法本国通道时不能滞留敌城或穿越敌城，按无路可退处理为溃散。
		army.size = 0
		return
	army.path = path
	_begin_next_leg(army)


func _start_diplomatic_repatriation(
	army: Army,
	current_city: int = -1
) -> void:
	army.diplomatic_repatriation = true
	if army.on_edge and army.move_to != -1:
		_retreat(army)
		return
	if current_city < 0:
		current_city = army.current_city_node()
	_start_morale_retreat_from_city(
		army,
		current_city,
		current_city
	)


## 释放该军占用的边通行槽。以 army.on_edge 为唯一判据，幂等（重复调用安全）。
func _release_edge(army: Army) -> void:
	army.encounter_blocked = false
	if not army.on_edge:
		return
	_untrack_movement_capacity(army)
	army.on_edge = false
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge != null and edge.passing_count > 0:
		edge.passing_count -= 1
		edge.occupied = edge.passing_count > 0


func _edge_key_of(a: int, b: int) -> int:
	return GameState.edge_key(a, b)


## 移除 size<=0 的军队，并释放它们占用的边。
func _purge_dead_armies() -> void:
	var survivors: Array[Army] = []
	for army in state.armies:
		if army.size > 0:
			survivors.append(army)
		else:
			_release_edge(army)   # 幂等释放
	state.armies = survivors
