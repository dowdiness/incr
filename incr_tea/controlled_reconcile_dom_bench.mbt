///|
/// Browser benchmark for equal-view controlled-property reconciliation (#394).
///
/// The timed operation is a production `BrowserRenderer::flush_all` after an
/// unrelated model write. Tree construction, browser-property drift, and the
/// dispatch that schedules the flush are outside the timed window.
///

///|
#cfg(target="js")
extern "js" fn controlled_reconcile_bench_now_ms() -> Double =
  #| () => performance.now()

///|
#cfg(target="js")
extern "js" fn controlled_reconcile_bench_mutate(
  host : DomElement,
  drifted : Bool,
) -> Unit =
  #| (host, drifted) => {
  #|   for (const element of host.querySelectorAll('[data-controlled="true"]')) {
  #|     const kind = element.getAttribute("data-controlled-kind");
  #|     if (kind === "value") element.value = drifted ? "drifted" : "stable";
  #|     if (kind === "checked") element.checked = !drifted;
  #|     if (kind === "disabled") element.disabled = !drifted;
  #|     if (kind === "selected") element.selected = !drifted;
  #|   }
  #| }

///|
#cfg(target="js")
extern "js" fn controlled_reconcile_bench_state_matches(
  host : DomElement,
  drifted : Bool,
) -> Bool =
  #| (host, drifted) => {
  #|   const expectedBool = !drifted;
  #|   for (const element of host.querySelectorAll('[data-controlled="true"]')) {
  #|     const kind = element.getAttribute("data-controlled-kind");
  #|     if (kind === "value" && element.value !== (drifted ? "drifted" : "stable")) {
  #|       return false;
  #|     }
  #|     if (kind === "checked" && element.checked !== expectedBool) return false;
  #|     if (kind === "disabled" && element.disabled !== expectedBool) return false;
  #|     if (kind === "selected" && element.selected !== expectedBool) return false;
  #|   }
  #|   return true;
  #| }

///|
#cfg(target="js")
extern "js" fn controlled_reconcile_bench_install_api(
  run : (String, Int, Int, Int, Int) -> String,
) -> Unit =
  #| (run) => {
  #|   const toInt = (value, fallback) => {
  #|     const parsed = Number(value);
  #|     return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
  #|   };
  #|   globalThis.__incrTeaControlledReconcileBench = {
  #|     run(mode, n, controlled, iterations = 200, samples = 9) {
  #|       return JSON.parse(run(
  #|         String(mode),
  #|         toInt(n, 1000),
  #|         toInt(controlled, 16),
  #|         toInt(iterations, 200),
  #|         toInt(samples, 9),
  #|       ));
  #|     },
  #|   };
  #| }

///|
#cfg(target="js")
priv enum ControlledReconcileBenchMode {
  EqualNoDrift
  MismatchRepair
}

///|
#cfg(target="js")
fn ControlledReconcileBenchMode::name(
  self : ControlledReconcileBenchMode,
) -> String {
  match self {
    EqualNoDrift => "equal-no-drift"
    MismatchRepair => "mismatch-repair"
  }
}

///|
#cfg(target="js")
fn controlled_reconcile_bench_mode(
  mode : String,
) -> ControlledReconcileBenchMode {
  if mode == "mismatch-repair" {
    MismatchRepair
  } else {
    EqualNoDrift
  }
}

///|
#cfg(target="js")
fn controlled_reconcile_bench_attrs(index : Int) -> Array[Attribute] {
  let kind = match index % 4 {
    0 => "value"
    1 => "checked"
    2 => "disabled"
    _ => "selected"
  }
  let marker = attr("data-controlled", "true")
  let kind_marker = attr("data-controlled-kind", kind)
  match index % 4 {
    0 => [attr("type", "text"), attr("value", "stable"), marker, kind_marker]
    1 =>
      [
        attr("type", "checkbox"),
        prop_bool_value("checked", true),
        marker,
        kind_marker,
      ]
    2 => [prop_bool_value("disabled", true), marker, kind_marker]
    _ => [prop_bool_value("selected", true), marker, kind_marker]
  }
}

///|
#cfg(target="js")
fn controlled_reconcile_bench_tree(
  node_count : Int,
  controlled_count : Int,
) -> Html[ControlledReconcileBenchMsg] {
  let children = Array::makei(node_count, index => {
    if index < controlled_count {
      match index % 4 {
        0 => node("input", attrs=controlled_reconcile_bench_attrs(index), [])
        1 => node("input", attrs=controlled_reconcile_bench_attrs(index), [])
        2 => button(attrs=controlled_reconcile_bench_attrs(index), "button")
        _ =>
          node("option", attrs=controlled_reconcile_bench_attrs(index), [
            text("option"),
          ])
      }
    } else {
      node("span", [text("leaf")])
    }
  })
  div(attrs=[attr("data-bench-root", "true")], children)
}

