# S6: Dart ↔ native event bridge stress

Report: [docs/spikes/S6.md](../../docs/spikes/S6.md).

- `native/` — mock core implementing the job part of [`enh.h`](../../docs/spec/appendix/enh.h)
  with a real `prep → infer → post` pipeline (depth-2 queues, ADR-0006) and simulated work;
  test hooks in `include/enh_debug.h`. `tests/stress.cpp` races cancel/pause/answer/
  set_callback/destroy across ~10k jobs and checks the event invariants (built plain, TSan,
  ASan+UBSan+LSan).
- `dart/` — ffigen bindings (`ffigen.yaml`, generated from the spec header), the bridge
  (`lib/bridge.dart`) in two modes and the scenarios (`bin/s6.dart`):
  - `S6_MODE=callable` — `NativeCallable.listener` + heap payload + `enh_free` (ADR-0005 before S6);
  - `S6_MODE=port` — `Dart_PostCObject_DL` into a `ReceivePort` (ADR-0005 after S6).

## Run

Needs clang-18, CMake ≥ 3.20 and a Dart SDK (default `~/sdk/dart-sdk`; override with `DART=`).
The port mode compiles `dart_api_dl.c` from `<dart-sdk>/include` (`-DDART_SDK_INCLUDE=`).

```sh
./run.sh                                   # everything; results in out/results.jsonl
SCENARIOS="cancel isolate_kill" ./run.sh   # subset
STRESS_ROUNDS=4000 ./run.sh                # longer native stress

# regenerate bindings after changing enh.h
cd dart && LIBCLANG_PATH=/usr/lib/llvm-18/lib dart run ffigen --config ffigen.yaml
```

Scenarios: `throughput` (10k events/job, latency, event-loop lateness, coalescing), `soak`
(200 × 10k), `concurrent` (8 jobs, one sink), `cancel` (cancel/pause latency per tile size),
`destroy_blocking`, `needs_user`, `early_close` and `isolate_kill` (sink dies before the job),
`bad_utf8`. In `callable` mode `early_close` and `isolate_kill` abort the process by design of
the Dart VM — that is the finding; `run.sh` records it as `"crash": true`.

TSan does not report anything on Linux 7.0 hosts with high-entropy ASLR (it re-execs and
stays silent even on a textbook race); treat the TSan line as meaningful only on CI runners.
