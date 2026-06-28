///|
fn runtime_eval_event_kind(event : @kernel.RuntimeEvaluationEvent) -> String {
  match event {
    DerivedRebuilt(_) => "derived_rebuilt"
    DerivedRebuildAborted(_) => "derived_aborted"
    EagerDerivedEvaluated(_) => "eager_evaluated"
    EffectExecuted(_) => "effect_executed"
    PushQueueSkipped(_) => "queue_skipped"
    PushPropagationCompleted(_) => "push_completed"
  }
}

///|
fn collect_runtime_eval_events(
  rt : Runtime,
) -> Array[@kernel.RuntimeEvaluationEvent] {
  let events : Array[@kernel.RuntimeEvaluationEvent] = []
  rt.runtime_evaluation_event_hook.listener = Some(fn(event) {
    events.push(event)
  })
  events
}

///|
test "runtime_eval: disabled hook does not buffer derived rebuild events" {
  let rt = Runtime()
  let source = Input(rt, 1)
  let derived = Derived(rt, () => source.get() + 1)
  inspect(derived.read_or_abort(), content="2")
  inspect(rt.runtime_evaluation_event_hook.pending.length(), content="0")
  inspect(rt.runtime_evaluation_event_hook.active.length(), content="0")
}

///|
test "runtime_eval: derived rebuild drains after typed cache is written" {
  let rt = Runtime()
  let source = Input(rt, 1)
  let derived = Derived(rt, () => source.get() + 1)
  let listener_reads : Array[Int] = []
  let events : Array[@kernel.RuntimeEvaluationEvent] = []
  rt.runtime_evaluation_event_hook.listener = Some(fn(event) {
    events.push(event)
    match event {
      DerivedRebuilt(_) => listener_reads.push(derived.read_or_abort())
      _ => ()
    }
  })
  inspect(derived.read_or_abort(), content="2")
  inspect(listener_reads.length(), content="1")
  inspect(listener_reads[0], content="2")
  inspect(events.length(), content="1")
  match events[0] {
    DerivedRebuilt(summary) => {
      inspect(summary.cell_id == derived.id(), content="true")
      inspect(
        summary.disposition ==
        @kernel.DerivedRebuildDisposition::RecomputedChanged,
        content="true",
      )
      inspect(summary.dependency_count_before, content="0")
      inspect(summary.dependency_count_after, content="1")
    }
    _ => abort("expected DerivedRebuilt")
  }
}

///|
test "runtime_eval: derived backdated rebuild reports backdated disposition" {
  let rt = Runtime()
  let source = Input(rt, 1)
  let derived = Derived(rt, () => source.get() % 2)
  let events = collect_runtime_eval_events(rt)
  inspect(derived.read_or_abort(), content="1")
  events.clear()
  source.set(3)
  inspect(derived.read_or_abort(), content="1")
  inspect(events.length(), content="1")
  match events[0] {
    DerivedRebuilt(summary) => {
      inspect(summary.cell_id == derived.id(), content="true")
      inspect(
        summary.disposition ==
        @kernel.DerivedRebuildDisposition::RecomputedBackdated,
        content="true",
      )
      inspect(
        summary.changed_at_before == summary.changed_at_after,
        content="true",
      )
    }
    _ => abort("expected DerivedRebuilt")
  }
}

///|
test "runtime_eval: derived catchable abort reports abort summary" {
  let rt = Runtime()
  let events = collect_runtime_eval_events(rt)
  let derived : Derived[Int] = Derived(rt, () => raise Failure("derived boom"))
  let mut failed = false
  try derived.force_recompute() catch {
    _ => failed = true
  } noraise {
    _ => ()
  }
  inspect(failed, content="true")
  rt.drain_pending_events_if_idle()
  inspect(events.length(), content="1")
  match events[0] {
    DerivedRebuildAborted(summary) => {
      inspect(summary.cell_id == derived.id(), content="true")
      inspect(summary.error.contains("derived boom"), content="true")
    }
    _ => abort("expected DerivedRebuildAborted")
  }
}

///|
test "runtime_eval: direct drain flushes abort with active tracking frame" {
  let rt = Runtime()
  let events = collect_runtime_eval_events(rt)
  let outer = Derived(rt, () => 0)
  let derived : Derived[Int] = Derived(rt, () => raise Failure("nested boom"))
  rt.begin_tracking(outer.id())
  let mut failed = false
  try derived.force_recompute() catch {
    _ => failed = true
  } noraise {
    _ => ()
  }
  inspect(failed, content="true")
  inspect(rt.core.tracking.stack.length(), content="1")
  rt.drain_pending_events_if_idle()
  inspect(events.length(), content="0")
  rt.drain_pending_events_direct()
  inspect(events.length(), content="1")
  match events[0] {
    DerivedRebuildAborted(summary) => {
      inspect(summary.cell_id == derived.id(), content="true")
      inspect(summary.error.contains("nested boom"), content="true")
    }
    _ => abort("expected DerivedRebuildAborted")
  }
  ignore(rt.pop_tracking_full())
}

