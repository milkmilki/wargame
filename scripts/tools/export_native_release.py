#!/usr/bin/env python3
"""Export WorldWar's native Windows release and optionally verify its real scene.

The existing source fingerprint reads original .gd/.tscn bytes. Preserve both
formats in the package; temporary project/preset changes are checked and restored.
The optional cache probe expects Earth seed 1, 40 nations and the Eurasia mask.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "native/runtime_graph"
VERSION = "4.7.1.stable.official.a13da4feb"
TEMPLATE_SHA256 = "76269a403bb832599edeee4432a5b7a7e88c018eb5c9c798dfd8289359b0ec07"
DLL_NAME = "runtime_graph.windows.template_release.x86_64.dll"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def preserve_text_resources(original: bytes) -> bytes:
    text = original.decode("utf-8")
    setting = "export/convert_text_resources_to_binary=false\n"
    section = re.search(r"(?m)^\[editor\]\s*\n", text)
    if section is None:
        return original + b"\n[editor]\n\n" + setting.encode()
    following = re.search(r"(?m)^\[", text[section.end():])
    end = section.end() + following.start() if following else len(text)
    block = text[section.end():end]
    updated, count = re.subn(r"(?m)^export/convert_text_resources_to_binary=.*$",
                            setting.rstrip("\n"), block)
    if count > 1:
        raise RuntimeError("Duplicate text-resource export settings")
    if not count:
        updated = setting + block
    return (text[:section.end()] + updated + text[end:]).encode("utf-8")


@contextmanager
def temporary_export_config(template: Path, output: Path, record: dict):
    project = ROOT / "project.godot"
    preset = ROOT / "export_presets.cfg"
    original = project.read_bytes()
    modified = preserve_text_resources(original)
    content = (
        '[preset.0]\nname="WorldWarReleaseVerification"\nplatform="Windows Desktop"\n'
        'runnable=true\nexport_filter="all_resources"\n'
        'include_filter="assets/atlas/*.json,assets/atlas/*.gz,assets/atlas/*.ttf,assets/atlas/*.txt,assets/atlas/*.md"\n'
        'exclude_filter=".dbg/*,.git/*,docs/*,tests/*,native/runtime_graph/.cache/*,native/runtime_graph/src/*,scripts/tools/*,*.py,*.mts"\n'
        'export_path=""\nscript_export_mode=0\n[preset.0.options]\n'
        'custom_template/debug=""\ncustom_template/release="' + template.as_posix() + '"\n'
        'binary_format/architecture="x86_64"\nbinary_format/embed_pck=false\n'
        'debug/export_console_wrapper=0\napplication/modify_resources=false\n'
    ).encode()
    record["export_configuration"] = {
        "script_export_mode": "text (0)",
        "editor/export/convert_text_resources_to_binary": False,
        "preset_sha256": hashlib.sha256(content).hexdigest(),
        "preset": content.decode(),
        "temporary_project_sha256": hashlib.sha256(modified).hexdigest(),
    }
    (output / "project.godot.original").write_bytes(original)
    with preset.open("xb") as stream:
        stream.write(content)
    try:
        if project.read_bytes() != original:
            raise RuntimeError("project.godot changed before export; preserved")
        staging = output / "project.godot.exporting"
        staging.write_bytes(modified)
        os.replace(staging, project)
        yield
    finally:
        cleanup_errors = []
        if project.read_bytes() == modified:
            staging = output / "project.godot.restoring"
            staging.write_bytes(original)
            os.replace(staging, project)
        elif project.read_bytes() != original:
            cleanup_errors.append("project.godot changed during export; preserved unexpected contents")
        if preset.exists() and preset.read_bytes() == content:
            preset.unlink()
        else:
            cleanup_errors.append("Temporary export preset changed; preserved unexpected contents")
        record["export_configuration"]["project_restored"] = project.read_bytes() == original
        record["export_configuration"]["temporary_preset_removed"] = not preset.exists()
        if cleanup_errors:
            raise RuntimeError("; ".join(cleanup_errors))


def invoke(command: list[str | Path], output: Path, label: str,
           *, env: dict | None = None, timeout: int = 300) -> tuple[dict, str]:
    log = output / (label + ".log")
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen([str(arg) for arg in command], cwd=output,
                                   env=env, stdout=stream, stderr=subprocess.STDOUT,
                                   startupinfo=startup)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise RuntimeError(f"{label} timed out; see {log}")
    text = log.read_text(encoding="utf-8", errors="replace")
    return {"pid": process.pid, "exit_code": code,
            "argv": [str(arg) for arg in command], "log": str(log)}, text


def verify_scene(executable: Path, cache: Path, output: Path, record: dict) -> None:
    capture = output / "main-scene-eurasia.png"
    # A previous capture must not satisfy the acceptance check for this PID.
    if capture.exists():
        capture.rename(output / f"previous-capture-{capture.stat().st_mtime_ns}.png")
    env = dict(os.environ)
    env["WARGAME_COMPUTE_BACKEND"] = "gdscript"
    command = [executable, "--", "--atlas-cache=" + cache.as_posix(),
               "--atlas-capture=" + capture.as_posix()]
    startup, text = invoke(command, output, "startup", env=env)
    record["startup"] = startup
    startup["requested_backend"] = "gdscript (release must force native)"
    startup["error_lines"] = [line for line in text.splitlines()
                              if line.startswith(("ERROR:", "SCRIPT ERROR:"))]
    if startup["exit_code"] != 0 or startup["error_lines"] or not capture.is_file() or "ATLAS_NATIVE_CAPTURE" not in text:
        raise RuntimeError("Actual release main scene failed clean startup/capture; see startup.log")
    match = re.search(r"\[DEBUG_RUN\] 日志：([^\r\n]+)", text)
    if not match:
        raise RuntimeError("Actual PID session log missing")
    log = Path(match.group(1))
    entries = [json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()]
    record["debug_run_log"] = str(log)
    record["debug_run_entries"] = entries
    session = next(entry for entry in entries if entry.get("event") == "session_start")
    world = next(entry for entry in entries if entry.get("event") == "world_start")
    if session["pid"] != startup["pid"] or session["scene"] != record["main_scene"]:
        raise RuntimeError("Unexpected release PID or main scene")
    if world["pid"] != startup["pid"] or world["seed"] != 1 or world["nation_count"] != 40:
        raise RuntimeError("Unexpected release PID, seed or nation count")
    mask = world["settings"]["options"]["settlement_mask"]
    if mask.get("enabled") is not True or any(mask.get(k) != v for k, v in
            (("south", 20), ("north", 55), ("west", -15), ("east", 145))):
        raise RuntimeError("Release cache does not contain the required Eurasia mask")
    renderer = next((line for line in text.splitlines() if "Using Device" in line), "")
    startup["renderer"] = renderer
    record["capture"] = {"path": str(capture), "sha256": sha256(capture),
                         "size_bytes": capture.stat().st_size}
    library = Path(record["packaged_release_dll"]["path"])
    disabled = library.with_suffix(".disabled")
    if disabled.exists():
        raise RuntimeError("A prior disabled packaged library already exists")
    library.rename(disabled)
    try:
        failed, failed_text = invoke(command, output, "missing-dll", env=env, timeout=30)
        record["missing_dll"] = failed
        failed["explicit_error"] = "NativeGraphSnapshot is missing" in failed_text
        failed["capture_reached"] = "ATLAS_NATIVE_CAPTURE" in failed_text
        if failed["exit_code"] != 1 or not failed["explicit_error"] or failed["capture_reached"]:
            raise RuntimeError("Packaged DLL missing guard failed; see missing-dll.log")
    finally:
        disabled.rename(library)
    record["missing_dll"]["packaged_library_restored"] = sha256(library) == record["source_release_dll_sha256"]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--release-template", type=Path, default=NATIVE / ".cache/windows_release_x86_64.exe")
    parser.add_argument("--output", type=Path, default=ROOT / ".dbg/wargame-release")
    parser.add_argument("--verify-cache", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    template = args.release_template.resolve()
    version = subprocess.check_output([str(args.godot), "--version"], encoding="utf-8").strip()
    if version != VERSION or sha256(template) != TEMPLATE_SHA256:
        raise RuntimeError("Expected the locked official Godot 4.7.1 engine and release template")
    verify_command = [os.sys.executable, str(ROOT / "scripts/tools/build_native_compute.py"),
                      "--godot", str(args.godot.resolve()), "--verify-only"]
    subprocess.run(verify_command, check=True)
    source_dll = NATIVE / "bin" / DLL_NAME
    adapter = ROOT / "scripts/core/native_compute.gd"
    api_match = re.search(r"(?m)^const API_VERSION\s*:=\s*(\d+)", adapter.read_text(encoding="utf-8"))
    if not api_match:
        raise RuntimeError("Native adapter API version is missing")
    record = {"engine": version, "main_scene": "res://atlas_military.tscn",
              "native_api_version": int(api_match.group(1)),
              "native_adapter_sha256": sha256(adapter),
              "main_scene_sha256": sha256(ROOT / "atlas_military.tscn"),
              "project_godot_sha256": sha256(ROOT / "project.godot"),
              "release_template_sha256": sha256(template),
              "source_release_dll_sha256": sha256(source_dll),
              "scope": "Actual main scene startup and screenshot; starts paused on day 0, not a simulation performance measurement."}
    try:
        executable = output / "wargame-release.exe"
        with temporary_export_config(template, output, record):
            result, text = invoke([args.godot, "--headless", "--path", ROOT,
                                   "--export-release", "WorldWarReleaseVerification", executable], output, "export")
            record["export"] = result
            if result["exit_code"] != 0 or any(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in text.splitlines()):
                raise RuntimeError("Full game export failed; see export.log")
        libraries = list(output.rglob(DLL_NAME))
        if len(libraries) != 1 or sha256(libraries[0]) != record["source_release_dll_sha256"]:
            raise RuntimeError("Packaged DLL differs from the verified source DLL")
        record["packaged_release_dll"] = {"path": str(libraries[0]), "sha256": sha256(libraries[0])}
        record["executable"] = {"path": str(executable), "sha256": sha256(executable)}
        pack = executable.with_suffix(".pck")
        record["pck"] = {"path": str(pack), "sha256": sha256(pack)}
        if args.verify_cache:
            cache = args.verify_cache.resolve()
            record["atlas_cache"] = {"path": str(cache), "sha256": sha256(cache)}
            verify_scene(executable, cache, output, record)
        if (sha256(ROOT / "project.godot") != record["project_godot_sha256"]
                or sha256(source_dll) != record["source_release_dll_sha256"]
                or sha256(adapter) != record["native_adapter_sha256"]):
            raise RuntimeError("Production project, adapter or source DLL changed")
        subprocess.run(verify_command, check=True)
        record["status"] = "pass"
    except BaseException as error:
        record["status"] = "failed"
        record["failure"] = str(error)
        raise
    finally:
        evidence = output / "full-game-release-raw.json"
        evidence.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print("FULL_GAME_RELEASE_EVIDENCE", evidence, record["status"], flush=True)


if __name__ == "__main__":
    main()
