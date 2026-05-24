# Checked Cookbook Examples

Literate tests that pin high-value target facade snippets from
[`cookbook.md`](cookbook.md). These examples focus on behavior that prose-only
snippets can easily drift on: diamond dependencies, batch semantics, dynamic
dependency changes, backdating with custom `Eq`, accumulator invalidation,
memo-event logging, field-level inputs, and scoped watch lifetimes.

## Diamond dependencies and layered derived values

```mbt check
///|
test "docs cookbook: diamond dependencies recompute each branch once" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 10, label="a")
  let b_runs : Ref[Int] = { val: 0 }
  let c_runs : Ref[Int] = { val: 0 }
  let d_runs : Ref[Int] = { val: 0 }

  let b = @incr.Derived(
    rt,
    () => {
      b_runs.val = b_runs.val + 1
      a.get() * 2
    },
    label="b",
  )
  let c = @incr.Derived(
    rt,
    () => {
      c_runs.val = c_runs.val + 1
      a.get() + 5
    },
    label="c",
  )
  let d = @incr.Derived(
    rt,
    () => {
      d_runs.val = d_runs.val + 1
      b.get_or_abort() + c.get_or_abort()
    },
    label="d",
  )

  inspect(d.read_or_abort(), content="35")
  inspect(b_runs.val, content="1")
  inspect(c_runs.val, content="1")
  inspect(d_runs.val, content="1")

  inspect(d.read_or_abort(), content="35")
  inspect(b_runs.val, content="1")
  inspect(c_runs.val, content="1")
  inspect(d_runs.val, content="1")

  a.set(20)
  inspect(d.read_or_abort(), content="65")
  inspect(b_runs.val, content="2")
  inspect(c_runs.val, content="2")
  inspect(d_runs.val, content="2")
}

///|
test "docs cookbook: layered derived values cache intermediate results" {
  let rt = @incr.Runtime()
  let raw = @incr.Input(rt, 21, label="raw")
  let normalized_runs : Ref[Int] = { val: 0 }
  let transformed_runs : Ref[Int] = { val: 0 }
  let formatted_runs : Ref[Int] = { val: 0 }

  let normalized = @incr.Derived(
    rt,
    () => {
      normalized_runs.val = normalized_runs.val + 1
      raw.get() / 3
    },
    label="normalized",
  )
  let transformed = @incr.Derived(
    rt,
    () => {
      transformed_runs.val = transformed_runs.val + 1
      normalized.get_or_abort() * 10
    },
    label="transformed",
  )
  let formatted = @incr.Derived(
    rt,
    () => {
      formatted_runs.val = formatted_runs.val + 1
      "value=" + transformed.get_or_abort().to_string()
    },
    label="formatted",
  )

  inspect(formatted.read_or_abort(), content="value=70")
  inspect(normalized_runs.val, content="1")
  inspect(transformed_runs.val, content="1")
  inspect(formatted_runs.val, content="1")

  raw.set(22)
  inspect(formatted.read_or_abort(), content="value=70")
  inspect(normalized_runs.val, content="2")
  inspect(transformed_runs.val, content="1")
  inspect(formatted_runs.val, content="1")

  raw.set(30)
  inspect(formatted.read_or_abort(), content="value=100")
  inspect(normalized_runs.val, content="3")
  inspect(transformed_runs.val, content="2")
  inspect(formatted_runs.val, content="2")
}
```

## Computed defaults

```mbt check
///|
test "docs cookbook: computed defaults yield to explicit overrides" {
  let rt = @incr.Runtime()
  let user_override : @incr.Input[Int?] = @incr.Input(
    rt,
    None,
    label="override",
  )
  let computed_default = @incr.Input(rt, 100, label="default")
  let effective_value = @incr.Derived(
    rt,
    () => {
      match user_override.get() {
        Some(v) => v
        None => computed_default.get()
      }
    },
    label="effective_value",
  )

  inspect(effective_value.read_or_abort(), content="100")

  computed_default.set(150)
  inspect(effective_value.read_or_abort(), content="150")

  user_override.set(Some(42))
  inspect(effective_value.read_or_abort(), content="42")

  computed_default.set(200)
  inspect(effective_value.read_or_abort(), content="42")

  user_override.set(None)
  inspect(effective_value.read_or_abort(), content="200")
}
```

## Conditional dependencies

