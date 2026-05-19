///|
/// Cross-cutting commit-phase observer for pull-mode memo recomputes.
///
/// Implementors register with `Runtime.commit_hooks` (insertion order) and
/// observe each memo recompute's lifecycle:
///
/// - `before_recompute` fires before the tracking frame is pushed.
/// - `after_abort` fires inside the catch arm, before pop_tracking, with the raised Error in scope.
/// - `after_success` fires AFTER the cell-level epilogue is complete
///   (`changed_at` / `verified_at` / `has_been_computed` / `in_progress = false`
///   are all settled). Backdating is detectable via
///   `cell.meta.changed_at < cell.verified_at`.
///
/// Implementors manage their own per-cell state (no associated `Snapshot`
/// type). For each `before_recompute(cell_id)` there is exactly one matching
/// `after_success(cell_id)` or `after_abort(cell_id)`. Dispatch is
/// forward-insertion-order on BOTH success and abort paths.
///
/// # Hook contract — implementors MUST NOT call user code inline
///
/// Hooks fire inside `memo_force_recompute`, but the typed wrapper at
/// `Memo::force_recompute` writes `self.value = Some(new_value)` after this
/// returns. A user callback that synchronously reads the memo would see the
/// stale typed cache. Hooks must mutate only their own state + runtime
/// fields; surfacing events to user code requires the buffer-and-flush
/// pattern documented in the event-observation ADR
/// (`docs/decisions/2026-05-17-memo-event-observation.md`).
///
/// # Placement
///
/// Lives at `cells/` (not `cells/internal/kernel/`) because methods take
/// `Runtime` as a parameter, and kernel cannot import `cells/` (invariant 4
/// in `scripts/check-engine-isolation.sh`). Mirrors the `CellLifecycle`
/// precedent at `cells/runtime.mbt:33`.
priv trait MemoCommitPhase {
  before_recompute(Self, Runtime, CellId) -> Unit
  after_success(Self, Runtime, CellId) -> Unit
  after_abort(Self, Runtime, CellId, Error) -> Unit
}
