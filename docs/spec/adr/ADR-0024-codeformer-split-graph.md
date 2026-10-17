# ADR-0024: CodeFormer as a split graph with the fidelity as an input

| | |
|---|---|
| Status | Accepted (2026-10-17) |
| Context | FR-FACE-005, ML-CNV-003, ADR-0011, ADR-0022 |

## Context

CodeFormer predicts, for each of the 16 × 16 tokens of a face, a code from a learned codebook
(`torch.topk(softmax(logits), 1)`), then decodes the codes with skip connections from the encoder
weighted by the fidelity w (`Fuse_sft_block`). ncnn has no top-k/scatter, and ML-CNV-003 wants w as
a graph input, not a constant. Converting the upstream module with pnnx also fails silently:

- `nn.MultiheadAttention(q, k, v)` with q = k ≠ v becomes an ncnn `MultiHeadAttention` with two
  inputs, which ncnn reads as (q, kv): the position embedding is lost from k (logits off by 5);
- pnnx takes the first axis of every tensor as the batch: 2D tensors get sliced on the wrong
  axis, `x[0]` becomes an `unbind` ncnn crashes on;
- `out_proj` (`NonDynamicallyQuantizableLinear`) and `matmul(q, k.T)` stay `F.linear` with two
  dynamic inputs, which ncnn cannot run.

## Decision

The pack holds two graphs and the codebook (`model.json` `{"split": "codeformer"}`):

1. `encoder.ncnn.*`: face [1, 3, 512, 512] in [-1, 1] → `out0` logits [256, 1024], `out1..out4`
   the encoder features at 32, 64, 128, 256 px;
2. the core takes the argmax of each logits row (first of ties, what top-k picks) and gathers the
   code from `codebook.f32` (1024 × 256, fp32) into a [256, 16, 16] feature;
3. `generator.ncnn.*`: that feature, the four features and w [1, 1, 1, 1] → face [1, 3, 512, 512].

The converter rewrites the transformer for export: explicit q, k, v and output projections as
`nn.Linear`, heads as channel slices of [1, tokens, channels] tensors, k transposed once. It checks
that the rewrite equals upstream (logits and every w) before conversion and writes the parity
report and a golden pair for `test_faces`. CodeFormer's code (S-Lab NC) is not copied into the
repository: the converter downloads the pinned upstream files.

## Consequences

(+) Exact codebook lookup in fp32 in the core; w is a live control (FR-FACE-005, default 0.7).
(+) The generator matches PyTorch at 57–59 dB on the same codes; end to end 43.9 dB at w 0.7.
(−) Two graphs to load (≈ 190 MB fp16) and a core path of its own (`FaceRestorer`).
(−) fp16 encoder: a few near-tie codes differ (252/256); at w 0 the result is 34.1 dB.
