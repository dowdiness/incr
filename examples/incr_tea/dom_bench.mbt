///|
#cfg(target="js")
priv enum DomBenchPatchMode {
  KeyedDomPatch
  RebuildDomPatch
}

///|
#cfg(target="js")
priv enum DomBenchOperation {
  DomBenchPrepend
  DomBenchRemoveFirst
  DomBenchReverse
}

///|
#cfg(target="js")
extern "js" fn dom_bench_now_ms() -> Double =
  #| () => performance.now()

///|
#cfg(target="js")
extern "js" fn dom_bench_create_host() -> DomElement =
  #| () => {
  #|   const host = document.createElement("div");
  #|   host.className = "incr-tea-dom-bench-host";
  #|   host.style.cssText = [
  #|     "position:absolute",
  #|     "left:-10000px",
  #|     "top:0",
  #|     "width:960px",
  #|     "contain:content",
  #|     "visibility:hidden",
  #|   ].join(";");
  #|   document.body.appendChild(host);
  #|   return host;
  #| }

///|
#cfg(target="js")
extern "js" fn dom_bench_remove_host(host : DomElement) -> Unit =
  #| (host) => { host.remove(); }

///|
#cfg(target="js")
extern "js" fn dom_bench_install_api(
  run : (String, String, Int, Int, Int) -> String,
) -> Unit =
  #| (run) => {
  #|   const toInt = (value, fallback) => {
  #|     const parsed = Number(value);
  #|     return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
  #|   };
  #|   globalThis.__incrTeaDomBench = {
  #|     run(mode, operation, n, iterations = 200, samples = 9) {
  #|       return JSON.parse(run(
  #|         String(mode),
  #|         String(operation),
  #|         toInt(n, 64),
  #|         toInt(iterations, 200),
  #|         toInt(samples, 9),
  #|       ));
  #|     },
  #|   };
  #| }

///|
#cfg(target="js")
priv struct DomBenchRoot[Msg] {
  program : Program[Msg, Html[Msg]]
  host : DomElement
  stats : RenderStats
  patch_mode : DomBenchPatchMode
  mut last_view : Html[Msg]?
  mut rendered : Rendered[Msg]?
}

///|
#cfg(target="js")
fn[Msg] DomBenchRoot::DomBenchRoot(
  program : Program[Msg, Html[Msg]],
  host : DomElement,
  patch_mode : DomBenchPatchMode,
) -> DomBenchRoot[Msg] {
  {
    program,
    host,
    stats: RenderStats::RenderStats(),
    patch_mode,
    last_view: None,
    rendered: None,
  }
}

///|
#cfg(target="js")
fn[Msg : Eq] DomBenchRoot::flush(self : DomBenchRoot[Msg]) -> Unit {
  let next = self.program.read_view_or_abort()
  match self.last_view {
    Some(prev) if prev == next =>
      self.stats.skipped_patches = self.stats.skipped_patches + 1
    _ => {
      self.stats.patch_attempts = self.stats.patch_attempts + 1
      self.last_view = Some(next)
      let sink : EventSink[Msg] = {
        dispatch: msg => ignore(self.program.dispatch(msg)),
        payload_resolvers: PayloadResolvers::PayloadResolvers(),
      }
      let rendered = match self.rendered {
        None => {
          let initial = render_html(next, sink)
          dom_replace_children(self.host, initial.node())
          initial
        }
        Some(old) =>
          match self.patch_mode {
            KeyedDomPatch => diff_rendered(old, next, self.host, sink)
            RebuildDomPatch => replace_rendered(old, next, self.host, sink)
          }
      }
      self.rendered = Some(rendered)
    }
  }
}

///|
#cfg(target="js")
priv struct DomListBenchHarness {
  runtime : @incr.Runtime
  items : @incr.InputField[Array[(String, String)]]
  baseline : Array[(String, String)]
  root : DomBenchRoot[Unit]
}

///|
#cfg(target="js")
fn dom_bench_make_items(n : Int) -> Array[(String, String)] {
  [
    for i in 0..<n => ("item-\{i}", "Item \{i}")
  ]
}

///|
#cfg(target="js")
fn[Msg] dom_bench_row(id : String, label : String) -> Html[Msg] {
  li(attrs=[class_attr("list-item")], [
    span(attrs=[class_attr("list-label")], [text("\{label} (\{id})")]),
    input(
      attrs=[
        class_attr("list-note"),
        attr("placeholder", "notes — survive reorder"),
      ],
      events=[on_input(tag="bench.note")],
    ),
  ])
}

///|
#cfg(target="js")
fn[Msg] dom_bench_keyed_list(items : Array[(String, String)]) -> Html[Msg] {
  let children = items.map(pair => {
    let (id, label) = pair
    (id, dom_bench_row(id, label))
  })
  keyed_ul(attrs=[class_attr("keyed-list")], children)
}

///|
#cfg(target="js")
fn[Msg] dom_bench_positional_list(items : Array[(String, String)]) -> Html[Msg] {
  ul(
    attrs=[class_attr("keyed-list")],
    items.map(pair => {
      let (id, label) = pair
      dom_bench_row(id, label)
    }),
  )
}

