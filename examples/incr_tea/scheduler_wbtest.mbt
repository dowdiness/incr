///|
enum SchedulerMsg {
  Start
  FollowUp
  First
  Second
  Third
  Atomic
} derive(Eq, Debug)

///|
struct SchedulerView {
  count : Int
  title : String
} derive(Eq, Debug)

///|
test "panic program: constructor rejects a scope from another Runtime" {
  let runtime = @incr.Runtime()
  let foreign_runtime = @incr.Runtime()
  let foreign_scope = @incr.Scope::new(foreign_runtime)
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = _ => Cmd::none()
  let view : () -> SchedulerView raise Failure = () => {
    count: 0,
    title: "mismatch",
  }
  ignore(
    Program::Program(
      runtime,
      foreign_scope,
      update,
      view,
      label="scheduler.runtime_mismatch.view",
    ),
  )
}

///|
test "scheduler: update returns Cmd" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="scheduler.update_returns_cmd.count")
  let title = scope.input_field(
    "Cmd",
    label="scheduler.update_returns_cmd.title",
  )
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = msg => {
    match msg {
      Start => {
        count.set(count.peek() + 1)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> SchedulerView raise Failure = () => {
    count: count.get(),
    title: title.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="scheduler.update_returns_cmd.view",
  )

  inspect(program.dispatch(Start), content="true")
  let view = program.read_view_or_abort()
  inspect(view.count, content="1")
  inspect(view.title, content="Cmd")

  program.dispose()
}

///|
test "scheduler: Cmd::message enqueues follow-up after current batch commits" {
  let changes : Ref[Int] = Ref(0)
  let runtime = @incr.Runtime(on_change=() => changes.val = changes.val + 1)
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="scheduler.message.count")
  let title = scope.input_field("Cmd", label="scheduler.message.title")
  let events : Ref[Array[String]] = Ref([])
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = msg => {
    match msg {
      Start => {
        count.set(1)
        Cmd::message(FollowUp)
      }
      FollowUp => {
        events.val.push("followup changes=\{changes.val} count=\{count.peek()}")
        count.set(2)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> SchedulerView raise Failure = () => {
    count: count.get(),
    title: title.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="scheduler.message.view",
  )

  inspect(program.dispatch(Start), content="true")
  inspect(events.val.join("|"), content="followup changes=1 count=1")
  let view = program.read_view_or_abort()
  inspect(view.count, content="2")
  inspect(changes.val, content="2")

  program.dispose()
}

///|
test "scheduler: Cmd::batch order is deterministic" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="scheduler.batch.count")
  let title = scope.input_field("Cmd", label="scheduler.batch.title")
  let events : Ref[Array[String]] = Ref([])
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = msg => {
    match msg {
      Start =>
        Cmd::batch([
          Cmd::message(First),
          Cmd::message(Second),
          Cmd::batch([Cmd::message(Third)]),
        ])
      First => {
        events.val.push("first")
        Cmd::none()
      }
      Second => {
        events.val.push("second")
        Cmd::none()
      }
      Third => {
        events.val.push("third")
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> SchedulerView raise Failure = () => {
    count: count.get(),
    title: title.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="scheduler.batch.view",
  )

  inspect(program.dispatch(Start), content="true")
  inspect(events.val.join(","), content="first,second,third")

  program.dispose()
}

///|
test "scheduler: Cmd::batch snapshots mutable input arrays" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="scheduler.batch_snapshot.count")
  let title = scope.input_field("Cmd", label="scheduler.batch_snapshot.title")
  let events : Ref[Array[String]] = Ref([])
  let cmds : Array[Cmd[SchedulerMsg]] = [Cmd::message(First)]
  let batch = Cmd::batch(cmds)
  cmds.push(Cmd::message(Second))
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = msg => {
    match msg {
      Start => batch
      First => {
        events.val.push("first")
        Cmd::none()
      }
      Second => {
        events.val.push("second")
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> SchedulerView raise Failure = () => {
    count: count.get(),
    title: title.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="scheduler.batch_snapshot.view",
  )

  inspect(program.dispatch(Start), content="true")
  inspect(events.val.join(","), content="first")

  program.dispose()
}

///|
test "scheduler: effects run outside tracked Derived computations" {
  let runtime = @incr.Runtime()
  let in_derived : Ref[Bool] = Ref(false)
  try! runtime.on_derived_event(event => {
    match event {
      @incr.DerivedEvent::EnteringCompute(_) => in_derived.val = true
      @incr.DerivedEvent::Completed(_) => in_derived.val = false
      @incr.DerivedEvent::Aborted(_) => in_derived.val = false
    }
  })
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="scheduler.effect.count")
  let title = scope.input_field("Cmd", label="scheduler.effect.title")
  let events : Ref[Array[String]] = Ref([])
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = msg => {
    match msg {
      Start =>
        Cmd::effect(_ => {
          events.val.push(if in_derived.val { "inside" } else { "outside" })
        })
      _ => Cmd::none()
    }
  }
  let view : () -> SchedulerView raise Failure = () => {
    count: count.get(),
    title: title.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="scheduler.effect.view",
  )

  inspect(program.dispatch(Start), content="true")
  inspect(events.val.join(","), content="outside")

  program.dispose()
}

///|
test "scheduler: Cmd::after_flush waits for renderer drain" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="scheduler.after_flush.count")
  let title = scope.input_field("Cmd", label="scheduler.after_flush.title")
  let events : Ref[Array[String]] = Ref([])
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = msg => {
    match msg {
      Start => {
        count.set(1)
        Cmd::after_flush(_ => events.val.push("after count=\{count.peek()}"))
      }
      _ => Cmd::none()
    }
  }
  let view : () -> SchedulerView raise Failure = () => {
    count: count.get(),
    title: title.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="scheduler.after_flush.view",
  )

  inspect(program.dispatch(Start), content="true")
  inspect(events.val.join(","), content="")
  program.drain_after_flush()
  inspect(events.val.join(","), content="after count=1")

  program.dispose()
}

///|
test "scheduler: Cmd::after_flush can enqueue follow-up messages" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="scheduler.after_flush_message.count")
  let title = scope.input_field(
    "Cmd",
    label="scheduler.after_flush_message.title",
  )
  let events : Ref[Array[String]] = Ref([])
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = msg => {
    match msg {
      Start => {
        count.set(1)
        Cmd::after_flush(enqueue => enqueue(Cmd::message(FollowUp)))
      }
      FollowUp => {
        events.val.push("followup count=\{count.peek()}")
        count.set(2)
        Cmd::none()
      }
      _ => Cmd::none()
    }
  }
  let view : () -> SchedulerView raise Failure = () => {
    count: count.get(),
    title: title.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="scheduler.after_flush_message.view",
  )

  inspect(program.dispatch(Start), content="true")
  inspect(events.val.join(","), content="")
  program.drain_after_flush()
  inspect(events.val.join(","), content="followup count=1")
  inspect(program.read_view_or_abort().count, content="2")

  program.dispose()
}

///|
test "scheduler: batched model writes remain atomic from view perspective" {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let count = scope.input_field(0, label="scheduler.atomic.count")
  let title = scope.input_field("Before", label="scheduler.atomic.title")
  let snapshots : Ref[Array[String]] = Ref([])
  let program_ref : Ref[Program[SchedulerMsg, SchedulerView]?] = Ref(None)
  let update : (SchedulerMsg) -> Cmd[SchedulerMsg] = msg => {
    match msg {
      Atomic => {
        count.set(7)
        title.set("Atomic")
        Cmd::effect(_ => {
          match program_ref.val {
            Some(program) => {
              let view = program.read_view_or_abort()
              snapshots.val.push("\{view.count}:\{view.title}")
            }
            None => snapshots.val.push("missing program")
          }
        })
      }
      _ => Cmd::none()
    }
  }
  let view : () -> SchedulerView raise Failure = () => {
    count: count.get(),
    title: title.get(),
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="scheduler.atomic.view",
  )
  program_ref.val = Some(program)

  inspect(program.dispatch(Atomic), content="true")
  inspect(snapshots.val.join(","), content="7:Atomic")
  let view = program.read_view_or_abort()
  inspect(view.count, content="7")
  inspect(view.title, content="Atomic")

  program.dispose()
}
