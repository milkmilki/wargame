#!/usr/bin/env bash
# WorldWar 回归测试：headless 编译 + 逻辑测试套件。
# 退出码 0=全通过，非 0=有失败。可接入 CI。
set -euo pipefail

GODOT="${GODOT:-/Users/bytedance/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${TMPDIR:-/tmp}"
GODOT_HOME="$LOG_DIR/world-war-godot-home"
mkdir -p "$GODOT_HOME"

if [[ ! -x "$GODOT" ]]; then
  echo "错误：未找到 Godot 可执行文件：$GODOT" >&2
  echo "可通过环境变量覆盖：GODOT=/path/to/godot ./run_tests.sh" >&2
  exit 2
fi

echo "==> Godot: $($GODOT --version)"
echo "==> 项目: $PROJECT_DIR"
echo

echo "==> [1/29] 编译检查（headless 导入，捕获脚本错误）"
# 导入阶段任何 SCRIPT ERROR 都会打印；grep 到即判失败。
IMPORT_LOG="$(HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" --editor --quit \
  --log-file "$LOG_DIR/world-war-import.log" 2>&1)"
if echo "$IMPORT_LOG" | grep -qiE "SCRIPT ERROR|Parse Error|ERROR: .*\.gd"; then
  echo "$IMPORT_LOG"
  echo "编译检查失败：发现脚本错误" >&2
  exit 1
fi
echo "    编译通过（class_name 全部注册，无脚本错误）"
echo

echo "==> [2/29] 逻辑测试套件"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/test_suite.gd \
  --log-file "$LOG_DIR/world-war-tests.log"
echo

echo "==> [2a/29] 行政州域划分门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/administrative_region_analysis.gd \
  --log-file "$LOG_DIR/world-war-administrative-region.log"
echo

echo "==> [2b/29] 行政产出门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/administrative_economy.gd \
  --log-file "$LOG_DIR/world-war-administrative-economy.log"
echo

echo "==> [2c/29] 州治守军效率门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/administrative_combat.gd \
  --log-file "$LOG_DIR/world-war-administrative-combat.log"
echo

echo "==> [2d/29] 整州和平结算门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/administrative_peace_settlement.gd \
  --log-file "$LOG_DIR/world-war-administrative-peace.log"
echo

echo "==> [2d1/29] 和平飞地转移门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/peace_enclave.gd \
  --log-file "$LOG_DIR/world-war-peace-enclave.log"
echo

echo "==> [2e/29] 行政州战争目标门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/administrative_ai_objective.gd \
  --log-file "$LOG_DIR/world-war-administrative-ai.log"
echo
echo "==> [2e1/29] 外交目标批次缓存门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/diplomacy_objective_batch_cache.gd \
  --log-file "$LOG_DIR/world-war-diplomacy-objective-cache.log"
echo

echo "==> [2f/29] 飞地仅按本国领土连通门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/enclave_own_territory.gd \
  --log-file "$LOG_DIR/world-war-enclave-own-territory.log"
echo

echo "==> [2g/29] 初始国家至少拥有一州门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/initial_nation_administrative_center.gd \
  --log-file "$LOG_DIR/world-war-initial-nation-admin-center.log"
echo
echo "==> [2h/29] 州治持久守军与战役需求门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/garrison_system.gd \
  --log-file "$LOG_DIR/world-war-garrison-system.log"
echo
echo "==> [2i/29] 州级战役状态机门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/garrison_campaign_ai.gd \
  --log-file "$LOG_DIR/world-war-garrison-campaign-ai.log"
echo
echo "==> [2i1/29] 敌方末州首都进攻门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/last_city_offensive_stall.gd \
  --log-file "$LOG_DIR/world-war-last-capital-offensive.log"
echo
echo "==> [2j/29] 州治守军战损比门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/garrison_combat_ratio.gd \
  --log-file "$LOG_DIR/world-war-garrison-combat-ratio.log"
echo

echo "==> [2k/29] 州级藩王、野战姿态与慢速补员门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/state_war_posture.gd \
  --log-file "$LOG_DIR/world-war-state-war-posture.log"
echo
echo "==> [3/29] 主战军/填线军兵棋角色 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/army_role_counter_smoke.gd \
  --log-file "$LOG_DIR/world-war-army-role-counter.log"
echo

echo "==> [4/29] 500 城双倍物理跨度场景 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/five_hundred_city_scene_smoke.gd \
  --log-file "$LOG_DIR/world-war-five-hundred-city-scene.log"
echo

echo "==> [5/29] 贸易结构缓存等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/trade_structure_cache_equivalence.gd \
  --log-file "$LOG_DIR/world-war-trade-structure-cache-equivalence.log"
echo

echo "==> [10/29] 贸易预测缓存等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/trade_forecast_cache_equivalence.gd \
  --log-file "$LOG_DIR/world-war-trade-forecast-cache-equivalence.log"
echo

echo "==> [11/29] 外交接壤矩阵等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/frontier_matrix_equivalence.gd \
  --log-file "$LOG_DIR/world-war-frontier-matrix-equivalence.log"
