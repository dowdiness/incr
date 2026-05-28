///|
struct EvaluationStrategyScenarioResult {
  derived_values : Array[Int]
  eager_derived_values : Array[Int]
  effect_log : Array[Int]
  revision : Revision
}

///|
fn run_evaluation_strategy_scenario(
  strategies : EvaluationStrategies,
) -> EvaluationStrategyScenarioResult {
  let rt = Runtime()
  rt.install_evaluation_strategies(strategies)
  let source = Signal(rt, 1)
  let derived = Memo(rt, () => source.get() * 10)
  let eager = Reactive::new(rt, () => derived.get() + 1)
  let effect_log : Array[Int] = []
  let _effect = Effect::new(rt, () => effect_log.push(eager.get()))
  let derived_values : Array[Int] = []
  let eager_derived_values : Array[Int] = []
  derived_values.push(read_memo_for_test(derived))
  eager_derived_values.push(read_reactive_for_test(eager))
  source.set(2)
  derived_values.push(read_memo_for_test(derived))
  eager_derived_values.push(read_reactive_for_test(eager))
  rt.batch(() => {
    source.set(3)
    source.set(4)
  })
  derived_values.push(read_memo_for_test(derived))
  eager_derived_values.push(read_reactive_for_test(eager))
  {
    derived_values,
    eager_derived_values,
    effect_log,
    revision: rt.core.revision.current_revision,
  }
}

///|
test "evaluation strategy: tracing preserves graph values and records counters" {
  let default_result = run_evaluation_strategy_scenario(
    EvaluationStrategies::default(),
  )
  let recorder = @kernel.EvaluationTraceRecorder()
  let tracing_result = run_evaluation_strategy_scenario(
    EvaluationStrategies::tracing(recorder),
  )
  debug_inspect(default_result.derived_values, content="[10, 20, 40]")
  debug_inspect(tracing_result.derived_values, content="[10, 20, 40]")
  debug_inspect(default_result.eager_derived_values, content="[11, 21, 41]")
  debug_inspect(tracing_result.eager_derived_values, content="[11, 21, 41]")
  debug_inspect(default_result.effect_log, content="[11, 21, 41]")
  debug_inspect(tracing_result.effect_log, content="[11, 21, 41]")
  inspect(default_result.revision == tracing_result.revision, content="true")
  let trace = recorder.summary()
  inspect(trace.derived_pull_verification_count, content="2")
  inspect(trace.derived_rebuild_count, content="3")
  inspect(trace.derived_rebuild_abort_count, content="0")
  inspect(trace.eager_derived_evaluation_count, content="2")
  inspect(trace.effect_execution_count, content="2")
  inspect(trace.push_propagation_count, content="2")
  inspect(trace.changed_source_count, content="2")
  inspect(trace.push_queue_skip_count, content="0")
  inspect(recorder.events().length(), content="9")
}

///|
test "evaluation strategy: tracing records lazy derived rebuilds without listener" {
  let recorder = @kernel.EvaluationTraceRecorder()
  let rt = Runtime()
  rt.install_evaluation_strategies(EvaluationStrategies::tracing(recorder))
  let source = Signal(rt, 1)
  let derived = Memo(rt, () => source.get() + 1)

  inspect(read_memo_for_test(derived), content="2")
  inspect(rt.runtime_evaluation_event_hook.pending.length(), content="0")
  source.set(2)
  inspect(read_memo_for_test(derived), content="3")

  let trace = recorder.summary()
  inspect(trace.derived_pull_verification_count, content="1")
  inspect(trace.derived_rebuild_count, content="2")
  inspect(trace.push_propagation_count, content="0")
  let events = recorder.events()
  inspect(events.length(), content="2")
  match events[events.length() - 1] {
    DerivedRebuilt(summary) => {
      inspect(summary.cell_id == derived.id(), content="true")
      inspect(summary.dependency_count_after, content="1")
    }
    _ => abort("expected DerivedRebuilt")
  }
}

///|
test "evaluation strategy: tracing records lazy derived aborts without listener" {
  let recorder = @kernel.EvaluationTraceRecorder()
  let rt = Runtime()
  rt.install_evaluation_strategies(EvaluationStrategies::tracing(recorder))
  let derived : Memo[Int] = Memo(rt, () => raise Failure("traced boom"))

  let result : Result[Result[Int, CycleError], Failure] = try? derived.force_recompute()
  inspect(result is Err(_), content="true")
  inspect(rt.runtime_evaluation_event_hook.pending.length(), content="0")

  let trace = recorder.summary()
  inspect(trace.derived_rebuild_count, content="0")
  inspect(trace.derived_rebuild_abort_count, content="1")
  let events = recorder.events()
  inspect(events.length(), content="1")
  match events[0] {
    DerivedRebuildAborted(summary) => {
      inspect(summary.cell_id == derived.id(), content="true")
      inspect(summary.error.contains("traced boom"), content="true")
    }
    _ => abort("expected DerivedRebuildAborted")
  }
}

///|
fn run_evaluation_strategy_fixpoint_scenario(
  strategies : EvaluationStrategies,
) -> Int {
  let rt = Runtime()
  rt.install_evaluation_strategies(strategies)
  let relation : Relation[Int] = Relation::Relation(rt)
  relation.insert(1) |> ignore
  relation.insert(2) |> ignore
  rt.fixpoint()
  relation.iter().fold(init=0, (sum, value) => sum + value)
}

///|
test "evaluation strategy: tracing records fixpoint dispatch" {
  let default_sum = run_evaluation_strategy_fixpoint_scenario(
    EvaluationStrategies::default(),
  )
  let recorder = @kernel.EvaluationTraceRecorder()
  let tracing_sum = run_evaluation_strategy_fixpoint_scenario(
    EvaluationStrategies::tracing(recorder),
  )
  inspect(default_sum, content="3")
  inspect(tracing_sum, content="3")
  let trace = recorder.summary()
  inspect(trace.fixpoint_run_count, content="1")
  inspect(recorder.events().length(), content="0")
}

///|
test "evaluation strategy: tracing forwards runtime evaluation events" {
  let recorder = @kernel.EvaluationTraceRecorder()
  let rt = Runtime()
  rt.install_evaluation_strategies(EvaluationStrategies::tracing(recorder))
  let source = Signal(rt, 0)
  let events : Array[@kernel.RuntimeEvaluationEvent] = []
  rt.runtime_evaluation_event_hook.listener = Some(fn(event) {
    events.push(event)
  })
  let eager = Reactive::new(rt, () => source.get() + 1)
  source.set(1)
  inspect(read_reactive_for_test(eager), content="2")
  let trace = recorder.summary()
  inspect(trace.push_propagation_count, content="1")
  inspect(trace.eager_derived_evaluation_count, content="1")
  inspect(events.length(), content="2")
  match events[events.length() - 1] {
    PushPropagationCompleted(summary) => {
      inspect(summary.changed_source_count, content="1")
      inspect(summary.eager_derived_evaluation_count, content="1")
    }
    _ => abort("expected PushPropagationCompleted")
  }
}
