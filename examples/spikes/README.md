# Spikes

Small checked probes that live with examples because they are useful to keep buildable, but are not part of the public library API.

- [`ideal_api_rename_phase0/`](ideal_api_rename_phase0/) — MoonBit language-mechanics probe for the public API rename migration plan.
- [`v12_3_write_capability/`](v12_3_write_capability/) — evidence-only nominal `Write[T]` capability probe for #456. Preserve on its spike branch; do not merge it into `main`.

Run from the repository root:

```bash
moon check examples/spikes/ideal_api_rename_phase0
./examples/spikes/v12_3_write_capability/check.sh
```