///|
#cfg(target="js")
priv enum ControlledReconcileBenchMsg {
  Touch(Int)
} derive(Eq)

///|
#cfg(target="js")
priv struct ControlledReconcileBenchHarness {
  renderer : BrowserRenderer[ControlledReconcileBenchMsg]
  program : Program[
    ControlledReconcileBenchMsg,
    Html[ControlledReconcileBenchMsg],
  ]
  host : DomElement
}

///|
#cfg(target="js")
fn ControlledReconcileBenchHarness::new(
  node_count : Int,
  controlled_count : Int,
) -> ControlledReconcileBenchHarness {
  let runtime = @incr.Runtime()
  let scope = @incr.Scope::new(runtime)
  let unrelated = scope.input_field(0, label="controlled-reconcile.unrelated")
  let view_html = controlled_reconcile_bench_tree(node_count, controlled_count)
  let update : (ControlledReconcileBenchMsg) -> Cmd[ControlledReconcileBenchMsg] = msg => {
    match msg {
      Touch(value) => {
        unrelated.set(value)
        Cmd::none()
      }
    }
  }
  let view : () -> Html[ControlledReconcileBenchMsg] raise Failure = () => {
    return view_html
  }
  let program = Program::Program(
    runtime,
    scope,
    update,
    view,
    label="controlled-reconcile.view",
  )
  let host = dom_bench_create_host()
  let renderer : BrowserRenderer[ControlledReconcileBenchMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  ignore(renderer.mount(host, program))
  { renderer, program, host }
}

///|
#cfg(target="js")
fn ControlledReconcileBenchHarness::measure_sample(
  self : ControlledReconcileBenchHarness,
  mode : ControlledReconcileBenchMode,
  iterations : Int,
) -> Double {
  let total = for index in 0..<iterations; total = 0.0 {
    ignore(self.program.dispatch(Touch(index)))
    match mode {
      EqualNoDrift => ()
      MismatchRepair => {
        controlled_reconcile_bench_mutate(self.host, true)
        if index == 0 {
          if !controlled_reconcile_bench_state_matches(self.host, true) {
            abort("controlled reconciliation benchmark failed to create drift")
          }
        }
      }
    }
    let started = controlled_reconcile_bench_now_ms()
    self.renderer.flush_all()
    let elapsed = controlled_reconcile_bench_now_ms() - started
    match mode {
      EqualNoDrift => ()
      MismatchRepair =>
        if index == 0 &&
          !controlled_reconcile_bench_state_matches(self.host, false) {
          abort("controlled reconciliation benchmark failed to repair drift")
        }
    }
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
#cfg(target="js")
fn ControlledReconcileBenchHarness::dispose(
  self : ControlledReconcileBenchHarness,
) -> Unit {
  self.renderer.dispose()
  dom_bench_remove_host(self.host)
}

///|
#cfg(target="js")
fn controlled_reconcile_bench_positive(value : Int, fallback : Int) -> Int {
  guard value > 0 else { fallback }
  value
}

///|
#cfg(target="js")
fn controlled_reconcile_bench_result_json(
  mode : ControlledReconcileBenchMode,
  node_count : Int,
  controlled_count : Int,
  iterations : Int,
  samples : Array[Double],
) -> String {
  let sample_json = samples.map(sample => "\{sample * 1000.0}").join(",")
  let json =
    $|{"mode":"\{mode.name()}","nodes":\{node_count},"controlled":\{controlled_count},"iterations":\{iterations},"unit":"us","samples":[\{sample_json}]}
  json
}

///|
#cfg(target="js")
fn controlled_reconcile_bench_run(
  mode : String,
  node_count : Int,
  controlled_count : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let benchmark_mode = controlled_reconcile_bench_mode(mode)
  let nodes = node_count.max(0)
  let controlled = controlled_count.max(0).min(nodes)
  let iteration_count = controlled_reconcile_bench_positive(iterations, 200)
  let samples_len = controlled_reconcile_bench_positive(sample_count, 9)
  let harness = ControlledReconcileBenchHarness::new(nodes, controlled)
  for _ in 0..<5 {
    ignore(harness.measure_sample(benchmark_mode, 1))
  }
  let samples = [
    for _ in 0..<samples_len => {
      harness.measure_sample(benchmark_mode, iteration_count)
    }
  ]
  harness.dispose()
  controlled_reconcile_bench_result_json(
    benchmark_mode, nodes, controlled, iteration_count, samples,
  )
}

///|
/// Installs `window.__incrTeaControlledReconcileBench.run(...)` for the
/// Playwright equal-view reconciliation benchmark.
#cfg(target="js")
pub fn install_controlled_reconcile_bench_api() -> Unit {
  controlled_reconcile_bench_install_api(controlled_reconcile_bench_run)
}
