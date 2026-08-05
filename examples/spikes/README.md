# Spikes

Small checked probes that live with examples because they are useful to keep buildable, but are not part of the public library API.

- [`ideal_api_rename_phase0/`](ideal_api_rename_phase0/) — MoonBit language-mechanics probe for the public API rename migration plan.
- [`ownership_graph_lifecycle/`](ownership_graph_lifecycle/) — interactive RC/SCC lifecycle-model probe for retention redesign issue #451.

Run a spike from the repository root:

```bash
moon check examples/spikes/ideal_api_rename_phase0
moon run examples/spikes/ownership_graph_lifecycle --target native
```