```mbt check
///|
test "docs cookbook: conditional dependencies follow the active branch" {
  let rt = @incr.Runtime()
  let use_cache = @incr.Input(rt, true, label="use_cache")
  let cache = @incr.Input(rt, "cached_value", label="cache")
  let expensive_source = @incr.Input(
    rt,
    "computed_value",
    label="expensive_source",
  )
  let recomputes : Ref[Int] = { val: 0 }

  let result = @incr.Derived(
    rt,
    () => {
      recomputes.val = recomputes.val + 1
      if use_cache.get() {
        cache.get()
      } else {
        expensive_source.get()
      }
    },
    label="conditional_result",
  )

  inspect(result.read_or_abort(), content="cached_value")
  inspect(recomputes.val, content="1")

  expensive_source.set("new_computed")
  inspect(result.read_or_abort(), content="cached_value")
  inspect(recomputes.val, content="1")

  cache.set("updated_cache")
  inspect(result.read_or_abort(), content="updated_cache")
  inspect(recomputes.val, content="2")

  use_cache.set(false)
  inspect(result.read_or_abort(), content="new_computed")
  inspect(recomputes.val, content="3")

  cache.set("ignored_cache")
  inspect(result.read_or_abort(), content="new_computed")
  inspect(recomputes.val, content="3")
}
```

## Backdating with custom equality

```mbt check
///|
priv struct CookbookVersioned {
  value : Int
  generation : Int
}

///|
impl Eq for CookbookVersioned with fn equal(self, other) -> Bool {
  self.value == other.value
}

///|
test "docs cookbook: backdating respects custom equality" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 100, label="input")
  let generation : Ref[Int] = { val: 0 }
  let versioned_runs : Ref[Int] = { val: 0 }
  let handler_runs : Ref[Int] = { val: 0 }

  let versioned = @incr.Derived(
    rt,
    () => {
      versioned_runs.val = versioned_runs.val + 1
      generation.val = generation.val + 1
      { value: input.get() / 10, generation: generation.val }
    },
    label="versioned",
  )
  let handler = @incr.Derived(
    rt,
    () => {
      handler_runs.val = handler_runs.val + 1
      versioned.get_or_abort().value * 2
    },
    label="handler",
  )

  inspect(handler.read_or_abort(), content="20")
  inspect(versioned_runs.val, content="1")
  inspect(handler_runs.val, content="1")

  input.set(105)
  inspect(handler.read_or_abort(), content="20")
  inspect(versioned_runs.val, content="2")
  inspect(handler_runs.val, content="1")
  inspect(generation.val, content="2")
  inspect(versioned.read_or_abort().generation, content="2")

  input.set(200)
  inspect(handler.read_or_abort(), content="40")
  inspect(versioned_runs.val, content="3")
  inspect(handler_runs.val, content="2")
  inspect(versioned.read_or_abort().generation, content="3")
}
```

## Batch callbacks and read isolation

```mbt check
///|
test "docs cookbook: on_change batches committed changes" {
  let rt = @incr.Runtime()
  let a = @incr.Input(rt, 0, label="a")
  let b = @incr.Input(rt, 0, label="b")
  let notifications : Ref[Int] = { val: 0 }

  rt.set_on_change(() => notifications.val = notifications.val + 1)

  a.set(1)
  b.set(2)
  inspect(notifications.val, content="2")

  rt.batch(() => {
    a.set(3)
    b.set(4)
  })
  inspect(notifications.val, content="3")

  rt.batch(() => {
    a.set(30)
    a.set(3)
    b.set(40)
    b.set(4)
  })
  inspect(notifications.val, content="3")
}

///|
test "docs cookbook: batch commits related inputs atomically" {
  let rt = @incr.Runtime()
  let x = @incr.Input(rt, 0, label="x")
  let y = @incr.Input(rt, 0, label="y")
  let position = @incr.Derived(rt, () => (x.get(), y.get()), label="position")

  rt.batch(() => {
    x.set(100)
    y.set(200)
  })

  debug_inspect(position.read_or_abort(), content="(100, 200)")
}

///|
test "docs cookbook: reading during batch sees the pre-batch value" {
  let rt = @incr.Runtime()
  let x = @incr.Input(rt, 10, label="x")
  let doubled = @incr.Derived(rt, () => x.get() * 2, label="doubled")
  let seen_inside_batch : Ref[Int] = { val: -1 }

  inspect(doubled.read_or_abort(), content="20")
  rt.batch(() => {
    x.set(20)
    seen_inside_batch.val = doubled.read_or_abort()
  })

  inspect(seen_inside_batch.val, content="20")
  inspect(doubled.read_or_abort(), content="40")
}
```

