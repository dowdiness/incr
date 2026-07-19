# Retractable dataflow correctness spike

`dowdiness/dataflow` is an unpublished, experimental Phase 0 correctness spike.
It tests whether an independent MoonBit module can maintain finite set-valued
recursive reachability under signed edge updates across isolated virtual
workers.

The spike is deliberately narrow:

- total integer epochs with explicit close and one active epoch at a time;
- whole-epoch consolidation and validation before state mutation;
- atomic rejection of invalid source multiplicity;
- worker-local keyed arrangements and parsed, copied routed envelopes;
- local deterministic or seeded-random scheduling;
- recursive threshold/set semantics with a full-recomputation oracle;
- validation with 1, 2, and 4 virtual workers.

It does not provide an Incr or Event Graph Walker adapter, networking,
checkpointing, capabilities, partial-order timestamps, a stable public API, or
any compatibility promise. The module must not be published while it remains a
spike.

## Phase 0 result

**GO for the bounded correctness semantics (2026-07-19).** This result does not
commission a production engine, public API, adapter, or distribution work.

The implementation passed the independent full-recomputation oracle after every
accepted epoch and preserved the previous completed state after every rejected
epoch. Table and generated tests cover duplicate support, alternate paths,
cycles, mixed insertion/retraction, N=1/2/4 workers, randomized delivery and
batch boundaries, same-seed decision-trace replay, no early publication, and
copied-envelope isolation. `pkg.generated.mbti` is intentionally empty.

The bounded retraction mechanism is explicit: a source update changes the graph
only when edge multiplicity crosses zero. The engine selects origins affected by
each changed edge source from the previous closure, removes only those origins'
derived facts, and rebuilds them through worker-routed keyed joins and
thresholded feedback. This avoids unbounded cyclic path multiplicity while
leaving unaffected origins in place. It is a spike mechanism, not a claim of a
general differential-dataflow algorithm.

Pure reducers own worker transitions and the complete epoch lifecycle. The
lifecycle reducer returns an immutable next phase plus a decision; the shell
applies that decision and remains responsible for seeded scheduling, transport,
mailboxes, trace recording, and publication effects. Persistent Core `Vector`
values retain staged input in open and closed phases without mutating prior
phase values; validated payloads remain immutable through draining. Raw envelope input is parsed once into a
routed-event variant that fuses the former operator, port, and event combination;
only parsed routed envelopes enter transport, mailboxes, traces, or a reducer.
Epoch, sender role, receiver identity, positive multiplicity, and key ownership
checks remain at this parser boundary because they depend on runtime values.

Source updates likewise cross explicit refinement boundaries. Consolidation
produces only nonzero net changes, complete epoch validation converts each
change to an absent or positive exact multiplicity, and workers accept only
those validated edge updates. The shell gathers pending transport, mailbox,
expected worker count, worker identity, and close facts; a pure parser requires
exact participant coverage before producing completion evidence. That evidence constructs the completed epoch consumed by publication
without repeated checks. The shell retains only a defensive snapshot of the
last publication and a monotonic publication count, not an unbounded
materialization history.

## Existing API reuse

The implementation reuses persistent Core `Vector` values for immutable staged
state and validated payloads; mutable `HashMap`/`HashSet` storage and owned
`Array` builders remain where mutation is local or belongs to the shell. It also
reuses `ArrayView` traversal, `Iter` transformations, `Option` and `Result`
protocol outcomes, `Compare`-derived canonical sorting, `@cmp.minimum`, `Queue`
for the independent oracle's breadth-first traversal, and seeded `splitmix`
scheduling. Deprecated `immut/array`, mutable `FixedArray`, read-only but
aliasing `ArrayView`, and immutable `List` were checked before selecting
`immut/vector`. `Map`/`Set` were checked as equivalent candidates but not mixed
with the explicit `HashMap`/`HashSet` package types. Incr `Relation`,
`MapRelation`, `Revision`, and `EvaluationStrategies` were checked only as
semantic references and are not dependencies. No codec is needed, so
`Bytes`/`Buffer`/`StringBuilder` are unused.

Private helpers each own one semantic phase:

- reduce every epoch event to an immutable phase and lifecycle decision;
- consolidate raw updates and validate the closed epoch;
- parse unrouted messages into ownership-checked routed envelopes;
- apply the accepted source batch;
- recompute affected origins;
- parse explicit completion facts into evidence and a completed epoch;
- canonicalize output;
- reduce one worker event; or
- route and drain shell messages.

Remaining mutation is confined to value builders, the shell's
mailboxes/lifecycle, and the oracle's BFS queue.

## Measurement

After correctness passed, `moon bench --release dataflow` measured the fixed
10-edge cyclic workload on MoonBit `moonc v0.10.4+2cc641edf`. Every timed
iteration intentionally includes engine construction, input staging, close,
scheduling, and materialization; this is an end-to-end closed-epoch measurement,
not an isolated operator benchmark:

| Mode | Mean | Standard deviation |
|---|---:|---:|
| N=1 | 116.15 µs | 5.82 µs |
| N=4 virtual workers | 77.03 µs | 3.32 µs |

These are one local release-mode observation with no acceptance threshold.
Transient routing batches remain mutable Arrays after an all-Vector experiment
regressed this workload; no further optimization was attempted.

## Validation

From the repository root:

```sh
NEW_MOON_MOD=0 moon check dataflow
NEW_MOON_MOD=0 moon test dataflow
NEW_MOON_MOD=0 moon bench --release dataflow
bash scripts/check-workspace-boundaries.sh
bash scripts/check-workspace-boundaries-selftest.sh
```

The full repository gate additionally runs `moon fmt`, `moon info`, workspace
`moon check` and `moon test`, and the engine-isolation script.
