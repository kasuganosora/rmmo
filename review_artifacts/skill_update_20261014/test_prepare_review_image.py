"""Behavior checks for the upload encoder using isolated synthetic screenshots."""
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageCms

SCRIPT = Path(sys.argv.pop(1)).resolve()
spec = importlib.util.spec_from_file_location("review_encoder", SCRIPT)
encoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(encoder)


def chunks(path):
    data = path.read_bytes()
    assert data[:4] == b"RIFF" and data[8:12] == b"WEBP"
    result, offset = [], 12
    while offset + 8 <= len(data):
        result.append(data[offset:offset + 4])
        length = struct.unpack_from("<I", data, offset + 4)[0]
        offset += 8 + length + length % 2
    return result


class UploadEncoding(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="encoder_", dir=SCRIPT.parents[2])
        self.root = Path(self.temp.name)
        self.im = Image.new("RGBA", (319, 181))
        self.im.putdata([((x * 13 + y * 7) % 256, (x * 3 + y * 19) % 256,
                          (x * 23 + y * 5) % 256, (x + y) % 256)
                         for y in range(181) for x in range(319)])

    def tearDown(self):
        self.temp.cleanup()

    def source(self, name="input.png", **save_options):
        path = self.root / name
        self.im.save(path, **save_options)
        return path

    def test_png_becomes_actual_lossy_webp_and_source_can_be_removed(self):
        source = self.source()
        result = encoder.prepare(source)
        target = Path(result["path"])
        self.assertIn(b"VP8 ", chunks(target))
        self.assertNotIn(b"VP8L", chunks(target))
        self.assertFalse(source.exists())
        self.assertEqual((result["quality"], result["lossless"]), (90, False))
        with Image.open(target) as actual:
            self.assertEqual(actual.size, self.im.size)
            self.assertEqual(actual.getchannel("A").tobytes(), self.im.getchannel("A").tobytes())
        self.assertEqual(json.loads(encoder.receipt_path(target).read_text())["sha256"], encoder.sha(target))

    def test_existing_lossless_webp_is_reencoded_in_place(self):
        source = self.source("input.webp", lossless=True)
        original = encoder.sha(source)
        result = encoder.prepare(source)
        self.assertEqual(Path(result["path"]), source)
        self.assertNotEqual(original, encoder.sha(source))
        self.assertIn(b"VP8 ", chunks(source))

    def test_existing_webp_keep_source_makes_upload_copy(self):
        source = self.source("input.webp", lossless=True)
        original = encoder.sha(source)
        result = encoder.prepare(source, keep_source=True)
        self.assertNotEqual(Path(result["path"]), source)
        self.assertEqual(original, encoder.sha(source))
        self.assertIn(b"VP8 ", chunks(Path(result["path"])))

    def test_second_call_does_not_accumulate_loss(self):
        first = encoder.prepare(self.source())
        second = encoder.prepare(Path(first["path"]))
        self.assertTrue(second["already_prepared"])
        self.assertEqual(first["sha256"], second["sha256"])

    def test_changed_file_cannot_reuse_stale_receipt(self):
        first = encoder.prepare(self.source())
        path = Path(first["path"])
        self.im.save(path, lossless=True)
        second = encoder.prepare(path)
        self.assertFalse(second.get("already_prepared", False))
        self.assertIn(b"VP8 ", chunks(path))

    def test_local_lossless_reference_keeps_pixels_and_upload_stays_lossy(self):
        source = self.source()
        local = encoder.prepare(source, lossless=True, keep_source=True)
        with Image.open(local["path"]) as actual:
            self.assertEqual(actual.convert("RGBA").tobytes(), self.im.tobytes())
        uploaded = encoder.prepare(Path(local["path"]), keep_source=True)
        self.assertIn(b"VP8 ", chunks(Path(uploaded["path"])))
        self.assertTrue(source.exists())
        self.assertTrue(Path(local["path"]).exists())

    def test_color_profile_and_exif_survive(self):
        profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
        exif = Image.Exif()
        exif[0x010E] = "synthetic review fixture"
        source = self.source(icc_profile=profile, exif=exif)
        result = encoder.prepare(source, keep_source=True)
        with Image.open(result["path"]) as actual:
            self.assertEqual(actual.info["icc_profile"], profile)
            self.assertEqual(actual.getexif()[0x010E], "synthetic review fixture")

    def test_unrelated_destination_is_not_overwritten(self):
        source = self.source()
        target = source.with_suffix(".webp")
        target.write_bytes(b"unrelated asset")
        with self.assertRaises(ValueError):
            encoder.prepare(source)
        self.assertEqual(target.read_bytes(), b"unrelated asset")
        self.assertTrue(source.exists())

    def test_failed_encoding_preserves_original(self):
        source = self.source("input.webp", lossless=True)
        before = encoder.sha(source)
        with patch.object(Image.Image, "save", side_effect=OSError("fixture failure")):
            with self.assertRaises(OSError):
                encoder.prepare(source)
        self.assertEqual(encoder.sha(source), before)

    def test_receipt_commit_failure_restores_inplace_original(self):
        source = self.source("input.webp", lossless=True)
        before = encoder.sha(source)
        original_replace = Path.replace

        def fail_receipt_commit(path, target):
            if str(target).endswith(".review-image.json"):
                raise OSError("fixture receipt is locked")
            return original_replace(path, target)

        with patch.object(Path, "replace", fail_receipt_commit):
            with self.assertRaises(OSError):
                encoder.prepare(source)
        self.assertEqual(encoder.sha(source), before)
        self.assertIn(b"VP8L", chunks(source))

    def test_reuse_does_not_delete_previously_retained_source(self):
        source = self.source()
        first = encoder.prepare(source, keep_source=True)
        second = encoder.prepare(source)
        self.assertTrue(second["already_prepared"])
        self.assertTrue(source.exists())
        stored = json.loads(encoder.receipt_path(Path(first["path"])).read_text())
        self.assertTrue(stored["source_retained"])

    def test_cli_default_is_quality90_and_no_base64_output(self):
        source = self.source()
        process = subprocess.run([sys.executable, "-X", "utf8", str(SCRIPT), str(source)],
                                 capture_output=True, text=True, check=True)
        result = json.loads(process.stdout)
        self.assertEqual(result["quality"], 90)
        self.assertFalse(result["lossless"])
        self.assertLess(len(process.stdout), 2000)
        self.assertIn(b"VP8 ", chunks(Path(result["path"])))


unittest.main(verbosity=2)