## Graceful cycle handling

```mbt check
///|
test "docs cookbook: derived.get can recover from a cycle inside compute" {
  let rt = @incr.Runtime()
  let derived_ref : Ref[@incr.Derived[Int]?] = { val: None }
  let saw_cycle : Ref[Bool] = { val: false }

  let derived = @incr.Derived(
    rt,
    () => {
      match derived_ref.val {
        Some(d) =>
          match d.get() {
            Ok(v) => v + 1
            Err(_err) => {
              saw_cycle.val = true
              0
            }
          }
        None => 0
      }
    },
    label="self_recovering",
  )
  derived_ref.val = Some(derived)

  inspect(derived.read_or_abort(), content="0")
  inspect(saw_cycle.val, content="true")
}
```

## Accumulator diagnostics and synthetic invalidation

```mbt check
///|
test "docs cookbook: accumulator peek reads memo-local diagnostics" {
  let rt = @incr.Runtime()
  let width = @incr.Signal(rt, -5, label="width")
  let diags : @incr.Accumulator[String] = @incr.Accumulator::new(
    rt~,
    label="diags",
  )
  let checked = @incr.Memo(
    rt,
    () => {
      let w = width.get()
      if w < 0 {
        diags.push("negative width: " + w.to_string())
      }
      w.abs()
    },
    label="checked_width",
  )
  let checked_reader = checked.observe()

  inspect(checked_reader.get(), content="5")
  debug_inspect(
    checked.accumulated_peek(diags),
    content="[\"negative width: -5\"]",
  )

  width.set(10)
  inspect(checked_reader.get(), content="10")
  debug_inspect(checked.accumulated_peek(diags), content="[]")

  checked_reader.dispose()
  diags.dispose()
}

///|
test "docs cookbook: accumulated invalidates when push set changes" {
  let rt = @incr.Runtime()
  let width = @incr.Signal(rt, -5, label="width")
  let diags : @incr.Accumulator[String] = @incr.Accumulator::new(
    rt~,
    label="diags",
  )
  let checked = @incr.Memo(
    rt,
    () => {
      let w = width.get()
      if w < 0 {
        diags.push("negative width: " + w.to_string())
      }
      w.abs()
    },
    label="checked_width",
  )
  let report_runs : Ref[Int] = { val: 0 }
  let report = @incr.Memo(
    rt,
    () => {
      report_runs.val = report_runs.val + 1
      let size = checked.get()
      let ds = checked.accumulated(diags)
      "size=" + size.to_string() + ", diags=" + ds.length().to_string()
    },
    label="width_report",
  )
  let report_reader = report.observe()

  inspect(report_reader.get(), content="size=5, diags=1")
  inspect(report_runs.val, content="1")

  width.set(5)
  inspect(report_reader.get(), content="size=5, diags=0")
  inspect(report_runs.val, content="2")

  report_reader.dispose()
  diags.dispose()
}
```

## Memo event logging

