# Checked API Reference Examples

Literate tests that mirror the executable snippets in [`api-reference.mbt.md`](api-reference.mbt.md).
They exist to catch docs/API drift on the target facade surfaces — `Derived`,
`DerivedMap`, `ReachableDerived`, `MapRelation`, and the `RuntimeContext` /
`Scope` helper families — beyond the README and getting-started examples already
covered by [`target_api_examples.mbt.md`](target_api_examples.mbt.md). They also
pin derived-event listener lifecycle, compatibility introspection/callbacks, and the
compatibility accumulator push path. The accumulator examples intentionally use
compatibility `Memo` handles because `Accumulator::push` is only legal from
compatibility `Memo` / `HybridMemo` compute frames.

## Runtime batching and change callbacks

```mbt check
///|
suberror ApiRefBatchResultError {
  ApiRefBatchStop
}

///|
test "docs api-ref: Runtime batch_result returns Err and rolls back writes" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 0, label="input")
  let notifications : Ref[Int] = { val: 0 }
  rt.set_on_change(() => notifications.val = notifications.val + 1)

  let result = rt.batch_result(fn() raise {
    input.set(1)
    raise ApiRefBatchStop
  })

  inspect(result is Err(_), content="true")
  inspect(input.get(), content="0")
  inspect(notifications.val, content="0")

  input.set(2)
  inspect(input.get(), content="2")
  inspect(notifications.val, content="1")
}

///|
test "docs api-ref: Runtime on_change fires for committed changes" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 0, label="input")
  let notifications : Ref[Int] = { val: 0 }

  rt.set_on_change(() => notifications.val = notifications.val + 1)

  input.set(1)
  inspect(notifications.val, content="1")

  input.set(1)
  inspect(notifications.val, content="1")

  rt.batch(() => {
    input.set(2)
    input.set(3)
  })
  inspect(input.get(), content="3")
  inspect(notifications.val, content="2")

  rt.clear_on_change()
  input.set(4)
  inspect(notifications.val, content="2")
}

///|
test "docs api-ref: InputField on_change fires before Runtime on_change" {
  let rt = @incr.Runtime()
  let price = @incr.InputField(rt, 100, label="price")
  let log : Ref[String] = { val: "" }

  price.on_change(new_price => {
    log.val = log.val + "cell:" + new_price.to_string() + ";"
  })
  rt.set_on_change(() => log.val = log.val + "global;")

  price.set(200)
  inspect(log.val, content="cell:200;global;")

  rt.batch(() => {
    price.set(150)
    price.set(250)
  })
  inspect(log.val, content="cell:200;global;cell:250;global;")

  price.clear_on_change()
  price.set(300)
  inspect(log.val, content="cell:200;global;cell:250;global;global;")
}
```

## Derived event listener lifecycle

```mbt check
///|
test "docs api-ref: derived event listener records and can be cleared" {
  let rt = @incr.Runtime()
  let input = @incr.Signal(rt, 1, label="input")
  let events : Ref[Int] = { val: 0 }

  rt.on_derived_event(_evt => events.val = events.val + 1)

  let doubled = @incr.Memo(rt, () => input.get() * 2, label="doubled")
  let observer = doubled.observe()
  inspect(observer.get(), content="2")
  inspect(events.val, content="2")

  rt.clear_derived_event_listener()
  input.set(2)
  inspect(observer.get(), content="4")
  inspect(events.val, content="2")
  observer.dispose()
}
```

## `Input` and `InputField` basics

