# Runtime graph GDExtension

This extension builds for Windows x64, Godot `4.7.1.stable.official.a13da4feb`, Python 3.11 and MSVC 14.44.35207. The checked dependency lock pins godot-cpp and a SHA-256 verified SCons wheel. The build exports the API from the selected engine, rather than using an API dump from a different patch release.

From the Godot project directory:

```powershell
python scripts/tools/build_native_compute.py --godot D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe
python scripts/tools/build_native_compute.py --verify-only
```

Use `--bootstrap-only` to prepare dependencies and export the API without compiling, `--target debug` or `--target release` for one DLL, and `--build-tools` to change the Visual Studio Build Tools installation path. The selected installation must contain the locked MSVC 14.44.35207 toolchain. Existing godot-cpp checkouts with another commit or tracked changes are rejected rather than reset. SCons is installed into a local virtual environment; global Python packages are unchanged.

Builds keep `precision=single` to match the official engine ABI. The graph's scalar costs use C++ `double`; both the binding library and kernels use `/fp:strict`, with link-time optimization disabled. The build profile includes RefCounted, OS, their inherited engine types and the core types godot-cpp requires; it avoids unused scene bindings. Debug DLLs include Godot debug features and both DLLs include PDB symbols.

`runtime_graph.gdextension` is a tracked project resource. Godot selects the debug DLL in the editor and debug exports, and the release DLL in release exports. The exporter follows its platform library entries and includes the selected DLL. Build the matching target before exporting; packaged release validation must check that the native class loads. Build outputs, dependency checkouts, generated bindings, API dumps and manifests live under ignored `.cache/` or `bin/` directories. DLLs must be built or provisioned on each checkout before using the native backend.

Each DLL has a `.build.json` manifest containing engine, API, dependency, build-source and DLL hashes. `--verify-only` rejects missing outputs, changed DLL bytes, modified engine/API inputs, changed locked build options and binaries built from older source files. A changed API cache is regenerated from the locked engine before building. This check does not prove ABI or simulation equivalence; the Godot load probe and the game's native/reference tests provide those checks. Its isolated fixture tests run with `python -m unittest discover -s tests -p test_native_build_metadata.py`.

The shipping contract is repeatable without installing export templates globally:

```powershell
python tests/native_extension_contract.py
```

It checks missing-library and API-mismatch errors in separate debug processes, then creates an isolated project and exports it with the official Windows 4.7.1 release template. The exported main scene must report `debug=false` and force the native backend even when `WARGAME_COMPUTE_BACKEND=gdscript`. Removing only the fixture's packaged DLL must emit the build instruction and exit with code 1. The game DLLs are never renamed. The template and export fixtures are cached locally; `--release-template` can supply an existing official template instead of downloading it. HTTPS byte-range extraction verifies the selected ZIP member's CRC, length and SHA-256; it does not claim to verify the full 1.28 GB archive checksum. Evidence is saved to `.cache/native_shipping_evidence.json`.

The complete game's main scene can also be exported and verified:

```powershell
python scripts/tools/export_native_release.py --godot D:/ProjectICreate/Godot_v4.7.1-stable_win64.exe --verify-cache .dbg/atlas-military-eurasia-mask.bin
```

This uses the cached official release template prepared by the shipping contract, or accepts `--release-template`. It first verifies the native build manifests. The existing game source fingerprint reads original `.gd` and `.tscn` bytes, so this export requires `script_export_mode=0` and `editor/export/convert_text_resources_to_binary=false`. The tool applies the latter temporarily, verifies exact contents before restoring the original `project.godot`, and removes its temporary preset only if its contents still match. It refuses to replace an existing `export_presets.cfg`. These export conditions are required for a clean startup; default binary scene conversion otherwise causes two empty-input hashing errors in the existing fingerprint routine. No gameplay source or DLL changes are needed.

The optional cache verification launches the exported executable's actual main scene, without `--path` or `--script`. It checks the actual PID/session log, seed 1, 40 nations and the Eurasia mask (south 20, north 55, west -15, east 145), waits for a rendered screenshot, and rejects engine/script errors. It then temporarily removes only the packaged release DLL, requires an explicit native-class error and exit code 1, and restores it. Raw evidence and logs are saved under `.dbg/wargame-release/`. The game starts paused on day 0; this is a packaging/startup check, not a simulation benchmark. Export omits test scripts, documentation, build tools, C++ sources and native dependency caches.

The registration and descriptor follow [Godot's official GDExtension example](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/gdextension_cpp_example.html). Custom API and trimmed build options come from the [locked godot-cpp build system](https://github.com/godotengine/godot-cpp/blob/b051e694cf493d417f5aa945c656cb77ae9011a9/tools/godotcpp.py).

Godot 4.7.1 can crash on first-scan shutdown while extension documentation is still queued ([upstream report](https://github.com/godotengine/godot-cpp/issues/2024)). The shipping contract allows capped editor frames before its strict `--import` check; every process must still exit successfully.

The runtime interface is API **4**. The adapter rejects older DLLs. CSR topology and geometry remain immutable, while `pack_edge_inputs` captures current jurisdiction controls alongside edge costs in its single native property-reading pass. `make_access_mask` accepts these explicit controls, and `patch_access_mask` applies already-permitted goal/exit exceptions against the same control snapshot. Frozen phases publish their masks and controls before workers start; standalone calls and subsequent phases observe direct `Edge.control_city_id` changes even when graph revisions and node/edge counts are unchanged. Invalid jurisdiction IDs remain inaccessible, matching the existing Atlas rule. These helpers do not change military or logistics permissions.

API 3 adds `query_administrative_fields(cities, adjacency, edge_lookup, nations, capitals, traffic_kind)`. This frozen boundary query reads the live directed road graph once for a fiscal batch, without using the cached CSR. The two FIFO queues preserve the reference's exact integer hop counts and dictionary insertion order: entering traffic costs zero, entering a settlement costs one, and every road jurisdiction must belong to the querying country. The result is a `fields` dictionary keyed by requested country; invalid, foreign or traffic capitals return an empty field. The adapter disables dead-country capitals and checks complete batches against GDScript in development compare mode. Monthly garrison costs use this batch for the canonical Atlas `GameState`; legacy maps and custom state callbacks keep their existing calculation path.

API 4 adds `query_key_order(keys)`, returning a `PackedInt32Array` permutation of integer rows. It uses Godot introsort with the same lexicographic comparison, preserving equal-key permutations without adding army IDs as tie breakers. Atlas nation-relative and mirror-orbit army batches of at least 16 items use this kernel; key generation stays in GDScript. Smaller lists, legacy worlds and the GDScript test backend retain their existing sort. Development compare mode checks the entire permutation.
