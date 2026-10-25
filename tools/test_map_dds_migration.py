"""Tiny transactional migration fixtures; never uses an authored pack."""
import argparse
import json
import struct
from pathlib import Path
import unittest
from unittest.mock import patch

from PIL import Image
import migrate_map_texture_sidecars as migration
from generate_texture_dds_sidecars import save_dds

OUTPUT = None


class MigrationTests(unittest.TestCase):
    def fixture(self, tag=""):
        root = OUTPUT / (self._testMethodName + tag)
        pack = root / "pack"
        assets = pack / "assets"
        assets.mkdir(parents=True)
        map_path = pack / "map.json"
        map_path.write_text("{}", encoding="utf-8")
        rows = []
        for name, normal in [("color.png", False), ("normal.png", True)]:
            source = assets / name
            image = Image.new("RGBA", (16, 8), (96, 64, 240, 255))
            image.save(source)
            existing = []
            for suffix in ([".dxt5.dds", ".flip.dxt5.dds"] if normal else [".dxt1.dds"]):
                target = source.with_name(source.name + suffix)
                self.assertTrue(save_dds(image, target, normal))
                raw = bytearray(target.read_bytes())
                top_bytes = struct.unpack_from("<I", raw, 20)[0]
                struct.pack_into("<I", raw, 28, 0)
                struct.pack_into("<I", raw, 8, struct.unpack_from("<I", raw, 8)[0] & ~0x20000)
                struct.pack_into("<I", raw, 108, 0x1000)
                target.write_bytes(raw[:128 + top_bytes])  # Actual legacy top-only candidate.
                existing.append({"path": str(target), "bytes": target.stat().st_size})
            rows.append({"source": str(source), "fields": ["normal_path" if normal else "texture_path"],
                         "selected": existing[-1]["path"], "existing": existing})
        plan = root / "plan.json"
        plan.write_text(json.dumps({"map_sha256": migration.sha(map_path), "sources": rows}), encoding="utf-8")
        output = root / "stage"
        migration.stage(plan, output, pack, map_path)
        manifest_path = output / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        return manifest_path, manifest

    def originals_unchanged(self, manifest):
        for row in manifest["originals"]:
            self.assertEqual(migration.sha(Path(row["path"])), row["sha256"])
        for row in manifest["changes"]:
            if row["path"] not in {old["path"] for old in manifest["originals"]}:
                self.assertFalse(Path(row["path"]).exists())

    def test_stage_preserves_pack_then_publish_has_exact_backups(self):
        path, manifest = self.fixture()
        self.originals_unchanged(manifest)
        self.assertEqual(len(manifest["originals"]), 3)
        self.assertEqual(len(manifest["changes"]), 3)
        migration.publish(path)
        for row in manifest["changes"]:
            self.assertEqual(migration.sha(Path(row["path"])), row["sha256"])
        for row in manifest["originals"]:
            self.assertEqual(migration.sha(Path(row["backup"])), row["sha256"])
        for retired in manifest["retire"]:
            self.assertFalse(Path(retired).exists())
        receipt = json.loads(path.with_name("published.json").read_text(encoding="utf-8"))
        self.assertTrue(receipt["sources_unchanged"] and receipt["map_unchanged"])
        self.assertTrue(receipt["installed_matches_candidates"])
        self.assertEqual(receipt["installed"], [{"path": row["path"], "sha256": row["sha256"], "bytes": row["bytes"]} for row in manifest["changes"]])

    def test_failed_nth_publish_restores_exact_originals(self):
        for nth in (1, 2, 3):
            with self.subTest(nth=nth):
                path, manifest = self.fixture(str(nth))
                original = migration.atomic_copy
                calls = 0
                def fail_once(source, target):
                    nonlocal calls
                    calls += 1
                    if calls == nth:
                        raise OSError("injected nth publish")
                    return original(source, target)
                with patch.object(migration, "atomic_copy", side_effect=fail_once):
                    with self.assertRaisesRegex(OSError, "injected"):
                        migration.publish(path)
                self.originals_unchanged(manifest)
                self.assertFalse(path.with_name("published.json").exists())

    def test_failed_retirement_restores_deleted_and_replaced_files(self):
        path, manifest = self.fixture()
        original = Path.unlink
        failed = False
        target = Path(manifest["retire"][1])
        def fail_once(current, *args, **kwargs):
            nonlocal failed
            if current == target and not failed:
                failed = True
                raise OSError("injected retirement")
            return original(current, *args, **kwargs)
        with patch.object(Path, "unlink", new=fail_once):
            with self.assertRaisesRegex(OSError, "injected"):
                migration.publish(path)
        self.originals_unchanged(manifest)
        self.assertFalse(path.with_name("published.json").exists())

    def test_changed_source_rejects_before_any_sidecar_write(self):
        path, manifest = self.fixture()
        source = Path(manifest["sources"][0]["path"])
        Image.new("RGBA", (16, 8), (20, 60, 90, 255)).save(source)
        with self.assertRaisesRegex(ValueError, "changed after staging"):
            migration.publish(path)
        self.originals_unchanged(manifest)

    def test_changed_candidate_rejects_before_any_sidecar_write(self):
        path, manifest = self.fixture()
        Path(manifest["changes"][0]["staged"]).write_bytes(b"changed after review")
        with self.assertRaisesRegex(ValueError, "candidate changed"):
            migration.publish(path)
        self.originals_unchanged(manifest)


def main():
    global OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    OUTPUT = args.output.resolve()
    if OUTPUT.is_relative_to(Path(__file__).resolve().parents[1]):
        raise ValueError("Test assets must stay outside the Godot project")
    OUTPUT.mkdir(parents=True, exist_ok=False)
    with (OUTPUT / "tests.log").open("w", encoding="utf-8") as log:
        result = unittest.TextTestRunner(stream=log, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(MigrationTests))
    print((OUTPUT / "tests.log").read_text(encoding="utf-8"))
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
