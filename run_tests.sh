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

echo "==> [6/29] 贸易联通预筛等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/trade_connectivity_prefilter_equivalence.gd \
  --log-file "$LOG_DIR/world-war-trade-connectivity-prefilter-equivalence.log"
echo

echo "==> [7/29] 贸易联通 gate-context 等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/trade_connectivity_gate_context_equivalence.gd \
  --log-file "$LOG_DIR/world-war-trade-connectivity-gate-context-equivalence.log"
echo

echo "==> [8/29] 国内共享 field 等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/trade_domestic_shared_field_equivalence.gd \
  --log-file "$LOG_DIR/world-war-trade-domestic-shared-field-equivalence.log"
echo

echo "==> [9/29] 国内 ideal field cache 等价门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/trade_domestic_ideal_field_cache_equivalence.gd \
  --log-file "$LOG_DIR/world-war-trade-domestic-ideal-field-cache-equivalence.log"
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
