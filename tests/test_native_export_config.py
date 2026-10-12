"""Exercise export rollback without touching the real project's configuration."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


PROJECT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("native_export_config", PROJECT / "scripts/tools/export_native_release.py")
EXPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORT)


class ExportConfigTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="native-export-config-", dir=PROJECT / ".dbg")
        self.root = Path(self.directory.name).resolve()
        assert self.root.is_relative_to((PROJECT / ".dbg").resolve())
        self.original = b'config_version=5\n[application]\nconfig/name="Fixture"\n'
        self.project = self.root / "project.godot"
        self.project.write_bytes(self.original)
        self.output = self.root / "output"
        self.output.mkdir()
        self.record = {}
        self.root_patch = patch.object(EXPORT, "ROOT", self.root)
        self.root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.directory.cleanup()

    def configured(self):
        return EXPORT.temporary_export_config(self.root / "template.exe", self.output, self.record)

    def test_restore_after_export_exception(self):
        with self.assertRaisesRegex(RuntimeError, "export failed"):
            with self.configured():
                self.assertIn(b"export/convert_text_resources_to_binary=false", self.project.read_bytes())
                raise RuntimeError("export failed")
        self.assertEqual(self.project.read_bytes(), self.original)
        self.assertFalse((self.root / "export_presets.cfg").exists())

    def test_existing_editor_setting_is_replaced_once(self):
        source = b'config_version=5\n[editor]\nexport/convert_text_resources_to_binary=true\n[rendering]\na=1\n'
        result = EXPORT.preserve_text_resources(source)
        self.assertEqual(result.count(b"export/convert_text_resources_to_binary="), 1)
        self.assertIn(b"export/convert_text_resources_to_binary=false", result)
        self.assertTrue(result.endswith(b"[rendering]\na=1\n"))

    def test_existing_preset_is_never_overwritten(self):
        preset = self.root / "export_presets.cfg"
        preset.write_bytes(b"user preset")
        with self.assertRaises(FileExistsError):
            with self.configured():
                self.fail("Should not enter export")
        self.assertEqual(preset.read_bytes(), b"user preset")
        self.assertEqual(self.project.read_bytes(), self.original)

    def test_concurrent_project_change_is_preserved_and_own_preset_removed(self):
        with self.assertRaisesRegex(RuntimeError, "project.godot changed"):
            with self.configured():
                self.project.write_bytes(b"changed concurrently")
        self.assertEqual(self.project.read_bytes(), b"changed concurrently")
        self.assertFalse((self.root / "export_presets.cfg").exists())

    def test_concurrent_preset_change_is_preserved_and_project_restored(self):
        preset = self.root / "export_presets.cfg"
        with self.assertRaisesRegex(RuntimeError, "preset changed"):
            with self.configured():
                preset.write_bytes(b"changed concurrently")
        self.assertEqual(preset.read_bytes(), b"changed concurrently")
        self.assertEqual(self.project.read_bytes(), self.original)


if __name__ == "__main__":
    unittest.main()
