#!/usr/bin/env python3
"""Verify native error handling and a real Windows release export in a local cache."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native/runtime_graph"
CACHE = NATIVE / ".cache"
TEMPLATE_URL = "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz"
TEMPLATE_SIZE = 1280486955
# Published GitHub release asset digest. Range extraction validates each ZIP
# member's CRC/size over authenticated HTTPS, not this whole-archive SHA-256.
TEMPLATE_ARCHIVE_SHA256 = "86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72"
TEMPLATE_MEMBER_SHA256 = "76269a403bb832599edeee4432a5b7a7e88c018eb5c9c798dfd8289359b0ec07"
VERSION = "4.7.1.stable.official.a13da4feb"


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def run(command: list[str | Path], *, cwd: Path = ROOT, env: dict | None = None,
        expected: int = 0, marker: str = "", timeout: int = 120) -> dict:
    result = subprocess.run([str(x) for x in command], cwd=cwd, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            encoding="utf-8", errors="replace", timeout=timeout)
    if result.returncode != expected or (marker and marker not in result.stdout):
        raise RuntimeError(f"Probe returned {result.returncode}, expected {expected}:\n{result.stdout}")
    return {"command": [str(x) for x in command], "exit_code": result.returncode, "output": result.stdout}


def download_range(start: int, end: int, path: Path) -> bytes:
    length = end - start + 1
    run(["curl.exe", "--fail", "--silent", "--show-error", "--location", "--retry", "3",
         "--range", f"{start}-{end}", "--max-filesize", str(length), "--output", path, TEMPLATE_URL])
    data = path.read_bytes()
    if len(data) != length:
        raise RuntimeError("Official template server returned an unexpected HTTP byte range")
    return data


def official_template() -> Path:
    target = CACHE / "windows_release_x86_64.exe"
    if target.exists() and digest(target) == TEMPLATE_MEMBER_SHA256:
        return target
    tail_start = TEMPLATE_SIZE - 65536
    tail = download_range(tail_start, TEMPLATE_SIZE - 1, CACHE / "template_tail.zip")
    directory = zipfile.ZipFile(io.BytesIO(tail))
    member = directory.getinfo("templates/windows_release_x86_64.exe")
    offset = member.header_offset + tail_start
    header = download_range(offset, offset + 1023, CACHE / "template_header.bin")
    fields = struct.unpack("<IHHHHHIIIHH", header[:30])
    if fields[0] != 0x04034B50 or member.compress_type != zipfile.ZIP_DEFLATED:
        raise RuntimeError("Unexpected official export-template ZIP format")
    start = offset + 30 + fields[-2] + fields[-1]
    packed = download_range(start, start + member.compress_size - 1,
                            CACHE / "windows_release_x86_64.exe.deflate")
    data = zlib.decompress(packed, -15)
    if len(data) != member.file_size or zlib.crc32(data) != member.CRC:
        raise RuntimeError("Official Windows release template failed ZIP CRC/size validation")
    target.write_bytes(data)
    if digest(target) != TEMPLATE_MEMBER_SHA256:
        raise RuntimeError("Official Windows release template SHA-256 changed")
    return target


def export_project(godot: Path, template: Path) -> tuple[Path, dict]:
    parent = CACHE / "export_contract"
    parent.mkdir(exist_ok=True)
    project = Path(tempfile.mkdtemp(prefix="probe_", dir=parent))
    for folder in ["scripts", "assets"]:
        shutil.copytree(ROOT / folder, project / folder,
                        ignore=shutil.ignore_patterns("__pycache__", "*.py", "*.mts"))
    (project / "tests").mkdir()
    shutil.copy2(ROOT / "tests/native_extension_contract.gd", project / "tests/native_extension_contract.gd")
    # Official release templates reject --path overrides. Run the same contract
    # as the exported main scene, using Node's lifecycle instead of a --script
    # SceneTree override, so the shipped executable's normal startup is tested.
    contract = (ROOT / "tests/native_extension_contract.gd").read_text(encoding="utf-8")
    contract = contract.replace("extends SceneTree", "extends Node").replace("func _initialize()", "func _ready()")
    contract = contract.replace("quit(", "get_tree().quit(")
    (project / "tests/native_extension_release.gd").write_text(contract, encoding="utf-8")
    (project / "native/runtime_graph/bin").mkdir(parents=True)
    shutil.copy2(NATIVE / "runtime_graph.gdextension", project / "native/runtime_graph/runtime_graph.gdextension")
    for target in ["debug", "release"]:
        dll = f"runtime_graph.windows.template_{target}.x86_64.dll"
        shutil.copy2(NATIVE / "bin" / dll, project / "native/runtime_graph/bin" / dll)
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Native release contract"\nrun/main_scene="res://main.tscn"\nconfig/features=PackedStringArray("4.7", "GL Compatibility")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
    (project / "main.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/native_extension_release.gd" id="1"]\n[node name="Contract" type="Node"]\nscript=ExtResource("1")\n', encoding="utf-8")
    preset = '[preset.0]\nname="NativeContract"\nplatform="Windows Desktop"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter=""\nexclude_filter=""\nexport_path=""\nscript_export_mode=2\n[preset.0.options]\ncustom_template/debug=""\ncustom_template/release="%s"\nbinary_format/architecture="x86_64"\nbinary_format/embed_pck=false\ndebug/export_console_wrapper=0\napplication/modify_resources=false\n' % template.as_posix()
    (project / "export_presets.cfg").write_text(preset, encoding="utf-8")
    # First-scan extension docs can still be queued when 4.7.1 --import quits
    # (godot-cpp #2024). Let editor frames drain before the strict import check.
    warmed = run([godot, "--headless", "--editor", "--path", project,
                  "--quit-after", "120", "--max-fps", "20"], cwd=project, timeout=180)
    imported = run([godot, "--headless", "--editor", "--path", project, "--import"], cwd=project, timeout=180)
    output = project / "output"
    output.mkdir()
    exported = run([godot, "--headless", "--path", project, "--export-release", "NativeContract", output / "contract.exe"],
                   cwd=project, timeout=180)
    return output, {"warm_editor": warmed, "import": imported, "export": exported}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=Path("D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe"))
    parser.add_argument("--release-template", type=Path)
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    evidence = {"engine_version": VERSION, "probes": {}}
    evidence["probes"]["normal_debug"] = run([args.godot, "--headless", "--path", ROOT, "--script", "res://tests/native_extension_contract.gd"],
                                                 marker="NATIVE_EXTENSION_CONTRACT failures=0")
    for mode, message in [("missing", "NativeGraphSnapshot is missing"), ("api_mismatch", "API version mismatch")]:
        probe = run([args.godot, "--headless", "--path", ROOT, "--script", "res://tests/native_extension_contract.gd", "--", "--probe=" + mode],
                    expected=1, marker="NATIVE_EXTENSION_EXPECTED_FAILURE mode=" + mode)
        if message not in probe["output"]:
            raise RuntimeError(f"The {mode} probe did not emit its actionable error")
        evidence["probes"][mode] = probe
    template = args.release_template.resolve() if args.release_template else official_template()
    version = run([template, "--headless", "--version"], marker=VERSION)
    evidence["template"] = {"executable": str(template), "sha256": digest(template),
                            "archive_url": TEMPLATE_URL, "archive_sha256": TEMPLATE_ARCHIVE_SHA256,
                            "version_probe": version}
    output, export_evidence = export_project(args.godot.resolve(), template)
    evidence.update(export_evidence)
    environment = dict(os.environ)
    environment["WARGAME_COMPUTE_BACKEND"] = "gdscript"
    command = [output / "contract.exe", "--headless", "--", "--expect-release"]
    evidence["probes"]["real_release"] = run(command, cwd=output, env=environment,
                                                marker="NATIVE_EXTENSION_CONTRACT failures=0 debug=false backend=native")
    # Only move the exported fixture's own DLL. The game's binaries stay loaded
    # and untouched while other agents may run simulation equivalence tests.
    libraries = list(output.rglob("runtime_graph.windows.template_release.x86_64.dll"))
    if len(libraries) != 1:
        raise RuntimeError(f"Expected exactly one packaged release DLL, found {libraries}")
    packaged = libraries[0]
    source = NATIVE / "bin/runtime_graph.windows.template_release.x86_64.dll"
    if digest(packaged) != digest(source):
        raise RuntimeError("Exporter included a different release DLL")
    evidence["release_dll_sha256"] = digest(packaged)
    renamed = packaged.with_suffix(".disabled")
    packaged.rename(renamed)
    try:
        evidence["probes"]["release_missing_dll"] = run(command, cwd=output, env=environment,
                                                           expected=1, marker="NativeGraphSnapshot is missing")
    finally:
        renamed.rename(packaged)
    evidence["adapter_sha256"] = digest(ROOT / "scripts/core/native_compute.gd")
    destination = CACHE / "native_shipping_evidence.json"
    destination.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print("NATIVE_SHIPPING_CONTRACT all probes passed; evidence:", destination)


if __name__ == "__main__":
    main()
