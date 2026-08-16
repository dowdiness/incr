# K1.6 local validation

**Reader:** Maintainers reviewing the local K1.6 product-quality conformance
candidate.

**Decision:** Decide whether the evidence-only candidate is ready for exact-HEAD
independent review and later maintainer acceptance. This record does not accept
K1.6 or authorize publication.

**Keep until:** K1.6 is accepted, rejected, or replaced and Plan 015 reaches its
separate product decision.

**Disposition:** Keep while Plan 015 is active. On a later accepted product
decision, update this record with hosted and merge evidence before applying the
plan documentation protocol.

## Status

K1.6 has a **LOCAL CANDIDATE** at implementation commit
`a36b6d721db78160f8aadde1c5880694c0df2bb6`, suffix-shrinker fix
`dbad5bd0ca66aee3b027ba0bd64da22722b1f164`, generated-failure evidence fix
`170a99643fda94411888f7ec4cfaacdc7ff38232`, and prefix-replay test fix
`d0131867b4324d8b6784ebf526cf2437fa5c7af3`, based on commission merge
`e66f3bfeb08343135ad0e180c1c7a3cfbfa92d75`.

Public branch review found that reports localized observations rather than
operations and that generated cutoff failures did not shrink. Commit `170a996`
addressed both implementation gaps; exact-tree review then required the
localization test to exercise reconstructed scenario prefixes. Commit `d013186`
adds that coverage locally.

Exact-tree revalidation and independent review remain pending. The published
branch still points to the earlier reviewed status tree until these fixes are
separately authorized for push. K1.6 is not accepted. Implementation PR, hosted
CI, maintainer acceptance, merge, ADR, and publication remain pending or
unauthorized.

No generated counterexample exposed a K0 contract defect. The candidate changes
only tests, evidence fixtures, testkit dependencies, boundary/CI gates, and
documentation. It adds no kernel capability.

## K1.6a-0 boundary result

MoonBit compile probes established three facts:

1. An external adapter cannot call package-private
   `Query::drop_memo_evidence`.
2. A function declared only in a kernel white-box test is not exported to an
   external package.
3. A kernel white-box test can import Fresh only after adding a module-level
   testkit dependency. Because the testkit already depends on the kernel, a
   permanent manifest edit would create a production module cycle rather than
   a test-only edge.

The selected boundary follows the existing compile-negative probe pattern.
Private K1.6 MoonBit fixtures remain disabled under
`incr_next/private_evidence/`. The
`check-incr-next-k1-6-private-evidence.sh` gate copies `incr_next` and
`incr_next_testkit` into a temporary workspace, enables all three private
white-box fixtures there, injects the Fresh and QuickCheck dependencies there,
runs every backend, and deletes the workspace. Permanent `incr_next/moon.mod` and `incr_next/moon.pkg` have no
testkit or QuickCheck dependency. The boundary checker rejects direct,
test-only, module-level, and Fresh-transitive violations.

## K1.6a generated evidence

The public differential package runs 84 fixed-seed cases spanning all 21
existing `Scenario` families and all seven `CutoffKind` choices. It compares
normalized Fresh and Incremental observations, excluding work counters. A failure reports the seed, case, recipe, initial Sources, operations, both
outcomes, the first differing operation, and the first differing observation.
The operation location comes from replaying valid operation prefixes, rather
than assuming an observation index equals an operation index.

Its real shrinker replays admissible candidates in this order:

1. operation suffix;
2. unrelated operations;
3. writes;
4. Source/Query graph simplification;
5. keys;
6. values;
7. cycle path.

Generated cutoff shrinking has two applicable phases. The suffix phase shortens
the input array by one; the value phase reduces individual entries to zero. The
fixed-point search retains only candidates that still reproduce the mismatch
and reports the first differing cutoff input position and observation.

Private fixed-seed evidence adds 64 proof-loss cases, 48 atomicity/Region-close
cases, and 32 structural-failure/recovery cases. Fresh projects proof loss to a
semantic no-op and projects one atomic multi-write to adjacent Fresh writes
without an intervening read. Only the temporary kernel white-box interpreter
calls the package-private proof-loss operation. Region close and rejected
atomic publication use a pure expected-transition oracle because neither is a
public testkit operation. Their shrinkers retain valid graph membership and the
mandatory proof-loss/rematerialization pair.

Expected divergences remain outside Fresh parity:

- mutable Query keys;
- mutable Source aliases;
- mutable memo-result aliases;
- observers forbidden by a propagation-equivalence contract;
- non-transitive type-owned cutoff relations.

## K1.6b work evidence

Package-private fields and existing memo/trace state assert exact work for:

- first compute and same-epoch cache hit;
- green verification and red recomputation;
- structural failure and Cycle cleanup/recovery;
- cutoff invocation and `changed_at` backdating;
- memo identity and forward-trace installation;
- proof loss and conservative rematerialization.

No new production counter is needed. QueryContext and Query results cannot read
these fields, and no counter or debug capability appears in generated public
interfaces. Work gates use exact counts, never elapsed time.

## K1.6c local gates

| Gate | Local result |
|---|---|
| Exact six roots × four targets | 24/24 PASS |
| `incr_next` tests | 86 default, 88 native, 86 JS, 86 wasm-gc PASS |
| `model` tests | 11 per target PASS |
| `fresh` tests | 4 per target PASS |
| `incremental_adapter` | check PASS; zero direct test entries as before |
| `scenarios` tests | 3 per target PASS |
| `differential` tests | 20 per target PASS after evidence fix |
| Private evidence fixtures | 9 tests × four targets PASS |
| Native RC/finalizer harness | PASS |
| Negative capability probes | PASS |
| Kernel/testkit boundaries and self-test | PASS |
| Workspace boundaries and self-test | PASS |
| Workspace `moon check` | PASS |
| Workspace default tests | 1,273 wasm-gc + 256 JS PASS at `2046d1f` |
| Explicit workspace JS tests | 1,529 PASS at `2046d1f` |
| Documentation boundary checker | 154 Markdown files PASS after review fix |

The matrix has no conditional target skip. The adapter has no package-local test
entry, but all four check/test commands run, and the differential package drives
it for every generated and commissioned public script.

Exact interface and documentation checks passed at evidence-status head
`2046d1f`, including the table totals above. Commit `d013186` changes only the
differential black-box test and requires another exact-tree rerun. The candidate
retains zero current-`incr/` delta, zero production `incr_next` manifest/source
delta, and zero generated `.mbti` delta. Pre-existing workspace warnings are
unchanged.

## K1.6d local review

Initial independent review found that suffix shrinking could remove a middle
operation. Commit `dbad5bd` switched to true retained-array truncation and added
an exact before/after assertion; its exact tree passed all gates and received
**APPROVE**. A later review of the published branch found two remaining evidence blockers:
failure reports named the first observation rather than the first operation,
and cutoff failures had no shrinker. Commit `170a996` adds prefix replay
localization, keeps both operation and observation indices, and adds fixed-point
cutoff suffix/value shrinking with injected-failure coverage. Exact-tree gates
passed at `2046d1f`, but review found that the operation-localization test only
exercised synthetic prefix lengths.

Commit `d013186` now drives the actual prefix reconstruction seam through Fresh
and Incremental replay for Source, KeyedQuery, DomainFailure, and
StructuralError scripts while preserving scenario and initial-Source setup. The
fetched base remained `e66f3bfeb08343135ad0e180c1c7a3cfbfa92d75`. Exact-tree
gates, base revalidation, and independent review must pass once more before an
implementation PR may be requested.

## Existing API First

Reused project APIs:

- `Script`, `CutoffScript`, existing scenario constructors, Fresh `evaluate`,
  and the Incremental adapter;
- package-private `drop_memo_evidence` and existing QueryCore counters,
  memo entries, traces, stamps, and identities;
- existing negative, boundary, interface, and native ownership gates.

Checked MoonBit core APIs:

- `Map`, `Set`, `Array`, `ArrayView`, `Option`, and `Result` for generated state,
  validity, projection, and comparison;
- QuickCheck `Gen::samples` for bounded fixed-seed input;
- `Debug::to_string` for replay reports;
- `String`/`StringView`, `Bytes`/`BytesView`, `Buffer`/`StringBuilder`, and
  `cmp`/`math` helpers were not used because the evidence has no textual or
  binary parsing, buffered assembly, or numeric ordering requirement.

New helpers are private test builders, interpreters, shrinkers, reporters, and a
shell gate. Their boundary is evidence construction/replay only. Remaining
mutation is confined to local output builders, deterministic shrink search, and
the imperative replay shell around pure recipes and expected transitions.