```mbt check
///|
test "docs api-ref: Input get tracks, peek is untracked" {
  let rt = @incr.Runtime()
  let count = @incr.Input(rt, 1, label="count")
  let tracked_runs : Ref[Int] = { val: 0 }
  let peek_runs : Ref[Int] = { val: 0 }

  let tracked = @incr.Derived(
    rt,
    () => {
      tracked_runs.val = tracked_runs.val + 1
      count.get() * 2
    },
    label="tracked_count",
  )
  let peeked = @incr.Derived(
    rt,
    () => {
      peek_runs.val = peek_runs.val + 1
      count.peek() * 2
    },
    label="peeked_count",
  )

  inspect(tracked.read_or_abort(), content="2")
  inspect(peeked.read_or_abort(), content="2")
  inspect(tracked_runs.val, content="1")
  inspect(peek_runs.val, content="1")

  count.set(2)
  inspect(tracked.read_or_abort(), content="4")
  inspect(tracked_runs.val, content="2")
  inspect(peeked.read_or_abort(), content="2")
  inspect(peek_runs.val, content="1")

  // Same-value `set` is a no-op; `force_set` invalidates even equal values.
  count.set(2)
  inspect(tracked.read_or_abort(), content="4")
  inspect(tracked_runs.val, content="2")
  count.force_set(2)
  inspect(tracked.read_or_abort(), content="4")
  inspect(tracked_runs.val, content="3")
}

///|
test "docs api-ref: InputField exposes field identity and participates in derived reads" {
  let rt = @incr.Runtime()
  let path = @incr.InputField(
    rt,
    "src/main.mbt",
    durability=High,
    label="SourceFile.path",
  )
  let read_count : Ref[Int] = { val: 0 }
  let extension = @incr.Derived(
    rt,
    () => {
      read_count.val = read_count.val + 1
      if path.get().contains(".mbt") {
        "moonbit"
      } else {
        "other"
      }
    },
    label="SourceFile.extension",
  )

  inspect(path.get(), content="src/main.mbt")
  inspect(path.peek(), content="src/main.mbt")
  inspect(path.durability(), content="High")
  match rt.cell_info(path.id()) {
    Some(info) => {
      debug_inspect(
        info.label,
        content=(
          #|Some("SourceFile.path")
        ),
      )
      inspect(info.durability, content="High")
      debug_inspect(info.dependencies, content="[]")
    }
    None => abort("expected InputField cell_info")
  }

  inspect(extension.read_or_abort(), content="moonbit")
  path.set("README.md")
  inspect(extension.read_or_abort(), content="other")
  inspect(read_count.val, content="2")
}
```

## Labels, cycle paths, and cell introspection

```mbt check
///|
test "docs api-ref: labels appear in cell_info and cycle errors" {
  let rt = @incr.Runtime()
  let version = @incr.InputField(rt, 1, label="SourceFile.version")
  let doubled = @incr.Derived(
    rt,
    () => version.get() * 2,
    label="SourceFile.version_doubled",
  )

  inspect(doubled.read_or_abort(), content="2")
  match rt.cell_info(doubled.id()) {
    Some(info) => {
      debug_inspect(
        info.label,
        content=(
          #|Some("SourceFile.version_doubled")
        ),
      )
      inspect(info.dependencies.contains(version.id()), content="true")
    }
    None => abort("expected Derived cell_info")
  }

  let a_ref : Ref[@incr.Derived[Int]?] = { val: None }
  let b_ref : Ref[@incr.Derived[Int]?] = { val: None }
  let formatted : Ref[String] = { val: "" }
  let a = @incr.Derived(
    rt,
    () => {
      match b_ref.val {
        Some(b) => b.get_or_abort() + 1
        None => 0
      }
    },
    label="price",
  )
  let b = @incr.Derived(
    rt,
    () => {
      match a_ref.val {
        Some(a0) =>
          match a0.get() {
            Ok(v) => v + 1
            Err(err) => {
              formatted.val = err.format_path()
              -1
            }
          }
        None => 0
      }
    },
    label="tax",
  )
  a_ref.val = Some(a)
  b_ref.val = Some(b)

  let _ = a.read_or_abort()
  inspect(formatted.val.contains("Cycle detected:"), content="true")
  inspect(formatted.val.contains("price"), content="true")
  inspect(formatted.val.contains("tax"), content="true")
}
```

## `Derived` — strict get, permissive read, watch

```mbt check
///|
test "docs api-ref: derived get inside compute, read outside" {
  let rt = @incr.Runtime()
  let price = @incr.Input(rt, 100, label="price")
  let tax_rate = @incr.Input(rt, 0.1, label="tax_rate")
  let tax = @incr.Derived(
    rt,
    () => price.get().to_double() * tax_rate.get(),
    label="tax",
  )
  let total = @incr.Derived(
    rt,
    // `get_or_abort` is the strict tracked-context read.
    () => price.get().to_double() + tax.get_or_abort(),
    label="total",
  )

  // Outside the graph: `read()` returns Result so cycles surface as Err.
  match total.read() {
    Ok(value) => inspect(value, content="110")
    Err(err) => abort(err.format_path())
  }

  // `read_or_abort` is the convenient permissive read.
  price.set(200)
  inspect(total.read_or_abort(), content="220")
}

///|
test "docs api-ref: derived map transforms a source value" {
  let rt = @incr.Runtime()
  let count = @incr.Input(rt, 2, label="count")
  let plus_one = @incr.Derived(rt, () => count.get() + 1, label="plus_one")
  let doubled = plus_one.map(v => v * 2, label="doubled")

  inspect(doubled.read_or_abort(), content="6")
  count.set(4)
  inspect(doubled.read_or_abort(), content="10")
}

///|
test "docs api-ref: derived.watch survives gc and tracks updates" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="input")
  let watch = {
    let derived = @incr.Derived(rt, () => input.get() * 10, label="derived")
    derived.watch()
  }

  // Even though the local `derived` handle is out of scope, the Watch keeps it
  // alive across GC sweeps.
  rt.gc()
  inspect(watch.read_or_abort(), content="10")

  input.set(4)
  match watch.read() {
    Ok(v) => inspect(v, content="40")
    Err(err) => abort(err.format_path())
  }
  watch.dispose()
}
```

