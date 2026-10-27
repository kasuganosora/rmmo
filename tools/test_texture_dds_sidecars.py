"""CPU-only DDS packaging regression. All generated files stay outside Godot."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import unittest
from unittest.mock import patch

from PIL import Image
import generate_texture_dds_sidecars as package

OUTPUT = None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def levels(path):
    raw = path.read_bytes()
    height, width = struct.unpack_from("<II", raw, 12)
    count = max(1, struct.unpack_from("<I", raw, 28)[0])
    block = 16 if raw[84:88] in (b"DXT5", b"ATI2") else 8
    at = 128
    result = []
    for _ in range(count):
        size = max(1, (width + 3) // 4) * max(1, (height + 3) // 4) * block
        header = bytearray(raw[:128])
        struct.pack_into("<II", header, 12, height, width)
        struct.pack_into("<I", header, 20, size)
        struct.pack_into("<I", header, 28, 1)
        image = Image.open(io.BytesIO(header + raw[at:at + size])).convert("RGBA")
        result.append((width, height, size, image))
        at += size
        width, height = max(1, width // 2), max(1, height // 2)
    if at != len(raw):
        raise AssertionError((at, len(raw)))
    return result


class SidecarTests(unittest.TestCase):
    def source(self, name, color=(90, 150, 220, 255), size=(16, 8)):
        path = OUTPUT / name
        Image.new("RGBA", size, color).save(path)
        return path

    def test_green_flip_preserves_uv_rows_and_other_channels(self):
        image = Image.new("RGBA", (4, 4))
        image.putdata([(x * 31, y * 53, 210 - x * 5, 170 + y) for y in range(4) for x in range(4)])
        transformed = package.flip_normal_green(image)
        for y in range(4):
            for x in range(4):
                before, after = image.getpixel((x, y)), transformed.getpixel((x, y))
                self.assertEqual(after, (before[0], 255 - before[1], before[2], before[3]))

    def test_complete_mip_chain(self):
        for name, color, dimensions in [("opaque.png", (90, 150, 220, 255), (16, 8)),
                                         ("alpha.png", (90, 150, 220, 91), (32, 16)),
                                         ("non_power_two.png", (90, 150, 220, 255), (12, 8))]:
            source = self.source(name, color, dimensions)
            before = digest(source)
            self.assertEqual(package.process(source, True), (1, 0, 0))
            sidecar = source.with_name(source.name + (".dxt1.dds" if color[3] == 255 else ".dxt5.dds"))
            chain = levels(sidecar)
            self.assertEqual(chain[-1][:2], (1, 1))
            self.assertEqual(len(chain), max(dimensions).bit_length())
            for _, _, _, image in chain:
                self.assertLessEqual(max(abs(a - b) for a, b in zip(image.getpixel((0, 0)), color)), 8)
            self.assertEqual(digest(source), before)

    def test_normal_orientation_dds(self):
        source = self.source("normal.png", (96, 64, 240, 255), (8, 8))
        before = digest(source)
        self.assertEqual(package.process(source, True), (2, 0, 0))
        flipped = levels(source.with_name(source.name + ".flip.bc5.dds"))
        for _, _, _, image in flipped:
            expected = (96, 191, 0, 255)
            self.assertLessEqual(max(abs(a - b) for a, b in zip(image.getpixel((0, 0)), expected)), 8)
        self.assertEqual(digest(source), before)

    def test_declared_normal_role_survives_content_hash_filename(self):
        source = self.source("a" * 64 + ".png", (96, 64, 240, 255), (8, 8))
        self.assertFalse(package.is_normal(source))
        self.assertEqual(package.process(source, True, normal=True), (2, 0, 0))
        flipped = levels(source.with_name(source.name + ".flip.bc5.dds"))
        self.assertLessEqual(abs(flipped[0][3].getpixel((0, 0))[1] - 191), 8)

    def test_partial_blocks_generate_complete_mips_for_each_declared_role(self):
        # These are staged test sources, not user assets. The source dimensions
        # remain unchanged while every compressed mip rounds its own blocks.
        for dimensions in ((5, 5), (6, 6), (7, 11), (1254, 1254)):
            for role, color in (("bc1", (96, 64, 240, 255)),
                                ("bc3", (96, 64, 240, 83)),
                                ("bc5", (96, 64, 240, 255))):
                with self.subTest(dimensions=dimensions, role=role):
                    source = self.source(f"{dimensions[0]}x{dimensions[1]}_{role}.png", color, dimensions)
                    before = digest(source)
                    normal = role == "bc5"
                    self.assertEqual(package.process(source, False, normal=normal),
                                     (2 if normal else 1, 0, 0))
                    suffixes = (".bc5.dds", ".flip.bc5.dds") if normal else (
                        ".dxt5.dds" if role == "bc3" else ".dxt1.dds",)
                    for suffix in suffixes:
                        target = source.with_name(source.name + suffix)
                        chain = levels(target)
                        self.assertEqual(chain[0][:2], dimensions)
                        self.assertEqual(len(chain), max(dimensions).bit_length())
                        self.assertEqual(chain[-1][:2], (1, 1))
                        expected_g = 255 - color[1] if suffix.startswith(".flip") else color[1]
                        for width, height, _, image in chain:
                            for point in ((0, 0), (width - 1, height - 1)):
                                pixel = image.getpixel(point)
                                self.assertLessEqual(abs(pixel[0] - color[0]), 8)
                                self.assertLessEqual(abs(pixel[1] - expected_g), 8)
                                if not normal:
                                    self.assertLessEqual(abs(pixel[2] - color[2]), 8)
                                    self.assertLessEqual(abs(pixel[3] - color[3]), 8)
                    self.assertEqual(digest(source), before)

    def test_partial_block_source_retains_color_and_normal_roles(self):
        for order in ((False, True), (True, False)):
            with self.subTest(order=order):
                source = self.source(f"partial_roles_{order[0]}.png", size=(13, 7))
                self.assertEqual(package.process(source, True, normal=order[0])[2], 0)
                first = source.with_name(source.name + (".bc5.dds" if order[0] else ".dxt1.dds"))
                self.assertTrue(first.exists())
                before = digest(first)
                self.assertEqual(package.process(source, True, normal=order[1])[2], 0)
                self.assertEqual(digest(first), before)
                self.assertTrue(source.with_name(source.name + ".bc5.dds").exists())
                self.assertTrue(source.with_name(source.name + ".dxt1.dds").exists())

    def test_bc5_retires_only_unambiguous_normal_aliases(self):
        source = self.source("replacement_normal.png")
        old = source.with_name(source.name + ".dxt5.dds")
        flipped = source.with_name(source.name + ".flip.dxt5.dds")
        with Image.open(source) as pixels:
            self.assertTrue(package.save_dds(pixels, old, True))
            self.assertTrue(package.save_dds(pixels, flipped, True))
        original = digest(old)
        self.assertEqual(package.process(source, True), (2, 0, 0))
        self.assertEqual(digest(old), original)  # May still be used as a color image.
        self.assertFalse(flipped.exists())
        candidate = source.with_name(source.name + ".bc5.dds")
        self.assertEqual(candidate.read_bytes()[84:88], b"ATI2")
        self.assertEqual(levels(candidate)[-1][:2], (1, 1))

    def test_same_source_color_and_normal_survive_both_build_orders(self):
        for order in [(False, True), (True, False)]:
            with self.subTest(order=order):
                source = self.source("shared_" + str(order[0]) + ".png")
                self.assertEqual(package.process(source, True, normal=order[0])[2], 0)
                first = source.with_name(source.name + (".bc5.dds" if order[0] else ".dxt1.dds"))
                original = digest(first)
                self.assertEqual(package.process(source, True, normal=order[1])[2], 0)
                self.assertTrue(first.exists(), "building another role must retain existing role")
                self.assertEqual(digest(first), original)
                self.assertTrue(source.with_name(source.name + ".bc5.dds").exists())
                self.assertTrue(source.with_name(source.name + ".dxt1.dds").exists())

    def test_partial_size_without_overwrite_preserves_both_roles(self):
        source = self.source("resized.png")
        package.process(source, True, normal=False)
        package.process(source, True, normal=True)
        before = {path: digest(path) for path in OUTPUT.glob("resized.png.*.dds")}
        Image.new("RGBA", (13, 7), (90, 150, 220, 255)).save(source)
        self.assertEqual(package.process(source, False, normal=False), (0, 1, 0))
        self.assertEqual({path: digest(path) for path in before}, before)

    def test_format_change_removes_obsolete_preferred_sibling(self):
        source = self.source("changed.png", (90, 150, 220, 80))
        self.assertEqual(package.process(source, True), (1, 0, 0))
        old = source.with_name(source.name + ".dxt5.dds")
        self.assertTrue(old.exists())
        Image.new("RGBA", (16, 8), (90, 150, 220, 255)).save(source)
        self.assertEqual(package.process(source, True), (1, 0, 0))
        self.assertFalse(old.exists())
        self.assertTrue(source.with_name(source.name + ".dxt1.dds").exists())

    def test_failed_rebuild_keeps_previous_siblings(self):
        source = self.source("failed.png")
        previous = source.with_name(source.name + ".dxt5.dds")
        previous.write_bytes(b"previous version")
        with patch.object(package, "save_dds", return_value=False):
            self.assertEqual(package.process(source, True), (0, 0, 1))
        self.assertEqual(previous.read_bytes(), b"previous version")

    def test_failed_encode_write_or_publish_keeps_valid_target(self):
        source = self.source("atomic.png")
        self.assertEqual(package.process(source, True), (1, 0, 0))
        target = source.with_name(source.name + ".dxt1.dds")
        before = digest(target)
        pixels = Image.new("RGBA", (16, 8), (220, 30, 40, 255))
        staging = target.with_suffix(target.suffix + ".tmp")
        for owner, method in [(Image.Image, "save"), (Path, "write_bytes"), (Path, "replace")]:
            with self.subTest(stage=method):
                with patch.object(owner, method, side_effect=OSError("injected " + method)):
                    self.assertFalse(package.save_dds(pixels, target, False))
                self.assertEqual(digest(target), before)
                self.assertFalse(staging.exists())
                self.assertEqual(levels(target)[-1][:2], (1, 1))

    def test_no_overwrite_preserves_existing_files(self):
        source = self.source("preserved.png")
        self.assertEqual(package.process(source, True), (1, 0, 0))
        sidecar = source.with_name(source.name + ".dxt1.dds")
        before = digest(sidecar)
        self.assertEqual(package.process(source, False), (0, 1, 0))
        self.assertEqual(digest(sidecar), before)


def main():
    global OUTPUT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    OUTPUT = args.output.resolve()
    project = Path(__file__).resolve().parents[1]
    if OUTPUT == project or project in OUTPUT.parents:
        raise ValueError("Generated texture fixtures must stay outside the Godot project")
    OUTPUT.mkdir(parents=True, exist_ok=False)
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SidecarTests))
    fixtures = []
    for path in sorted(OUTPUT.glob("*.dds")):
        if path.name == "failed.png.dxt5.dds":
            continue
        chain = levels(path)
        fixtures.append({"path": str(path), "sha256": digest(path), "width": chain[0][0],
                         "height": chain[0][1], "mipmaps": len(chain) - 1,
                         "image_bytes": sum(level[2] for level in chain)})
    manifest = {"tests": result.testsRun, "success": result.wasSuccessful(), "fixtures": fixtures,
                "sources": {str(p): digest(p) for p in OUTPUT.glob("*.png")}}
    (OUTPUT / "fixtures.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
