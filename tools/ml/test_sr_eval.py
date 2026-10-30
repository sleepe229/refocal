"""Regression tests for the S11 release gates; no model weights required."""

import contextlib
import copy
import io
import unittest

from sr_eval import NR_METRICS, SYNTHETIC, report


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


if __name__ == "__main__":
    unittest.main()
