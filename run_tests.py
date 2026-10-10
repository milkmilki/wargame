#!/usr/bin/env python3
"""Native Atlas and shared simulation regressions, one isolated process per test."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent
CORE = [
    "project_compile", "test_suite", "movement_capacity_index_equivalence",
    "war_count_and_conqueror", "zhou_defection", "field_manpower_requirements",
    "campaign_reinforcement_ownership", "chronicle_smoke", "political_history_test",
    "regional_strategy", "regional_access_recovery", "family_tree_smoke",
    "royal_title_origin", "royal_title_generations", "royal_title_lifecycle",
    "succession_counterattack", "diplomatic_battle_lifecycle",
    "encirclement_index_equivalence", "diplomacy_objective_batch_cache",
    "strategic_betweenness_preference", "war_diplomacy_runtime_equivalence",
]
ATLAS = [
    "atlas_static_layers",
    "atlas_runtime_costs",
    "atlas_runtime_equivalence",
    "atlas_time_controls", "atlas_map_selection", "atlas_diplomacy_view", "atlas_nation_list",
    "atlas_startup_cache", "atlas_startup_climate", "atlas_startup_order",
    "atlas_information_model", "atlas_information_panel",
    "atlas_render_scheduler", "atlas_render_index", "atlas_persistent_strokes", "atlas_shared_stroke_cache",
    "atlas_symbol_mesh", "atlas_symbol_tiles", "atlas_incremental_text", "atlas_wrapped_text", "atlas_city_markers",
    "atlas_entry_contract", "atlas_preview_lifecycle", "atlas_render_invalidation", "atlas_view_caches", "atlas_camera_feedback", "atlas_war_fronts", "atlas_military_contract", "atlas_hierarchy_cases",
    "atlas_traffic_graph", "atlas_zhoufu_roads", "atlas_road_smoothing",
    "atlas_segmented_movement", "atlas_junction_encounters",
    "atlas_access_and_repatriation", "atlas_territory_transactions",
    "atlas_path_cache_lifecycle", "atlas_template_invalid",
    "atlas_military_persistence", "atlas_visual_land_audit", "atlas_military_smoke",
]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4"))
    parser.add_argument("--group", choices=["core", "atlas", "all"], default="all")
    parser.add_argument("--days", type=int, default=35, help="Atlas military smoke days; use 365 for the full run")
    parser.add_argument("--timeout", type=int, default=300, help="Per-process timeout in seconds")
    parser.add_argument("--tests", nargs="+", help="Explicit test names override group")
    args = parser.parse_args()
    if not args.godot: parser.error("Set GODOT or pass --godot /path/to/godot")
    logs = ROOT / ".dbg" / "regression"
    logs.mkdir(parents=True, exist_ok=True)
    tests = args.tests or (CORE if args.group == "core" else ATLAS if args.group == "atlas" else CORE + ATLAS)
    results = []
    for test in tests:
        if not re.fullmatch(r"[a-z0-9_]+", test): parser.error("Invalid test name: " + test)
        command = [args.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/" + test + ".gd"]
        if test == "atlas_military_smoke": command += ["--", "--atlas-smoke-days=" + str(args.days)]
        started = time.monotonic()
        log = logs / (test + ".log")
        try:
            with log.open("w", encoding="utf-8") as output:
                process = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout)
            code = process.returncode
        except subprocess.TimeoutExpired:
            code = 124
        text = log.read_text(encoding="utf-8", errors="replace")
        ok = code == 0 and not re.search(r"SCRIPT ERROR|Parse Error|^ERROR:", text, re.MULTILINE)
        row = {"test": test, "ok": ok, "exit_code": code, "elapsed_ms": round((time.monotonic()-started)*1000), "log": str(log)}
        results.append(row)
        print(("PASS " if ok else "FAIL ") + test + " (" + str(row["elapsed_ms"]) + " ms)", flush=True)
        if not ok: print(text[-4000:], flush=True)
    report = {"godot": args.godot, "days": args.days, "results": results, "failures": sum(not row["ok"] for row in results)}
    report_name = "summary-selected.json" if args.tests else "summary-" + args.group + ".json"
    (logs / report_name).write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("Tests:", len(results), "failures:", report["failures"], flush=True)
    return 1 if report["failures"] else 0

if __name__ == "__main__":
    raise SystemExit(main())
