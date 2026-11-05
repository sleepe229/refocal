"""Conversion gate regressions (TEST-ML-001); no checkpoints or pnnx needed."""

import pathlib
import types
import unittest
from unittest.mock import patch

import convert_community_sr as converter
import numpy as np
import torch
from spandrel.architectures.PLKSR import RealPLKSR


class Extractor:
    def __init__(self, output):
        self.output = output

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def input(self, _, tile):
        self.tile = np.asarray(tile)
        return 0

    def extract(self, _):
        return 0, self.output(self.tile)


class Net:
    def __init__(self, output):
        self.output = output
        self.opt = types.SimpleNamespace()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def load_param(self, _):
        return 0

    def load_model(self, _):
        return 0

    def create_extractor(self):
        return Extractor(self.output)


class ConversionGateTest(unittest.TestCase):
    def check(self, output, reference=torch.zeros_like):
        with patch.object(converter.ncnn, "Net", return_value=Net(output)):
            return converter.check_conversion(
                reference, pathlib.Path("candidate"), torch.Generator().manual_seed(1)
            )

    def test_accepts_parity_at_both_unseen_sizes(self):
        scores = self.check(np.zeros_like)
        self.assertEqual([(r["height"], r["width"]) for r in scores], [(96, 96), (71, 103)])

    def test_rejects_nonfinite_output(self):
        for value in (np.nan, np.inf, -np.inf):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.check(lambda x, value=value: np.full_like(x, value))

    def test_rejects_nonfinite_reference(self):
        for value in (torch.nan, torch.inf, -torch.inf):
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.check(np.zeros_like, lambda x, value=value: torch.full_like(x, value))

    def test_rejects_wrong_shape(self):
        with self.assertRaises(ValueError):
            self.check(lambda _: np.zeros((3, 1, 1)))

    def test_rejects_low_parity(self):
        with self.assertRaisesRegex(ValueError, "TEST-ML-001"):
            self.check(lambda x: np.full_like(x, 0.1))


class DownloadUrlTest(unittest.TestCase):
    def test_drive_link(self):
        self.assertEqual(
            converter.download_url("https://drive.google.com/file/d/checkpoint"),
            "https://drive.usercontent.google.com/download?id=checkpoint&export=download&confirm=t",
        )

    def test_direct_github_link_is_preserved(self):
        url = "https://github.com/owner/repo/releases/download/v1/model.pth"
        self.assertEqual(converter.download_url(url), url)

    def test_rejects_unsupported_urls(self):
        for url in (
            "file:///tmp/model.pth",
            "http://example.com/model.pth",
            "https://drive.google.com/",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                converter.download_url(url)


class ExportAdapterTest(unittest.TestCase):
    def test_repeats_each_rgb_plane_in_upstream_order(self):
        tile = torch.arange(3 * 5 * 7, dtype=torch.float32).reshape(1, 3, 5, 7)
        for scale in (2, 4):
            with self.subTest(scale=scale):
                repeats = scale * scale
                model = types.SimpleNamespace(
                    feats=lambda x, repeats=repeats: torch.repeat_interleave(x, repeats, dim=1),
                    to_img=torch.nn.PixelShuffle(scale),
                )
                adapter = converter.RealPLKSRExport(model, scale)
                expected = model.to_img(2 * torch.repeat_interleave(tile, repeats, dim=1))
                torch.testing.assert_close(adapter(tile), expected, rtol=0, atol=0)

    def test_dysample_matches_upstream_at_unseen_rectangular_sizes(self):
        torch.manual_seed(1)
        model = RealPLKSR(
            dim=8, n_blocks=1, kernel_size=3, upscaling_factor=2, dysample=True, layer_norm=True
        ).eval()
        adapter = converter.RealPLKSRExport(model, 2).eval()
        with torch.inference_mode():
            for height, width in ((5, 7), (7, 5), (1, 3), (3, 1)):
                with self.subTest(height=height, width=width):
                    tile = torch.rand(1, 3, height, width)
                    torch.testing.assert_close(adapter(tile), model(tile), rtol=0, atol=0)


if __name__ == "__main__":
    unittest.main()
