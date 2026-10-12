#!/usr/bin/env python3
"""Run isolated, alternating native/GDScript benchmarks on the same frozen states."""
import argparse
import ctypes
from ctypes import wintypes
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".dbg" / "native-runtime"


class ProcessMemoryCounters(ctypes.Structure):
    _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                ("PrivateUsage", ctypes.c_size_t)]


def process_memory(handle):
    counters = ProcessMemoryCounters()
    counters.cb = ctypes.sizeof(counters)
    api = ctypes.WinDLL("psapi", use_last_error=True).GetProcessMemoryInfo
    api.argtypes = [wintypes.HANDLE, ctypes.POINTER(ProcessMemoryCounters), wintypes.DWORD]
    api.restype = wintypes.BOOL
    if not api(wintypes.HANDLE(int(handle)), ctypes.byref(counters), counters.cb):
        raise ctypes.WinError(ctypes.get_last_error())
    return {"peak_working_set": counters.PeakWorkingSetSize,
            "peak_pagefile": counters.PeakPagefileUsage, "private_usage": counters.PrivateUsage}


def run_process(godot, backend, stages, days, iteration):
    environment = dict(os.environ, WARGAME_COMPUTE_BACKEND=backend)
    command = [str(godot), "--headless", "--path", str(ROOT), "--script",
               "res://tests/native_runtime_benchmark.gd", "--", f"--days={days}",
               f"--stages={stages}"]
    log = OUTPUT / f"paired-{iteration}-{backend}.log"
    with log.open("w", encoding="utf-8") as stream:
        started = time.monotonic()
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, env=environment)
        peaks = {"peak_working_set": 0, "peak_pagefile": 0, "private_usage": 0}
        while process.poll() is None:
            if time.monotonic() - started > 1800:
                process.kill()
                process.wait()
                raise subprocess.TimeoutExpired(command, 1800)
            try:
                for key, value in process_memory(process._handle).items():
                    peaks[key] = max(peaks[key], value)
            except OSError:
                if process.poll() is None:
                    raise
            time.sleep(.05)
        if not peaks["peak_working_set"]:
            raise RuntimeError("Windows process memory sampling failed")
    text = log.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"NATIVE_BENCH_PASS report=(.+)", text)
    if process.returncode or not match or re.search(r"SCRIPT ERROR|^ERROR:", text, re.M):
        raise RuntimeError(f"Benchmark failed: {log}\n{text[-6000:]}")
    report_path = Path(match.group(1).strip())
    report = json.loads(report_path.read_text(encoding="utf-8"))
    report["wall_seconds"] = time.monotonic() - started
    report["os_memory_peaks"] = peaks
    report["log_path"] = str(log)
    print(f"{backend} iteration={iteration} {report['wall_seconds']:.1f}s {report_path}", flush=True)
    return report


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[max(0, min(len(ordered) - 1, math.ceil(len(ordered) * fraction) - 1))]


def aggregate(reports):
    days = [value for report in reports for stage in report["stages"]
            for value in stage["daily"]["raw_usec"]]
    by_module = {}
    for report in reports:
        for stage in report["stages"]:
            for query in stage["query_batches"]:
                by_module.setdefault(query["module"], []).extend(query["timing"]["raw_usec"])
    return {"mean_usec": statistics.mean(days), "p95_usec": percentile(days, .95),
            "p99_usec": percentile(days, .99),
            "monthly_peak_usec": max(stage["monthly_peak_usec"] for report in reports for stage in report["stages"]),
            "memory_peak": max(report["os_memory_peaks"]["peak_working_set"] for report in reports),
            "peak_pagefile": max(report["os_memory_peaks"]["peak_pagefile"] for report in reports),
            "godot_static_memory_peak": max(stage["memory"] for report in reports for stage in report["stages"]),
            "query_mean_usec": {name: statistics.mean(values) for name, values in by_module.items()}}


def summarize_pairs(pairs):
    condition_keys = ["fixture_manifest", "processor", "cpu_count", "engine", "days_per_stage",
                      "dll_hashes", "build_manifests", "current_source_sha256"]
    reference = pairs[0]["gdscript"]
    for pair in pairs:
        first, second = pair["gdscript"], pair["native"]
        for key in condition_keys:
            if first[key] != second[key] or first[key] != reference[key]:
                raise RuntimeError(f"Mismatched benchmark condition: {key}")
        if len(first["stages"]) != len(second["stages"]):
            raise RuntimeError("Mismatched benchmark stages")
        for a, b in zip(first["stages"], second["stages"]):
            for key in ["start_day", "end_day", "input_sha256", "output_sha256"]:
                if a[key] != b[key]:
                    raise RuntimeError(f"State divergence {key}, stage={a['start_day']}")
    baseline = aggregate([pair["gdscript"] for pair in pairs])
    native = aggregate([pair["native"] for pair in pairs])
    reductions = {name: 1 - native[name] / baseline[name] for name in ["mean_usec", "p95_usec", "p99_usec"]}
    module_reductions = {name: 1 - native["query_mean_usec"][name] / baseline["query_mean_usec"][name]
                         for name in baseline["query_mean_usec"]}
    targets = {"daily_mean_20pct": reductions["mean_usec"] >= .20,
               "daily_p95_10pct": reductions["p95_usec"] >= .10,
               "monthly_peak_10pct": native["monthly_peak_usec"] <= baseline["monthly_peak_usec"] * 1.10,
               "memory_10pct": native["memory_peak"] <= baseline["memory_peak"] * 1.10,
               **{f"query_{name}_50pct": reduction >= .50 for name, reduction in module_reductions.items()}}
    return {"baseline": baseline, "native": native, "daily_reductions": reductions,
            "query_reductions": module_reductions, "targets": targets,
            "performance_targets_met": all(targets.values()), "exact_states": True,
            "pairs": pairs}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--iterations", type=int, default=5)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--stages", default="0,330,600")
    parser.add_argument("--reuse", action="store_true", help="Aggregate already completed reports instead of computing")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    pairs = []
    for iteration in range(args.iterations):
        if args.reuse:
            pair = json.loads((OUTPUT / f"pair-{iteration}.json").read_text(encoding="utf-8"))
        else:
            pair = {}
            for backend in (["gdscript", "native"] if iteration % 2 == 0 else ["native", "gdscript"]):
                pair[backend] = run_process(args.godot, backend, args.stages, args.days, iteration)
            (OUTPUT / f"pair-{iteration}.json").write_text(json.dumps(pair, indent=2), encoding="utf-8")
        pairs.append(pair)
    summary = summarize_pairs(pairs)
    path = OUTPUT / "paired-summary.json"
    path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in summary.items() if key != "pairs"}, indent=2))
    print(f"Report: {path}", flush=True)
    return 0 if summary["performance_targets_met"] else 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
