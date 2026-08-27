# K1.2 validation record

**Reader:** K1.2 maintainers and reviewers.

**Decision:** Add typed per-Query memos, last-successful forward verification,
and target-local failure atomicity to the accepted K1.1 kernel while preserving
Fresh independence, ownership boundaries, and the small public interface.
The testkit model is corrected to a two-phase Script: `initial_sources` fixes
Source membership and values before graph setup, while `operations` only replay
Reads, existing Source Sets, or invocations of prepared error Views.

**Keep until:** The accepted K1 baseline is superseded by an explicit K0
contract change.

**Disposition:** Accepted K1.2 validation record. The candidate is based on
`0c5ae4e50622f55b288aa536722e3ac77a71e030`; the accepted implementation head
is `12ec2404b676ef7864e353aeb3681c0fef6f20e3`; it merged as squash commit
`db2ac77ac0362a7c5ff8d20887868cbdbb635aa8`. Local gates, hosted CI,
CodeRabbit, independent reviews, and maintainer acceptance pass. K1.3
invocation-level cycle detection is accepted at implementation head
`e187b562f87ec4ecd50940a5e8fc2bc5d478380c`, finalized at status-only head
`a8115757662a6412e053aad9b7dc451f39a825c6`, and merged as squash commit
`5657cfc99734c9ac9e7093dd71819d6a0c48df87`. K1.3 CodeRabbit skipped content
review and is not positive evidence; hosted CI, independent public diff review,
and maintainer acceptance pass. K1.4 is accepted at implementation/validation head
`0036bdd199a685823b6769bf1acdac3f9b6b9014`, finalized at status-only head
`c88e724383ca5f3e817f30226a9fa23cf3ad7358`, and merged as squash commit
`9d53d51d6ec6e282b8aa247442ee126acfe64a2d`. Hosted acceptance passed 46/46,
public diff review was APPROVE, maintainer acceptance was PASS, and squash-tree
equivalence passed. CodeRabbit skipped content review and is not positive
evidence; independent public review supplies review evidence. K1.5 is accepted
and merged at implementation head `064a80ac884f7c5588f123cc62dd784adeb26b48`,
review-fix head `378df40f7b84e1b6a3ebdb7f32299e2d628f1d54`, status-only
head `6de46abf19acb69cc5d5274b89a0ee780e48fb8d`, and squash merge commit
`4e66654d021435179116c0cffd56c0216b1bc664`; hosted and maintainer acceptance
and squash-tree equivalence passed. K1.6 is accepted and merged, completing K1
under the sibling-product ADR. Package publication remains unauthorized.

## Generated-interface probe

The pinned MoonBit archive probe selected this sole public interface delta:

```text
Region::query[K : Hash + Eq, V]
```

`Query[K, V]` and `Query::at` remain unbounded. A generic struct bound is not
accepted by the compiler, and placing the bound on `Query::at` moves the
constraint away from the typed memo construction boundary. The reproducible
probe and compiler identity are recorded in
[the key-bound compile probe](2026-08-14-k1-2-key-bound-compile-probe.md).
Callers must keep a retained key's hashing and equality stable.

## Behavioral evidence

K1.2a provides one private `Map[K, MemoEntry[V]]` and `MemoId` sequence per
Query. Successful entries own their value, last-successful Source/Query/Revision
forward trace, `verified_at`, and `changed_at`. Same-epoch reads hit the typed
memo. Different Query instances and keys remain isolated, and Region close
clears memo values, traces, and compute captures while surviving Views retain
only their recipe shell and key.

K1.2b checks every direct dependency against the entry's prior `verified_at`.
A green verification changes only `verified_at`; a selected red path recomputes
with a fresh trace and current epoch stamps. Tests cover recursive child
verification, one verification or compute per selected diamond child and epoch,
unrelated and selected publication, Revision-clock dependencies, dynamic trace
replacement, and same-Store cross-Region branch-away after an old Region closes.
The DynamicBranch test predeclares both Source handles and captures them before
Query construction. Its Script starts with `0=0, 1=0`, then publishes branch
`1 -> 9` and the old base `0 -> 7`; the final `9` result and Fresh/kernel work
counts `3/2` show that the replaced trace no longer treats the base as
authoritative. The keyed differential similarly starts with `0=0, 1=10`.

K1.2c keeps last-successful authority local to the target invocation. An initial
structural failure installs no memo. A failed stale recomputation returns the
current structural error without stale fallback and preserves the old value,
trace, stamps, and `MemoId` exactly. Successful child work remains installed
when its parent fails. A later success keeps the target `MemoId`, replaces the
value and trace, and stamps the current epoch. Failed temporary frames are
expired and released.

Fresh remains independent of `dowdiness/incr_next` and evaluates every graph
from scratch. Differential comparison excludes its separate work counter but
keeps ordered values, missing-source observations, and normalized errors. The
failure/recovery workload records the middle read as
`StructuralFailure(1)`, distinct from `Missing(0)`, in both Fresh and the kernel
adapter.

The private Script validator now checks required setup IDs and operation shape
before either evaluator constructs a graph. Fixed-root reads of present
non-root IDs are rejected, while reads of absent IDs remain valid `Missing`
cases. Keyed reads and the domain/structural error capabilities are restricted
to their matching scenarios. Both evaluators construct every logical Source and
all Query/error fixtures from setup data before replay; replay only performs
Reads, existing Source Sets, or invokes prepared error Views. A valid Set must
commit successfully; the adapter aborts on any unexpected transaction error so
a failed publication cannot become a false-positive differential result. The
structural fixture uses prebuilt keyed Query/Views, so it does not add a hidden
logical Source.

## Acceptance gate evidence

The candidate passes:

- six package roots across default, native, JavaScript, and wasm-gc targets:
  24 of 24 check-and-test cells;
- workspace tests: 1,211 wasm-gc and 256 JavaScript;
- native RC/finalizer probes for successful replacement of old memo values and
  traces, failed temporary-trace release with old authority retained, and
  Region-close release while a View survives;
- boundary self-tests and checks, typed negative probes, engine/workspace
  isolation, and documentation boundaries;
- generated-interface review: the `Region::query` bound is the only public
  `incr_next/pkg.generated.mbti` delta;
- zero current-`incr/` implementation or interface diff;
- zero K1.3+ cycle, cutoff/backdating, eviction, Mount, Program, or public
  debug/explain surface;
- independent MoonBit and adversarial reviews;
- hosted CI, the `Incr Next Required` aggregate, CodeRabbit, and maintainer
  acceptance.

## Reuse check

The implementation reuses the K1.1 `QueryContext` child/frame/expiry boundary,
Region close actions, Store lifetime and clock checks, and the existing
Source/Query/Revision dependency-verifier shape. MoonBit core `Map` supplies
typed key lookup and replacement; `Array::fold` verifies complete traces; `Ref`
owns private clocks, counters, and capabilities; `Option` and `Result` retain
lifetime and structural-failure channels; and `Hash`/`Eq` define typed memo key
identity.

Key erasure, a linear-search table, and a generic defensive copy were checked
and rejected because they would weaken the selected typed ownership and caller
contracts. The kernel adds no public helper or type. The independent testkit
adds transparent `SourceInit` setup values and defensive Script snapshot
accessors to expose its two-phase input language. Remaining kernel mutation is
confined to private memo tables, counters, temporary tracking frames, clock
publication, and Region-close actions. Testkit mutation is local to setup
validation, Fresh state, and transactional replay.
