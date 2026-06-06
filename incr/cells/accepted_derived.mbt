// `AcceptedDerived[V, E]` — a success-gated derived authoring primitive.
//
// A fallible candidate `Result[V, E]` is computed from current inputs; only
// `Ok(v)` candidates that differ from the last accepted value advance the
// accepted semantic state. On `Err(e)` the previous accepted value is RETAINED
// while the current channel still reports the error. This keeps current
// diagnostics honest without destroying the last accepted value downstream UI,
// preview, or indexing stages still need.
//
// Design: docs/design/specs/2026-06-05-committed-derived.md. The engine
// mechanism was proven by the stage-2 spike
// (accepted_derived_spike_wbtest.mbt): the accept fold runs EAGERLY once per
// committed revision via an `EagerDerived` reading the candidate (push
// propagation is reachability-driven, so the fold observes every committed
// revision even when the candidate pull memo backdates), and the previous
// accepted value lives in a `Ref` OUTSIDE the reactive graph so the
// self-referencing fold forms no derived cycle.
//
// ## ReadError channel (graph mechanism failures: Cycle / Disposed)
//
// The read accessors compose `candidate.read()` DIRECTLY so a graph mechanism
// failure surfaces honestly on the read channel rather than being mistaken for
// a domain `Err(e)` or silently retaining a stale accepted value. A ReadError
// does NOT drive the acceptance state machine: the fold reads the candidate
// gracefully (`candidate.get()` -> `Result[_, ReadError]`) and skips advancing
// the retained state on `Err`.
//
// NOTE (engine limitation, verified 2026-06-06): in this engine the only
// gracefully-surfaceable ReadError is `Disposed`. A transient, persistent
// `Err(Cycle)` is structurally unreachable — incr prevents recorded dependency
// cycles, so a cell either aborts (`get_or_abort` on an in-progress dep) or
// self-heals a cycle into a domain value (`get()` handled in-compute); it never
// leaves a clean transient `Err(Cycle)` to recover from. The spec's
// "resume after a transient ReadError clears" acceptance row therefore cannot
// be constructed for Cycle (Disposed is permanent). The accessors still report
// `Disposed` honestly and leave the retained accepted state untouched.

///|
/// Status of a single committed-revision transition through the accept gate.
/// Mirrors the spec's state-machine `Status` column.
pub(all) enum AcceptStatus {
  /// No prior accepted value, candidate `Err` — nothing accepted yet.
  NoAccept
  /// The accepted value changed (first success, or a later differing success).
  AcceptedChanged
  /// A success equal to the retained accepted value — no advance.
  AcceptedUnchanged
  /// Candidate `Err` while a prior accepted value exists — value retained.
  RetainedDueToError
} derive(Eq)

///|
pub impl Show for AcceptStatus with fn output(self, logger) {
  logger.write_string(
    match self {
      NoAccept => "NoAccept"
      AcceptedChanged => "AcceptedChanged"
      AcceptedUnchanged => "AcceptedUnchanged"
      RetainedDueToError => "RetainedDueToError"
    },
  )
}

///|
/// A coherent view of one committed revision: the current candidate result, the
/// retained accepted value, and the transition status. `current` carries the
/// domain `Result[V, E]` (the read-error channel lives on the accessor return
/// type, not here).
pub struct AcceptedSnapshot[V, E] {
  current : Result[V, E]
  accepted : V?
  status : AcceptStatus
} derive(Eq)

///|
/// A success-gated derived value. Construct with `AcceptedDerived::AcceptedDerived`
/// (owns its candidate compute), `AcceptedDerived::from_candidate` (wraps an
/// existing candidate `Derived`), or `Scope::accepted_derived`.
pub struct AcceptedDerived[V, E] {
  // The fallible candidate stage. Read DIRECTLY by the accessors so a graph
  // mechanism failure (Disposed) surfaces on the read channel.
  priv candidate : Derived[Result[V, E]]
  // Graph handle for the accepted projection. Backdates on `V?`-equality, so
  // accepted-only downstream consumers do not observe current-error churn, and
  // its `changed_at()` answers `accepted_changed_at()`.
  priv accepted_cell : Derived[V?]
  // The eager accept fold. Runs once per committed revision; advances the
  // retained slot/status on a successful candidate read.
  priv fold : EagerDerived[AcceptedSnapshot[V, E]?]
  // Retained acceptance state, held OUTSIDE the reactive graph (no self-cycle).
  priv accepted_slot : Ref[V?]
  priv last_status : Ref[AcceptStatus]
  // Internal scope owning the fold, accepted_cell, the gc anchor, and (for the
  // owns-compute / scope constructors) the candidate.
  priv scope : Scope
  // Persistent gc anchor on `accepted_cell`, primed so the chain
  // (accepted_cell -> fold -> candidate) survives `Runtime::gc()`.
  priv anchor : Watch[V?]
}

