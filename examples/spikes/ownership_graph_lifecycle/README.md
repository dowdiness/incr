# Ownership graph lifecycle prototype

**PROTOTYPE — throwaway evidence for [incr #451](https://github.com/dowdiness/incr/issues/451), not production code.**

## Question

Can the proposed retention-redesign ownership graph pass through lifecycle
transitions without creating either a passive-only strong-reference cycle or
an active cycle whose designated `Stop` / `store.close()` capability is no
longer callable?

This prototype models reference-count elimination and strongly connected
components. It is a counterexample finder for the field-level ownership
argument; it does not prove native-RC reclamation or authorize a replacement
kernel.

## Run

From the repository root:

```bash
moon run examples/spikes/ownership_graph_lifecycle --target native
```

Enter one command per line. The terminal redraws the complete modeled state,
strong edges, nontrivial SCCs, reclaimed nodes, and current violations after
each transition.

Useful scenarios:

- `m`, `d`, `s`: mount an Effect, drop the public View root, then invoke Stop;
  the active cycle should break and the passive graph should be reclaimed.
- `m`, `d`, `r`, `x`: drop View, Store, and Stop roots without teardown; the
  remaining Effect SCC should be reported as having no callable breaker.
- `b`: inject an adversarial passive back-edge; the passive-only SCC should be
  reported immediately.
- `k`, `g`, `u`, `d`: retain a getter after keyed membership removal; the
  surviving getter should retain its one-way subgraph without creating an SCC.

Reset with `z`; quit with `q`.

## Model verdict

**Pass with constraints, for the modeled graph only.**

- The passive View graph is reclaimed after its external/active roots disappear
  as long as ownership remains one-way toward dependencies.
- Any passive back-edge creates an RC-retained passive-only SCC.
- An Effect cycle remains breakable only while either its Stop handle or an
  open Store capability is callable; dropping both without teardown leaves an
  unbreakable active SCC.
- A surviving keyed getter retains its entry and upstream state without forming
  an SCC after membership removal. This does not resolve F7 retirement
  semantics.

V12.4 remains open until the field-level ownership table and native-RC evidence
confirm that the production-shaped fields match this model.

## Deliberate limits

- The graph is a field-faithful model, not the replacement kernel.
- Reference counting is modeled as repeated zero-incoming-count elimination.
- Native allocation, compiler lowering, destructor timing, and process memory
  are outside this prototype; those require the separate native-RC evidence
  phase in #451.
- F7 retirement semantics remain open. This prototype only exposes ownership
  consequences.
