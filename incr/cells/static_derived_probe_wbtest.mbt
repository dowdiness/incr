///|
fn static_probe_subscriber_contains(
  rt : Runtime,
  dep : CellId,
  subscriber : CellId,
) -> Bool {
  match rt.core.cell_index[dep.id] {
    PullInput(idx) =>
      rt.pull.inputs[idx].meta.subscribers.contains(subscriber)
    PullMemo(idx) | HybridMemo(idx) =>
      rt.pull.memos[idx].meta.subscribers.contains(subscriber)
    _ => abort("expected pull dependency")
  }
}

///|
fn static_probe_subscriber_count(rt : Runtime, dep : CellId) -> Int {
  match rt.core.cell_index[dep.id] {
    PullInput(idx) => rt.pull.inputs[idx].meta.subscribers.length()
    PullMemo(idx) | HybridMemo(idx) =>
      rt.pull.memos[idx].meta.subscribers.length()
    _ => abort("expected pull dependency")
  }
}

///|
test "static derived: registers fixed deps and subscribers once" {
  let rt = Runtime()
  let left = Input(rt, 1)
  let right = Input(rt, 2)
  let derived = static_derived_map2(left, right, (a, b) => a + b)
  inspect(derived.dependencies().length(), content="2")
  inspect(
    static_probe_subscriber_contains(rt, left.id(), derived.id()),
    content="true",
  )
  inspect(
    static_probe_subscriber_contains(rt, right.id(), derived.id()),
    content="true",
  )
  inspect(derived.read_or_abort(), content="3")
  left.set(10)
  inspect(derived.read_or_abort(), content="12")
  inspect(derived.dependencies().length(), content="2")
}

///|
test "static derived: normalizes duplicate fixed deps" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let derived = static_derived(
    rt,
    [input.id(), input.id()],
    () => input.peek() + 1,
    (a, b) => a == b,
  )
  inspect(derived.dependencies().length(), content="1")
  inspect(static_probe_subscriber_count(rt, input.id()), content="1")
  inspect(derived.read_or_abort(), content="2")
}

///|
test "static derived: backdates equal recompute" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let derived = static_derived_map1(input, x => x % 2)
  inspect(derived.read_or_abort(), content="1")
  let original_changed_at = derived.changed_at()
  input.set(3)
  inspect(derived.read_or_abort(), content="1")
  inspect(derived.changed_at() == original_changed_at, content="true")
  input.set(4)
  inspect(derived.read_or_abort(), content="0")
  inspect(derived.changed_at() == original_changed_at, content="false")
}

///|
test "static derived: dynamic parent records only static cell" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let addend = Input(rt, 10)
  let static_derived = static_derived_map1(input, x => x + 1)
  let parent = Derived(rt, () => static_derived.get_or_abort() + addend.get())
  inspect(parent.read_or_abort(), content="12")
  let deps = parent.dependencies()
  inspect(deps.contains(static_derived.id()), content="true")
  inspect(deps.contains(addend.id()), content="true")
  inspect(deps.contains(input.id()), content="false")
  input.set(2)
  inspect(parent.read_or_abort(), content="13")
}

///|
test "panic static derived: rejects tracked reads during static recompute" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let static_derived = static_derived(rt, [input.id()], () => input.get() + 1, (
    a,
    b,
  ) => a == b)
  ignore(static_derived.read_or_abort())
}

///|
test "static derived: establishes computing runtime during recompute" {
  @kernel.set_current_computing_runtime_id(None)
  let rt = Runtime()
  let seen_runtime : Ref[@incr_types.RuntimeId?] = { val: None }
  let static_derived = static_derived(
    rt,
    [],
    () => {
      seen_runtime.val = @kernel.get_current_computing_runtime_id()
      1
    },
    (a, b) => a == b,
  )
  inspect(@kernel.get_current_computing_runtime_id() is None, content="true")
  inspect(static_derived.read_or_abort(), content="1")
  inspect(seen_runtime.val == Some(rt.core.runtime_id), content="true")
  inspect(@kernel.get_current_computing_runtime_id() is None, content="true")
}

