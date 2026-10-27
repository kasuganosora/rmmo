"""Pure Python subprocess tests; no Godot, GPU, or real map is launched."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from tools.run_isolated_axel_sample import run_sample
except ModuleNotFoundError:
    from run_isolated_axel_sample import run_sample

ARTIFACTS = Path("D:/code/rmmo_runtime/review_artifacts")


class IsolationTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="axel_wrapper_test_", dir=ARTIFACTS)
        self.root = Path(self.tmp.name)
        self.content = self.root / "content"
        self.content.mkdir()
        self.map = self.content / "map.gltf"
        self.map.write_bytes(b"fixture map")
        self.source = self.content / "fixture.png"
        self.source.write_bytes(b"fixture source")
        self.blob = self.content / "candidate.dds"
        dds = bytearray(128)
        dds[:4] = b"DDS "
        struct.pack_into("<I", dds, 4, 124)
        struct.pack_into("<I", dds, 12, 2)
        struct.pack_into("<I", dds, 16, 2)
        struct.pack_into("<I", dds, 28, 1)
        dds[84:88] = b"DXT1"
        self.blob.write_bytes(dds)
        self.sidecar = Path(str(self.source) + ".dxt1.dds")
        sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
        header = {"width": 2, "height": 2, "mip_count": 1, "bytes": 128,
                  "fourcc": "DXT1", "format": "BC1"}
        manifest = {"target_root": str(self.content), "target_map": str(self.map),
                    "target_map_sha256": sha(self.map), "resource_dependencies": {}, "native": [],
                    "copied": [{"target": str(p), "sha256": sha(p)} for p in (self.source, self.blob)],
                    "candidate_targets": [{"source": str(self.source), "target": str(self.sidecar),
                                           "blob": str(self.blob), "sha256": sha(self.blob),
                                           "role": "color", "flip": False}],
                    "texture_variants": [{"source": str(self.source), "normal": False, "flip": False,
                                          "baseline_sidecar": "", "baseline_header": {},
                                          "candidate_sidecar": str(self.sidecar), "candidate_header": header}]}
        self.manifest = self.content / "fixture_manifest.json"
        self.manifest.write_text(json.dumps(manifest), encoding="utf-8")
        self.engine = self.root / "engine.exe"
        self.engine.write_bytes(b"not an engine")
        self.settings = self.root / "frozen.cfg"
        self.settings.write_bytes(b"private settings fixture")
        self.fake = self.root / "fake_runner.py"
        self.fake.write_text("import os,sys,json\nsys.path.insert(0, " + repr(str(Path(__file__).resolve().parent)) + ")\n"
                             "from isolated_fixture_lock import fixture_lock\n"
                             "root=sys.argv[sys.argv.index('--content-root')+1]\n"
                             "locked=False\ntry:\n with fixture_lock(root): pass\n"
                             "except TimeoutError:\n locked=True\n"
                             "print(json.dumps({'fixture_locked':locked,'args':sys.argv[1:],"
                             "'APPDATA':os.environ['APPDATA'],"
                             "'LOCALAPPDATA':os.environ['LOCALAPPDATA'],"
                             "'TEMP':os.environ['TEMP'],"
                             "'PYTHONDONTWRITEBYTECODE':os.environ['PYTHONDONTWRITEBYTECODE']}))\n", encoding="utf-8")
        self.args = argparse.Namespace(engine=self.engine, sample_dir=self.root / "sample",
            user_dir=self.root / "user", content_root=self.content, map_path=self.map,
            settings=self.settings, settings_sha256=hashlib.sha256(self.settings.read_bytes()).hexdigest(),
            manifest_sha256=sha(self.manifest), expected_state="A", expected_candidates=1,
            stage="map", timeout=1, traverse=True, cold_index=True, texture_profile=False)

    def tearDown(self):
        self.tmp.cleanup()

    def test_child_environment_and_inputs(self):
        original = self.settings.read_bytes()
        result = run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertEqual(result, {"exit_code": 0, "frozen_settings_unchanged": True,
                                  "private_settings_unchanged": True, "map_unchanged": True,
                                  "variants_unchanged": True})
        before = json.loads((self.args.sample_dir / "isolation.variants.before.json").read_text())
        after = json.loads((self.args.sample_dir / "isolation.variants.after.json").read_text())
        self.assertEqual(before, after)
        self.assertEqual(before["variants"][0]["source_sha256"], hashlib.sha256(self.source.read_bytes()).hexdigest())
        self.assertEqual(before["state"], "A")
        child = json.loads((self.args.sample_dir / "isolation.runner.log").read_text())
        self.assertTrue(child["fixture_locked"])
        self.assertEqual(child["APPDATA"], str(self.args.user_dir / "roaming"))
        self.assertEqual(child["LOCALAPPDATA"], str(self.args.user_dir / "local"))
        self.assertEqual(child["TEMP"], str(self.args.sample_dir / "temp"))
        self.assertEqual(child["PYTHONDONTWRITEBYTECODE"], "1")
        for value in ("--map-path", str(self.map), "--content-root", str(self.content),
                      "--traverse", "--cold-index"):
            self.assertIn(value, child["args"])
        self.assertNotIn("--texture-profile", child["args"])
        self.assertNotIn("--legacy-requeue", child["args"])
        self.assertNotIn("--suppress-sync-slow-logs", child["args"])
        self.assertEqual((self.args.user_dir / "roaming/Godot/app_userdata/rmmo/game_settings.cfg").read_bytes(), original)
        self.assertEqual(self.settings.read_bytes(), original)

    def test_rejects_bad_hash_before_output(self):
        self.args.settings_sha256 = "0" * 64
        with self.assertRaises(ValueError):
            run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertFalse(self.args.sample_dir.exists())

    def test_rejects_overlapping_mutable_root(self):
        self.args.user_dir = self.content / "user"
        with self.assertRaises(ValueError):
            run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertFalse(self.args.sample_dir.exists())

    def test_rejects_map_outside_content(self):
        self.args.map_path = self.settings
        with self.assertRaises(ValueError):
            run_sample(self.args, runner=self.fake, artifacts=self.root)

    def test_rejects_existing_sample_and_mismatched_reused_settings(self):
        run_sample(self.args, runner=self.fake, artifacts=self.root)
        with self.assertRaises(FileExistsError):
            run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.args.sample_dir = self.root / "sample2"
        private = self.args.user_dir / "roaming/Godot/app_userdata/rmmo/game_settings.cfg"
        private.write_bytes(b"changed")
        with self.assertRaises(ValueError):
            run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertEqual(private.read_bytes(), b"changed")

    def test_cross_process_fixture_lock_conflict(self):
        code = ("import sys\nfrom isolated_fixture_lock import fixture_lock\n"
                "with fixture_lock(sys.argv[1]):\n print('LOCKED',flush=True)\n sys.stdin.read(1)\n")
        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONPATH"] = str(Path(__file__).resolve().parent)
        child = subprocess.Popen([sys.executable, "-c", code, str(self.content)], env=env,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(child.stdout.readline().strip(), "LOCKED")
            with self.assertRaises(TimeoutError):
                run_sample(self.args, runner=self.fake, artifacts=self.root)
            self.assertFalse(self.args.sample_dir.exists())
        finally:
            child.communicate("x", timeout=10)
        self.assertEqual(child.returncode, 0)
        self.assertTrue(run_sample(self.args, runner=self.fake, artifacts=self.root)["map_unchanged"])

    def test_variant_b_header_and_expected_state(self):
        self.sidecar.write_bytes(self.blob.read_bytes())
        self.args.expected_state = "B"
        result = run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertTrue(result["variants_unchanged"])
        evidence = json.loads((self.args.sample_dir / "isolation.variants.before.json").read_text())
        self.assertEqual(evidence["variants"][0]["header"]["fourcc"], "DXT1")
        self.assertEqual(evidence["variants"][0]["format"], "BC1")

    def test_texture_profile_is_passed_when_enabled(self):
        self.args.texture_profile = True
        run_sample(self.args, runner=self.fake, artifacts=self.root)
        child = json.loads((self.args.sample_dir / "isolation.runner.log").read_text())
        self.assertIn("--texture-profile", child["args"])

    def test_prepack_rejected_outside_full_stage(self):
        self.args.full_native_worker_prepack = True
        with self.assertRaisesRegex(ValueError, "requires full stage"):
            run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertFalse((self.args.sample_dir / "isolation.runner.log").exists())

    def test_template_reuse_rejected_outside_full_stage(self):
        self.args.full_native_template_reuse = True
        with self.assertRaisesRegex(ValueError, "requires full stage"):
            run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertFalse((self.args.sample_dir / "isolation.runner.log").exists())

    def test_requeue_controls_are_passed_and_recorded(self):
        self.args.legacy_requeue = True
        self.args.suppress_sync_slow_logs = True
        run_sample(self.args, runner=self.fake, artifacts=self.root)
        child = json.loads((self.args.sample_dir / "isolation.runner.log").read_text())
        self.assertIn("--legacy-requeue", child["args"])
        self.assertIn("--suppress-sync-slow-logs", child["args"])
        launch = json.loads((self.args.sample_dir / "isolation.launch.json").read_text())
        self.assertIs(launch["legacy_requeue"], True)
        self.assertIs(launch["suppress_sync_slow_logs"], True)

    def test_state_mismatch_prevents_launch(self):
        self.args.expected_state = "B"
        with self.assertRaisesRegex(ValueError, "sidecar state"):
            run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertFalse((self.args.sample_dir / "isolation.runner.log").exists())

    def test_changed_stable_file_invalidates_sample(self):
        self.fake.write_text("import sys,pathlib\n"
                             "root=pathlib.Path(sys.argv[sys.argv.index('--content-root')+1])\n"
                             "(root/'fixture.png').write_bytes(b'changed')\n", encoding="utf-8")
        result = run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertFalse(result["variants_unchanged"])
        after = json.loads((self.args.sample_dir / "isolation.variants.after.json").read_text())
        self.assertFalse(after["ok"])
        self.assertIn("fixture file changed", after["error"])

    def test_manifest_changed_during_run_invalidates_sample(self):
        self.fake.write_text("import sys,pathlib\n"
                             "root=pathlib.Path(sys.argv[sys.argv.index('--content-root')+1])\n"
                             "(root/'fixture_manifest.json').write_text('{}')\n", encoding="utf-8")
        result = run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertFalse(result["variants_unchanged"])
        after = json.loads((self.args.sample_dir / "isolation.variants.after.json").read_text())
        self.assertEqual(after["error"], "fixture manifest changed")

    def test_state_changed_during_run_invalidates_sample(self):
        self.fake.write_text("import sys,pathlib\n"
                             "root=pathlib.Path(sys.argv[sys.argv.index('--content-root')+1])\n"
                             "(root/'fixture.png.dxt1.dds').write_bytes((root/'candidate.dds').read_bytes())\n", encoding="utf-8")
        result = run_sample(self.args, runner=self.fake, artifacts=self.root)
        self.assertFalse(result["variants_unchanged"])
        after = json.loads((self.args.sample_dir / "isolation.variants.after.json").read_text())
        self.assertEqual(after["state"], "B")
        self.assertFalse(after["ok"])


if __name__ == "__main__":
    unittest.main()