///|
/// Pure acceptance transition: `(previous accepted, candidate) -> (new accepted,
/// status)`. The retained value is held externally; this is the fold body.
fn[V : Eq, E] accepted_transition(
  prev : V?,
  current : Result[V, E],
) -> (V?, AcceptStatus) {
  match (prev, current) {
    (None, Err(_)) => (None, NoAccept)
    (None, Ok(v)) => (Some(v), AcceptedChanged)
    (Some(old), Err(_)) => (Some(old), RetainedDueToError)
    (Some(old), Ok(v)) =>
      if v == old {
        (Some(old), AcceptedUnchanged)
      } else {
        (Some(v), AcceptedChanged)
      }
  }
}

///|
/// Wires the fold, accepted projection, and gc anchor over `candidate` into
/// `scope`, returning the assembled `AcceptedDerived`. The caller decides
/// whether `candidate` is owned by `scope` (owns-compute) or external
/// (`from_candidate`).
fn[V : Eq, E : Eq] AcceptedDerived::assemble(
  scope : Scope,
  candidate : Derived[Result[V, E]],
  label? : String = "accepted_derived",
) -> AcceptedDerived[V, E] {
  let accepted_slot : Ref[V?] = { val: None }
  let last_status : Ref[AcceptStatus] = { val: NoAccept }
  // Eager accept fold: runs at construction and once per committed revision.
  // A graceful `candidate.get()` lets a Disposed read skip advancing without
  // aborting; a successful read (including a domain `Err(e)`) drives the state
  // machine. Backdates on equal snapshot so an unchanged committed revision
  // (e.g. `Err(e)` then equal `Err(e)`) does not wake snapshot watchers.
  let fold = scope.eager_derived(() => {
    match candidate.get() {
      Ok(domain) => {
        let (new_accepted, status) = accepted_transition(
          accepted_slot.val,
          domain,
        )
        accepted_slot.val = new_accepted
        last_status.val = status
        Some({ current: domain, accepted: new_accepted, status })
      }
      Err(_) => None // ReadError (Disposed): do not advance the state machine.
    }
  })
  // Accepted projection: recomputes when the fold's value changes, projects the
  // retained accepted value, and backdates on `V?`-equality.
  let accepted_cell = scope.derived(
    () => {
      ignore(fold.get())
      accepted_slot.val
    },
    label="\{label}.accepted",
  )
  // gc anchor: root `accepted_cell` and prime it so its upstream
  // dependencies (fold -> candidate) are recorded before any `Runtime::gc()`.
  let anchor = scope.add_watch(accepted_cell.watch())
  ignore(anchor.read())
  { candidate, accepted_cell, fold, accepted_slot, last_status, scope, anchor }
}

///|
/// Builds an `AcceptedDerived` that owns its candidate compute. Domain failures
/// are values (`Result[V, E]`), never raised — the compute is `noraise` like
/// `Derived::fallible`.
pub fn[V : Eq, E : Eq] AcceptedDerived::AcceptedDerived(
  rt : Runtime,
  compute : () -> Result[V, E],
  label? : String,
) -> AcceptedDerived[V, E] {
  let scope = Scope::new(rt)
  let candidate = Derived::fallible(rt, compute, label?)
  scope.add_cell_ids([candidate.inner.id()])
  AcceptedDerived::assemble(scope, candidate, label?)
}

///|
/// Builds an `AcceptedDerived` over an existing candidate `Derived`. The
/// candidate's lifecycle is owned by the CALLER — `AcceptedDerived::dispose`
/// disposes only the fold, accepted projection, and gc anchor, not the
/// candidate.
pub fn[V : Eq, E : Eq] AcceptedDerived::from_candidate(
  candidate : Derived[Result[V, E]],
  label? : String,
) -> AcceptedDerived[V, E] {
  let scope = Scope::new(candidate.inner.rt)
  AcceptedDerived::assemble(scope, candidate, label?)
}

