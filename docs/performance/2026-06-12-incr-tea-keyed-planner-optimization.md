# 2026-06-12 Incremental TEA keyed planner optimization

Issue #241 replaced the large-list duplicate-free `plan_keyed_diff` path with a key-to-old-index map. Tiny lists still use the original scan because map setup dominates there; duplicate old keys also fall back to the original first-available scan so the documented degradation semantics stay unchanged.

## Headline results

At N=256, the pure planner improves:

- reverse: 127.49 → 17.10 µs (**7.46× faster**)
- prepend one: 51.29 → 17.63 µs (**2.91× faster**)
- unchanged: 52.31 → 19.69 µs (**2.66× faster**)

The large duplicate-free path now scales linearly: the N=64→256 step is 4.24× for reverse and 4.26× for prepend, matching the 4× list-size increase. Browser timings only move where planner cost was visible through DOM work: N=256 reverse improves 395 → 271 µs, while prepend/remove-first stay within run noise.

## Pure planner benchmark

Command:

```bash
NEW_MOON_MOD=0 moon bench --target js --package examples/incr_tea
```

Before/after rows below are from the same machine and MoonBit toolchain. The "before" run is the pre-change O(n·m) planner; the "after" run is the key-map planner with the tiny-list scan threshold.

| operation | N | before | after | change |
|---|---:|---:|---:|---:|
| reverse | 16 | 0.571 µs | 0.594 µs | 0.96× |
| reverse | 64 | 9.26 µs | 4.03 µs | 2.30× faster |
| reverse | 256 | 127.49 µs | 17.10 µs | 7.46× faster |
| prepend one | 16 | 0.330 µs | 0.324 µs | 1.02× faster |
| prepend one | 64 | 3.74 µs | 4.14 µs | 0.90× |
| prepend one | 256 | 51.29 µs | 17.63 µs | 2.91× faster |
| unchanged | 256 | 52.31 µs | 19.69 µs | 2.66× faster |
| naive positional | 256 | 2.58 µs | 2.41 µs | noise |

Scaling after the change is linear once the key-map path is active. Reverse grows 4.24× from N=64 to N=256; prepend grows 4.26× over the same interval. The N=16 rows stay on the bounded scan path, so they should be read as the small-list constant-factor guard rather than as part of the large-list scaling curve.

The N=64 prepend row is slightly slower than the old scan in this run: the workload has one miss and otherwise cheap forward matches, so the hash-map setup just outweighs the consumed-prefix savings at that size. At N=256 the same case is 2.91× faster.

## Browser DOM applier check

Command:

```bash
cd examples/incr_tea
npm run bench:dom
```

No DOM applier code changed. This run checks that the planner improvement still flows through the real browser path.

### Keyed applier after #241 (µs/op)

| operation | N=16 | N=64 | N=256 |
|---|---:|---:|---:|
| prepend | 36.8 ± 15.6 | 99.9 ± 17.1 | 337 ± 50.2 |
| remove-first | 19.4 ± 3.45 | 80.9 ± 3.96 | 311 ± 26.0 |
| reverse | 19.0 ± 3.48 | 70.0 ± 3.20 | 271 ± 4.10 |

Against the 2026-06-12 browser baseline, prepend and remove-first are effectively unchanged at N=256 (334→337 µs and 308→311 µs, within run noise). Reverse improves from 395→271 µs at N=256 (**1.46× faster**) because it was the planner's worst consumed-prefix scan case.

## Validation

```bash
NEW_MOON_MOD=0 moon test --target js examples/incr_tea
cd examples/incr_tea && npm run test:dom
```

Both passed. The DOM behavior baseline remains unchanged: keyed row identity and uncontrolled input retention survive prepend/remove/reverse, unchanged-list focus survives a flush, and focus leaves the list when the focused row is removed.