```mbt check
///|
struct CookbookLogRow {
  phase : String
  cell : @incr.CellId
  elapsed_ns : Int64
}

///|
test "docs cookbook: memo event listener records recompute phases" {
  let rt = @incr.Runtime()
  let price = @incr.Input(rt, 100, label="price")
  let total = @incr.Derived(rt, () => price.get() * 2, label="total")
  let frames : Array[String] = []

  rt.on_memo_event(evt => {
    match evt {
      EnteringCompute(e) => {
        let label = match rt.cell_info(e.cell_id) {
          Some(info) =>
            match info.label {
              Some(s) => s
              None => e.cell_id.id.to_string()
            }
          None => e.cell_id.id.to_string()
        }
        frames.push("enter " + label)
      }
      Completed(e) => frames.push("complete " + e.cell_id.id.to_string())
      Aborted(e) => frames.push("abort " + e.cell_id.id.to_string())
    }
  })

  inspect(total.read_or_abort(), content="200")
  inspect(frames.length(), content="2")
  inspect(frames[0], content="enter total")
  inspect(frames[1].contains("complete "), content="true")
  rt.clear_memo_event_listener()
}

///|
test "docs cookbook: memo event listener can enqueue compact log rows" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="input")
  let doubled = @incr.Derived(rt, () => input.get() * 2, label="doubled")
  let rows : Array[CookbookLogRow] = []

  rt.on_memo_event(evt => {
    match evt {
      EnteringCompute(e) =>
        rows.push({ phase: "enter", cell: e.cell_id, elapsed_ns: 0L })
      Completed(e) =>
        rows.push({
          phase: if e.backdated {
            "backdated"
          } else {
            "completed"
          },
          cell: e.cell_id,
          elapsed_ns: e.elapsed_ns,
        })
      Aborted(e) =>
        rows.push({
          phase: "aborted",
          cell: e.cell_id,
          elapsed_ns: e.elapsed_ns,
        })
    }
  })

  inspect(doubled.read_or_abort(), content="2")
  inspect(rows.length(), content="2")
  inspect(rows[0].phase, content="enter")
  inspect(rows[1].phase, content="completed")
  inspect(rows[0].cell == rows[1].cell, content="true")
  inspect(rows[1].elapsed_ns >= 0L, content="true")
  rows.clear()

  input.set(2)
  inspect(doubled.read_or_abort(), content="4")
  inspect(rows.length(), content="2")
  rt.clear_memo_event_listener()
}
```

## Field-level inputs and scoped watches

```mbt check
///|
struct CookbookSourceFile {
  path : @incr.InputField[String]
  content : @incr.InputField[String]
  version : @incr.InputField[Int]
}

///|
impl @incr.InputFieldOwner for CookbookSourceFile with fn cell_ids(self) {
  [self.path.id(), self.content.id(), self.version.id()]
}

///|
fn CookbookSourceFile::CookbookSourceFile(
  rt : @incr.Runtime,
  path : String,
  content : String,
  version? : Int = 0,
) -> CookbookSourceFile {
  {
    path: @incr.InputField(rt, path, label="CookbookSourceFile.path"),
    content: @incr.InputField(rt, content, label="CookbookSourceFile.content"),
    version: @incr.InputField(rt, version, label="CookbookSourceFile.version"),
  }
}

///|
test "docs cookbook: input fields isolate field-specific dependencies" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let file = CookbookSourceFile(rt, "/src/main.mbt", "hello")
  @incr.add_input_fields(scope, file)
  let length_runs : Ref[Int] = { val: 0 }
  let path_runs : Ref[Int] = { val: 0 }

  let content_length = @incr.Derived(
    rt,
    () => {
      length_runs.val = length_runs.val + 1
      file.content.get().length()
    },
    label="content_length",
  )
  let is_test_file = @incr.Derived(
    rt,
    () => {
      path_runs.val = path_runs.val + 1
      file.path.get().contains("_test.mbt")
    },
    label="is_test_file",
  )

  inspect(content_length.read_or_abort(), content="5")
  inspect(is_test_file.read_or_abort(), content="false")
  inspect(length_runs.val, content="1")
  inspect(path_runs.val, content="1")

  file.version.set(1)
  inspect(content_length.read_or_abort(), content="5")
  inspect(is_test_file.read_or_abort(), content="false")
  inspect(length_runs.val, content="1")
  inspect(path_runs.val, content="1")

  file.content.set("hello!")
  inspect(content_length.read_or_abort(), content="6")
  inspect(is_test_file.read_or_abort(), content="false")
  inspect(length_runs.val, content="2")
  inspect(path_runs.val, content="1")

  file.path.set("/src/main_test.mbt")
  inspect(is_test_file.read_or_abort(), content="true")
  inspect(path_runs.val, content="2")

  scope.dispose()
  inspect(file.path.is_disposed(), content="true")
  inspect(file.content.is_disposed(), content="true")
  inspect(file.version.is_disposed(), content="true")
}

///|
test "docs cookbook: scope.add_watch keeps a target watch scoped" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let input = scope.input(21, label="input")
  let summary = scope.derived(() => input.get() * 2, label="summary")
  let watch = scope.add_watch(summary.watch())

  inspect(watch.read_or_abort(), content="42")
  rt.gc()
  input.set(25)
  inspect(watch.read_or_abort(), content="50")

  scope.dispose()
  inspect(watch.is_disposed(), content="true")
}
```