## `DerivedMap` — keyed derived values

```mbt check
///|
test "docs api-ref: derived_map permissive and strict reads" {
  let rt = @incr.Runtime()
  let multiplier = @incr.Input(rt, 10, label="multiplier")
  let by_id : @incr.DerivedMap[Int, Int] = @incr.DerivedMap(
    rt,
    (id : Int) => id * multiplier.get(),
    label="by_id",
  )

  // Outside the graph: `read_or_abort` lazily computes and caches the entry.
  inspect(by_id.read_or_abort(3), content="30")
  inspect(by_id.read_or_abort(4), content="40")
  inspect(by_id.has_cached(3), content="true")
  inspect(by_id.cache_len(), content="2")

  // Inside a tracked compute, `get_or_abort` records a per-key dependency.
  let sum_3_4 = @incr.Derived(
    rt,
    () => by_id.get_or_abort(3) + by_id.get_or_abort(4),
    label="sum_3_4",
  )
  inspect(sum_3_4.read_or_abort(), content="70")

  // Bumping the multiplier invalidates only the keys read by `sum_3_4`.
  multiplier.set(5)
  inspect(sum_3_4.read_or_abort(), content="35")
}

///|
test "docs api-ref: derived_map clear_cache drops cached entries" {
  let rt = @incr.Runtime()
  let by_key : @incr.DerivedMap[Int, Int] = @incr.DerivedMap(rt, (key : Int) => {
    key + 1
  })

  inspect(by_key.read_or_abort(1), content="2")
  inspect(by_key.read_or_abort(2), content="3")
  inspect(by_key.cache_len(), content="2")

  by_key.clear_cache()
  inspect(by_key.cache_len(), content="0")
  inspect(by_key.has_cached(1), content="false")
}

///|
test "docs api-ref: derived_map read_or / read_or_else return the value on the happy path" {
  let rt = @incr.Runtime()
  let by_key : @incr.DerivedMap[Int, Int] = @incr.DerivedMap(rt, (key : Int) => {
    key * 100
  })

  // No cycle — both fallback forms see Ok(value) and pass through.
  inspect(by_key.read_or(3, 999), content="300")
  inspect(by_key.read_or_else(4, _err => -1), content="400")
}

///|
test "docs api-ref: derived_map sweep_cache prunes gc-disposed entries" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, 10, label="source")
  let by_key : @incr.DerivedMap[Int, Int] = @incr.DerivedMap(
    rt,
    (key : Int) => source.get() + key,
    label="by_key",
  )

  // Populate three entries with no persistent observer.
  inspect(by_key.read_or_abort(1), content="11")
  inspect(by_key.read_or_abort(2), content="12")
  inspect(by_key.read_or_abort(3), content="13")
  inspect(by_key.cache_len(), content="3")

  // `rt.gc()` disposes the unobserved interior memos; `sweep_cache` then
  // drops the now-stale entries from the cache.
  rt.gc()
  inspect(by_key.sweep_cache(), content="3")
  inspect(by_key.cache_len(), content="0")
}
```

## `ReachableDerived` — lazy reads that participate in reachability

```mbt check
///|
test "docs api-ref: reachable_derived chained with watch survives gc" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 1, label="input")
  let reachable = @incr.ReachableDerived(
    rt,
    () => input.get() * 2,
    label="doubled",
  )
  let downstream = @incr.Derived(
    rt,
    () => reachable.get_or_abort() + 100,
    label="downstream",
  )
  let watch = downstream.watch()

  inspect(watch.read_or_abort(), content="102")
  rt.gc()
  input.set(5)
  inspect(watch.read_or_abort(), content="110")
  inspect(reachable.is_fresh(), content="true")
  watch.dispose()
}

///|
test "docs api-ref: reachable_derived.watch is a GC root for the reachable cell itself" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 2, label="input")
  let watch = {
    let reachable = @incr.ReachableDerived(
      rt,
      () => input.get() * 3,
      label="reachable_watched",
    )
    reachable.watch()
  }

  // The local `reachable` handle is gone, but `watch` keeps the cell alive
  // across gc — the next read still reflects updated input.
  inspect(watch.read_or_abort(), content="6")
  rt.gc()
  input.set(4)
  inspect(watch.read_or_abort(), content="12")
  watch.dispose()
}
```

