///|
pub using @incr_types {
  type Revision,
  type Durability,
  type CellId,
  type SignalId,
  type MemoId,
  type ReactiveId,
  type RelationId,
  type RuleId,
  type FunctionalRelationId,
  type CycleError,
  type ReadError,
  DURABILITY_COUNT,
  MAX_CYCLE_DISPLAY_STEPS,
  trait HasChangedAt,
  trait BackdateEq,
  type GcRole,
  type InternId,
  type InternTable,
  type AccumulatorId,
}

///|
pub using @internal {
  type Runtime,
  type CellInfo,
  type Signal,
  type Input,
  type InputField,
  type Memo,
  type Derived,
  type DerivedEnteringEvent,
  type DerivedCompletedEvent,
  type DerivedAbortedEvent,
  type DerivedEvent,
  type MemoMap,
  type DerivedMap,
  type TrackedCell,
  type HybridMemo,
  type ReachableDerived,
  type Relation,
  type FunctionalRelation,
  type MapRelation,
  type Reactive,
  type EagerDerived,
  type Effect,
  type Scope,
  type Observer,
  type Watch,
  type Accumulator,
}

// Note: @internal alias above refers to dowdiness/incr/cells (renamed from
// internal/ to enable pub using to work for external consumers who import
// dowdiness/incr). The alias name @internal is preserved for source compat.

///|
/// Deprecated alias of `DerivedEvent`. Renamed in 0.8.0; kept for source
/// compatibility and scheduled for removal in a future major release.
#deprecated("Use DerivedEvent", skip_current_package=true)
pub type MemoEvent = @internal.DerivedEvent

///|
/// Deprecated alias of `DerivedEnteringEvent`. Renamed in 0.8.0.
#deprecated("Use DerivedEnteringEvent", skip_current_package=true)
pub type MemoEnteringEvent = @internal.DerivedEnteringEvent

///|
/// Deprecated alias of `DerivedCompletedEvent`. Renamed in 0.8.0.
#deprecated("Use DerivedCompletedEvent", skip_current_package=true)
pub type MemoCompletedEvent = @internal.DerivedCompletedEvent

///|
/// Deprecated alias of `DerivedAbortedEvent`. Renamed in 0.8.0.
#deprecated("Use DerivedAbortedEvent", skip_current_package=true)
pub type MemoAbortedEvent = @internal.DerivedAbortedEvent

// Traits and helper functions are defined in traits.mbt and are part of this
// package's public API.