///|
/// Scope-owned convenience, mirroring `Scope::derived`. The returned
/// `AcceptedDerived` lives in a child scope, so disposing `self` disposes it.
pub fn[V : Eq, E : Eq] Scope::accepted_derived(
  self : Scope,
  compute : () -> Result[V, E],
  label? : String,
) -> AcceptedDerived[V, E] {
  guard !self.is_disposed() else {
    abort("Scope::accepted_derived called on a disposed scope")
  }
  let child = self.child()
  let candidate = Derived::fallible(child.runtime, compute, label?)
  child.add_cell_ids([candidate.inner.id()])
  AcceptedDerived::assemble(child, candidate, label?)
}

///|
/// The current candidate result for the latest committed revision. The outer
/// `Result` is the read channel (`Cycle` / `Disposed`); the inner `Result[V, E]`
/// is the domain candidate.
pub fn[V, E] AcceptedDerived::current(
  self : AcceptedDerived[V, E],
) -> Result[Result[V, E], ReadError] {
  self.candidate.read()
}

///|
/// The last accepted value, or a read error. The retained accepted value is
/// left untouched by a read error; the read returns the error in its place.
pub fn[V, E] AcceptedDerived::accepted(
  self : AcceptedDerived[V, E],
) -> Result[V?, ReadError] {
  match self.candidate.read() {
    Ok(_) => Ok(self.accepted_slot.val)
    Err(e) => Err(e)
  }
}

///|
/// A coherent snapshot (current + accepted + status), or a read error.
pub fn[V, E] AcceptedDerived::snapshot(
  self : AcceptedDerived[V, E],
) -> Result[AcceptedSnapshot[V, E], ReadError] {
  match self.candidate.read() {
    Ok(current) =>
      Ok({
        current,
        accepted: self.accepted_slot.val,
        status: self.last_status.val,
      })
    Err(e) => Err(e)
  }
}

///|
/// Strict `current` read; aborts on a read error.
pub fn[V, E] AcceptedDerived::current_or_abort(
  self : AcceptedDerived[V, E],
) -> Result[V, E] {
  match self.current() {
    Ok(c) => c
    Err(e) => abort(e.format_path())
  }
}

///|
/// Strict `accepted` read; aborts on a read error.
pub fn[V, E] AcceptedDerived::accepted_or_abort(
  self : AcceptedDerived[V, E],
) -> V? {
  match self.accepted() {
    Ok(a) => a
    Err(e) => abort(e.format_path())
  }
}

///|
/// Strict `snapshot` read; aborts on a read error.
pub fn[V, E] AcceptedDerived::snapshot_or_abort(
  self : AcceptedDerived[V, E],
) -> AcceptedSnapshot[V, E] {
  match self.snapshot() {
    Ok(s) => s
    Err(e) => abort(e.format_path())
  }
}

///|
/// Revision at which the accepted value last actually changed. Gated solely by
/// `V`-equality on the accepted value: current-result churn (changing
/// diagnostics, repeated errors, equal successful recomputations) never
/// advances it. This is an `incr` graph `Revision`, not a domain document
/// revision.
pub fn[V, E] AcceptedDerived::accepted_changed_at(
  self : AcceptedDerived[V, E],
) -> Revision {
  // `accepted_cell` is lazy; force verification through the persistent anchor
  // so `changed_at` reflects the latest committed revision rather than a stale
  // pre-recompute value.
  ignore(self.anchor.read())
  self.accepted_cell.changed_at()
}

///|
/// A persistent outside-graph anchor on the accepted projection. The caller
/// owns the returned `Watch` and must `dispose()` it when done. It backdates
/// with the accepted value, so it is woken only when the accepted value
/// actually changes — not on current-error churn.
pub fn[V, E] AcceptedDerived::watch_accepted(
  self : AcceptedDerived[V, E],
) -> Watch[V?] {
  self.accepted_cell.watch()
}

///|
/// Disposes this `AcceptedDerived`. Idempotent. For `from_candidate`, the
/// external candidate is NOT disposed (the caller owns it).
pub fn[V, E] AcceptedDerived::dispose(self : AcceptedDerived[V, E]) -> Unit {
  self.scope.dispose()
}

///|
/// Returns true if this `AcceptedDerived` has been disposed.
pub fn[V, E] AcceptedDerived::is_disposed(self : AcceptedDerived[V, E]) -> Bool {
  self.scope.is_disposed()
}
