"""Regression tests for the S11 release gates; no model weights required."""

import contextlib
import copy
import hashlib
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image
from sr_eval import NR_METRICS, SYNTHETIC, evaluate_seams, kodak, main, report


class ReleaseGateTest(unittest.TestCase):
    def setUp(self):
        self.base, self.candidate = "baseline", "candidate"
        self.rows = [
            {
                "part": "synthetic",
                "category": category,
                "eff": False,
                "model": model,
                "psnr": 30.0,
                "ssim": 0.9,
            }
            for category in SYNTHETIC
            for model in (self.base, self.candidate)
        ]
        self.rows += [
            {
                "part": "real",
                "category": "phone",
                "eff": False,
                "model": model,
                **dict.fromkeys(NR_METRICS, 0.5),
            }
            for model in (self.base, self.candidate)
        ]
        self.seams = [
            {"model": model, "tile": tile, "psnr": 50.0}
            for model in (self.base, self.candidate)
            for tile in (128, 256)
        ]

    def result(self, nr=True):
        with contextlib.redirect_stdout(io.StringIO()):
            return report(self.rows, self.seams, self.base, self.candidate, nr)

    def test_qualifies_with_two_metrics_and_psnr_within_limit(self):
        self.rows[-1][NR_METRICS[0]] = 0.4
        self.rows[1]["psnr"] = 29.7
        self.assertEqual(self.result(), 0)

    def test_rejects_when_all_real_categories_lose_two_metrics(self):
        self.rows[-1][NR_METRICS[0]] = 0.4
        self.rows[-1][NR_METRICS[1]] = 0.4
        self.assertEqual(self.result(), 1)

    def test_one_winning_category_is_enough(self):
        losing = copy.deepcopy(self.rows[-2:])
        for row in losing:
            row["category"] = "noise"
        losing[-1].update(dict.fromkeys(NR_METRICS, 0.1))
        self.rows += losing
        self.assertEqual(self.result(), 0)

    def test_no_iqa_is_not_release_evidence(self):
        self.assertEqual(self.result(nr=False), 1)

    def test_quick_run_cannot_qualify_even_with_winning_metrics(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(
                report(self.rows, self.seams, self.base, self.candidate, True, complete=False),
                1,
            )

    def test_nonfinite_seam_cannot_hide_behind_a_finite_minimum(self):
        self.seams.append({"model": self.candidate, "tile": 128, "psnr": float("nan")})
        self.assertEqual(self.result(), 1)

    def test_effective_resolution_loss_invalidates_the_category(self):
        effective = copy.deepcopy(self.rows[-2:])
        for row in effective:
            row["eff"] = True
        effective[-1].update(dict.fromkeys(NR_METRICS, 0.1))
        self.rows += effective
        self.assertEqual(self.result(), 1)

    def test_synthetic_regression_rejects_despite_nr_win(self):
        self.rows[1]["psnr"] = 29.69
        self.assertEqual(self.result(), 1)

    def test_seam_regression_rejects(self):
        self.seams[-1]["psnr"] = 44.9
        self.assertEqual(self.result(), 1)

    def test_missing_evidence_rejects(self):
        for missing in ("synthetic", "real"):
            with self.subTest(part=missing):
                saved = self.rows
                self.rows = [r for r in saved if r["part"] != missing]
                self.assertEqual(self.result(), 1)
                self.rows = saved
        self.seams = []
        self.assertEqual(self.result(), 1)

    def test_nonfinite_metrics_reject(self):
        for value in (float("nan"), float("inf")):
            with self.subTest(value=value):
                self.rows[-1][NR_METRICS[0]] = value
                self.assertEqual(self.result(), 1)

    def test_missing_or_nonfinite_synthetic_ssim_rejects(self):
        self.rows[0]["ssim"] = float("nan")
        self.assertEqual(self.result(), 1)
        del self.rows[0]["ssim"]
        self.assertEqual(self.result(), 1)


class SeamInputTest(unittest.TestCase):
    def test_failed_rerun_cannot_leave_a_stale_qualification(self):
        with tempfile.TemporaryDirectory() as directory:
            work = pathlib.Path(directory)
            for name in ("sr.json", "seams.json"):
                (work / name).write_text('{"qualified": true}')
            with (
                patch(
                    "sys.argv",
                    [
                        "sr_eval.py",
                        directory,
                        "--cli",
                        "unused",
                        "--models",
                        "unused",
                        "--seams-only",
                    ],
                ),
                patch("sr_eval.evaluate_seams", side_effect=RuntimeError("transport failed")),
                self.assertRaisesRegex(RuntimeError, "transport failed"),
            ):
                main()
            self.assertFalse((work / "sr.json").exists())
            self.assertFalse((work / "seams.json").exists())

    def test_both_tile_sizes_cross_boundaries_at_native_x2_and_x4(self):
        for scale in (2, 4):
            with self.subTest(scale=scale), tempfile.TemporaryDirectory() as directory:
                work = pathlib.Path(directory)
                (work / "src").mkdir()
                (work / "out").mkdir()
                reference = work / "kodak.png"
                Image.new("RGB", (768, 512)).save(reference)
                calls = []

                class Cli:
                    def __init__(self, calls):
                        self.calls = calls

                    def run(self, src, out, model, requested_scale, pre, tile):
                        with Image.open(src) as image:
                            source_size = image.size
                            image.resize(
                                (image.width * requested_scale, image.height * requested_scale)
                            ).save(out)
                        self.calls.append((source_size, model, requested_scale, pre, tile))

                with patch("sr_eval.kodak", return_value=reference):
                    seams = evaluate_seams(Cli(calls), work, ["candidate"], scale, [1])
                self.assertEqual(
                    calls,
                    [((384, 384), "candidate", scale, 1.0, tile) for tile in (1024, 128, 256)],
                )
                self.assertEqual([s["tile"] for s in seams], [128, 256])
                self.assertEqual(json.loads((work / "seams.json").read_text()), seams)


class KodakDownloadTest(unittest.TestCase):
    def test_retries_transport_failure_and_only_caches_verified_bytes(self):
        data = b"pinned image"
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict("sr_eval.KODAK_SHA", {1: hashlib.sha256(data).hexdigest()}),
            patch(
                "sr_eval.urllib.request.urlopen", side_effect=[OSError("TLS"), io.BytesIO(data)]
            ) as download,
            patch("sr_eval.time.sleep"),
        ):
            path = pathlib.Path(directory) / "kodim01.png"
            self.assertEqual(kodak(1, path).read_bytes(), data)
            self.assertEqual(kodak(1, path).read_bytes(), data)
            self.assertEqual(download.call_count, 2)
            self.assertFalse(path.with_suffix(".png.part").exists())

    def test_bad_hash_never_becomes_a_cached_image(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch("sr_eval.urllib.request.urlopen", return_value=io.BytesIO(b"bad image")),
        ):
            path = pathlib.Path(directory) / "kodim01.png"
            with self.assertRaisesRegex(ValueError, "sha256"):
                kodak(1, path)
            self.assertFalse(path.exists())
            self.assertFalse(path.with_suffix(".png.part").exists())


if __name__ == "__main__":
    unittest.main()
