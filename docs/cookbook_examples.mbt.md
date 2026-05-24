# Checked Cookbook Examples

Literate tests that pin high-value target facade snippets from
[`cookbook.md`](cookbook.md). These examples focus on behavior that prose-only
snippets can easily drift on: dynamic dependency changes, backdating with custom
`Eq`, field-level inputs, and scoped watch lifetimes.

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

  rt.set_on_change(() => { notifications.val = notifications.val + 1 })

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