///|
test "panic static derived: rejects foreign tracked read during static recompute" {
  let rt = Runtime()
  let foreign_rt = Runtime()
  let foreign_input = Input(foreign_rt, 1)
  let static_derived = static_derived(rt, [], () => foreign_input.get(), (a, b) => {
    a == b
  })
  ignore(static_derived.read_or_abort())
}

///|
test "static derived: dispose removes fixed subscriber links" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let derived = static_derived_map1(input, x => x + 1)
  inspect(derived.read_or_abort(), content="2")
  inspect(
    static_probe_subscriber_contains(rt, input.id(), derived.id()),
    content="true",
  )
  derived.dispose()
  inspect(
    static_probe_subscriber_contains(rt, input.id(), derived.id()),
    content="false",
  )
}

///|
test "static derived: static child dispose removes parent subscriber link" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let parent = static_derived_map1(input, x => x + 1)
  let child = static_derived_map_derived1(parent, x => x * 2)
  inspect(child.read_or_abort(), content="4")
  inspect(
    static_probe_subscriber_contains(rt, parent.id(), child.id()),
    content="true",
  )
  child.dispose()
  inspect(
    static_probe_subscriber_contains(rt, parent.id(), child.id()),
    content="false",
  )
}

///|
test "static derived: gc traverses static dependency chain" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let parent = static_derived_map1(input, x => x + 1)
  let child = static_derived_map_derived1(parent, x => x * 2)
  inspect(child.read_or_abort(), content="4")
  rt.add_read_root(child.id())
  rt.gc()
  inspect(rt.is_cell_disposed(input.id()), content="false")
  inspect(rt.is_cell_disposed(parent.id()), content="false")
  inspect(rt.is_cell_disposed(child.id()), content="false")
  rt.remove_read_root(child.id())
  rt.gc()
  inspect(rt.is_cell_disposed(parent.id()), content="true")
  inspect(rt.is_cell_disposed(child.id()), content="true")
}

///|
test "panic static derived: gc is rejected during static recompute" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let derived = static_derived_map1(input, x => {
    rt.gc()
    x + 1
  })
  ignore(derived.read_or_abort())
}

///|
test "static derived: compute failure clears in-progress and hooks" {
  let rt = Runtime()
  rt.on_derived_event(_evt => ())
  // Seeds accumulator hook state so the active-entry cleanup assertion is meaningful.
  let _acc : Accumulator[Int] = Accumulator::new(rt~)
  let should_fail : Ref[Bool] = { val: true }
  let derived : Derived[Int] = static_derived(
    rt,
    [],
    () => {
      if should_fail.val {
        raise Failure("boom")
      }
      42
    },
    (a, b) => a == b,
  )
  let mut failed = false
  try derived.force_recompute() catch {
    _ => failed = true
  } noraise {
    _ => ()
  }
  inspect(failed, content="true")
  inspect(rt.get_memo_data(derived.id()).in_progress, content="false")
  inspect(rt.static_recompute_depth, content="0")
  inspect(rt.static_recompute_tracking_floors.length(), content="0")
  inspect(rt.static_recompute_previous_runtime_ids.length(), content="0")
  inspect(
    rt.accumulator_commit_hook.active.contains(derived.id()),
    content="false",
  )
  inspect(
    rt.event_broadcast_hook.active.contains(derived.id()),
    content="false",
  )
  should_fail.val = false
  inspect(derived.read_or_abort(), content="42")
}

///|
test "static derived: listener mutation is blocked during recompute" {
  let rt = Runtime()
  let derived : Derived[Int] = static_derived(
    rt,
    [],
    () => {
      rt.on_derived_event(_evt => ())
      1
    },
    (a, b) => a == b,
  )
  let mut failed = false
  try derived.force_recompute() catch {
    _ => failed = true
  } noraise {
    _ => ()
  }
  inspect(failed, content="true")
  inspect(rt.static_recompute_depth, content="0")
  inspect(rt.static_recompute_tracking_floors.length(), content="0")
  inspect(rt.static_recompute_previous_runtime_ids.length(), content="0")
  inspect(rt.get_memo_data(derived.id()).in_progress, content="false")
}