## `EagerDerived` — eager recomputation and outside reads

```mbt check
///|
test "docs api-ref: eager_derived recomputes eagerly and can be read from outside" {
  let rt = @incr.Runtime()
  let input = @incr.Input(rt, 4, label="input")
  let runs : Ref[Int] = { val: 0 }
  let eager = @incr.EagerDerived(rt, () => {
    runs.val = runs.val + 1
    input.get() * 3
  })
  let view = @incr.Derived(rt, () => eager.get() + 1, label="eager_view")
  let watch = eager.watch()

  inspect(eager.read(), content="12")
  inspect(view.read_or_abort(), content="13")
  inspect(runs.val > 0, content="true")

  let runs_before_set = runs.val
  input.set(5)
  inspect(runs.val == runs_before_set + 1, content="true")
  inspect(watch.read_or_abort(), content="15")
  inspect(view.read_or_abort(), content="16")

  rt.gc()
  input.set(6)
  inspect(watch.read_or_abort(), content="18")
  watch.dispose()
}
```

## `AcceptedDerived` — success-gated retention

`AcceptedDerived[V, E]` computes a fallible candidate `Result[V, E]` from current
inputs, but only `Ok(v)` candidates advance the *accepted* value. On `Err(e)` the
current channel reports the error while the previously accepted value is retained.

The in-graph `accepted_get_or_abort` reads the accepted projection, so an
accepted-only consumer re-runs only when the accepted value actually changes —
never on current-error churn.

