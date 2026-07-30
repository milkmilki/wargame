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

echo "==> [1/2] 编译检查（headless 导入，捕获脚本错误）"
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

echo "==> [2/2] 逻辑测试套件"
HOME="$GODOT_HOME" "$GODOT" --headless --path "$PROJECT_DIR" \
  --script res://tests/test_suite.gd \
  --log-file "$LOG_DIR/world-war-tests.log"
