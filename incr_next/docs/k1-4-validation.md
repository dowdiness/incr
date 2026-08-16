# K1.4 validation record

**Reader:** K1.4 implementers and reviewers.

**Decision:** Implement the commissioned K1.4 typed cutoff and backdating
contract. The accepted implementation/validation head is
`0036bdd199a685823b6769bf1acdac3f9b6b9014` (component heads:
compile-probe `fad637a57e668924156a50c7af8b4f2e8c58fa59`,
Fresh/model evidence `9318408740b6865c14735da0be922a872e2c21bb`,
semantic implementation `16e6a1fc1a4cb48ac1ba11463096595398115472`,
ownership/boundary evidence `f84d9589d4b979b711036263255f6a3f2e684525`). The selected
surface preserves existing `Region::query` and adds explicit
`query_always_changed`, `query_eq` with `V : Eq`, and `query_type_owned` with
standalone `pub(open) CutoffEq`.

**Keep until:** K1 alpha is superseded or a durable published API record is
separately authorized.

**Disposition:** **ACCEPTED AND MERGED.** The accepted implementation/validation
head is `0036bdd199a685823b6769bf1acdac3f9b6b9014`, the status-only head is
`c88e724383ca5f3e817f30226a9fa23cf3ad7358`, and PR #478 squash-merged the
equivalent tree as `9d53d51d6ec6e282b8aa247442ee126acfe64a2d`.
Both heads passed 46 of 46 hosted checks, public diff review was APPROVE,
maintainer acceptance was PASS, and squash-tree equivalence passed.

CodeRabbit skipped content review because manual review was required and is not
positive evidence; independent public review supplies review evidence. K1.5 is
**IMPLEMENTATION COMPLETE** and **MAINTAINER ACCEPTED** at validated review-fix
head `378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`; PR #480 merge is pending.
K1.6 remains **BLOCKED** and **UNCOMMISSIONED**. ADR, publication, and Canopy
integration remain unauthorized. Plan 015 remains active. **No ADR needed:** K1.4 is one accepted
increment under the existing K0 contracts; adoption and publication remain
separate decisions.

## Scope and invariants

The kernel commits cutoff only after a successful current recomputation. It
installs the newest value and trace, retains `MemoId`, and backdates `changed_at`
only when the fixed per-Query relation says the old and new values are
equivalent. First success, same-epoch hit, green verification, failed target
recomputation, and Cycle do not invoke cutoff. Closing a Region clears memo
state and resets the private cutoff slot to `AlwaysChanged`.

Fresh and incremental cutoff evaluators are independent. They compare semantic
values and, for type-owned workloads, the direct newest marker. They do not
fabricate work counters; private white-box `compute_count`, verification,
green, red, cutoff, and dependency counters are the work gate. Expected
unsound divergences are white-box-only and excluded from differential parity:
custom `Eq` that ignores a generation read by a downstream query, and the
non-transitive local-nearness relation over `0 -> 1 -> 2`.

The native RC probe covers equivalent dynamic trace replacement: the parent
switches child trace keys while retaining an equivalent semantic value, its old
memo value is released, the old trace key is released when the child closes,
and the newest trace key/value are released when the parent closes. It does
not claim an external cutoff-policy capture finalizer; the selected public
constructors do not expose such a policy object.

## Validation commands and results

```text
moon fmt                                      PASS
(cd incr_next && moon info)                  PASS
(cd incr_next_testkit && moon info)          PASS
moon check incr_next                          PASS
moon check incr_next_testkit                  PASS
moon test incr_next --target native           PASS (75 tests)
moon test incr_next                           PASS (75 tests)
moon test incr_next --target js               PASS (75 tests)
moon test incr_next_testkit/differential --target native
                                             PASS (13 tests)
moon test incr_next_testkit/differential    PASS (13 tests)
moon test incr_next_testkit/differential --target js
                                             PASS (13 tests)
moon test incr_next_testkit/model             PASS (11 tests)
moon test incr_next_testkit/fresh             PASS (4 tests)
moon test incr_next_testkit/scenarios         PASS (3 tests)
six roots x four targets                    PASS (24/24)
workspace moon check                         PASS
workspace moon test                          PASS (1,255 wasm-gc; 256 JS)
moon run incr_next/native_rc --target native  PASS
./scripts/probe-incr-next-k1-4-cutoff.sh      PASS
./scripts/check-incr-next-negative-probes.sh  PASS
./scripts/check-incr-next-boundaries.sh       PASS
./scripts/check-incr-next-boundaries-selftest.sh PASS
```

The white-box test list includes cutoff timing and close reset, Eq and
type-owned stamp/identity cases, consecutive equivalent newest-marker reads,
dynamic trace replacement counters, failed-target preservation, existing-memo
self-Cycle recovery, equivalent descendant-before-ancestor-Cycle ordering, and
both expected-divergence cases. The differential list contains only admissible
Fresh-parity scenarios; the divergence cases are intentionally absent.

The probe's exact interface-delta guard runs against the committed production
candidate. Its allowed delta is exactly the three selected constructors and
standalone `CutoffEq`; no policy, predicate, counter, memo, trace, or debug item
is public. Negative probes reject arbitrary/public policy forms, and boundary
checks reject kernel/testkit and Fresh-reachable dependency leaks.

The full 24-cell matrix, workspace tests, ownership, interface, negative, and
boundary gates pass. Current `incr/` diff and K1.5+ surface remain zero at the
accepted implementation head. Implementation push, PR, hosted acceptance,
public diff review, maintainer acceptance, status-only finalization, and squash
merge are complete. The separate K1.5 implementation is complete and
maintainer accepted at validated review-fix head
`378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`; PR #480 merge is pending. ADR,
publication, and Canopy integration remain unauthorized.
