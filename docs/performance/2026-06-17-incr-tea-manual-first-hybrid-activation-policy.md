# Incremental TEA manual-first hybrid activation policy — 2026-06-17

This validates the accepted [#280 ADR](../decisions/2026-06-17-incr-tea-inactive-root-activation-policy.md) with the example-local `BrowserRootActivationController` prototype. The controller adds semantic `show(root)` / `hide(root)` operations over the existing `BrowserRenderer::activate` / `deactivate` lifecycle, plus advisory `prewarm(root)` for roots where early activation side effects are acceptable.

The harness reuses the activation-trigger probe rather than adding a new scheduler. For every sample it resets roots to active hidden-mounted state, hides/deactivates them, applies one inactive hidden-mounted update, then measures one operation. The probe removes the renderer's normal on-change listener and manually drives inactive skip walks so the timed window isolates activation policy cost rather than rAF scheduling. A production inactive update can still have a pending rAF; if semantic `show` runs before that frame, activation performs the catch-up immediately and the later frame is an unchanged no-op. `prewarm-hit` performs `prewarm` before the timed window and times the later semantic `show`; `prewarm-miss` times semantic `show` with no earlier prewarm. Because `prewarm` uses the same catch-up flush and after-flush drain as `show`, its early effects are intentionally outside the hit timing.

## Environment

| | |
|---|---|
| Date | 2026-06-17 |
| CPU | AMD Ryzen 7 6800H with Radeon Graphics, 8 vCPU under WSL2 |
| Toolchain | MoonBit `moon 0.1.20260608 (60bc8c3 2026-06-08)` |
| JS runtime | Node.js v24.14.1 |
| Browser | HeadlessChrome 148.0.7778.96 |
| Command | `cd examples/incr_tea && npm run bench:activation-trigger` |

Each cell is reported in microseconds, mean ± sample standard deviation. This run used 9 samples and one inactive update before activation. Per-root subtree size is N=256.

## Results

### Shared Program

| roots | manual activate one | semantic show one | prewarm hit one | prewarm miss one | manual activate all | semantic show all | prewarm hit all | prewarm miss all |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 544 ± 292 | 833 ± 250 | 0.00 ± 0.00 | 378 ± 164 | 578 ± 186 | 367 ± 150 | 11.1 ± 33.3 | 333 ± 122 |
| 4 | 544 ± 174 | 444 ± 101 | 11.1 ± 33.3 | 367 ± 122 | 1489 ± 564 | 1033 ± 218 | 0.00 ± 0.00 | 1044 ± 364 |
| 16 | 778 ± 880 | 833 ± 946 | 0.00 ± 0.00 | 478 ± 233 | 4044 ± 1009 | 3600 ± 339 | 0.00 ± 0.00 | 3778 ± 360 |

### Independent Programs

| roots | manual activate one | semantic show one | prewarm hit one | prewarm miss one | manual activate all | semantic show all | prewarm hit all | prewarm miss all |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 367 ± 166 | 356 ± 167 | 0.00 ± 0.00 | 378 ± 148 | 333 ± 112 | 356 ± 174 | 0.00 ± 0.00 | 322 ± 97.2 |
| 4 | 389 ± 78.2 | 333 ± 86.6 | 0.00 ± 0.00 | 344 ± 88.2 | 1322 ± 249 | 1344 ± 305 | 0.00 ± 0.00 | 1356 ± 174 |
| 16 | 389 ± 117 | 456 ± 230 | 0.00 ± 0.00 | 356 ± 142 | 7333 ± 2258 | 7233 ± 1992 | 0.00 ± 0.00 | 7622 ± 2708 |

Observer-triggered controls in the same run stayed at roughly 9–16 ms, matching the earlier trigger-overhead finding. Direct manual activation and semantic `show` stay in the same band; the controller adds no visible scheduler layer. A prewarm hit makes the later semantic show a no-op at the harness timer resolution, while prewarm miss matches semantic show/direct activation because it is the same catch-up path. Some browser rows remain noisy, so use the bands and order-of-magnitude separation rather than individual means as the conclusion.

## Conclusion

The manual-first hybrid policy is implemented in `examples/incr_tea` without adding a core `incr` scheduler. Product code can use `show` / `hide` as semantic names for the existing lifecycle, and optional `prewarm` remains explicitly side-effect-bearing: it is only safe where early activation, DOM catch-up, and after-flush work are acceptable.

## Reproduction

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon build --target js --release examples/incr_tea/browser_bench
cd examples/incr_tea
npm run bench:activation-trigger
```
