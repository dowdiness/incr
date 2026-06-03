# Checked Cookbook Examples

Literate tests that pin high-value snippets from [`cookbook.mbt.md`](cookbook.mbt.md).
These examples focus on behavior that prose-only snippets can easily drift on:
diamond dependencies, batch semantics, dynamic dependency changes, backdating
with custom `Eq`, domain errors as values, accumulator invalidation, derived-event
logging, compatibility introspection, extension-owned batch rollback, field-level
inputs, sparse presence anchors, long-lived authoring pipelines, and scoped watch
lifetimes.

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

```mbt check
///|
priv enum CookbookStatus {
  CookbookLoading(progress~ : Int)
  CookbookReady(data~ : Int)
  CookbookError(code~ : Int, message~ : String)
}

///|
impl Eq for CookbookStatus with fn equal(self, other) -> Bool {
  match (self, other) {
    (CookbookLoading(progress=p1), CookbookLoading(progress=p2)) => p1 == p2
    (CookbookReady(data=d1), CookbookReady(data=d2)) => d1 == d2
    (CookbookError(code=c1, ..), CookbookError(code=c2, ..)) => c1 == c2
    _ => false
  }
}

///|
test "docs cookbook: enum backdating can ignore incidental fields" {
  match CookbookLoading(progress=7) {
    CookbookLoading(progress=p) => inspect(p, content="7")
    _ => abort("expected loading")
  }
  match CookbookReady(data=42) {
    CookbookReady(data=d) => inspect(d, content="42")
    _ => abort("expected ready")
  }
  match CookbookError(code=500, message="boom") {
    CookbookError(code=c, message=m) => {
      inspect(c, content="500")
      inspect(m, content="boom")
    }
    _ => abort("expected error")
  }

  let rt = @incr.Runtime()
  let error_code = @incr.Input(rt, 404, label="error_code")
  let error_msg = @incr.Input(rt, "Not Found", label="error_msg")
  let status_runs : Ref[Int] = { val: 0 }
  let handler_runs : Ref[Int] = { val: 0 }

  let status = @incr.Derived(
    rt,
    () => {
      status_runs.val = status_runs.val + 1
      CookbookError(code=error_code.get(), message=error_msg.get())
    },
    label="status",
  )
  let handler = @incr.Derived(
    rt,
    () => {
      handler_runs.val = handler_runs.val + 1
      match status.get_or_abort() {
        CookbookError(code=c, ..) => "Error: " + c.to_string()
        CookbookReady(data=d) => "Data: " + d.to_string()
        CookbookLoading(progress=p) => "Loading: " + p.to_string() + "%"
      }
    },
    label="handler",
  )

  inspect(handler.read_or_abort(), content="Error: 404")
  inspect(status_runs.val, content="1")
  inspect(handler_runs.val, content="1")

  error_msg.set("Page Not Found")
  inspect(handler.read_or_abort(), content="Error: 404")
  inspect(status_runs.val, content="2")
  inspect(handler_runs.val, content="1")

  error_code.set(500)
  inspect(handler.read_or_abort(), content="Error: 500")
  inspect(status_runs.val, content="3")
  inspect(handler_runs.val, content="2")
}
```

## Batch callbacks, read isolation, and extension rollback

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

```mbt check
///|
suberror CookbookExternalRollbackError {
  CookbookRollbackAbort
}

///|
priv struct CookbookExternalIndex {
  rt : @incr.Runtime
  rollback_token : @incr.InputField[Bool]
  rows : Map[String, Int]
}

///|
fn CookbookExternalIndex::CookbookExternalIndex(
  rt : @incr.Runtime,
) -> CookbookExternalIndex {
  {
    rt,
    rollback_token: @incr.InputField(rt, false, label="external-index-rollback"),
    rows: Map([]),
  }
}

///|
fn CookbookExternalIndex::restore_rows(
  self : CookbookExternalIndex,
  previous_rows : Map[String, Int],
) -> Unit {
  self.rows.clear()
  for key, value in previous_rows {
    self.rows[key] = value
  }
}

///|
fn CookbookExternalIndex::put(
  self : CookbookExternalIndex,
  key : String,
  value : Int,
) -> Unit {
  let previous_rows = self.rows.copy()
  self.rows[key] = value
  self.rt.record_batch_rollback(self.rollback_token.id(), () => {
    self.restore_rows(previous_rows)
  })
}

///|
test "docs cookbook: extension-owned map rollback restores insertion and replacement" {
  let rt = @incr.Runtime()
  let index = CookbookExternalIndex(rt)
  index.put("existing", 1)

  let result = rt.batch_result(() => {
    index.put("inserted", 2)
    index.put("existing", 99)
    raise CookbookExternalRollbackError::CookbookRollbackAbort
  })

  inspect(result is Err(CookbookRollbackAbort), content="true")
  inspect(index.rows.contains("inserted"), content="false")
  match index.rows.get("existing") {
    Some(value) => inspect(value, content="1")
    None => abort("expected original value after rollback")
  }

  rt.batch(() => {
    index.put("inserted", 2)
    index.put("existing", 3)
  })

  match index.rows.get("inserted") {
    Some(value) => inspect(value, content="2")
    None => abort("expected committed insertion")
  }
  match index.rows.get("existing") {
    Some(value) => inspect(value, content="3")
    None => abort("expected committed replacement")
  }
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

## Domain errors as values

```mbt check
///|
priv struct CookbookDiagnostic {
  code : String
  message : String
} derive(Eq)

