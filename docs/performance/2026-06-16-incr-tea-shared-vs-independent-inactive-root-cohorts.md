# Incremental TEA shared vs independent inactive-root cohorts — 2026-06-16

This synthesis compares two consecutive `examples/incr_tea` inactive-root cohort
measurements:

- **PR #277** ([shared-`Program` snapshot](2026-06-15-incr-tea-inactive-root-cohorts.md)):
  one workspace `Program` and one shared view `Watch` mounted into 1 / 4 / 16
  inactive DOM roots. The model update stream is shared, so each burst is one
  application update plus a per-root `flush_if_active` skip walk.
- **PR #278** ([independent-root snapshot](2026-06-16-incr-tea-independent-inactive-root-cohorts.md)):
  each inactive DOM root owns a separate `Program`, model, view `Watch`, and
  rendered/last-view cache. Each burst update is broadcast to every root/program,
  then the harness walks the inactive skip path for every root.

Both snapshots use the same environment, same subtree size (N=256), same root
counts (1 / 4 / 16), same burst lengths (10 / 100 / 1000 inactive updates), and
the same timing modes (total burst vs activation only; activate one root vs
activate all roots). Units are microseconds, mean ± sample standard deviation
(9 samples × 200 timed operations). See the source snapshots for full tables and
raw numbers.

## 16-root comparison

| timing | activation | updates | shared (#277) | independent (#278) | independent / shared |
|---|---|---:|---:|---:|---:|
| activation only | one root | 10 | 319 ± 6.23 | 440 ± 70.2 | 1.38× |
| activation only | one root | 100 | 344 ± 18.6 | 551 ± 39.7 | 1.60× |
| activation only | one root | 1000 | 426 ± 10.0 | 636 ± 64.3 | 1.49× |
| activation only | all roots | 10 | 3552 ± 36.0 | 6832 ± 34.7 | 1.92× |
| activation only | all roots | 100 | 3802 ± 45.9 | 7932 ± 132 | 2.09× |
| activation only | all roots | 1000 | 4228 ± 59.8 | 8680 ± 264 | 2.05× |
| total burst | one root | 10 | 371 ± 10.7 | 1006 ± 53.8 | 2.71× |
| total burst | one root | 100 | 688 ± 18.5 | 5632 ± 80.4 | 8.19× |
| total burst | one root | 1000 | 3590 ± 48.7 | 54908 ± 592 | 15.3× |
| total burst | all roots | 10 | 3691 ± 63.5 | 7375 ± 69.3 | 2.00× |
| total burst | all roots | 100 | 4017 ± 59.4 | 13355 ± 213 | 3.32× |
| total burst | all roots | 1000 | 7198 ± 27.6 | 59555 ± 253 | 8.27× |

## Conclusions

1. **Shared-Program cohorts are cheaper in every measured 16-root case.** The
   gap is smallest for activation-only / one-root (≈1.4–1.6×) and largest for
   total-burst / one-root at long bursts (≈15× at 1000 updates).
2. **Activation-only / one-root stays bounded by one catch-up root in both
   designs.** Independent is modestly slower because the activated root must
   catch up its own private `Watch` chain and model, not just replay a shared
   view diff against a shared model.
3. **Activation-only / all-roots scales roughly 2× worse for independent roots.**
   Shared activation diffuses 16 N=256 subtrees from one caught-up view;
   independent activation must verify and diff 16 separate `Watch` chains.
4. **Total-burst / one-root diverges sharply with burst length for independent
   roots.** At 16 roots and 1000 updates the independent total is 54.9 ms vs
   3.59 ms shared, because the independent harness broadcasts every logical
   update to 16 separate programs. The shared harness applies the burst once and
   only pays per-root skip walks.
5. **Neither snapshot chooses a trigger policy.** Both measurements keep
   lifecycle semantics, `Watch` ownership, and the renderer's
   `deactivate`/`activate` contract identical; they only vary whether the cohort
   shares one `Program` or uses one `Program` per root. See the out-of-scope
   notes in the source snapshots:
   [shared](2026-06-15-incr-tea-inactive-root-cohorts.md:90) and
   [independent](2026-06-16-incr-tea-independent-inactive-root-cohorts.md:93).

## Reproduction

Run either cohort from the same harness:

```bash
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea
NEW_MOON_MOD=0 moon check --deny-warn --target js examples/incr_tea/browser_ui_compare_bench
cd examples/incr_tea
npm run bench:ui-compare-dom
```

Set `INCR_TEA_UI_COMPARE_DOM_BENCH_ITERATIONS` and
`INCR_TEA_UI_COMPARE_DOM_BENCH_SAMPLES` to change the sampling budget.
