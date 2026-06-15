///|
/// Multi-root inactive workspace cohort benchmark. The ordinary inactive-root
/// bench varies subtree size; this one fixes each subtree at N=256 and varies
/// how many inactive DOM roots share one workspace `Program`.

///|
#cfg(target="js")
const UI_COMPARE_INACTIVE_COHORT_WORKSPACE_SIZE : Int = 256

///|
#cfg(target="js")
priv enum UiCompareInactiveWorkspaceCohortActivationMode {
  UiCompareInactiveWorkspaceCohortActivateOne
  UiCompareInactiveWorkspaceCohortActivateAll
}

///|
#cfg(target="js")
fn UiCompareInactiveWorkspaceCohortActivationMode::name(
  self : UiCompareInactiveWorkspaceCohortActivationMode,
) -> String {
  match self {
    UiCompareInactiveWorkspaceCohortActivateOne => "activate-one"
    UiCompareInactiveWorkspaceCohortActivateAll => "activate-all"
  }
}

///|
#cfg(target="js")
priv enum UiCompareInactiveWorkspaceCohortTiming {
  UiCompareInactiveWorkspaceCohortTotal
  UiCompareInactiveWorkspaceCohortActivationOnly
}

///|
#cfg(target="js")
fn UiCompareInactiveWorkspaceCohortTiming::name(
  self : UiCompareInactiveWorkspaceCohortTiming,
) -> String {
  match self {
    UiCompareInactiveWorkspaceCohortTotal => "total"
    UiCompareInactiveWorkspaceCohortActivationOnly => "activation"
  }
}

///|
#cfg(target="js")
fn UiCompareInactiveWorkspaceCohortTiming::is_activation_only(
  self : UiCompareInactiveWorkspaceCohortTiming,
) -> Bool {
  match self {
    UiCompareInactiveWorkspaceCohortTotal => false
    UiCompareInactiveWorkspaceCohortActivationOnly => true
  }
}

///|
#cfg(target="js")
priv struct UiCompareInactiveWorkspaceCohortOperation {
  update_count : Int
  activation : UiCompareInactiveWorkspaceCohortActivationMode
  timing : UiCompareInactiveWorkspaceCohortTiming
}

///|
#cfg(target="js")
fn UiCompareInactiveWorkspaceCohortOperation::UiCompareInactiveWorkspaceCohortOperation(
  update_count : Int,
  activation : UiCompareInactiveWorkspaceCohortActivationMode,
  timing : UiCompareInactiveWorkspaceCohortTiming,
) -> UiCompareInactiveWorkspaceCohortOperation {
  { update_count, activation, timing }
}

///|
#cfg(target="js")
fn ui_compare_inactive_workspace_cohort_operation_tail(
  update_count : Int,
  tail : StringView,
) -> UiCompareInactiveWorkspaceCohortOperation {
  match tail {
    "activate-one-total" =>
      UiCompareInactiveWorkspaceCohortOperation(
        update_count,
        UiCompareInactiveWorkspaceCohortActivateOne,
        UiCompareInactiveWorkspaceCohortTotal,
      )
    "activate-one-activation" =>
      UiCompareInactiveWorkspaceCohortOperation(
        update_count,
        UiCompareInactiveWorkspaceCohortActivateOne,
        UiCompareInactiveWorkspaceCohortActivationOnly,
      )
    "activate-all-total" =>
      UiCompareInactiveWorkspaceCohortOperation(
        update_count,
        UiCompareInactiveWorkspaceCohortActivateAll,
        UiCompareInactiveWorkspaceCohortTotal,
      )
    "activate-all-activation" =>
      UiCompareInactiveWorkspaceCohortOperation(
        update_count,
        UiCompareInactiveWorkspaceCohortActivateAll,
        UiCompareInactiveWorkspaceCohortActivationOnly,
      )
    _ => abort("unknown inactive workspace cohort operation suffix: \{tail}")
  }
}

///|
#cfg(target="js")
fn ui_compare_inactive_workspace_cohort_operation(
  operation : String,
) -> UiCompareInactiveWorkspaceCohortOperation {
  let normalized = operation.replace_all(old="_", new="-")
  match normalized {
    [.. "inactive-10-updates-", .. tail] =>
      ui_compare_inactive_workspace_cohort_operation_tail(10, tail)
    [.. "inactive-100-updates-", .. tail] =>
      ui_compare_inactive_workspace_cohort_operation_tail(100, tail)
    [.. "inactive-1000-updates-", .. tail] =>
      ui_compare_inactive_workspace_cohort_operation_tail(1000, tail)
    _ => abort("unknown inactive workspace cohort operation: \{operation}")
  }
}

///|
#cfg(target="js")
fn UiCompareInactiveWorkspaceCohortOperation::is_activation_only(
  self : UiCompareInactiveWorkspaceCohortOperation,
) -> Bool {
  self.timing.is_activation_only()
}