```mbt check
///|
/// A toy fallible parse with hand-reasoned outcomes: `"1"` → `Ok(1)`, `"2"` →
/// `Ok(2)`, anything else → `Err`.
fn ad_doc_parse(src : String) -> Result[Int, String] {
  match src {
    "1" => Ok(1)
    "2" => Ok(2)
    _ => Err("cannot parse \"\{src}\"")
  }
}

///|
test "docs api-ref: accepted_derived retains last accepted value across errors" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, "1", label="source")
  let parsed = @incr.AcceptedDerived::AcceptedDerived(
    rt,
    () => ad_doc_parse(source.get()),
    label="parsed",
  )

  // First success accepts the value.
  inspect(parsed.accepted_or_abort() is Some(1), content="true")
  inspect(parsed.snapshot_or_abort().status, content="AcceptedChanged")

  // An in-graph accepted-only consumer reads through `accepted_get_or_abort`, so
  // it depends on the accepted projection — not the candidate.
  let runs = [0]
  let consumer = @incr.Derived(rt, () => {
    runs[0] = runs[0] + 1
    parsed.accepted_get_or_abort()
  })
  let watch = consumer.watch()
  ignore(watch.read_or_abort()) // prime
  let base = runs[0]

  // Err → the current channel reports the error, but the accepted value is
  // RETAINED and the accepted-only consumer does NOT re-run.
  source.set("oops")
  inspect(parsed.current_or_abort() is Err(_), content="true")
  inspect(parsed.accepted_or_abort() is Some(1), content="true")
  inspect(parsed.snapshot_or_abort().status, content="RetainedDueToError")
  ignore(watch.read_or_abort())
  inspect(runs[0] == base, content="true")

  // A genuine accepted-value change DOES advance the accepted projection and
  // re-runs the consumer.
  source.set("2")
  ignore(watch.read_or_abort())
  inspect(parsed.accepted_or_abort() is Some(2), content="true")
  inspect(runs[0] > base, content="true")
  watch.dispose()
}

///|
test "docs api-ref: accepted_derived status transitions and accepted_changed_at gating" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, "1", label="source")
  let parsed = @incr.AcceptedDerived::AcceptedDerived(
    rt,
    () => ad_doc_parse(source.get()),
    label="parsed",
  )
  let r1 = parsed.accepted_changed_at()

  // Err while a value is accepted: the snapshot exposes the error current, the
  // retained accepted value, and RetainedDueToError. `accepted_changed_at` does
  // not advance — it is gated solely by accepted-value equality.
  source.set("oops")
  let snap = parsed.snapshot_or_abort()
  inspect(snap.current is Err(_), content="true")
  inspect(snap.accepted is Some(1), content="true")
  inspect(snap.status, content="RetainedDueToError")
  inspect(parsed.accepted_changed_at() == r1, content="true")

  // Equal success (same accepted value from a different source): AcceptedUnchanged,
  // still no advance.
  source.set("1")
  inspect(parsed.snapshot_or_abort().status, content="AcceptedUnchanged")
  inspect(parsed.accepted_changed_at() == r1, content="true")

  // Changed success: AcceptedChanged, and now `accepted_changed_at` advances.
  source.set("2")
  inspect(parsed.snapshot_or_abort().status, content="AcceptedChanged")
  inspect(parsed.accepted_changed_at() == r1, content="false")
}

///|
test "docs api-ref: accepted_derived accepts a transient success between failures" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, "bad", label="source")
  let parsed = @incr.AcceptedDerived::AcceptedDerived(
    rt,
    () => ad_doc_parse(source.get()),
    label="parsed",
  )
  // No prior accepted value, candidate Err → NoAccept.
  inspect(parsed.accepted_or_abort() is None, content="true")
  inspect(parsed.snapshot_or_abort().status, content="NoAccept")

  // A transient success, then a failure, with NO read in between. The accept fold
  // runs eagerly once per committed revision, so it still observes the Ok(1) and
  // retains it after the later Err.
  source.set("1")
  source.set("bad")
  inspect(parsed.accepted_or_abort() is Some(1), content="true")
  inspect(parsed.snapshot_or_abort().status, content="RetainedDueToError")
}

///|
test "docs api-ref: batch coalesces intra-batch writes to one committed transition" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, "bad", label="source")
  let parsed = @incr.AcceptedDerived::AcceptedDerived(
    rt,
    () => ad_doc_parse(source.get()),
    label="parsed",
  )
  inspect(parsed.accepted_or_abort() is None, content="true")

  // A batch publishes a single committed revision: the transient Ok(1) written
  // inside the batch is never separately accepted because the committed value is
  // the trailing Err.
  rt.batch(() => {
    source.set("1")
    source.set("bad")
  })
  inspect(parsed.accepted_or_abort() is None, content="true")
  inspect(parsed.snapshot_or_abort().status, content="NoAccept")
}

///|
test "docs api-ref: from_candidate wraps an external candidate and spares it on dispose" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, "1", label="source")
  // The caller owns this candidate `Derived`; the wrapper only adds the accept gate.
  let candidate = @incr.Derived::fallible(rt, () => ad_doc_parse(source.get()))
  let parsed = @incr.AcceptedDerived::from_candidate(candidate)

  // `watch_accepted` is a persistent outside-graph anchor on the accepted value.
  let watch = parsed.watch_accepted()
  inspect(watch.read_or_abort() is Some(1), content="true")
  source.set("2")
  inspect(watch.read_or_abort() is Some(2), content="true")
  watch.dispose()

  // Disposing the wrapper spares the externally-owned candidate.
  parsed.dispose()
  inspect(parsed.is_disposed(), content="true")
  inspect(candidate.read_or_abort() is Ok(2), content="true")
}

///|
test "docs api-ref: scope-owned accepted_derived disposes with its scope" {
  let rt = @incr.Runtime()
  let source = @incr.Input(rt, "1", label="source")
  let scope = @incr.Scope::new(rt)
  let parsed = scope.accepted_derived(() => ad_doc_parse(source.get()))
  inspect(parsed.accepted_or_abort() is Some(1), content="true")

  scope.dispose()
  inspect(parsed.is_disposed(), content="true")
  // After disposal every read channel surfaces Disposed on its read-error channel.
  inspect(
    match parsed.current() {
      Err(e) => e.is_disposed()
      Ok(_) => false
    },
    content="true",
  )
}
```

## `Accumulator` — compatibility push side-channel

```mbt check
///|
test "docs api-ref: Accumulator::new and push capture memo-local values" {
  let rt = @incr.Runtime()
  let width = @incr.Signal(rt, -1, label="width")
  let diags : @incr.Accumulator[String] = @incr.Accumulator::new(
    rt~,
    label="diags",
  )
  let producer = @incr.Memo(
    rt,
    () => {
      if width.get() < 0 {
        diags.push("negative width")
      }
      width.get()
    },
    label="width_check",
  )
  let observer = producer.observe()

  debug_inspect(
    diags.label(),
    content=(
      #|Some("diags")
    ),
  )
  inspect(observer.get(), content="-1")
  let first = producer.accumulated_peek(diags)
  inspect(first.length(), content="1")
  inspect(first[0], content="negative width")

  width.set(4)
  inspect(observer.get(), content="4")
  debug_inspect(producer.accumulated_peek(diags), content="[]")
  observer.dispose()
  diags.dispose()
}

///|
test "docs api-ref: Scope::accumulator owns accumulator disposal" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let diags : @incr.Accumulator[String] = scope.accumulator(
    label="typecheck_diags",
  )

  inspect(diags.is_disposed(), content="false")
  scope.dispose()
  inspect(diags.is_disposed(), content="true")
}
```

