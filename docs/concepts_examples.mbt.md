# Checked Concepts Examples

Literate tests that pin high-value behavior described in
[`concepts.mbt.md`](concepts.mbt.md). These examples focus on conceptual claims that can
silently drift: same-value input updates, labels in cell metadata, inside-vs-
outside reads, backdating, batch revert detection, field-level dependency
isolation, keyed derived maps, accumulators, and reachable derived reads.

## Inputs, labels, and read vocabulary

```mbt check
///|
test "docs concepts: same-value input set is a no-op" {
  let rt = @incr.Runtime()
  let count = @incr.Input(rt, 0, label="count")
  let notifications : Ref[Int] = { val: 0 }
  rt.set_on_change(() => notifications.val = notifications.val + 1)

  inspect(count.get(), content="0")
  count.set(5)
  inspect(count.get(), content="5")
  inspect(notifications.val, content="1")

  count.set(5)
  inspect(notifications.val, content="1")

  count.force_set(5)
  inspect(notifications.val, content="2")
}

///|
test "docs concepts: labels are available through cell_info" {
  let rt = @incr.Runtime()
  let price = @incr.Input(rt, 100, label="price")
  let qty = @incr.Input(rt, 2, label="qty")
  let total = @incr.Derived(rt, () => price.get() * qty.get(), label="total")

  match rt.cell_info(total.id()) {
    Some(info) =>
      debug_inspect(
        info.label,
        content=(
          #|Some("total")
        ),
      )
    None => abort("expected total cell_info")
  }
}

///|
test "docs concepts: derived get tracks inside and read works outside" {
  let rt = @incr.Runtime()
  let count = @incr.Input(rt, 2, label="count")
  let doubled = @incr.Derived(rt, () => count.get() * 2, label="doubled")
  let plus_one = doubled.map(x => x + 1, label="plus_one")

  inspect(doubled.read_or_abort(), content="4")
  inspect(plus_one.read_or_abort(), content="5")
  count.set(4)
  inspect(plus_one.read_or_abort(), content="9")
}
```

## Backdating, batching, and dynamic dependencies

```mbt check
///|
test "docs concepts: backdating skips unchanged downstream value" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 4, label="input")
  let is_even_runs : Ref[Int] = { val: 0 }
  let label_runs : Ref[Int] = { val: 0 }
  let is_even = @incr.Derived(
    rt,
    () => {
      is_even_runs.val = is_even_runs.val + 1
      input.get() % 2 == 0
    },
    label="is_even",
  )
  let label = @incr.Derived(
    rt,
    () => {
      label_runs.val = label_runs.val + 1
      if is_even.get_or_abort() {
        "even"
      } else {
        "odd"
      }
    },
    label="label",
  )

  inspect(label.read_or_abort(), content="even")
  inspect(is_even_runs.val, content="1")
  inspect(label_runs.val, content="1")

  input.set(6)
  inspect(label.read_or_abort(), content="even")
  inspect(is_even_runs.val, content="2")
  inspect(label_runs.val, content="1")
}

///|
test "docs concepts: batch revert produces no committed change" {
  let rt = @incr.Runtime()
  let counter = @incr.Input(rt, 0, label="counter")
  let notifications : Ref[Int] = { val: 0 }
  rt.set_on_change(() => notifications.val = notifications.val + 1)

  rt.batch(() => {
    counter.set(5)
    counter.set(0)
  })

  inspect(counter.get(), content="0")
  inspect(notifications.val, content="0")
}

///|
test "docs concepts: high-durability derived stays cached when low input changes" {
  let rt = @incr.Runtime()
  let config = @incr.Input(rt, "production", durability=High, label="config")
  let user_input = @incr.Input(rt, "hello", label="user_input")
  let config_runs : Ref[Int] = { val: 0 }
  let processed_runs : Ref[Int] = { val: 0 }
  let config_hash = @incr.Derived(
    rt,
    () => {
      config_runs.val = config_runs.val + 1
      config.get().length()
    },
    label="config_hash",
  )
  let processed = @incr.Derived(
    rt,
    () => {
      processed_runs.val = processed_runs.val + 1
      user_input.get().length()
    },
    label="processed",
  )

  inspect(config_hash.read_or_abort(), content="10")
  inspect(processed.read_or_abort(), content="5")
  user_input.set("world")
  inspect(processed.read_or_abort(), content="5")
  inspect(config_hash.read_or_abort(), content="10")
  inspect(config_runs.val, content="1")
  inspect(processed_runs.val, content="2")
}

///|
test "docs concepts: dynamic dependencies follow active branch" {
  let rt = @incr.Runtime()
  let mode = @incr.Input(rt, "add", label="mode")
  let x = @incr.Input(rt, 10, label="x")
  let y = @incr.Input(rt, 20, label="y")
  let result_runs : Ref[Int] = { val: 0 }
  let result = @incr.Derived(
    rt,
    () => {
      result_runs.val = result_runs.val + 1
      if mode.get() == "add" {
        x.get() + y.get()
      } else {
        x.get() * y.get()
      }
    },
    label="result",
  )

  inspect(result.read_or_abort(), content="30")
  inspect(result_runs.val, content="1")
  mode.set("multiply")
  inspect(result.read_or_abort(), content="200")
  inspect(result_runs.val, content="2")
  x.set(11)
  inspect(result.read_or_abort(), content="220")
  inspect(result_runs.val, content="3")
}
```