///|
test "static derived: cycle reporting follows fixed deps" {
  let rt = Runtime()
  let input = Input(rt, 0)
  let parent = static_derived_map1(input, x => x, label="static-a")
  let child = static_derived_map_derived1(parent, x => x + 1, label="static-b")
  inspect(child.read_or_abort(), content="1")
  let parent_data = rt.get_memo_data(parent.id())
  parent_data.dependencies = [child.id(), input.id()]
  rt.add_subscriber(child.id(), parent.id())
  input.set(1)
  match child.read() {
    Ok(_) => abort("expected fixed-dep cycle")
    Err(e) => {
      inspect(e.path().length(), content="3")
      inspect(
        e.format_path(),
        content="Cycle detected: static-b → static-a → static-b",
      )
    }
  }
  inspect(rt.get_memo_data(parent.id()).in_progress, content="false")
  inspect(rt.get_memo_data(child.id()).in_progress, content="false")
}

///|
test "static derived: accumulator use fails explicitly" {
  let rt = Runtime()
  let pushed : Accumulator[Int] = Accumulator::new(rt~)
  let push_probe = static_derived(
    rt,
    [],
    () => {
      pushed.push(1)
      1
    },
    (a, b) => a == b,
  )
  let push_failed = try push_probe.force_recompute() catch {
    e =>
      e
      .to_string()
      .contains("Accumulator::push is unsupported inside static Derived")
  } noraise {
    _ => false
  }
  inspect(push_failed, content="true")
  inspect(rt.static_recompute_depth, content="0")

  let read_acc : Accumulator[Int] = Accumulator::new(rt~)
  let producer = Derived(rt, () => {
    read_acc.push(7)
    7
  })
  inspect(producer.read_or_abort(), content="7")
  let read_probe = static_derived(
    rt,
    [producer.id()],
    () => {
      ignore(producer.accumulated_or_abort(read_acc))
      0
    },
    (a, b) => a == b,
  )
  let read_failed = try read_probe.force_recompute() catch {
    e =>
      e
      .to_string()
      .contains("Derived::accumulated is unsupported inside static Derived")
  } noraise {
    _ => false
  }
  inspect(read_failed, content="true")
  inspect(rt.static_recompute_depth, content="0")
}

///|
test "static derived: event hook pairs enter and completed" {
  let rt = Runtime()
  let events : Array[String] = []
  rt.on_derived_event(evt => {
    events.push(
      match evt {
        EnteringCompute(_) => "enter"
        Completed(_) => "completed"
        Aborted(_) => "aborted"
      },
    )
  })
  let input = Input(rt, 1)
  let derived = static_derived_map1(input, x => x + 1)
  inspect(derived.read_or_abort(), content="2")
  debug_inspect(events, content="[\"enter\", \"completed\"]")
}

///|
test "static derived: nested events drain after outer recompute" {
  let rt = Runtime()
  let depths : Array[Int] = []
  rt.on_derived_event(_evt => depths.push(rt.static_recompute_depth))
  let input = Input(rt, 1)
  let child = static_derived_map1(input, x => x + 1)
  let parent = static_derived_map_derived1(child, x => x * 2)
  inspect(parent.read_or_abort(), content="4")
  debug_inspect(depths, content="[0, 0, 0, 0]")
}