## `MapRelation` — materialized reads after fixpoint

```mbt check
///|
test "docs api-ref: map_relation staged values become visible after fixpoint" {
  let rt = @incr.Runtime()
  let weights : @incr.MapRelation[(Int, Int), Int] = @incr.MapRelation(
    rt,
    label="weights",
  )

  inspect(weights.insert((1, 2), 10), content="true")
  inspect(weights.insert((2, 3), 5), content="true")
  debug_inspect(weights.get((1, 2)), content="None")
  inspect(
    weights.delta_iter().fold(init=0, fn(acc, _entry) { acc + 1 }),
    content="2",
  )
  inspect(weights.iter().fold(init=0, fn(acc, _entry) { acc + 1 }), content="0")

  rt.fixpoint()
  debug_inspect(weights.get((1, 2)), content="Some(10)")
  inspect(weights.iter().fold(init=0, fn(acc, _entry) { acc + 1 }), content="2")
  inspect(weights.insert((1, 2), 10), content="false")
}
```

## Compatibility introspection and callbacks

```mbt check
///|
test "docs api-ref: compatibility introspection exposes ids dependencies and dependents" {
  let rt = @incr.Runtime()
  let input = @incr.Signal(rt, 10, durability=High, label="input")
  let doubled = @incr.Memo(rt, () => input.get() * 2, label="doubled")
  let observer = doubled.observe()

  inspect(input.durability(), content="High")
  inspect(observer.get(), content="20")
  inspect(doubled.dependencies().contains(input.id()), content="true")
  inspect(rt.dependents(input.id()).contains(doubled.id()), content="true")
  match rt.cell_info(doubled.id()) {
    Some(info) => {
      debug_inspect(
        info.label,
        content=(
          #|Some("doubled")
        ),
      )
      inspect(info.dependencies.contains(input.id()), content="true")
    }
    None => abort("expected memo cell_info")
  }

  let changed = doubled.changed_at()
  let verified = doubled.verified_at()
  input.set(11)
  inspect(observer.get(), content="22")
  inspect(doubled.changed_at() > changed, content="true")
  inspect(doubled.verified_at() > verified, content="true")
  observer.dispose()
}

///|
test "docs api-ref: compatibility per-cell callbacks can be registered and cleared" {
  let rt = @incr.Runtime()
  let input = @incr.Signal(rt, 1, label="input")
  let doubled = @incr.Memo(rt, () => input.get() * 2, label="doubled")
  let observer = doubled.observe()
  let input_log : Ref[String] = { val: "" }
  let memo_log : Ref[String] = { val: "" }

  input.on_change(value => input_log.val = value.to_string())
  doubled.on_change(value => memo_log.val = value.to_string())

  inspect(observer.get(), content="2")
  input.set(3)
  inspect(input_log.val, content="3")
  inspect(observer.get(), content="6")
  inspect(memo_log.val, content="6")

  input.clear_on_change()
  doubled.clear_on_change()
  input.set(4)
  inspect(observer.get(), content="8")
  inspect(input_log.val, content="3")
  inspect(memo_log.val, content="6")
  observer.dispose()
}
```

## `RuntimeContext` and the `create_*` helpers

