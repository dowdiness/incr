///|
pub(all) enum DerivedRebuildDisposition {
  RecomputedChanged
  RecomputedBackdated
} derive(Eq, Debug)
pub extend DerivedRebuildDisposition with Eq::{not_equal, equal}
pub extend DerivedRebuildDisposition with Debug::{to_repr}

///|
pub(all) struct DerivedRebuildSummary {
  cell_id : CellId
  disposition : DerivedRebuildDisposition
  dependency_count_before : Int
  dependency_count_after : Int
  changed_at_before : Revision
  changed_at_after : Revision
  verified_at : Revision
  had_synthetic_accumulator_reads : Bool
} derive(Debug)
pub extend DerivedRebuildSummary with Debug::{to_repr}

///|
pub(all) struct DerivedRebuildAbortSummary {
  cell_id : CellId
  dependency_count_before : Int
  changed_at_before : Revision
  verified_at_before : Revision
  error : String
} derive(Debug)
pub extend DerivedRebuildAbortSummary with Debug::{to_repr}

///|
pub(all) enum EagerDerivedEvaluationDisposition {
  RecomputedChanged
  RecomputedUnchanged
} derive(Eq, Debug)
pub extend EagerDerivedEvaluationDisposition with Eq::{not_equal, equal}
pub extend EagerDerivedEvaluationDisposition with Debug::{to_repr}

///|
pub(all) struct EagerDerivedEvaluationSummary {
  cell_id : CellId
  disposition : EagerDerivedEvaluationDisposition
  level_before : Int
  level_after : Int
  dependency_count_before : Int
  dependency_count_after : Int
  changed_at_before : Revision
  changed_at_after : Revision
} derive(Debug)
pub extend EagerDerivedEvaluationSummary with Debug::{to_repr}

///|
pub(all) struct EffectExecutionSummary {
  cell_id : CellId
  level_before : Int
  level_after : Int
  dependency_count_before : Int
  dependency_count_after : Int
} derive(Debug)
pub extend EffectExecutionSummary with Debug::{to_repr}

///|
pub(all) enum PushQueueSkipReason {
  StaleLevel
  DisposedOrKindMismatch
  NotDirty
} derive(Eq, Debug)
pub extend PushQueueSkipReason with Eq::{not_equal, equal}
pub extend PushQueueSkipReason with Debug::{to_repr}

///|
pub(all) struct PushQueueSkipSummary {
  cell_id : CellId
  queued_level : Int
  current_level : Int
  reason : PushQueueSkipReason
} derive(Debug)
pub extend PushQueueSkipSummary with Debug::{to_repr}

///|
pub(all) struct PushPropagationSummary {
  changed_source_count : Int
  eager_derived_evaluation_count : Int
  effect_execution_count : Int
  skipped_queue_entry_count : Int
} derive(Debug)
pub extend PushPropagationSummary with Debug::{to_repr}

///|
pub(all) enum RuntimeEvaluationEvent {
  DerivedRebuilt(DerivedRebuildSummary)
  DerivedRebuildAborted(DerivedRebuildAbortSummary)
  EagerDerivedEvaluated(EagerDerivedEvaluationSummary)
  EffectExecuted(EffectExecutionSummary)
  PushQueueSkipped(PushQueueSkipSummary)
  PushPropagationCompleted(PushPropagationSummary)
} derive(Debug)
pub extend RuntimeEvaluationEvent with Debug::{to_repr}
