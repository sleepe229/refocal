"""Validate the isolated GroupNorm experiment before interpreting its evidence."""

import unittest

import torch
from webphoto_context_eval import FrozenGroupNorm, capture, shared_stats, tiled, whole


class SharedContextTest(unittest.TestCase):
    def test_matches_original_normalization_on_the_context_itself(self):
        torch.manual_seed(7)
        norm = torch.nn.GroupNorm(2, 8).eval()
        with torch.no_grad():
            norm.weight.uniform_(0.2, 2)
            norm.bias.uniform_(-1, 1)
            for image in (torch.randn(1, 8, 9, 13), torch.ones(1, 8, 9, 13)):
                frozen = FrozenGroupNorm(norm, image)
                torch.testing.assert_close(frozen(image), norm(image), atol=2e-5, rtol=1e-5)

    def test_capture_preserves_output_and_shared_stats_are_restored_on_failure(self):
        model = torch.nn.Sequential(torch.nn.GroupNorm(2, 8), torch.nn.GroupNorm(4, 8))
        image = torch.randn(1, 8, 9, 13)
        original = dict(model.named_modules())
        with torch.inference_mode():
            expected = model(image)
            output, stats = capture(model, image)
            torch.testing.assert_close(output, expected, atol=0, rtol=0)
            with self.assertRaisesRegex(RuntimeError, "interrupted"), shared_stats(model, stats):
                torch.testing.assert_close(model(image), expected, atol=2e-5, rtol=1e-5)
                raise RuntimeError("interrupted")
            self.assertEqual(dict(model.named_modules()), original)
            torch.testing.assert_close(model(image), expected, atol=0, rtol=0)

    def test_rejects_nonfinite_statistics_and_multiple_images(self):
        norm = torch.nn.GroupNorm(2, 8)
        for image in (torch.full((1, 8, 3, 3), torch.nan), torch.zeros(2, 8, 3, 3)):
            with self.assertRaises(ValueError):
                FrozenGroupNorm(norm, image)

    def test_tiling_covers_image_including_shifted_last_tile(self):
        model = torch.nn.Upsample(scale_factor=4, mode="nearest")
        image = torch.rand(1, 3, 384, 384)
        for tile in (128, 256):
            torch.testing.assert_close(
                tiled(model, image, tile), whole(model, image), atol=0, rtol=0
            )


if __name__ == "__main__":
    unittest.main()