```mbt check
///|
struct AppCtx {
  rt : @incr.Runtime
}

///|
impl @incr.RuntimeContext for AppCtx with fn runtime(self) {
  self.rt
}

///|
impl @incr.Database for AppCtx with fn runtime(self) {
  self.rt
}

///|
struct CompatTrackedFields {
  path : @incr.TrackedCell[String]
  version : @incr.TrackedCell[Int]
}

///|
impl @incr.Trackable for CompatTrackedFields with fn cell_ids(self) {
  [self.path.id(), self.version.id()]
}

///|
test "docs api-ref: create_input / create_derived / create_derived_map via context" {
  let ctx : AppCtx = { rt: @incr.Runtime() }
  let price = @incr.create_input(ctx, 100, label="price")
  let quantity = @incr.create_input(ctx, 2, label="quantity")
  let total = @incr.create_derived(
    ctx,
    () => price.get() * quantity.get(),
    label="total",
  )
  let by_id = @incr.create_derived_map(
    ctx,
    (id : Int) => id * price.get(),
    label="by_id",
  )

  inspect(total.read_or_abort(), content="200")
  inspect(by_id.read_or_abort(3), content="300")

  quantity.set(5)
  inspect(total.read_or_abort(), content="500")
}

///|
test "docs api-ref: create_input_field / create_reachable_derived / create_eager_derived" {
  let ctx : AppCtx = { rt: @incr.Runtime() }
  let count = @incr.create_input(ctx, 1, label="count")
  let path_field = @incr.create_input_field(
    ctx,
    "src/main.mbt",
    label="SourceFile.path",
  )
  let reachable = @incr.create_reachable_derived(
    ctx,
    () => count.get() * 10,
    label="reachable_doubled",
  )
  let eager = @incr.create_eager_derived(ctx, () => count.get() + 100)

  inspect(path_field.get(), content="src/main.mbt")
  inspect(reachable.read_or_abort(), content="10")
  inspect(eager.read(), content="101")

  count.set(3)
  inspect(reachable.read_or_abort(), content="30")
  inspect(eager.read(), content="103")
}

///|
test "docs api-ref: Database batch helper commits one atomic update" {
  let app : AppCtx = { rt: @incr.Runtime() }
  let price = @incr.Input(app.rt, 100, label="price")
  let quantity = @incr.Input(app.rt, 2, label="quantity")
  let total = @incr.Derived(
    app.rt,
    () => price.get() * quantity.get(),
    label="total",
  )
  let notifications : Ref[Int] = { val: 0 }
  app.rt.set_on_change(() => notifications.val = notifications.val + 1)

  @incr.batch(app, () => {
    price.set(125)
    quantity.set(3)
  })

  inspect(total.read_or_abort(), content="375")
  inspect(notifications.val, content="1")
}

///|
test "docs api-ref: Database batch_result helper rolls back on Err" {
  let app : AppCtx = { rt: @incr.Runtime() }
  let price = @incr.Input(app.rt, 100, label="price")
  let quantity = @incr.Input(app.rt, 2, label="quantity")
  let total = @incr.Derived(
    app.rt,
    () => price.get() * quantity.get(),
    label="total",
  )

  let result = @incr.batch_result(app, fn() raise {
    price.set(500)
    quantity.set(9)
    raise ApiRefBatchStop
  })

  inspect(result is Err(_), content="true")
  inspect(price.get(), content="100")
  inspect(quantity.get(), content="2")
  inspect(total.read_or_abort(), content="200")

  let ok = @incr.batch_result(app, () => price.set(120))
  inspect(ok is Ok(_), content="true")
  inspect(total.read_or_abort(), content="240")
}

///|
test "docs api-ref: compatibility helpers create_signal / hybrid_memo / memo_map" {
  let app : AppCtx = { rt: @incr.Runtime() }
  let signal = @incr.create_signal(
    app,
    10,
    durability=High,
    label="compat_signal",
  )
  let hybrid = @incr.create_hybrid_memo(
    app,
    () => signal.get() * 2,
    label="compat_hybrid",
  )
  let by_key = @incr.create_memo_map(
    app,
    (key : Int) => signal.get() + key,
    label="compat_by_key",
  )

  inspect(signal.get(), content="10")
  inspect(signal.durability(), content="High")
  match app.rt.cell_info(signal.id()) {
    Some(info) =>
      debug_inspect(
        info.label,
        content=(
          #|Some("compat_signal")
        ),
      )
    None => abort("expected signal cell_info")
  }

  let observer = hybrid.observe()
  inspect(observer.get(), content="20")
  inspect(by_key.get(5), content="15")
  signal.set(11)
  inspect(observer.get(), content="22")
  inspect(by_key.get(5), content="16")
  observer.dispose()
}

///|
test "docs api-ref: compatibility create_accumulator captures memo pushes" {
  let app : AppCtx = { rt: @incr.Runtime() }
  let diags : @incr.Accumulator[String] = @incr.create_accumulator(
    app,
    label="diags",
  )
  let width = @incr.create_signal(app, -1, label="width")
  let producer = @incr.create_memo(
    app,
    () => {
      if width.get() < 0 {
        diags.push("negative width")
      }
      width.get()
    },
    label="width_check",
  )
  let observer = producer.observe()

  inspect(observer.get(), content="-1")
  let first = producer.accumulated_peek(diags)
  inspect(first.length(), content="1")
  inspect(first[0], content="negative width")

  width.set(4)
  inspect(observer.get(), content="4")
  inspect(producer.accumulated_peek(diags).length(), content="0")
  observer.dispose()
}

///|
test "docs api-ref: compatibility create_tracked_cell / create_scope / add_tracked" {
  let app : AppCtx = { rt: @incr.Runtime() }
  let scope = @incr.create_scope(app)
  let tracked : CompatTrackedFields = {
    path: @incr.create_tracked_cell(
      app,
      "src/main.mbt",
      durability=High,
      label="Tracked.path",
    ),
    version: @incr.create_tracked_cell(app, 1, label="Tracked.version"),
  }

  inspect(tracked.path.get(), content="src/main.mbt")
  match app.rt.cell_info(tracked.path.id()) {
    Some(info) => {
      debug_inspect(
        info.label,
        content=(
          #|Some("Tracked.path")
        ),
      )
      inspect(info.durability, content="High")
    }
    None => abort("expected tracked path cell_info")
  }

  @incr.add_tracked(scope, tracked)
  scope.dispose()
  inspect(tracked.path.is_disposed(), content="true")
  inspect(tracked.version.is_disposed(), content="true")
}
```

