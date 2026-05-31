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
  type MemoEnteringEvent,
  type MemoCompletedEvent,
  type MemoAbortedEvent,
  type MemoEvent,
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

// Traits and helper functions are defined in traits.mbt and are part of this
// package's public API.
