# K1.2 local validation record

**Reader:** K1.2 maintainers and reviewers.

**Decision:** Add typed per-Query memos, last-successful forward verification,
and target-local failure atomicity to the accepted K1.1 kernel while preserving
Fresh independence, ownership boundaries, and the small public interface.

**Keep until:** K1.2 is accepted, rejected, or superseded by a later kernel
slice.

**Disposition:** Local gate pass; implementation not accepted; unpublished.
The candidate is based on `0c5ae4e50622f55b288aa536722e3ac77a71e030`.
The kernel implementation ends at `ece8cfe`; later commits contain testkit and
documentation corrections only. PR #474 is open. Hosted CI, maintainer
acceptance, and merge remain pending separate authorization. K1.3–K1.6 remain
blocked and uncommissioned.

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
Query construction. It publishes branch `0 -> 9`, then publishes the old base;
the final `9` result and Fresh/kernel work counts `3/2` show that the replaced
trace no longer treats the base as authoritative.

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

## Local gate evidence

The candidate passes:

- six package roots across default, native, JavaScript, and wasm-gc targets:
  24 of 24 check-and-test cells;
- workspace tests: 1,204 wasm-gc and 256 JavaScript;
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
- independent MoonBit and adversarial reviews.

These are local results. They do not constitute hosted CI or maintainer
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
contracts. No new public helper or type was introduced. Remaining mutation is
confined to private memo tables, counters, temporary tracking frames, clock
publication, and Region-close actions; these form the imperative shell around
the deterministic verification decision.
