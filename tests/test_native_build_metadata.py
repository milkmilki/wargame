"""Build-input validation tests; fixtures never modify the real DLL/API cache."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("native_build", Path(__file__).resolve().parents[1] / "scripts/tools/build_native_compute.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class NativeBuildMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.native = self.root / "native"
        self.cache = self.native / ".cache"
        (self.cache / "api").mkdir(parents=True)
        (self.native / "bin").mkdir()
        self.engine = self.root / "engine.exe"
        self.engine.write_bytes(b"fixture-engine")
        self.api = self.cache / "api/extension_api.json"
        self.header = {"version_major": 4, "version_minor": 7, "version_patch": 1, "precision": "single"}
        self.api.write_text(json.dumps({"header": self.header}))
        self.patches = [patch.object(build, "NATIVE", self.native), patch.object(build, "CACHE", self.cache),
                        patch.object(build, "source_hashes", return_value={"fixture.cpp": "source-hash"})]
        for item in self.patches:
            item.start()
        self.dll = build.binary("debug")
        self.dll.write_bytes(b"fixture-dll")
        self.metadata = {"target": "debug", **build.expected_metadata(), "engine_sha256": build.sha256(self.engine),
                         "api_sha256": build.sha256(self.api), "dll_sha256": build.sha256(self.dll),
                         "source_sha256": {"fixture.cpp": "source-hash"}}
        self.write_manifest()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def write_manifest(self):
        self.dll.with_suffix(".build.json").write_text(json.dumps(self.metadata))

    def test_matching_inputs_pass(self):
        build.verify(["debug"], self.engine)

    def test_modified_dll_or_sources_rejected(self):
        self.dll.write_bytes(b"changed-dll")
        with self.assertRaisesRegex(RuntimeError, "DLL or its sources changed"):
            build.verify(["debug"], self.engine)
        self.dll.write_bytes(b"fixture-dll")
        with patch.object(build, "source_hashes", return_value={"fixture.cpp": "changed-source"}):
            with self.assertRaisesRegex(RuntimeError, "DLL or its sources changed"):
                build.verify(["debug"], self.engine)

    def test_modified_engine_or_api_rejected(self):
        self.engine.write_bytes(b"changed-engine")
        with self.assertRaisesRegex(RuntimeError, "engine_sha256"):
            build.verify(["debug"], self.engine)
        self.engine.write_bytes(b"fixture-engine")
        self.api.write_text(json.dumps({"header": self.header, "modified": True}))
        with self.assertRaisesRegex(RuntimeError, "api_sha256"):
            build.verify(["debug"], self.engine)

    def test_locked_build_options_rejected_when_manifest_differs(self):
        for key in ["godot_version", "godot_cpp_commit", "msvc_toolset", "scons", "precision", "floating_point", "architecture", "target"]:
            with self.subTest(key=key):
                original = self.metadata[key]
                self.metadata[key] = "wrong-input"
                self.write_manifest()
                with self.assertRaisesRegex(RuntimeError, key):
                    build.verify(["debug"], self.engine)
                self.metadata[key] = original

    def test_tampered_api_cache_is_regenerated(self):
        engine_stamp = self.cache / "api/engine.sha256"
        api_stamp = self.cache / "api/api.sha256"
        engine_stamp.write_text(build.sha256(self.engine))
        api_stamp.write_text("original-api-hash")

        def fake_run(args, **kwargs):
            if "--version" in args:
                return build.LOCK["godot"]["version"]
            self.assertIn("--dump-extension-api", args)
            self.api.write_text(json.dumps({"header": self.header}))
            return ""

        with patch.object(build, "run", side_effect=fake_run) as runner:
            build.export_api(self.engine)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(api_stamp.read_text().strip(), build.sha256(self.api))

    def test_wrong_api_precision_rejected(self):
        def fake_run(args, **kwargs):
            if "--version" in args:
                return build.LOCK["godot"]["version"]
            self.api.write_text(json.dumps({"header": {**self.header, "precision": "double"}}))
            return ""

        with patch.object(build, "run", side_effect=fake_run):
            with self.assertRaisesRegex(RuntimeError, "unexpected extension API header"):
                build.export_api(self.engine)

    def test_wrong_engine_version_rejected(self):
        with patch.object(build, "run", return_value="4.7.0.stable.official.other"):
            with self.assertRaisesRegex(RuntimeError, "Godot version"):
                build.export_api(self.engine)

    def test_different_msvc_patch_rejected(self):
        tools = self.root / "build_tools"
        setup = tools / "VC/Auxiliary/Build/vcvarsall.bat"
        setup.parent.mkdir(parents=True)
        setup.write_text("fixture only")
        with patch.object(build.subprocess, "check_output", return_value="VCToolsVersion=14.44.35199\n"):
            with self.assertRaisesRegex(RuntimeError, "14.44.35207"):
                build.msvc_environment(tools)

    def test_source_edit_during_compile_does_not_relabel_existing_dll(self):
        (self.native / "src").mkdir()
        for name in ["runtime_graph.cpp", "runtime_graph.hpp"]:
            (self.native / "src" / name).write_text("fixture")
        original_manifest = self.dll.with_suffix(".build.json").read_text()
        with patch.object(build.sys, "argv", ["native_build", "--godot", str(self.engine), "--target", "debug"]), \
                patch.object(build, "tool_python", return_value=self.engine), \
                patch.object(build, "godot_cpp"), patch.object(build, "export_api", return_value=self.api), \
                patch.object(build, "msvc_environment", return_value={}), patch.object(build, "run"), \
                patch.object(build, "source_hashes", side_effect=[{"fixture.cpp": "before"}, {"fixture.cpp": "after"}]):
            with self.assertRaisesRegex(RuntimeError, "changed during compilation"):
                build.main()
        self.assertEqual(self.dll.with_suffix(".build.json").read_text(), original_manifest)


if __name__ == "__main__":
    unittest.main()
