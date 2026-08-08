# Spikes

Small checked probes that live with examples because they are useful to keep buildable, but are not part of the public library API.

- [`ideal_api_rename_phase0/`](ideal_api_rename_phase0/) — MoonBit language-mechanics probe for the public API rename migration plan.
- [`incr_next_fresh_evaluator/`](incr_next_fresh_evaluator/) — evidence-only memo-free evaluator and atomic transaction oracle for Incr Next.
- [`incr_next_incremental_parity/`](incr_next_incremental_parity/) — issue #462 keyed incremental evaluator compared with the unchanged #461 oracle.
- [`incr_next_cycle_detection/`](incr_next_cycle_detection/) — issue #463 invocation-level semantic cycle detection over independent fresh and incremental providers.
- [`incr_next_cutoff_backdating/`](incr_next_cutoff_backdating/) — typed Query-owned cutoff and changed-at backdating evidence over the unchanged cycle boundary.

Run from the repository root:

```bash
moon check examples/spikes/ideal_api_rename_phase0
```
