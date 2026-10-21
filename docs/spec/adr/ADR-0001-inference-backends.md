# ADR-0001: Inference backends

- **Статус:** Accepted
- **Дата:** 2026-10-09

## Контекст

Нужен быстрый и стабильный инференс SR- и face-моделей на Android и iOS. NNAPI устарел (Android 15), у ONNX Runtime на Android нет общего GPU-EP, ANE на iOS доступен только через Core ML.

## Решение

Общий C++ интерфейс `InferenceBackend` и реализации:
- **Android:** `NcnnVulkanBackend` (основной), `NcnnCpuBackend` (fallback).
- **iOS:** `CoreMLBackend` (Objective-C++ в native core; mlprogram fp16, `computeUnits=.all`); fallback `.cpuAndGPU` → `.cpuOnly` → `NcnnCpuBackend`.
- **R1.4** (перенесено с R1.3 2026-10-21, 13): `OrtQnnBackend` (Snapdragon NPU, w8a8) как отдельная загрузка.

## Последствия

(+) ANE на iOS (2–5× энергоэффективнее GPU); проверенный путь ncnn для Real-ESRGAN; один формат ncnn для GPU и CPU на Android.
(−) Два формата моделей (ncnn, Core ML) и два набора паритетных тестов; Vulkan-драйверы нестабильны → нужен blocklist (ADR-0016).

## Отклонённые альтернативы

- ncnn везде (iOS через MoltenVK): нет ANE, оверхед MoltenVK.
- ONNX Runtime везде: нет GPU на Android, CoreML EP дробит граф.
- LiteRT: хрупкая конверсия GAN, `CompiledModel` нестабилен.
- MNN: меньше экосистема; SuperImage (GPL) — только референс.
- ExecuTorch: нет зрелого Flutter-пути.