///|
test "runtime_eval: input set emits eager derived, effect, and pass summaries" {
  let rt = Runtime()
  let source = Input(rt, 0)
  let events = collect_runtime_eval_events(rt)
  let eager = Reactive::new(rt, () => source.get() + 1)
  let effect_log : Array[Int] = []
  let _effect = Effect::new(rt, () => effect_log.push(source.get()))
  events.clear()
  source.set(1)
  inspect(read_reactive_for_test(eager), content="2")
  debug_inspect(effect_log, content="[0, 1]")
  let kinds = events.map(runtime_eval_event_kind)
  inspect(kinds.contains("eager_evaluated"), content="true")
  inspect(kinds.contains("effect_executed"), content="true")
  inspect(kinds.contains("push_completed"), content="true")
  for event in events {
    match event {
      EagerDerivedEvaluated(summary) => {
        inspect(summary.cell_id == eager.id(), content="true")
        inspect(
          summary.disposition ==
          @kernel.EagerDerivedEvaluationDisposition::RecomputedChanged,
          content="true",
        )
      }
      PushPropagationCompleted(summary) => {
        inspect(summary.changed_source_count, content="1")
        inspect(summary.eager_derived_evaluation_count >= 1, content="true")
        inspect(summary.effect_execution_count >= 1, content="true")
      }
      _ => ()
    }
  }
}

///|
test "runtime_eval: eager derived unchanged summary reports unchanged" {
  let rt = Runtime()
  let source = Input(rt, 0)
  let events = collect_runtime_eval_events(rt)
  let eager = Reactive::new(rt, () => {
    ignore(source.get())
    5
  })
  events.clear()
  source.set(1)
  inspect(read_reactive_for_test(eager), content="5")
  let mut saw_unchanged = false
  for event in events {
    match event {
      EagerDerivedEvaluated(summary) => {
        inspect(summary.cell_id == eager.id(), content="true")
        inspect(
          summary.disposition ==
          @kernel.EagerDerivedEvaluationDisposition::RecomputedUnchanged,
          content="true",
        )
        saw_unchanged = true
      }
      _ => ()
    }
  }
  inspect(saw_unchanged, content="true")
}

///|
test "runtime_eval: queue skip and pass summary report stale entry" {
  let rt = Runtime()
  let source = Input(rt, 0)
  let events = collect_runtime_eval_events(rt)
  let r2_ref : Ref[Reactive[Int]?] = { val: None }
  let r0 = Reactive::new(rt, () => {
    let v = source.get()
    if v > 0 {
      match r2_ref.val {
        Some(r) => r.dispose()
        None => ()
      }
    }
    v
  })
  let r2 = Reactive::new(rt, () => {
    let _ = source.get()
    r0.get() + 1
  })
  r2_ref.val = Some(r2)
  events.clear()
  source.set(1)
  let mut saw_skip = false
  let mut saw_pass_count = false
  for event in events {
    match event {
      PushQueueSkipped(summary) => {
        inspect(summary.cell_id == r2.id(), content="true")
        inspect(
          summary.reason == @kernel.PushQueueSkipReason::DisposedOrKindMismatch,
          content="true",
        )
        saw_skip = true
      }
      PushPropagationCompleted(summary) => {
        inspect(summary.skipped_queue_entry_count >= 1, content="true")
        saw_pass_count = true
      }
      _ => ()
    }
  }
  inspect(saw_skip, content="true")
  inspect(saw_pass_count, content="true")
}

///|
test "runtime_eval: queue skip keeps original cell id after slot reuse" {
  let rt = Runtime()
  let source = Input(rt, 0)
  let events = collect_runtime_eval_events(rt)
  let r2_ref : Ref[Reactive[Int]?] = { val: None }
  let replacement_ref : Ref[Reactive[Int]?] = { val: None }
  let mut replacement_runs = 0
  let r0 = Reactive::new(rt, () => {
    let v = source.get()
    if v > 0 {
      match r2_ref.val {
        Some(r) => {
          r.dispose()
          let replacement = Reactive::new(rt, () => {
            replacement_runs += 1
            source.get() + 100
          })
          replacement_ref.val = Some(replacement)
          match rt.core.cell_index[replacement.id().id] {
            PushReactive(idx) => {
              rt.push.reactives[idx].dirty = true
              rt.push.reactives[idx].level = 2
            }
            _ => abort("expected replacement PushReactive")
          }
        }
        None => ()
      }
    }
    v
  })
  let r2 = Reactive::new(rt, () => {
    let _ = source.get()
    r0.get() + 1
  })
  r2_ref.val = Some(r2)
  let queued_cell_id = r2.id()
  events.clear()
  source.set(1)
  inspect(replacement_runs, content="1")
  let replacement_id = match replacement_ref.val {
    Some(r) => r.id()
    None => abort("expected replacement")
  }
  let mut saw_original_skip = false
  for event in events {
    match event {
      PushQueueSkipped(summary) => {
        inspect(summary.cell_id != replacement_id, content="true")
        if summary.cell_id == queued_cell_id {
          inspect(
            summary.reason ==
            @kernel.PushQueueSkipReason::DisposedOrKindMismatch,
            content="true",
          )
          saw_original_skip = true
        }
      }
      _ => ()
    }
  }
  inspect(saw_original_skip, content="true")
}

///|
test "runtime_eval: batch commit threads push event sink" {
  let rt = Runtime()
  let source = Input(rt, 0)
  let events = collect_runtime_eval_events(rt)
  let eager = Reactive::new(rt, () => source.get() + 1)
  events.clear()
  rt.batch(() => source.set(2))
  inspect(read_reactive_for_test(eager), content="3")
  let kinds = events.map(runtime_eval_event_kind)
  inspect(kinds.contains("eager_evaluated"), content="true")
  inspect(kinds.contains("push_completed"), content="true")
}
