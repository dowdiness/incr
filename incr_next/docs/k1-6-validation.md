# K1.6 accepted validation

**Reader:** Maintainers and contributors relying on the accepted K1
product-quality conformance baseline.

**Decision:** Accept K1.6 product-quality conformance as the final K1 slice.
This record does not authorize publication or production integration.

**Keep until:** The K1 baseline is superseded by an explicit K0 contract change.

**Disposition:** Durable accepted evidence for the completed Plan 015 product
decision; the completed plan file is deleted under the root plan workflow.

## Status

K1.6 is **ACCEPTED AND MERGED**, completing K1. Implementation evidence is
`b7d2c32ebdc65472db2ed0fd36f36a678c86822f`; status record
`6f51d63e4e406554e74cbbbb3e6c3f481d559547`; final PR/CI head
`15892973a556dc8a1c960bd3544f8e3c3922596a`; and squash merge
`58469934c5644686992688bc7a9f1685326a081d`.

Public branch review found that reports localized observations rather than
operations and that generated cutoff failures did not shrink. Commit `170a996`
addressed both implementation gaps; review then required the localization test
to exercise reconstructed scenario prefixes. Commit `d013186` added that
coverage. PR #482 review then required the private suites to report the same
operation/observation precision, the mutable-key divergence to be observable
without violating Hash/Eq stability, and unrelated-operation shrinking to be
scenario-aware. Commit `b7d2c32` closes those evidence gaps.

| Acceptance item | Result |
|---|---|
| Public operation localization | PASS |
| Public cutoff shrinking | PASS |
| Private operation localization | PASS |
| Lifetime suffix shrinking | PASS |
| Stable-identity mutable-key divergence | PASS |
| Scenario-aware unrelated-operation shrinking | PASS |
| Exact-tree gates | PASS |
| Independent review | APPROVE |
| Base revalidation | PASS; `origin/main` remained `e66f3bf` |
| Implementation PR | #482; hosted acceptance 46/46 including Incr Next Required |

K1.6 is accepted. Independent reviews returned **APPROVE**, squash-tree
equality passed, and current `incr`, production kernel/manifests, and generated
`.mbti` deltas are zero. CodeRabbit skipped content review and is not positive
evidence. Publication, K2 implementation, Canopy production
integration, Mount, Program/Port/Formula, public debug/explain, public or
automatic eviction/LRU, and parallel evaluation remain gated or excluded.

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
Unrelated-operation candidates exist only for `UnrelatedPublication`; selector
and selected-Source writes in DynamicBranch and KeyedQuery remain for the
subsequent Writes phase.

Private fixed-seed evidence adds 64 proof-loss cases, 48 atomicity/Region-close
cases, and 32 structural-failure/recovery cases. Fresh projects proof loss to a
semantic no-op and projects one atomic multi-write to adjacent Fresh writes
without an intervening read. Only the temporary kernel white-box interpreter
calls the package-private proof-loss operation. Region close and rejected
atomic publication use a pure expected-transition oracle because neither is a
public testkit operation.

Private reports replay operation prefixes and include the first differing
operation and observation. Lifetime shrinking removes
trailing operations before reducing values; structural recovery reduces values
but retains its mandatory recovery/read witness. Proof shrinking retains valid
graph membership and the mandatory proof-loss/rematerialization pair.

Expected divergences remain outside Fresh parity:

- mutable Query-key meaning, demonstrated with immutable Hash/Eq identity and a
  mutable semantic field;
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
| `differential` tests | 21 per target PASS after evidence fix |
| Private evidence fixtures | 10 tests × four targets PASS |
| Native RC/finalizer harness | PASS |
| Negative capability probes | PASS |
| Kernel/testkit boundaries and self-test | PASS |
| Workspace boundaries and self-test | PASS |
| Workspace `moon check` | PASS |
| Workspace default tests | 1,274 wasm-gc + 256 JS PASS at `b7d2c32` |
| Explicit workspace JS tests | 1,530 PASS at `b7d2c32` |
| Documentation boundary checker | 154 Markdown files PASS after review fix |

The matrix has no conditional target skip. The adapter has no package-local test
entry, but all four check/test commands run, and the differential package drives
it for every generated and commissioned public script.

Exact interface checks passed at implementation candidate `b7d2c32`, including
the table totals above; documentation checks pass on this status record. The candidate retains zero current-`incr/`
delta, zero production `incr_next` manifest/source delta, and zero generated
`.mbti` delta. Pre-existing workspace warnings are unchanged.

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

Commit `d013186` drives the actual prefix reconstruction seam through Fresh and
Incremental replay for Source, KeyedQuery, DomainFailure, and StructuralError
scripts while preserving scenario and initial-Source setup. PR #482 review then
found three private/divergence/shrink-phase evidence gaps. Commit `b7d2c32`
adds private operation-prefix reports and lifetime suffix shrinking, demonstrates
mutable-key divergence with stable identity, and limits unrelated-operation
shrinking to its owning scenario. Injected tests distinguish operation from
observation indices and retain the mandatory structural-recovery witness.

The exact-tree gates pass against unchanged base
`e66f3bfeb08343135ad0e180c1c7a3cfbfa92d75`. Independent MoonBit and
adversarial evidence reviews returned **APPROVE** after their findings were
resolved. PR #482 supplied the accepted hosted evidence; the final CI head was
`15892973a556dc8a1c960bd3544f8e3c3922596a`.

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