///|
#cfg(target="js")
fn UiCompareInactiveWorkspaceCohortOperation::name(
  self : UiCompareInactiveWorkspaceCohortOperation,
) -> String {
  let update_count = self.update_count
  let activation = self.activation.name()
  let timing = self.timing.name()
  "inactive-\{update_count}-updates-\{activation}-\{timing}"
}

///|
#cfg(target="js")
priv struct UiCompareIncrInactiveWorkspaceCohortHarness {
  renderer : BrowserRenderer[UiCompareWorkspaceMsg]
  roots : Array[(DomElement, BrowserRoot[UiCompareWorkspaceMsg])]
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceCohortHarness::UiCompareIncrInactiveWorkspaceCohortHarness(
  root_count : Int,
) -> UiCompareIncrInactiveWorkspaceCohortHarness {
  let runtime = @incr.Runtime()
  let renderer : BrowserRenderer[UiCompareWorkspaceMsg] = BrowserRenderer::BrowserRenderer(
    runtime,
  )
  match renderer.on_change_listener_id {
    Some(id) => {
      runtime.remove_on_change_listener(id)
      renderer.on_change_listener_id = None
    }
    None => ()
  }
  let program = ui_compare_incr_workspace_program(
    runtime,
    UI_COMPARE_INACTIVE_COHORT_WORKSPACE_SIZE,
  )
  let roots = Array::makei(root_count, _ => {
    let host = dom_bench_create_host()
    let root = renderer.mount(host, program)
    (host, root)
  })
  ui_compare_dom_click_action(roots[0].0, "set-hidden-mounted")
  for pair in roots {
    pair.1.flush()
  }
  { renderer, roots }
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceCohortHarness::reset_hidden_active(
  self : UiCompareIncrInactiveWorkspaceCohortHarness,
) -> Unit {
  for pair in self.roots {
    self.renderer.activate(pair.1)
  }
  ui_compare_dom_click_action(self.roots[0].0, "set-hidden-mounted")
  for pair in self.roots {
    pair.1.flush()
  }
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceCohortHarness::deactivate_all(
  self : UiCompareIncrInactiveWorkspaceCohortHarness,
) -> Unit {
  for pair in self.roots {
    self.renderer.deactivate(pair.1)
  }
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceCohortHarness::inactive_updates(
  self : UiCompareIncrInactiveWorkspaceCohortHarness,
  update_count : Int,
) -> Unit {
  let host = self.roots[0].0
  for _ in 0..<update_count {
    ui_compare_dom_click_action(host, "hidden-mounted-update")
    for pair in self.roots {
      pair.1.flush_if_active()
    }
  }
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceCohortHarness::activate(
  self : UiCompareIncrInactiveWorkspaceCohortHarness,
  activation : UiCompareInactiveWorkspaceCohortActivationMode,
) -> Unit {
  match activation {
    UiCompareInactiveWorkspaceCohortActivateOne =>
      self.renderer.activate(self.roots[0].1)
    UiCompareInactiveWorkspaceCohortActivateAll =>
      for pair in self.roots {
        self.renderer.activate(pair.1)
      }
  }
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceCohortHarness::measure_operation(
  self : UiCompareIncrInactiveWorkspaceCohortHarness,
  operation : UiCompareInactiveWorkspaceCohortOperation,
  iterations : Int,
) -> Double {
  let total = for _ in 0..<iterations; total = 0.0 {
    let activation_only = operation.is_activation_only()
    self.reset_hidden_active()
    self.deactivate_all()
    if activation_only {
      self.inactive_updates(operation.update_count)
    }
    let started = dom_bench_now_ms()
    if !activation_only {
      self.inactive_updates(operation.update_count)
    }
    self.activate(operation.activation)
    let elapsed = dom_bench_now_ms() - started
    continue total + elapsed
  } nobreak {
    total
  }
  total / iterations.to_double()
}

///|
#cfg(target="js")
fn UiCompareIncrInactiveWorkspaceCohortHarness::dispose(
  self : UiCompareIncrInactiveWorkspaceCohortHarness,
) -> Unit {
  self.renderer.dispose()
  for pair in self.roots {
    dom_bench_remove_host(pair.0)
  }
}

///|
#cfg(target="js")
fn ui_compare_incr_run_inactive_workspace_cohort(
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  let op = ui_compare_inactive_workspace_cohort_operation(operation)
  let root_count = dom_bench_positive(n, 4)
  let iteration_count = dom_bench_positive(iterations, 200)
  let samples_len = dom_bench_positive(sample_count, 9)
  let harness = UiCompareIncrInactiveWorkspaceCohortHarness(root_count)
  for _ in 0..<5 {
    ignore(harness.measure_operation(op, 1))
  }
  let samples = [
    for _ in 0..<samples_len => harness.measure_operation(op, iteration_count)
  ]
  harness.dispose()
  ui_compare_result_json(
    "incr_tea",
    "workspace-inactive-root-cohort",
    op.name(),
    root_count,
    iteration_count,
    samples,
  )
}