## `Scope` constructors and `InputFieldOwner`

```mbt check
///|
struct SourceFile {
  path : @incr.InputField[String]
  version : @incr.InputField[Int]
}

///|
impl @incr.InputFieldOwner for SourceFile with fn cell_ids(self) {
  [self.path.id(), self.version.id()]
}

///|
test "docs api-ref: scope-owned target handles dispose together" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let count = scope.input(0, label="count")
  let path_field = scope.input_field("src/main.mbt", label="path")
  let doubled = scope.derived(() => count.get() * 2, label="doubled")
  let reachable = scope.reachable_derived(
    () => count.get() + 100,
    label="reachable",
  )
  let eager = scope.eager_derived(() => count.get() * 10)
  let by_id = scope.derived_map((id : Int) => count.get() + id)

  count.set(7)
  inspect(path_field.get(), content="src/main.mbt")
  inspect(doubled.read_or_abort(), content="14")
  inspect(reachable.read_or_abort(), content="107")
  inspect(eager.read(), content="70")
  inspect(by_id.read_or_abort(3), content="10")

  scope.dispose()
  inspect(scope.is_disposed(), content="true")
  inspect(path_field.is_disposed(), content="true")
}

///|
test "docs api-ref: scope.add_watch owns target watch lifetime" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let input = scope.input(20, label="input")
  let summary = scope.derived(() => input.get() * 2, label="summary")
  let watch = scope.add_watch(summary.watch())

  inspect(watch.read_or_abort(), content="40")
  rt.gc()
  input.set(21)
  inspect(watch.read_or_abort(), content="42")

  scope.dispose()
  inspect(watch.is_disposed(), content="true")
}

///|
test "docs api-ref: add_input_fields wires struct-owned input fields to a scope" {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let file : SourceFile = {
    path: @incr.InputField(rt, "src/main.mbt", label="SourceFile.path"),
    version: @incr.InputField(rt, 1, label="SourceFile.version"),
  }
  @incr.add_input_fields(scope, file)

  inspect(file.path.get(), content="src/main.mbt")
  inspect(file.version.get(), content="1")

  scope.dispose()
  inspect(file.path.is_disposed(), content="true")
  inspect(file.version.is_disposed(), content="true")
}
```

## `ReadError::Cycle` captured via strict `Derived::get` inside a compute

When a compute reads a derived value that is part of a cycle, `Derived::get`
returns `Err(ReadError::Cycle(_))` to the *inner* call site (the read channel
carries `ReadError = Cycle | Disposed`; `ReadError::path` / `format_path`
delegate to the underlying cycle). The compute closure is expected to react to
that (by returning a sentinel, raising `Failure`, or otherwise handling it) —
outer `read()` / `read_or_abort()` do not catch the cycle after the closure has
produced a value. See
[`cells/cycle_path_test.mbt`](../incr/cells/cycle_path_test.mbt) for the full set of
cycle shapes.

```mbt check
///|
test "docs api-ref: derived.get surfaces Err(ReadError::Cycle) inside compute" {
  let rt = @incr.Runtime()
  let self_ref : Ref[@incr.Derived[Int]?] = { val: None }
  let captured_formatted : Ref[String] = { val: "" }
  let captured_len : Ref[Int] = { val: 0 }

  let m = @incr.Derived(
    rt,
    () => {
      match self_ref.val {
        Some(d) =>
          match d.get() {
            Ok(v) => v + 1
            Err(err) => {
              captured_formatted.val = err.format_path()
              captured_len.val = err.path().length()
              -1
            }
          }
        None => 0
      }
    },
    label="self_cycle",
  )
  self_ref.val = Some(m)

  // Trigger the cycle and observe the captured error from inside the compute.
  let _ = m.read_or_abort()
  inspect(captured_len.val >= 1, content="true")
  inspect(captured_formatted.val.contains("Cycle"), content="true")
}
```