///|
#cfg(target="js")
fn DomListBenchHarness::DomListBenchHarness(
  host : DomElement,
  n : Int,
  patch_mode : DomBenchPatchMode,
) -> DomListBenchHarness {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let baseline = dom_bench_make_items(n)
  let items = scope.input_field(baseline, label="dom_bench.items")
  let update : (Unit) -> Cmd[Unit] = _ => Cmd::none()
  let view : () -> Html[Unit] raise Failure = () => {
    match patch_mode {
      KeyedDomPatch => dom_bench_keyed_list(items.get())
      RebuildDomPatch => dom_bench_positional_list(items.get())
    }
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="dom_bench.view",
  )
  let root = DomBenchRoot(program, host, patch_mode)
  root.flush()
  { runtime, items, baseline, root }
}

///|
#cfg(target="js")
fn DomListBenchHarness::set_items(
  self : DomListBenchHarness,
  next : Array[(String, String)],
) -> Unit {
  self.runtime.batch(() => self.items.set(next))
  self.root.flush()
}

///|
#cfg(target="js")
fn DomListBenchHarness::reset(self : DomListBenchHarness) -> Unit {
  self.set_items(self.baseline)
}

///|
#cfg(target="js")
fn DomListBenchHarness::next_items(
  self : DomListBenchHarness,
  operation : DomBenchOperation,
) -> Array[(String, String)] {
  match operation {
    DomBenchPrepend => [("item-new", "Prepended"), ..self.baseline]
    DomBenchRemoveFirst =>
      match self.baseline {
        [_, .. rest] => rest.to_owned()
        [] => []
      }
    DomBenchReverse => self.baseline.rev()
  }
}

///|
#cfg(target="js")
fn DomListBenchHarness::measure_operation(
  self : DomListBenchHarness,
  operation : DomBenchOperation,
  iterations : Int,
) -> Double {
  let total = for _ in 0..<iterations; total = 0.0 {
    let next = self.next_items(operation)
    let started = dom_bench_now_ms()
    self.set_items(next)
    let elapsed = dom_bench_now_ms() - started
    self.reset()
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
#cfg(target="js")
fn dom_bench_patch_mode(mode : String) -> DomBenchPatchMode {
  match mode {
    "keyed" => KeyedDomPatch
    "rebuild" | "positional" | "non-keyed" => RebuildDomPatch
    _ => abort("unknown DOM bench mode: \{mode}")
  }
}

///|
#cfg(target="js")
fn DomBenchPatchMode::name(self : DomBenchPatchMode) -> String {
  match self {
    KeyedDomPatch => "keyed"
    RebuildDomPatch => "rebuild"
  }
}

///|
#cfg(target="js")
fn dom_bench_operation(operation : String) -> DomBenchOperation {
  match operation {
    "prepend" => DomBenchPrepend
    "remove-first" | "remove_first" => DomBenchRemoveFirst
    "reverse" => DomBenchReverse
    _ => abort("unknown DOM bench operation: \{operation}")
  }
}

///|
#cfg(target="js")
fn DomBenchOperation::name(self : DomBenchOperation) -> String {
  match self {
    DomBenchPrepend => "prepend"
    DomBenchRemoveFirst => "remove-first"
    DomBenchReverse => "reverse"
  }
}

///|
#cfg(target="js")
fn dom_bench_positive(value : Int, fallback : Int) -> Int {
  guard value > 0 else { fallback }
  value
}

///|
#cfg(target="js")
fn dom_bench_result_json(
  mode : DomBenchPatchMode,
  operation : DomBenchOperation,
  n : Int,
  iterations : Int,
  samples : Array[Double],
) -> String {
  let sample_json = samples.map(sample => "\{sample * 1000.0}").join(",")
  let json =
    $|{"mode":"\{mode.name()}","operation":"\{operation.name()}","n":\{n},"iterations":\{iterations},"unit":"us","samples":[\{sample_json}]}
  json
}

///|
#cfg(target="js")
fn dom_bench_run(
  mode : String,
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let patch_mode = dom_bench_patch_mode(mode)
  let op = dom_bench_operation(operation)
  let size = dom_bench_positive(n, 64)
  let iteration_count = dom_bench_positive(iterations, 200)
  let samples_len = dom_bench_positive(sample_count, 9)
  let host = dom_bench_create_host()
  let harness = DomListBenchHarness(host, size, patch_mode)
  for _ in 0..<5 {
    ignore(harness.measure_operation(op, 1))
  }
  let samples = [
    for _ in 0..<samples_len => harness.measure_operation(op, iteration_count)
  ]
  dom_bench_remove_host(host)
  dom_bench_result_json(patch_mode, op, size, iteration_count, samples)
}

///|
/// Installs `window.__incrTeaDomBench.run(...)` for the Playwright DOM applier
/// benchmark page.
#cfg(target="js")
pub fn install_dom_bench_api() -> Unit {
  dom_bench_install_api(dom_bench_run)
}
