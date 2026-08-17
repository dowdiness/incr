# K1.5 validation record

**Reader:** K1.5 implementers, reviewers, and maintainers.

**Decision:** Accept the commissioned package-private proof-loss operation and
its rematerialization, failure, Cycle, phase, lifetime, and ownership evidence.
The implementation head is
`064a80ac884f7c5588f123cc62dd784adeb26b48`; the review-fix and validated head
is `378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`; the status-only head is
`6de46abf19acb69cc5d5274b89a0ee780e48fb8d`; and the squash merge commit is
`4e66654d021435179116c0cffd56c0216b1bc664`.

**Keep until:** The accepted K1 baseline is superseded by an explicit K0
contract change.

**Disposition:** **ACCEPTED AND MERGED.** PR #480 passed 46 of 46 hosted
checks at the review-fix and status-only heads, including `Incr Next Required`,
all 24 Incr Next root/target cells, interface clean, architecture boundaries,
and native RC ownership, with no pending or failed checks. Public diff review
was APPROVE, maintainer acceptance was PASS, and squash-tree equivalence
passed. CodeRabbit skipped content review because manual review was required
and is not positive evidence.

At K1.5 acceptance, Plan 015 remained active and K1.6 was commissioned but not
accepted. Public proof loss or eviction, automatic retention policy, public
debug/explain, Mount/Program/Port/Formula, Canopy integration, representation
optimization, and publication remained unauthorized. **No ADR needed:** K1.5
was one private accepted increment under active Plan 015; the later product
adoption decision has its own ADR.

## Accepted semantics

`Query::drop_memo_evidence` is package-private. It checks the module-global
phase and Region generation before invoking caller `Hash` or `Eq`, then removes
one typed Query-local memo. Successful removal, absent removal, and duplicate
removal do not change `Revision`, `ChangeEpoch`, Query definition, View recipe,
cutoff policy, Region generation, or Source state.

Proof loss discards the memo value, last-successful forward trace, stamps,
`MemoId`, and old-value cutoff evidence. A later read follows the existing
initial-materialization path. Success installs a distinct `MemoId` with current
`verified_at` and `changed_at` and does not call cutoff because no old value
remains.

Downstream dependencies retain `QueryCore` plus their typed key rather than a
memo entry or old `MemoId`. A same-epoch parent may keep its cache. After a
later semantic publication, the retained recipe rematerializes the child and
conservatively recomputes the parent. Dynamic rematerialization records only
the current successful branch.

Failure or Cycle during rematerialization installs no memo and returns no stale
fallback. Active maps, temporary tracking frames, and the evaluation stack are
cleaned before later recovery creates a new memo identity.

## Review correction

The first reviewed implementation allowed one dynamic-trace assertion to pass
if publication of the abandoned branch failed. The validated head replaces
that ignored transaction result with fail-fast handling:

```moonbit
match store.transaction(tx => tx.set(old_source, 11)) {
  Ok(_) => ()
  Err(_) => abort("valid proof-loss publication failed unexpectedly")
}
```

The test therefore distinguishes a successful abandoned-branch publication
that remains green from a failed publication. No kernel, public interface,
testkit, or ownership-harness change was required.

## Ownership evidence

Native RC/finalizer tests distinguish memo-table values, keys retained only by
installed traces, external value aliases, surviving View keys, and Query
compute captures. Proof loss releases table-owned memo and trace edges without
invalidating legitimate external aliases. Rematerialization does not overlap
old and new memo incarnations. Region close releases remaining memo, trace,
compute, cutoff-policy, active-state, and payload ownership; a surviving View
may retain only its recipe key until that View is released.

## Validation commands and results

```text
moon fmt                                         PASS
(cd incr_next && moon info)                     PASS
public generated-interface delta                0
proof-loss dynamic-trace test, four targets     PASS
six roots x four targets                        PASS (24/24)
workspace moon check                            PASS
workspace moon test                             PASS (1,265 wasm-gc; 256 JS)
moon run incr_next/native_rc --target native    PASS
./scripts/check-incr-next-negative-probes.sh    PASS
./scripts/check-incr-next-boundaries.sh         PASS
./scripts/check-incr-next-boundaries-selftest.sh PASS
./scripts/check-workspace-boundaries.sh         PASS
./scripts/check-engine-isolation.sh             PASS
hosted required checks                          PASS (46/46)
Incr Next Required                              PASS
```

The validated implementation changes only five `incr_next/` kernel/test files.
Current `incr/`, `incr_next_testkit/`, generated `.mbti`, public API, CI, and
K1.6 implementation deltas are zero. The status-only finalization changes only
documentation, and PR #480 squash-merged an equivalent tree as
`4e66654d021435179116c0cffd56c0216b1bc664`.
