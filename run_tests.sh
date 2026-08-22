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

echo "==> [1/10] 编译检查（headless 导入，捕获脚本错误）"
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

echo "==> [2/10] 逻辑测试套件"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/test_suite.gd \
  --log-file "$LOG_DIR/world-war-tests.log"
echo

echo "==> [3/10] 政治、命名与贸易 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/politics_trade_smoke.gd \
  --log-file "$LOG_DIR/world-war-politics-trade.log"
echo

echo "==> [4/10] 高程图打包与海岸无插值门禁"
python3 "$PROJECT_DIR/tests/low_poly_map_source_tool.py" 2>&1 \
  | tee "$LOG_DIR/world-war-low-poly-map-source.log"
echo

echo "==> [5/10] 地图编辑器运行时与 MapDefinition 往返 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/map_editor_runtime.gd \
  --log-file "$LOG_DIR/world-war-map-editor-runtime.log"
echo

echo "==> [6/10] 3D 低模平滑着色与双灯光门禁"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/terrain_3d_smoke.gd \
  --log-file "$LOG_DIR/world-war-terrain-3d.log"
echo

echo "==> [7/10] 默认前端场景 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/frontend_scene_smoke.gd \
  --log-file "$LOG_DIR/world-war-frontend-scene.log"
echo

echo "==> [8/10] 道路调节与地图模式 UI smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/road_tuning_ui_smoke.gd \
  --log-file "$LOG_DIR/world-war-road-tuning-ui.log"
echo

echo "==> [9/10] 前端 3D 视觉构件 smoke"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/frontend_visual_smoke.gd \
  --log-file "$LOG_DIR/world-war-frontend-visual.log"
echo

echo "==> [10/10] 100%政治图海岸白点门禁"
HOME="$GODOT_HOME" "$GODOT" --path "$PROJECT_DIR" \
  --script res://tests/coast_fringe_visual.gd \
  --log-file "$LOG_DIR/world-war-coast-fringe.log"