///|
test "static derived: direct drain waits for static recompute unwind" {
  let rt = Runtime()
  let events : Array[String] = []
  rt.on_derived_event(_evt => events.push("event"))
  let input = Input(rt, 1)
  let derived = static_derived_map1(input, x => x + 1)
  rt.event_broadcast_hook.pending.push(
    EnteringCompute({
      cell_id: derived.id(),
      started_revision: rt.core.revision.current_revision,
    }),
  )
  rt.static_recompute_depth = 1
  rt.drain_pending_events_direct()
  debug_inspect(events, content="[]")
  inspect(rt.event_broadcast_hook.pending.length(), content="1")
  rt.static_recompute_depth = 0
  rt.drain_pending_events_direct()
  debug_inspect(events, content="[\"event\"]")
  inspect(rt.event_broadcast_hook.pending.length(), content="0")
}

///|
test "static derived: drains runtime evaluation events after read" {
  let rt = Runtime()
  let events : Array[String] = []
  rt.runtime_evaluation_event_hook.listener = Some(event => {
    events.push(
      match event {
        DerivedRebuilt(_) => "derived_rebuilt"
        DerivedRebuildAborted(_) => "derived_aborted"
        EagerDerivedEvaluated(_) => "eager_evaluated"
        EffectExecuted(_) => "effect_executed"
        PushQueueSkipped(_) => "queue_skipped"
        PushPropagationCompleted(_) => "push_completed"
      },
    )
  })
  let input = Input(rt, 1)
  let derived = static_derived_map1(input, x => x + 1)
  inspect(derived.read_or_abort(), content="2")
  debug_inspect(events, content="[\"derived_rebuilt\"]")
  inspect(rt.runtime_evaluation_event_hook.pending.length(), content="0")
}

///|
test "panic static derived: rejects cross-runtime fixed dependency" {
  let rt1 = Runtime()
  let rt2 = Runtime()
  let left = Input(rt1, 1)
  let right = Input(rt2, 2)
  let _ = static_derived_map2(left, right, (a, b) => a + b)
}

///|
test "panic static derived: permissive read rejects cross-runtime compute" {
  let rt1 = Runtime()
  let rt2 = Runtime()
  let input = Input(rt1, 1)
  let derived = static_derived_map1(input, x => x + 1)
  inspect(derived.read_or_abort(), content="2")
  let trigger = Input(rt2, 0)
  let foreign = Derived(rt2, () => derived.read_or_abort() + trigger.get())
  ignore(foreign.read_or_abort())
}

///|
test "panic static derived: declared fixed-source read rejects undeclared dep" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let other = Input(rt, 10)
  let source = static_derived_map1(input, x => x + 1)
  let probe = rt.install_static_derived(
    [other.id()],
    dependent => source.read_declared_fixed_dep_or_abort(dependent),
    (a, b) => a == b,
  )
  ignore(probe.read_or_abort())
}

///|
test "static derived: dynamic source is a fixed declared dependency" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let source = Derived(rt, () => input.get() + 1)
  let child = static_derived_map_derived1(source, x => x * 2)
  inspect(child.read_or_abort(), content="4")
  let deps = child.dependencies()
  inspect(deps.contains(source.id()), content="true")
  inspect(deps.contains(input.id()), content="false")
  input.set(2)
  inspect(child.read_or_abort(), content="6")
}

///|
test "panic static derived: restores runtime before mapper after dynamic source read" {
  let rt = Runtime()
  let foreign_rt = Runtime()
  let input = Input(rt, 1)
  let foreign = Input(foreign_rt, 10)
  let source = Derived(rt, () => input.get() + 1)
  let child = static_derived_map_derived1(source, x => x + foreign.get())
  ignore(child.read_or_abort())
}

///|
test "static derived: normal watch roots and disposed reads are honest" {
  let rt = Runtime()
  let input = Input(rt, 1)
  let derived = static_derived_map1(input, x => x + 1)
  let watch = derived.watch()
  inspect(watch.read_or_abort(), content="2")
  rt.gc()
  inspect(rt.is_cell_disposed(derived.id()), content="false")
  derived.dispose()
  match derived.read() {
    Ok(_) => abort("expected disposed read")
    Err(e) => inspect(e.is_disposed(), content="true")
  }
  watch.dispose()
}