///|
priv enum CookbookQuantityStatus {
  QuantityOk(Int)
  QuantityDiagnostics(Array[CookbookDiagnostic])
} derive(Eq)

///|
test "docs cookbook: custom domain diagnostics are cached as values" {
  let rt = @incr.Runtime()
  let raw = @incr.Input(rt, -1, label="raw_quantity")
  let status_runs = Ref(0)
  let rendered_runs = Ref(0)

  let status : @incr.Derived[CookbookQuantityStatus] = @incr.Derived(
    rt,
    () => {
      status_runs.val += 1
      let v = raw.get()
      if v < 0 {
        QuantityDiagnostics([
          {
            code: "negative_quantity",
            message: "quantity must be non-negative",
          },
        ])
      } else {
        QuantityOk(v)
      }
    },
    label="quantity_status",
  )

  let rendered : @incr.Derived[String] = @incr.Derived(
    rt,
    () => {
      rendered_runs.val += 1
      match status.get_or_abort() {
        QuantityOk(v) => "ok:" + v.to_string()
        QuantityDiagnostics([{ code, message }, ..]) =>
          "diagnostic:" + code + ":" + message
        QuantityDiagnostics([]) => "diagnostic:<empty>"
      }
    },
    label="rendered_quantity_status",
  )

  guard status.read() is Ok(QuantityDiagnostics(_)) else {
    fail("expected graph read to succeed with diagnostics")
  }
  inspect(
    rendered.read_or_abort(),
    content="diagnostic:negative_quantity:quantity must be non-negative",
  )
  inspect(status_runs.val, content="1")
  inspect(rendered_runs.val, content="1")

  raw.set(-2)
  guard status.read() is Ok(QuantityDiagnostics(_)) else {
    fail("expected equal diagnostics to remain a domain value")
  }
  inspect(status_runs.val, content="2")
  inspect(
    rendered.read_or_abort(),
    content="diagnostic:negative_quantity:quantity must be non-negative",
  )
  inspect(rendered_runs.val, content="1")

  raw.set(3)
  guard status.read() is Ok(QuantityOk(3)) else {
    fail("expected recovery to a valid quantity")
  }
  inspect(rendered.read_or_abort(), content="ok:3")
  inspect(status_runs.val, content="3")
  inspect(rendered_runs.val, content="2")
}
```

```mbt check
///|
test "docs cookbook: Derived::fallible surfaces domain failure as a cached value" {
  let rt = @incr.Runtime()
  let n = @incr.Input(rt, 0, label="n")
  // The compute is noraise: a domain failure is *returned* as Err, never raised.
  let parsed : @incr.Derived[Result[Int, String]] = @incr.Derived::fallible(
    rt,
    () => {
      let v = n.get()
      if v < 0 {
        Err("negative")
      } else {
        Ok(v * 2)
      }
    },
    label="parsed",
  )

  // Three-way read outcome, each owned by a different layer:
  //   Err(_)     -> a graph-read failure (cycle/disposal): graph health
  //   Ok(Err(e)) -> a domain failure reified as a value: a diagnostic to report
  //   Ok(Ok(v))  -> the value
  guard parsed.read() is Ok(Ok(0)) else { fail("expected Ok(Ok(0))") }
  n.set(5)
  guard parsed.read() is Ok(Ok(10)) else {
    fail("expected Ok(Ok(10)) after set(5)")
  }

  // A domain failure surfaces as Ok(Err(_)) — a cached value, not an abort.
  n.set(-1)
  guard parsed.read() is Ok(Err("negative")) else {
    fail("expected Ok(Err(\"negative\")) after set(-1)")
  }

  // Recovery: a valid input invalidates and recomputes, proving the Err value
  // is change-detected like any other value.
  n.set(2)
  guard parsed.read() is Ok(Ok(4)) else {
    fail("expected Ok(Ok(4)) after recovery")
  }
}
```

## Aggregate computation

```mbt check
///|
test "docs cookbook: aggregate computation updates affected totals" {
  let rt = @incr.Runtime()
  let items : Array[@incr.Input[Int]] = [
    @incr.Input(rt, 10, label="item_0"),
    @incr.Input(rt, 20, label="item_1"),
    @incr.Input(rt, 30, label="item_2"),
  ]
  let sum = @incr.Derived(
    rt,
    () => {
      let mut total = 0
      for item in items {
        total = total + item.get()
      }
      total
    },
    label="sum",
  )
  let count = items.length()
  let average = @incr.Derived(
    rt,
    () => sum.get_or_abort() / count,
    label="average",
  )

  inspect(sum.read_or_abort(), content="60")
  inspect(average.read_or_abort(), content="20")

  items[1].set(50)
  inspect(sum.read_or_abort(), content="90")
  inspect(average.read_or_abort(), content="30")
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
      let ds = checked.accumulated_or_abort(diags)
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

## Derived event logging

```mbt check
///|
struct CookbookLogRow {
  phase : String
  cell : @incr.CellId
  elapsed_ns : Int64
}

///|
test "docs cookbook: derived event listener records recompute phases" {
  let rt = @incr.Runtime()
  let price = @incr.Input(rt, 100, label="price")
  let total = @incr.Derived(rt, () => price.get() * 2, label="total")
  let frames : Array[String] = []

  rt.on_derived_event(evt => {
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
  rt.clear_derived_event_listener()
}

///|
test "docs cookbook: derived event listener can enqueue compact log rows" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="input")
  let doubled = @incr.Derived(rt, () => input.get() * 2, label="doubled")
  let rows : Array[CookbookLogRow] = []

  rt.on_derived_event(evt => {
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
  rt.clear_derived_event_listener()
}
```

## Debugging with compatibility introspection

```mbt check
///|
test "docs cookbook: introspection identifies changed dependencies and dependents" {
  let rt = @incr.Runtime()
  let x = @incr.Signal(rt, 10, label="x")
  let y = @incr.Signal(rt, 20, label="y")
  let sum = @incr.Memo(rt, () => x.get() + y.get(), label="sum")
  let reader = sum.observe()

  inspect(reader.get(), content="30")
  let baseline = sum.verified_at()

  x.set(15)
  inspect(reader.get(), content="35")

  let changed_deps : Array[String] = []
  for dep_id in sum.dependencies() {
    match rt.cell_info(dep_id) {
      Some(info) =>
        if info.changed_at.value > baseline.value {
          match info.label {
            Some(label) => changed_deps.push(label)
            None => changed_deps.push(dep_id.id.to_string())
          }
        }
      None => ()
    }
  }
  debug_inspect(changed_deps, content="[\"x\"]")
  inspect(rt.dependents(x.id()).contains(sum.id()), content="true")
  reader.dispose()
}

///|
test "docs cookbook: memo changed_at shows backdating" {
  let rt = @incr.Runtime()
  let config = @incr.Signal(rt, "abcd", label="config")
  let length = @incr.Memo(rt, () => config.get().length(), label="length")
  let reader = length.observe()

  inspect(reader.get(), content="4")
  let old_changed = length.changed_at()

  config.set("wxyz")
  inspect(reader.get(), content="4")
  inspect(length.changed_at() == old_changed, content="true")
  reader.dispose()
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

## Sparse address maps with presence anchors

```mbt check
///|
priv struct CookbookSparseTable {
  rt : @incr.Runtime
  presence : Map[String, @incr.InputField[Bool]]
  values : Map[String, @incr.InputField[Int]]
}

///|
fn CookbookSparseTable::CookbookSparseTable(
  rt : @incr.Runtime,
) -> CookbookSparseTable {
  { rt, presence: Map([]), values: Map([]) }
}

///|
fn CookbookSparseTable::presence_for(
  self : CookbookSparseTable,
  key : String,
) -> @incr.InputField[Bool] {
  self.presence.get_or_init(key, () => {
    @incr.InputField(self.rt, false, label="presence:" + key)
  })
}

///|
fn CookbookSparseTable::set(
  self : CookbookSparseTable,
  key : String,
  value : Int,
) -> Unit {
  match self.values.get(key) {
    Some(field) => field.set(value)
    None =>
      self.values[key] = @incr.InputField(self.rt, value, label="value:" + key)
  }
  self.presence_for(key).set(true)
}

///|
fn CookbookSparseTable::delete(
  self : CookbookSparseTable,
  key : String,
) -> Unit {
  self.presence_for(key).set(false)
}

///|
fn CookbookSparseTable::read_with_presence(
  self : CookbookSparseTable,
  key : String,
  presence : @incr.InputField[Bool],
) -> Result[Int, String] {
  if !presence.get() {
    Err("missing " + key)
  } else {
    match self.values.get(key) {
      Some(field) => Ok(field.get())
      None => Err("missing value slot for " + key)
    }
  }
}

///|
test "docs cookbook: sparse map presence anchors invalidate missing reads" {
  let rt = @incr.Runtime()
  let table = CookbookSparseTable(rt)
  let z9_presence = table.presence_for("Z9")
  let runs : Ref[Int] = { val: 0 }
  let z9_plus_one = @incr.Derived::fallible(
    rt,
    () => {
      runs.val = runs.val + 1
      match table.read_with_presence("Z9", z9_presence) {
        Ok(value) => Ok(value + 1)
        Err(message) => Err(message)
      }
    },
    label="z9_plus_one",
  )

  guard z9_plus_one.read() is Ok(Err("missing Z9")) else {
    fail("expected missing read to be a domain error")
  }
  inspect(runs.val, content="1")

  table.set("Z9", 41)
  guard z9_plus_one.read() is Ok(Ok(42)) else {
    fail("expected creation to invalidate and resolve")
  }
  inspect(runs.val, content="2")

  table.delete("Z9")
  guard z9_plus_one.read() is Ok(Err("missing Z9")) else {
    fail("expected deletion to invalidate back to a domain error")
  }
  inspect(runs.val, content="3")

  table.set("Z9", 9)
  guard z9_plus_one.read() is Ok(Ok(10)) else {
    fail("expected recreation to invalidate and resolve")
  }
  inspect(runs.val, content="4")
}
```

## Long-lived authoring pipelines

```mbt check
///|
priv struct CookbookAuthoringTerminal {
  lowered : Result[String, String]
}

///|
impl Eq for CookbookAuthoringTerminal with fn equal(self, other) -> Bool {
  match (self.lowered, other.lowered) {
    (Ok(a), Ok(b)) => a == b
    (Err(a), Err(b)) => a == b
    _ => false
  }
}

///|
priv struct CookbookAuthoringSnapshot {
  active : String?
  diagnostics : String
}

///|
priv struct CookbookAuthoringPipeline {
  scope : @incr.Scope
  source : @incr.Input[String]
  terminal_cell : @incr.Derived[CookbookAuthoringTerminal]
  terminal_watch : @incr.Watch[CookbookAuthoringTerminal]
  last_good : Ref[String?]
}

///|
priv struct CookbookInspectorPanel {
  scope : @incr.Scope
  watch : @incr.Watch[String]
}

///|
fn CookbookAuthoringPipeline::CookbookAuthoringPipeline(
  rt : @incr.Runtime,
) -> CookbookAuthoringPipeline {
  let scope = @incr.Scope::new(rt)
  let source = scope.input("ok", label="authoring.source")
  let parse = scope.derived(
    () => {
      let text = source.get()
      if text.contains("parse-error") {
        Err("parse: invalid token")
      } else {
        Ok(text)
      }
    },
    label="authoring.parse",
  )
  let projection = scope.derived(
    () => {
      match parse.get_or_abort() {
        Ok(text) => Ok("project(" + text + ")")
        Err(diag) => Err(diag)
      }
    },
    label="authoring.projection",
  )
  let semantic = scope.derived(
    () => {
      match projection.get_or_abort() {
        Ok(projected) =>
          if projected.contains("semantic-error") {
            Err("semantic: unknown symbol")
          } else {
            Ok("sem(" + projected + ")")
          }
        Err(diag) => Err(diag)
      }
    },
    label="authoring.semantic",
  )
  let lowered = scope.derived(
    () => {
      match semantic.get_or_abort() {
        Ok(graph) => Ok("lower(" + graph + ")")
        Err(diag) => Err(diag)
      }
    },
    label="authoring.lowered",
  )
  let terminal_cell = scope.derived(
    () => { lowered: lowered.get_or_abort() },
    label="authoring.terminal",
  )
  let terminal_watch = scope.add_watch(terminal_cell.watch())
  let last_good : Ref[String?] = { val: None }
  // Prime before exposing: an uncomputed watched cell has no recorded deps for gc().
  match terminal_watch.read_or_abort().lowered {
    Ok(graph) => last_good.val = Some(graph)
    Err(_) => ()
  }
  { scope, source, terminal_cell, terminal_watch, last_good }
}

///|
fn CookbookAuthoringPipeline::snapshot(
  self : CookbookAuthoringPipeline,
) -> CookbookAuthoringSnapshot {
  let terminal = self.terminal_watch.read_or_abort()
  match terminal.lowered {
    Ok(graph) => {
      self.last_good.val = Some(graph)
      { active: Some(graph), diagnostics: "" }
    }
    Err(diag) => { active: self.last_good.val, diagnostics: diag }
  }
}

///|
fn CookbookAuthoringPipeline::open_inspector(
  self : CookbookAuthoringPipeline,
) -> CookbookInspectorPanel {
  let panel_scope = self.scope.child()
  let inspector = panel_scope.reachable_derived(
    () => {
      match self.terminal_cell.get_or_abort().lowered {
        Ok(graph) => "inspect:" + graph
        Err(diag) => "diagnostic:" + diag
      }
    },
    label="authoring.inspector",
  )
  let watch = panel_scope.add_watch(inspector.watch())
  // Prime before exposing so a pre-read gc keeps panel dependencies alive.
  ignore(watch.read_or_abort())
  { scope: panel_scope, watch }
}

///|
fn CookbookAuthoringPipeline::dispose(self : CookbookAuthoringPipeline) -> Unit {
  self.scope.dispose()
}

///|
fn CookbookInspectorPanel::read(self : CookbookInspectorPanel) -> String {
  self.watch.read_or_abort()
}

///|
fn CookbookInspectorPanel::dispose(self : CookbookInspectorPanel) -> Unit {
  self.scope.dispose()
}

///|
test "docs cookbook: long-lived authoring pipeline keeps last good result" {
  let rt = @incr.Runtime()
  let early_invalid = CookbookAuthoringPipeline(rt)
  rt.gc()
  early_invalid.source.set("parse-error")
  let early_parse_invalid = early_invalid.snapshot()
  guard early_parse_invalid.active is Some(early_active) else {
    fail("expected primed last good graph after early parse failure")
  }
  inspect(early_active, content="lower(sem(project(ok)))")
  inspect(early_parse_invalid.diagnostics, content="parse: invalid token")
  early_invalid.dispose()

  let pipeline = CookbookAuthoringPipeline(rt)
  rt.gc()

  let first = pipeline.snapshot()
  guard first.active is Some(first_active) else {
    fail("expected initial active graph")
  }
  inspect(first_active, content="lower(sem(project(ok)))")
  inspect(first.diagnostics, content="")

  let panel = pipeline.open_inspector()
  rt.gc()
  inspect(panel.read(), content="inspect:lower(sem(project(ok)))")

  pipeline.source.set("semantic-error")
  let invalid = pipeline.snapshot()
  guard invalid.active is Some(still_active) else {
    fail("expected last good graph")
  }
  inspect(still_active, content="lower(sem(project(ok)))")
  inspect(invalid.diagnostics, content="semantic: unknown symbol")
  inspect(panel.read(), content="diagnostic:semantic: unknown symbol")

  pipeline.source.set("parse-error")
  let parse_invalid = pipeline.snapshot()
  guard parse_invalid.active is Some(still_active) else {
    fail("expected last good graph after parse failure")
  }
  inspect(still_active, content="lower(sem(project(ok)))")
  inspect(parse_invalid.diagnostics, content="parse: invalid token")
  inspect(panel.read(), content="diagnostic:parse: invalid token")

  pipeline.source.set("next")
  let recovered = pipeline.snapshot()
  guard recovered.active is Some(recovered_active) else {
    fail("expected recovered graph")
  }
  inspect(recovered_active, content="lower(sem(project(next)))")
  inspect(recovered.diagnostics, content="")
  inspect(panel.read(), content="inspect:lower(sem(project(next)))")

  panel.dispose()
  inspect(panel.watch.is_disposed(), content="true")
  pipeline.dispose()
  inspect(pipeline.terminal_watch.is_disposed(), content="true")
}
```
