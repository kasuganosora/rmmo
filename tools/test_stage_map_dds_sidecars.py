"""Offline-only map DDS stage tests; all fixtures live in an external directory."""
import argparse
from contextlib import contextmanager
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

from PIL import Image
from generate_texture_dds_sidecars import save_dds
import stage_map_dds_sidecars as stage

OUTPUT = None

def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()

def pack_snapshot(root):
    return {str(p.relative_to(root)): sha_bytes(p.read_bytes())
            for p in root.rglob("*") if p.is_file()}

def make_directory_link(link, target):
    try:
        os.symlink(target, link, target_is_directory=True)
    except OSError:
        if os.name != "nt":
            raise
        result = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)],
                                capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode:
            raise OSError(result.stderr.decode(errors="replace"))

class StageTests(unittest.TestCase):
    def fixture(self, suffix=""):
        root = OUTPUT / (self._testMethodName + suffix)
        pack = root / "pack"
        source_dir = pack / "assets"
        source_dir.mkdir(parents=True)
        map_file = pack / "map.gltf"
        map_file.write_bytes(b"fake map manifest")
        output = root / "stage"
        return root, pack, source_dir, map_file, output

    def make_source(self, directory, name, color=(96, 64, 240, 255)):
        buffer = io.BytesIO()
        Image.new("RGBA", (13, 7), color).save(buffer, format="PNG")
        data = buffer.getvalue()
        if name == "hash": name = sha_bytes(data) + ".png"
        path = directory / name
        path.write_bytes(data)
        return path

    def inventory(self, root, map_file, rows):
        path = root / "audit.json"
        path.write_text(json.dumps({"map": str(map_file), "map_sha256": sha_bytes(map_file.read_bytes()),
            "map_unchanged": True, "errors": [], "texture_variants": rows}), encoding="utf-8")
        return path

    def row(self, source, normal=False, flip=False):
        return {"source": str(source), "normal_role": normal, "flip_normal_green": flip,
                "fields": ["normal_path" if normal else "texture_path"], "selected_sidecar": ""}

    def test_declared_hash_normal_and_color_flip_dedup_without_pack_writes(self):
        root, pack, folder, map_file, output = self.fixture()
        a = self.make_source(folder, "hash")
        b = folder / "other.png"
        b.write_bytes(a.read_bytes())
        rows = [self.row(a,True), self.row(a,True), self.row(a,True,True),
                self.row(a), self.row(b,True)]
        audit = self.inventory(root, map_file, rows)
        before = pack_snapshot(pack)
        result = stage.stage(audit, pack, output)
        self.assertEqual(pack_snapshot(pack), before)
        self.assertEqual(len(result["targets"]), 4)
        self.assertEqual(len(result["blobs"]), 3)
        normal = [r for r in result["targets"] if r["role"] == "normal" and not r["flip"]]
        self.assertEqual(len(normal), 2)
        self.assertEqual(normal[0]["blob_sha256"], normal[1]["blob_sha256"])
        self.assertTrue(all(r["target"].endswith(".bc5.dds") for r in normal))
        self.assertTrue(any(r["target"].endswith(".flip.bc5.dds") for r in result["targets"]))
        self.assertTrue(any(r["target"].endswith(".dxt1.dds") for r in result["targets"]))
        for blob in result["blobs"]:
            f=output / blob["path"]
            self.assertEqual(sha_bytes(f.read_bytes()), blob["sha256"])
            self.assertEqual(blob["width"],13)
            self.assertEqual(blob["height"],7)

    def test_existing_role_sidecar_preserved_and_missing_other_role_is_staged(self):
        root, pack, folder, map_file, output = self.fixture()
        a = self.make_source(folder, "x.png")
        old=a.with_name(a.name+".bc5.dds");old.write_bytes(b"do not replace")
        audit=self.inventory(root,map_file,[self.row(a),self.row(a,True)])
        before=pack_snapshot(pack)
        result=stage.stage(audit,pack,output)
        self.assertEqual(pack_snapshot(pack),before)
        self.assertEqual(len(result["targets"]),1)
        self.assertEqual(result["targets"][0]["role"],"color")
        self.assertEqual(len(result["skipped"]),1)

    def test_existing_legacy_normal_fallback_is_not_replaced(self):
        root, pack, folder, map_file, output = self.fixture()
        a = self.make_source(folder, "a.png")
        old = a.with_name(a.name + ".dxt5.dds")
        old.write_bytes(b"existing normal fallback")
        audit = self.inventory(root, map_file, [self.row(a, True)])
        before = pack_snapshot(pack)
        result = stage.stage(audit, pack, output)
        self.assertEqual(pack_snapshot(pack), before)
        self.assertEqual(result["targets"], [])
        self.assertEqual(len(result["skipped"]), 1)

    def test_invalid_selected_sidecar_is_not_reported_as_usable_fallback(self):
        root, pack, folder, map_file, output = self.fixture()
        a = self.make_source(folder, "a.png")
        invalid = a.with_name(a.name + ".bc5.dds")
        invalid.write_bytes(b"invalid preferred DDS")
        fallback = a.with_name(a.name + ".dxt5.dds")
        self.assertTrue(save_dds(Image.new("RGBA", (13, 7), (40, 60, 90, 80)), fallback, True))
        audit = self.inventory(root, map_file, [self.row(a, True)])
        before = pack_snapshot(pack)
        result = stage.stage(audit, pack, output)
        self.assertEqual(pack_snapshot(pack), before)
        self.assertEqual(result["targets"], [])
        selected = result["skipped"][0]
        self.assertEqual(selected["selection_status"], "selected_unusable")
        self.assertTrue(selected["selected"].endswith(".bc5.dds"))
        self.assertEqual(len(selected["existing"]), 2)
        self.assertFalse(selected["freshness_verified"])
        invalid.unlink()
        later = stage.stage(audit, pack, root / "stage_fallback")
        self.assertEqual(later["skipped"][0]["selection_status"], "header_usable")
        self.assertTrue(later["skipped"][0]["selected"].endswith(".dxt5.dds"))

    def test_rejects_source_outside_pack_without_writes(self):
        root, pack, folder, map_file, output = self.fixture()
        outside=self.make_source(root,"outside.png")
        audit=self.inventory(root,map_file,[self.row(outside)])
        before=pack_snapshot(pack)
        with self.assertRaises(ValueError):stage.stage(audit,pack,output)
        self.assertEqual(pack_snapshot(pack),before)
        self.assertFalse(output.exists())

    def test_rejects_link_escaping_pack_without_writes(self):
        root, pack, folder, map_file, output = self.fixture()
        outside_dir=root/"outside_dir";outside_dir.mkdir()
        self.make_source(outside_dir,"outside.png")
        link=folder/"linked_dir"
        make_directory_link(link,outside_dir)
        audit=self.inventory(root,map_file,[self.row(link/"outside.png")])
        with self.assertRaises(ValueError):stage.stage(audit,pack,output)
        self.assertFalse(output.exists())
        self.assertFalse((outside_dir/"outside.png.dxt1.dds").exists())

    def test_opened_source_handle_rejects_ancestor_swapped_to_junction(self):
        root, pack, folder, map_file, output = self.fixture()
        a = self.make_source(folder, "a.png")
        outside = root / "outside_dir"; outside.mkdir()
        self.make_source(outside, "a.png", (1, 2, 3, 255))
        audit = self.inventory(root, map_file, [self.row(a)])
        original = stage._read
        moved = pack / "original_assets"
        swapped = False
        def exchange(path, selected_root):
            nonlocal swapped
            if path == a and not swapped:
                folder.rename(moved)
                make_directory_link(folder, outside)
                swapped = True
            return original(path, selected_root)
        with patch.object(stage, "_read", side_effect=exchange):
            with self.assertRaisesRegex(ValueError, "escaped"):stage.stage(audit, pack, output)
        self.assertTrue(swapped)
        self.assertFalse((output / "COMPLETE").exists())
        self.assertFalse((outside / "a.png.dxt1.dds").exists())

    def test_output_parent_junction_swap_cannot_write_into_pack(self):
        root, pack, folder, map_file, _ = self.fixture()
        a = self.make_source(folder, "a.png")
        audit = self.inventory(root, map_file, [self.row(a)])
        outbox = root / "outbox"; outbox.mkdir()
        output = outbox / "stage"
        before = pack_snapshot(pack)
        hold = stage._hold_output_parents
        @contextmanager
        def exchange(parent):
            outbox.rename(root / "outbox_saved")
            make_directory_link(outbox, pack)
            with hold(parent):
                yield
        with patch.object(stage, "_hold_output_parents", side_effect=exchange):
            with self.assertRaises(ValueError):stage.stage(audit, pack, output)
        self.assertEqual(pack_snapshot(pack), before)
        self.assertFalse((pack / "stage").exists())
        self.assertEqual(list(pack.glob(".rmmo-dds-stage-*")), [])

    def test_new_temporary_directory_cannot_be_replaced_by_pack_junction(self):
        root, pack, folder, map_file, output = self.fixture()
        source = self.make_source(folder, "a.png")
        audit = self.inventory(root, map_file, [self.row(source)])
        before = pack_snapshot(pack)
        original = Path.mkdir
        def swap(path, *args, **kwargs):
            original(path, *args, **kwargs)
            if path == output:
                path.rename(root / "moved_temporary")
                make_directory_link(path, pack)
        with patch.object(Path, "mkdir", new=swap):
            with self.assertRaises((ValueError, RuntimeError)):stage.stage(audit, pack, output)
        self.assertEqual(pack_snapshot(pack), before)
        self.assertTrue(stage._link(output))
        self.assertFalse((pack / "COMPLETE").exists())

    def test_new_blobs_directory_cannot_be_replaced_by_pack_junction(self):
        root, pack, folder, map_file, output = self.fixture()
        source = self.make_source(folder, "a.png")
        audit = self.inventory(root, map_file, [self.row(source)])
        before = pack_snapshot(pack)
        original = Path.mkdir
        swapped = False
        def swap(path, *args, **kwargs):
            nonlocal swapped
            original(path, *args, **kwargs)
            if path.name == "blobs" and not swapped:
                swapped = True
                path.rename(root / "moved_blobs")
                make_directory_link(path, pack)
        with patch.object(Path, "mkdir", new=swap):
            with self.assertRaises((ValueError, RuntimeError)):stage.stage(audit, pack, output)
        self.assertEqual(pack_snapshot(pack), before)
        self.assertFalse((output / "COMPLETE").exists())

    def test_preexisting_encoder_temporary_hardlink_cannot_change_other_file(self):
        root, pack, folder, map_file, output = self.fixture()
        source = self.make_source(folder, "a.png")
        audit = self.inventory(root, map_file, [self.row(source)])
        before = pack_snapshot(pack)
        victim = root / "victim.bin"; victim.write_bytes(b"external bytes")
        original = stage._encode
        def hijack(image, role, flip, destination, alpha):
            tmp = destination.with_suffix(destination.suffix + ".tmp")
            os.link(victim, tmp)
            return original(image, role, flip, destination, alpha)
        with patch.object(stage, "_encode", side_effect=hijack):
            try:stage.stage(audit, pack, output)
            except (OSError, ValueError):pass
        self.assertEqual(victim.read_bytes(), b"external bytes")
        self.assertEqual(pack_snapshot(pack), before)

    def test_changed_completed_blob_is_not_reported_as_complete(self):
        root, pack, folder, map_file, output = self.fixture()
        source = self.make_source(folder, "a.png")
        audit = self.inventory(root, map_file, [self.row(source, True), self.row(source, True, True)])
        before = pack_snapshot(pack)
        original = stage._encode
        count = 0
        def mutate(image, role, flip, destination, alpha):
            nonlocal count
            count += 1
            if count == 2:
                first = next(destination.parent.glob("*.dds"))
                first.write_bytes(b"changed after encoding")
            return original(image, role, flip, destination, alpha)
        with patch.object(stage, "_encode", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "blob changed"):stage.stage(audit, pack, output)
        self.assertEqual(pack_snapshot(pack), before)
        self.assertFalse((output / "COMPLETE").exists())

    def test_failed_stage_never_deletes_a_replaced_blob(self):
        root, pack, folder, map_file, output = self.fixture()
        source = self.make_source(folder, "a.png")
        audit = self.inventory(root, map_file, [self.row(source, True), self.row(source, True, True)])
        original = stage._encode
        replaced = []
        def exchange(image, role, flip, destination, alpha):
            if flip:
                first = next(destination.parent.glob("*.dds"))
                first.unlink()
                first.write_bytes(b"independent replacement")
                replaced.append(first)
                raise OSError("injected failure after replacement")
            return original(image, role, flip, destination, alpha)
        with patch.object(stage, "_encode", side_effect=exchange):
            with self.assertRaisesRegex(OSError, "injected failure"):stage.stage(audit, pack, output)
        self.assertEqual(len(replaced), 1)
        self.assertEqual(replaced[0].read_bytes(), b"independent replacement")
        self.assertFalse((output / "COMPLETE").exists())

    def test_completion_marker_is_created_only_after_manifest_write(self):
        root, pack, folder, map_file, output = self.fixture()
        source = self.make_source(folder, "a.png")
        audit = self.inventory(root, map_file, [self.row(source)])
        original = stage._write_exclusive
        observed = []
        def observe(path, parent, data):
            if path.name == "manifest.json":
                observed.append((output / "COMPLETE").exists())
                original(path, parent, data)
                observed.append((output / "COMPLETE").exists())
            else:
                original(path, parent, data)
        with patch.object(stage, "_write_exclusive", side_effect=observe):
            result = stage.stage(audit, pack, output)
        self.assertEqual(observed, [False, False])
        self.assertEqual((output / "COMPLETE").read_bytes(), b"")
        self.assertEqual(json.loads((output / "manifest.json").read_text(encoding="utf-8")), result)

    def test_source_mutation_during_encode_fails_without_publishing(self):
        root, pack, folder, map_file, output = self.fixture()
        a=self.make_source(folder,"a.png")
        audit=self.inventory(root,map_file,[self.row(a)])
        original=stage._encode
        def mutate(*args,**kwargs):
            encoded=original(*args,**kwargs)
            self.make_source(folder,"a.png",(1,2,3,255))
            return encoded
        with patch.object(stage,"_encode",side_effect=mutate):
            with self.assertRaisesRegex(ValueError,"changed"):stage.stage(audit,pack,output)
        self.assertFalse((output / "COMPLETE").exists())
        self.assertEqual(list(folder.glob("*.dds")),[])

    def test_encoder_failure_preserves_incomplete_stage_and_does_not_touch_pack(self):
        root, pack, folder, map_file, output = self.fixture()
        a=self.make_source(folder,"a.png")
        audit=self.inventory(root,map_file,[self.row(a)])
        before=pack_snapshot(pack)
        with patch.object(stage,"_encode",side_effect=OSError("injected")):
            with self.assertRaisesRegex(OSError,"injected"):stage.stage(audit,pack,output)
        self.assertEqual(pack_snapshot(pack),before)
        self.assertTrue(output.is_dir())
        self.assertFalse((output / "COMPLETE").exists())

    def test_generator_change_during_encode_fails_without_publishing(self):
        root, pack, folder, map_file, output = self.fixture()
        a = self.make_source(folder, "a.png")
        audit = self.inventory(root, map_file, [self.row(a)])
        before = pack_snapshot(pack)
        generator_copy = root / "generator.py"
        generator_copy.write_bytes(stage.GENERATOR_SOURCE)
        original = stage._encode
        def mutate(*args, **kwargs):
            encoded = original(*args, **kwargs)
            generator_copy.write_bytes(stage.GENERATOR_SOURCE + b"\n# modified during encoding\n")
            return encoded
        with patch.object(stage, "GENERATOR_PATH", generator_copy):
            with patch.object(stage, "_encode", side_effect=mutate):
                with self.assertRaisesRegex(ValueError, "source changed"):stage.stage(audit, pack, output)
        self.assertEqual(pack_snapshot(pack), before)
        self.assertTrue(output.is_dir())
        self.assertFalse((output / "COMPLETE").exists())

    def test_shared_source_alpha_scanned_once(self):
        root, pack, folder, map_file, output = self.fixture()
        source = self.make_source(folder, "original.png", (70, 80, 90, 64))
        rows = []
        for i in range(5):
            copy = folder / f"copy_{i}.png"; copy.write_bytes(source.read_bytes())
            rows.append(self.row(copy))
        audit = self.inventory(root, map_file, rows)
        with patch.object(stage, "has_alpha", wraps=stage.has_alpha) as measured:
            result = stage.stage(audit, pack, output)
        self.assertEqual(len(result["targets"]), 5)
        self.assertEqual(len(result["blobs"]), 1)
        self.assertEqual(measured.call_count, 1)

    def test_staged_normal_flip_changes_green_without_reversing_uv_rows(self):
        root, pack, folder, map_file, output = self.fixture()
        a = folder / "pattern.png"
        image = Image.new("RGBA", (13, 7))
        image.putdata([(96, 40 if y < 4 else 210, 240, 255) for y in range(7) for _ in range(13)])
        image.save(a)
        audit = self.inventory(root, map_file, [self.row(a, True), self.row(a, True, True)])
        result = stage.stage(audit, pack, output)
        for target in result["targets"]:
            with Image.open(io.BytesIO((output / target["blob"]).read_bytes())) as decoded:
                rgba = decoded.convert("RGBA")
                for y, expected in ((1, 40), (5, 210)):
                    if target["flip"]:expected = 255 - expected
                    self.assertLessEqual(abs(rgba.getpixel((1, y))[1] - expected), 8)

    def test_bad_roles_and_stale_map_fail_without_writes(self):
        for case in ("bad_role","stale_map"):
            with self.subTest(case=case):
                root,pack,folder,map_file,output=self.fixture(case)
                a=self.make_source(folder,"a.png")
                row=self.row(a)
                if case=="bad_role":row["fields"]=["normal_path"]
                audit=self.inventory(root,map_file,[row])
                if case=="stale_map":map_file.write_bytes(b"changed")
                before=pack_snapshot(pack)
                with self.assertRaises(ValueError):stage.stage(audit,pack,output)
                self.assertEqual(pack_snapshot(pack),before)
                self.assertFalse(output.exists())

def main():
    global OUTPUT
    parser=argparse.ArgumentParser()
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    OUTPUT=args.output.resolve()
    project=Path(__file__).resolve().parents[1]
    if OUTPUT == project or OUTPUT.is_relative_to(project):raise ValueError("fixtures must be outside project")
    OUTPUT.mkdir(parents=True,exist_ok=False)
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(StageTests))
    return 0 if result.wasSuccessful() else 1

if __name__=="__main__":raise SystemExit(main())
