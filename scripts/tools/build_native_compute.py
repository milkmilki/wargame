#!/usr/bin/env python3
"""Bootstrap and build the locked Windows runtime graph GDExtension.

Example: python scripts/tools/build_native_compute.py --godot D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe
Dependencies, engine API dumps and SCons objects stay in an ignored local cache.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import venv


PROJECT = Path(__file__).resolve().parents[2]
NATIVE = PROJECT / "native" / "runtime_graph"
CACHE = NATIVE / ".cache"
LOCK_PATH = NATIVE / "dependencies.lock.json"
LOCK = json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def run(args: list[str | Path], *, cwd: Path = NATIVE,
        env: dict[str, str] | None = None, capture: bool = False) -> str:
    command = [str(arg) for arg in args]
    print("+ " + subprocess.list2cmdline(command), flush=True)
    result = subprocess.run(command, cwd=cwd, env=env, check=False,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.STDOUT if capture else None,
                            text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        if capture and result.stdout:
            print(result.stdout, file=sys.stderr)
        raise subprocess.CalledProcessError(result.returncode, command, output=result.stdout)
    return result.stdout.strip() if capture else ""


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def tool_python() -> Path:
    tool_dir = CACHE / "python"
    executable = tool_dir / "Scripts" / "python.exe"
    if not executable.exists():
        venv.EnvBuilder(with_pip=True).create(tool_dir)
    installed = run([executable, "-c", "import importlib.metadata; print(importlib.metadata.version('SCons'))"],
                    capture=True) if (tool_dir / "Lib/site-packages/SCons").is_dir() else ""
    if installed != LOCK["scons"]["version"]:
        wheel = CACHE / Path(LOCK["scons"]["wheel_url"]).name
        if not wheel.exists() or sha256(wheel) != LOCK["scons"]["sha256"]:
            # curl supports the SOCKS proxies often present in the desktop runtime;
            # pip only installs the hash-verified local wheel, without an index.
            curl = shutil.which("curl.exe")
            if not curl:
                raise RuntimeError("curl.exe is required to download the locked SCons wheel")
            run([curl, "--fail", "--location", "--retry", "3", "--output", wheel,
                 LOCK["scons"]["wheel_url"]])
        if sha256(wheel) != LOCK["scons"]["sha256"]:
            raise RuntimeError("SCons wheel SHA-256 does not match dependencies.lock.json")
        run([executable, "-m", "pip", "install", "--no-index", "--no-deps", wheel])
    return executable


def godot_cpp() -> Path:
    checkout = CACHE / "godot-cpp"
    if not checkout.exists():
        run(["git", "clone", "--no-checkout", LOCK["godot_cpp"]["repository"], checkout])
        run(["git", "checkout", "--detach", LOCK["godot_cpp"]["commit"]], cwd=checkout)
    commit = run(["git", "rev-parse", "HEAD"], cwd=checkout, capture=True)
    if commit != LOCK["godot_cpp"]["commit"]:
        raise RuntimeError(f"Cached godot-cpp is at {commit}, expected {LOCK['godot_cpp']['commit']}. "
                           "Use a fresh cache; the build will not reset an existing checkout.")
    dirty = run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=checkout, capture=True)
    if dirty:
        raise RuntimeError("Cached godot-cpp has tracked changes; use an unmodified locked dependency")
    return checkout


def export_api(godot: Path) -> Path:
    version = run([godot, "--headless", "--version"], capture=True)
    if version != LOCK["godot"]["version"]:
        raise RuntimeError(f"Godot version {version!r} does not match locked {LOCK['godot']['version']!r}")
    engine_hash = sha256(godot)
    api_dir = CACHE / "api"
    api_dir.mkdir(exist_ok=True)
    api = api_dir / "extension_api.json"
    engine_stamp = api_dir / "engine.sha256"
    api_stamp = api_dir / "api.sha256"
    cache_valid = (api.exists() and engine_stamp.exists() and api_stamp.exists()
                   and engine_stamp.read_text().strip() == engine_hash
                   and api_stamp.read_text().strip() == sha256(api))
    if not cache_valid:
        run([godot, "--headless", "--dump-extension-api"], cwd=api_dir)
    header = json.loads(api.read_text(encoding="utf-8"))["header"]
    if ((header["version_major"], header["version_minor"], header["version_patch"]) != (4, 7, 1)
            or header.get("precision") != LOCK["godot"]["precision"]):
        raise RuntimeError("Engine exported an unexpected extension API header")
    engine_stamp.write_text(engine_hash + "\n", encoding="ascii")
    api_stamp.write_text(sha256(api) + "\n", encoding="ascii")
    return api


def msvc_environment(build_tools: Path) -> dict[str, str]:
    vcvars = build_tools / "VC/Auxiliary/Build/vcvarsall.bat"
    if not vcvars.is_file():
        raise RuntimeError(f"MSVC setup not found: {vcvars}")
    # Only the compiler environment is evaluated by cmd. File operations use
    # pathlib, and compiler/build invocations use argument lists without a shell.
    command = f'call "{vcvars}" x64 -vcvars_ver={LOCK["msvc"]} >nul && set'
    # cmd does not accept the C-runtime backslash quoting used for argument
    # lists. Its /c command must be passed as a raw, outer-quoted command line.
    cmd = subprocess.list2cmdline([os.environ.get("COMSPEC", "cmd.exe")])
    output = subprocess.check_output(f'{cmd} /d /s /c "{command}"', text=True, errors="replace")
    result = {key.upper(): value for key, value in os.environ.items()}
    for line in output.splitlines():
        if "=" in line and not line.startswith("="):
            key, value = line.split("=", 1)
            result[key.upper()] = value
    vc_version = result.get("VCTOOLSVERSION", "")
    if vc_version.rstrip("\\/") != LOCK["msvc_toolset"]:
        raise RuntimeError(f"MSVC version {vc_version!r} does not match locked {LOCK['msvc_toolset']}")
    return result


def source_hashes() -> dict[str, str]:
    sources = [LOCK_PATH, NATIVE / "SConstruct", NATIVE / "build_profile.json",
               NATIVE / "runtime_graph.gdextension", Path(__file__).resolve(), *sorted((NATIVE / "src").glob("*"))]
    return {path.relative_to(PROJECT).as_posix(): sha256(path) for path in sources if path.is_file()}


def binary(target: str) -> Path:
    return NATIVE / "bin" / f"runtime_graph.windows.template_{target}.x86_64.dll"


def expected_metadata() -> dict[str, str]:
    return {"godot_version": LOCK["godot"]["version"], "godot_cpp_commit": LOCK["godot_cpp"]["commit"],
            "msvc": LOCK["msvc"], "msvc_toolset": LOCK["msvc_toolset"], "scons": LOCK["scons"]["version"],
            "precision": LOCK["godot"]["precision"], "platform": LOCK["platform"],
            "architecture": LOCK["architecture"], "floating_point": "/fp:strict", "lto": "none"}


def verify(targets: list[str], godot: Path) -> None:
    api = CACHE / "api/extension_api.json"
    if not api.is_file() or not godot.is_file():
        raise RuntimeError("The recorded engine or API dump is missing; bootstrap and rebuild")
    current_api_hash, current_engine_hash = sha256(api), sha256(godot)
    for target in targets:
        library = binary(target)
        manifest = library.with_suffix(".build.json")
        if not library.is_file() or not manifest.is_file():
            raise RuntimeError(f"Build {target} first; missing DLL or build manifest: {library}")
        data = json.loads(manifest.read_text(encoding="utf-8"))
        if data.get("dll_sha256") != sha256(library) or data.get("source_sha256") != source_hashes():
            raise RuntimeError(f"The {target} DLL or its sources changed since the recorded build; rebuild")
        expected = {"target": target, **expected_metadata(), "api_sha256": current_api_hash,
                    "engine_sha256": current_engine_hash}
        mismatches = [key for key, value in expected.items() if data.get(key) != value]
        if mismatches:
            raise RuntimeError(f"The {target} build inputs do not match its manifest ({', '.join(mismatches)}); rebuild")
        print(f"Verified {target}: {library} ({data['dll_sha256']})")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=Path("D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe"))
    parser.add_argument("--build-tools", type=Path, default=Path("C:/BuildTools"))
    parser.add_argument("--target", choices=["debug", "release", "both"], default="both")
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--bootstrap-only", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if sys.platform != "win32" or f"{sys.version_info.major}.{sys.version_info.minor}" != LOCK["python"]:
        parser.error(f"Builds require Windows and Python {LOCK['python']}")
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    targets = ["debug", "release"] if args.target == "both" else [args.target]
    if args.verify_only:
        verify(targets, args.godot.resolve())
        return 0
    CACHE.mkdir(parents=True, exist_ok=True)
    python = tool_python()
    godot_cpp()
    api = export_api(args.godot.resolve())
    environment = msvc_environment(args.build_tools.resolve())
    if args.bootstrap_only:
        print("Locked native dependencies and engine API are ready.")
        return 0
    for required in ["src/runtime_graph.cpp", "src/runtime_graph.hpp"]:
        if not (NATIVE / required).is_file():
            raise RuntimeError(f"Missing native source: {required}")
    build_sources = source_hashes()
    build_engine_hash = sha256(args.godot.resolve())
    build_api_hash = sha256(api)
    for target in targets:
        run([python, "-m", "SCons", f"-j{args.jobs}", "platform=windows", "arch=x86_64",
             f"target=template_{target}", f"custom_api_file={api}",
             f"build_profile={NATIVE / 'build_profile.json'}", "precision=single",
             "lto=none", "use_static_cpp=yes", "use_hot_reload=no", "debug_symbols=yes"], env=environment)
        if (source_hashes() != build_sources or sha256(args.godot.resolve()) != build_engine_hash
                or sha256(api) != build_api_hash):
            raise RuntimeError("Native build inputs changed during compilation; retry once edits are complete")
        library = binary(target)
        metadata = {
            "target": target, **expected_metadata(),
            "engine_sha256": build_engine_hash, "api_sha256": build_api_hash,
            "dll_sha256": sha256(library), "source_sha256": build_sources,
        }
        library.with_suffix(".build.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    verify(targets, args.godot.resolve())
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        print(f"Native build failed: {error}", file=sys.stderr)
        raise SystemExit(1)
