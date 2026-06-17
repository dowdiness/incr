# Incremental TEA activation-trigger overhead probe — 2026-06-17

This adds a measurement-only probe for the missing trigger-policy data point:
IntersectionObserver callback dispatch overhead and observer-triggered activation
cost for DOM-preserving inactive workspace roots.

No activation policy is chosen here. The renderer lifecycle contract is unchanged:
`BrowserRenderer::deactivate(root)` marks a mounted root inactive, and
`BrowserRenderer::activate(root)` marks it active and performs one catch-up flush.
The probe exercises that existing path without hardening visibility, idle, or
manual trigger policy. A later ADR uses this measurement to choose the
[#280 manual-first hybrid policy](../decisions/2026-06-17-incr-tea-inactive-root-activation-policy.md).

Per-root subtree size is fixed at N=256. The root-count axis is 1 / 4 / 16, with
both shared-program and independent-program ownership. Before each timed sample,
the harness resets all roots to active hidden-mounted state, deactivates them,
applies one hidden-mounted inactive update, then times one of these operations:

- **observer-dispatch-only** — one observer per root, all hosts revealed in one
  DOM turn, with no activation call;
- **observer-activate-one** — observer callback calls `activate` for root 0;
- **observer-activate-all** — one observer per root, all hosts revealed in one
  DOM turn, first callback calls `activate` for all roots;
- **manual-activate-one** — direct `activate` for root 0 control baseline;
- **manual-activate-all** — direct `activate` for every root control baseline.

The observer rows move hidden hosts from offscreen (`left:-10000px`) into the
viewport to force an IntersectionObserver threshold crossing. This avoids using
the renderer's rAF scheduling path and keeps the timed window focused on browser
observer dispatch plus the existing activation path.

## Environment

| | |
|---|---|
| Date | 2026-06-17 |
| CPU | AMD Ryzen 7 6800H with Radeon Graphics, 8 vCPU under WSL2 |
| Toolchain | MoonBit `moon 0.1.20260608 (60bc8c3 2026-06-08)` |
| JS runtime | Node.js v24.14.1 |
| Browser | HeadlessChrome 148.0.7778.96 |
| Command | `cd examples/incr_tea && npm run bench:activation-trigger` |

Each cell is reported in microseconds, mean ± sample standard deviation. This
run used 9 samples and one inactive update before activation.

## Results

### Shared Program

| roots | observer dispatch | observer activate one | observer activate all | manual activate one | manual activate all |
|---:|---:|---:|---:|---:|---:|
| 1 | 14289 ± 1598 | 15567 ± 2484 | 15711 ± 2084 | 656 ± 459 | 800 ± 510 |
| 4 | 13378 ± 3632 | 14489 ± 2891 | 15422 ± 3012 | 889 ± 423 | 1500 ± 723 |
| 16 | 11644 ± 633 | 10944 ± 1505 | 14500 ± 2933 | 644 ± 592 | 5400 ± 4211 |

### Independent Programs

| roots | observer dispatch | observer activate one | observer activate all | manual activate one | manual activate all |
|---:|---:|---:|---:|---:|---:|
| 1 | 15600 ± 480 | 15956 ± 1437 | 16078 ± 1018 | 356 ± 167 | 300 ± 100.0 |
| 4 | 13300 ± 3537 | 14633 ± 1411 | 15500 ± 2220 | 544 ± 219 | 1811 ± 162 |
| 16 | 8511 ± 2280 | 9600 ± 1584 | 14467 ± 2642 | 489 ± 262 | 7078 ± 1873 |

The observer-triggered rows include browser IntersectionObserver scheduling
latency and are therefore much larger than direct `activate` calls. In this run,
manual activation remains sub-millisecond for single-root activation and scales
to roughly 5.4 ms shared / 7.1 ms independent for 16-root activate-all. This is
measurement input only; it still does not select a default activation policy.

## Interpretation checklist

- Compare `observer-dispatch-only` against the manual baselines to isolate pure
  browser callback dispatch cost.
- Compare `observer-activate-one` with `manual-activate-one` to estimate trigger
  overhead when activation cost is fixed to one root.
- Compare `observer-activate-all` with `manual-activate-all` to see whether the
  browser batches or serializes observer callbacks when many roots become
  visible in the same DOM turn.
- Treat the result as measurement input only. The later #280 ADR chooses the
  manual-first hybrid policy; this document does not itself choose
  visibility-driven, idle-callback, document-level, or manual activation.

## Reproduction

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon build --target js --release examples/incr_tea/browser_bench
cd examples/incr_tea
npm run bench:activation-trigger
```

Set `INCR_TEA_ACTIVATION_TRIGGER_SAMPLES`,
`INCR_TEA_ACTIVATION_TRIGGER_UPDATES`, or
`INCR_TEA_ACTIVATION_TRIGGER_TIMEOUT_MS` to adjust the sampling budget and guard
rail. The current harness also emits manual-first policy-controller rows added
by the follow-up [policy validation](2026-06-17-incr-tea-manual-first-hybrid-activation-policy.md); the table above is the original trigger-overhead slice.