## Field-level inputs and keyed derived values

```mbt check
///|
struct ConceptsSourceFile {
  path : @incr.InputField[String]
  content : @incr.InputField[String]
  version : @incr.InputField[Int]
}

///|
impl @incr.InputFieldOwner for ConceptsSourceFile with fn cell_ids(self) {
  [self.path.id(), self.content.id(), self.version.id()]
}

///|
test "docs concepts: input fields isolate field-specific dependencies" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let file : ConceptsSourceFile = {
    path: @incr.InputField(rt, "/src/main.mbt", label="path"),
    content: @incr.InputField(rt, "hello world", label="content"),
    version: @incr.InputField(rt, 0, label="version"),
  }
  @incr.add_input_fields(scope, file)
  let word_count_runs : Ref[Int] = { val: 0 }
  let is_test_runs : Ref[Int] = { val: 0 }
  let word_count = @incr.Derived(
    rt,
    () => {
      word_count_runs.val = word_count_runs.val + 1
      file.content.get().split(" ").fold(init=0, fn(acc, _s) { acc + 1 })
    },
    label="word_count",
  )
  let is_test = @incr.Derived(
    rt,
    () => {
      is_test_runs.val = is_test_runs.val + 1
      file.path.get().has_suffix("_test.mbt")
    },
    label="is_test",
  )

  inspect(word_count.read_or_abort(), content="2")
  inspect(is_test.read_or_abort(), content="false")
  file.version.set(1)
  inspect(word_count.read_or_abort(), content="2")
  inspect(is_test.read_or_abort(), content="false")
  inspect(word_count_runs.val, content="1")
  inspect(is_test_runs.val, content="1")
  scope.dispose()
  inspect(file.path.is_disposed(), content="true")
}

///|
test "docs concepts: derived maps cache per key and recompute lazily" {
  let rt = @incr.Runtime()
  let base = @incr.Input(rt, 10, label="base")
  let by_id = @incr.DerivedMap(rt, (id : Int) => base.get() + id, label="by_id")

  inspect(by_id.read_or_abort(1), content="11")
  inspect(by_id.read_or_abort(2), content="12")
  inspect(by_id.cache_len(), content="2")
  base.set(20)
  inspect(by_id.read_or_abort(1), content="21")
  inspect(by_id.read_or_abort(2), content="22")
}
```

## Accumulators and reachable derived values

```mbt check
///|
test "docs concepts: accumulators expose memo-local side-channel data" {
  let rt = @incr.Runtime()
  let width = @incr.Input(rt, -5, label="width")
  let diags : @incr.Accumulator[String] = @incr.Accumulator::new(
    rt~,
    label="diags",
  )
  let checked = @incr.Derived(
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
  let observer = checked.observe()

  inspect(observer.get(), content="5")
  debug_inspect(
    checked.accumulated_peek(diags),
    content="[\"negative width: -5\"]",
  )
  observer.dispose()
  diags.dispose()
}

///|
test "docs concepts: reachable derived reads lazily and updates" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="input")
  let reachable = @incr.ReachableDerived(
    rt,
    () => input.get() * 2,
    label="reachable",
  )

  inspect(reachable.read_or_abort(), content="2")
  input.set(5)
  inspect(reachable.read_or_abort(), content="10")
}
```