echo

echo "==> [12/29] 外交结构缓存等价门禁"
DIPLOMACY_CACHE_EQUIV_DAYS=90 \
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/diplomacy_structure_cache_equivalence.gd \
  --log-file "$LOG_DIR/world-war-diplomacy-structure-cache-equivalence.log"
echo

echo "==> [13/29] AI 决策上下文等价门禁"
AI_CONTEXT_EQUIV_DAYS=90 AI_CONTEXT_EQUIV_NATIONS=20 AI_CONTEXT_EQUIV_CITIES=80 \
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/ai_decision_context_equivalence.gd \
  --log-file "$LOG_DIR/world-war-ai-decision-context-equivalence.log"
echo

echo "==> [14/29] 行军容量索引等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/movement_capacity_index_equivalence.gd \
  --log-file "$LOG_DIR/world-war-movement-capacity-index-equivalence.log"
echo

echo "==> [15/29] 包围索引等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/encirclement_index_equivalence.gd \
  --log-file "$LOG_DIR/world-war-encirclement-index-equivalence.log"
echo

echo "==> [16/29] 忠诚行政半径门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/loyalty_admin_radius.gd \
  --log-file "$LOG_DIR/world-war-loyalty-admin-radius.log"
echo

echo "==> [17/29] 国家食物快照门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/nation_food_snapshot.gd \
  --log-file "$LOG_DIR/world-war-nation-food-snapshot.log"
echo

echo "==> [18/29] 外交防御方索引等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/diplomacy_defender_index_equivalence.gd \
  --log-file "$LOG_DIR/world-war-diplomacy-defender-index-equivalence.log"
echo

echo "==> [19/29] 国家详情单次建造门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/nation_detail_single_build.gd \
  --log-file "$LOG_DIR/world-war-nation-detail-single-build.log"
echo

echo "==> [20/29] 前线容量分配器门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/frontline_capacity_allocator.gd \
  --log-file "$LOG_DIR/world-war-frontline-capacity-allocator.log"
echo

echo "==> [21/29] 同日占领刷新门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/frontline_capture_refresh.gd \
  --log-file "$LOG_DIR/world-war-frontline-capture-refresh.log"
echo

echo "==> [22/29] 政治、命名与贸易 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/politics_trade_smoke.gd \
  --log-file "$LOG_DIR/world-war-politics-trade.log"
echo

echo "==> [22a/29] 年度人钱粮自动平衡门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/automatic_resource_balance.gd \
  --log-file "$LOG_DIR/world-war-automatic-resource-balance.log"
echo

echo "==> [22b/29] 君主继位与夸张特质门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/ruler_succession_extremes.gd \
  --log-file "$LOG_DIR/world-war-ruler-succession-extremes.log"
echo

echo "==> [22c/29] 完整州藩王常规军事 AI 门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/vassal_regular_military_ai.gd \
  --log-file "$LOG_DIR/world-war-vassal-regular-military-ai.log"
echo

echo "==> [23/29] 高程图打包与海岸无插值门禁"
python3 "$PROJECT_DIR/tests/low_poly_map_source_tool.py" 2>&1 \
  | tee "$LOG_DIR/world-war-low-poly-map-source.log"
echo

echo "==> [24/29] 地图编辑器运行时与 MapDefinition 往返 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/map_editor_runtime.gd \
  --log-file "$LOG_DIR/world-war-map-editor-runtime.log"
echo

echo "==> [24a/29] 省份陆地连通性门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/province_land_connectivity.gd \
  --log-file "$LOG_DIR/world-war-province-land-connectivity.log"
echo

echo "==> [24b/29] 独立政治蒙版与 30 天推演门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/political_generation_mask.gd \
  --log-file "$LOG_DIR/world-war-political-generation-mask.log"
echo

echo "==> [24c/29] Province ID 与政治视觉 LUT 像素等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/province_visual_lookup_test.gd \
  --log-file "$LOG_DIR/world-war-province-visual-lookup.log"
echo

echo "==> [25/29] 3D 低模平滑着色与双灯光门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/terrain_3d_smoke.gd \
  --log-file "$LOG_DIR/world-war-terrain-3d.log"
echo

echo "==> [26/29] 默认前端场景 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/frontend_scene_smoke.gd \
  --log-file "$LOG_DIR/world-war-frontend-scene.log"
echo

echo "==> [27/29] 道路调节与地图模式 UI smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/road_tuning_ui_smoke.gd \
  --log-file "$LOG_DIR/world-war-road-tuning-ui.log"
echo

echo "==> [28/29] 前端 3D 视觉构件 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/frontend_visual_smoke.gd \
  --log-file "$LOG_DIR/world-war-frontend-visual.log"
echo

echo "==> [29/29] 100%政治图海岸白点门禁"
HOME="$GODOT_HOME" "$GODOT" --path "$PROJECT_DIR" \
  --script res://tests/coast_fringe_visual.gd \
  --log-file "$LOG_DIR/world-war-coast-fringe.log"
