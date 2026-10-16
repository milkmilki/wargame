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
	"regional_rebellion_realm",
	"royal_landed_titles", "royal_foreign_recall", "atlas_family_genealogy",
	"royal_birth_eligibility",
	"environment_nations", "nomad_names", "empire_recognition", "empire_security",
	"vassal_centralization", "vassal_faction_conflict", "enfeoff_shared_lineage",
	"administrative_state_integrity", "regional_rebel_capital_capture", "campaign_forward_camp_access", "campaign_neutral_route", "vassal_occupation_routes",
    "state_campaign_lifecycle", "coalition_campaign_pairs", "coalition_campaign_frame_slice_equivalence",
    "native_city_partitions",
    "campaign_frozen_reinforcement",
    "native_logistics_access",
    "administrative_member_index",
    "native_extension_contract", "native_graph_equivalence", "native_edge_inputs", "native_administrative_fields", "native_key_order", "native_trade_city_inputs", "native_frozen_batch", "native_world_lifecycle", "native_runtime_equivalence",
    "game_calendar", "project_compile", "test_suite", "field_establishment_costs", "trade_fingerprint_reuse", "capital_tax_batch", "resource_capacity_batch", "ruler_modifier_table", "threat_field_lazy", "forecast_token_packing", "supply_field_lazy_order", "reinforcement_fiscal_cache", "forecast_selected_rows", "trade_packed_fingerprint", "campaign_enemy_memo", "atlas_capital_hops", "movement_capacity_index_equivalence", "battle_group_index_equivalence",
    "army_precontact_hold", "war_count_and_conqueror", "zhou_defection", "field_manpower_requirements", "supply_combat_attributes", "field_battle_supply", "city_field_defender_supply", "morale_rout_only", "field_shared_morale", "military_funding", "battle_opening_dice",
    "campaign_simple_retreat", "campaign_single_wave", "campaign_defense_regroup", "campaign_defense_response", "campaign_defense_center_activity", "campaign_mobilization_costs",
    "campaign_action_readiness", "campaign_staging_legality", "coalition_dispatch_lifecycle", "coalition_siege_participation",
    "campaign_reinforcement_ownership", "chronicle_smoke", "political_history_test", "political_history_rulers",
    "regional_strategy", "regional_access_recovery", "family_tree_smoke",
    "royal_title_origin", "royal_title_generations", "royal_title_lifecycle",
    "succession_virtual", "succession_virtual_lifecycle", "succession_preparation", "succession_conflict", "succession_chain", "succession_lifecycle", "atlas_family_model", "atlas_family_runtime", "atlas_family_interaction", "atlas_family_person_types", "atlas_family_close_input", "ruler_succession_extremes", "succession_counterattack", "diplomatic_battle_lifecycle",
    "encirclement_index_equivalence", "diplomacy_objective_batch_cache",
    "strategic_betweenness_preference", "strategic_target_cache", "strategic_edge_queries", "war_diplomacy_runtime_equivalence",
    "ultimatum_forecast_cache_equivalence",
]
ATLAS = [
	"environment_nations_atlas", "atlas_shipping", "atlas_shipping_world", "trade_corridors", "atlas_trade_declutter", "atlas_trade_corridor_world", "atlas_geographic_names", "atlas_formal_nation_labels",
    "atlas_diplomacy_wakes",
    "atlas_alliance_cache", "atlas_alliance_runtime",
    "atlas_coalition_components", "atlas_coalition_runtime",
    "atlas_trade_allocations",
    "atlas_forecast_dependencies",
    "atlas_supply_batch_cache", "atlas_supply_shared_fields", "atlas_supply_runtime",
    "atlas_trade_schedule",
    "atlas_trade_runtime",
    "atlas_space_routing",
    "atlas_trade_view",
    "atlas_politics_trade",
    "atlas_prewar_batch",
    "atlas_settlement_mask", "atlas_settlement_mask_controls", "atlas_settlement_mask_pipeline", "atlas_masked_military_smoke",
    "atlas_daily_reserves", "atlas_reserve_stations", "atlas_event_slicing", "atlas_path_order_equivalence", "atlas_contact_index", "atlas_supply_sources", "atlas_traffic_supply", "atlas_attack_supply", "atlas_supply_dependencies", "atlas_ai_cadence",
    "atlas_static_layers", "atlas_static_symbol_baking",
    "atlas_runtime_costs", "atlas_battle_strength", "atlas_battle_information", "atlas_battle_information_interaction", "atlas_battle_comparison",
    "atlas_runtime_equivalence",
    "atlas_time_controls", "atlas_history_timeline", "atlas_map_drag", "atlas_map_selection", "atlas_diplomacy_view", "atlas_nation_list",
    "atlas_startup_cache", "atlas_startup_climate", "atlas_startup_order",
    "atlas_information_model", "atlas_world_naming", "atlas_information_panel", "atlas_ruler_editor",
    "atlas_render_scheduler", "atlas_render_publication_batch", "atlas_render_lifetime", "atlas_native_display", "atlas_political_incremental",
    "atlas_military_marker_cache", "atlas_military_layer_invalidation", "atlas_attack_arrows", "atlas_city_marker_preparation",
    "atlas_render_index", "atlas_persistent_strokes", "atlas_shared_stroke_cache",
    "atlas_symbol_mesh", "atlas_symbol_tiles", "atlas_incremental_text", "atlas_wrapped_text", "atlas_city_markers",
    "atlas_entry_contract", "atlas_preview_lifecycle", "atlas_render_invalidation", "atlas_view_caches", "atlas_camera_feedback", "atlas_war_fronts", "atlas_vassal_borders", "atlas_military_contract", "atlas_hierarchy_cases",
    "atlas_traffic_graph", "atlas_zhoufu_roads", "atlas_road_smoothing",
    "atlas_segmented_movement", "atlas_junction_encounters",
    "atlas_access_and_repatriation", "atlas_campaign_reachability", "atlas_territory_transactions",
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
        if test in ("atlas_military_smoke", "atlas_masked_military_smoke"): command += ["--", "--atlas-smoke-days=" + str(args.days)]
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
