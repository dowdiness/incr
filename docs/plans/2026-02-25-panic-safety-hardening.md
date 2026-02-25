# Graceful Error Handling Plan (Updated Direction)

**Goal:** Make `incr` handle user-facing failures gracefully by default (`Result` / `raise` paths), while reserving `abort()` for true invariant corruption only.

**Direction change:** prioritize graceful behavior over panic-centric behavior.  
The library should continue running after expected failure modes (cycles, raised callback errors, invalid dynamic flows) without leaving runtime state poisoned.

**Important language constraint:** MoonBit `abort()` is not catchable. We can recover from `raise`, but not from `abort`.

---

### Scope

In scope:
- Graceful handling for **raised** errors in batching and callback paths
- Runtime state restoration on raised errors (no leaked batch/transient state)
- Tests that lock in graceful behavior and characterize uncaught `abort` limits
- Documentation updates for graceful usage patterns

Out of scope:
- Full recovery from `abort()` (not possible in MoonBit)
- Push-pull invalidation and GC work

---

### Progress Snapshot

- [x] Added characterization tests for leaked batch/tracking state simulation
  - `internal/batch_wbtest.mbt`
  - `internal/verify_wbtest.mbt`
- [x] Implemented raised-error-safe batching
  - `Runtime::batch` now accepts `f : () -> Unit raise?`
  - raised errors rollback pending writes and restore `batch_depth`
- [x] Added rollback plumbing for batched signals
  - `rollback_pending` closure in `CellMeta`
  - signal rollback hook registration in batch set paths
- [x] Added regression test: raised error in batch rolls back and preserves runtime consistency
- [x] Added non-panicking convenience reads
  - `Memo::get_or`, `Memo::get_or_else`
  - `MemoMap::get_or`, `MemoMap::get_or_else`
- [x] Added transactional `Result` batch API
  - `Runtime::batch_result`
  - `@incr.batch_result`

---

### Task 1: Finish graceful API documentation pass

**Files:**
- Modify: `README.md`
- Modify: `docs/getting-started.md`
- Modify: `docs/api-reference.md`
- Modify: `docs/design.md`

Update docs to clearly state:
- Prefer `get_result()` over `get()` for graceful cycle handling
- `Runtime::batch` supports raised-error rollback semantics
- `abort()` inside user closures is not recoverable

---

### Task 2: Audit and reduce user-triggerable aborts

**Files:**
- Modify: `internal/runtime.mbt`
- Modify: `internal/memo.mbt`
- Modify: `internal/verify.mbt`
- Modify tests under `internal/*_wbtest.mbt`

Actions:
- Classify each `abort()` site as:
  - internal invariant guard (keep, but improve message), or
  - user-triggerable path (replace with graceful return/raise API)
- Add tests for each converted path

### Remaining `abort()` Sites (Post-Audit)

User-facing convenience aborts (kept, with graceful alternatives):
- `Memo::get()` aborts on cycle
  - alternatives: `Memo::get_result`, `Memo::get_or`, `Memo::get_or_else`
- `MemoMap::get()` can abort via underlying memo cycle
  - alternatives: `MemoMap::get_result`, `MemoMap::get_or`, `MemoMap::get_or_else`

Invariant guards (kept):
- Runtime cell lookup invariants (`get_cell`)
- Batch depth underflow guards
- Missing `commit_pending` / `rollback_pending` invariant checks
- Tracking stack underflow
- Missing derived recompute closure in verifier

Rationale:
- These indicate internal corruption or whitebox misuse and should fail fast.

---

### Task 3: Add explicit non-panicking entrypoints where missing

**Files:**
- Modify: `internal/*.mbt`
- Modify: `traits.mbt`
- Modify: `incr.mbt` (re-exports if needed)
- Modify tests in `tests/*.mbt`

Actions:
- Ensure each public operation with realistic failure mode has a graceful variant
- Keep existing panic-oriented convenience methods for ergonomics, but document them as such

---

### Task 4: Validate behavior and coverage

Run:
```bash
moon check
moon test
moon coverage analyze
```

Acceptance criteria:
- no regressions in existing suite
- graceful-path tests pass
- coverage improves in newly added rollback/error branches

---

### Task 5: Update project tracking docs

**Files:**
- Modify: `docs/todo.md`
- Modify: `docs/roadmap.md` (if needed)

Update TODO/roadmap to reflect:
- graceful handling direction
- completed rollback-on-raise batching work
- explicit `abort` limitation note
