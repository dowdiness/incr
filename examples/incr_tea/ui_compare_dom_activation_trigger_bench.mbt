///|
/// Measurement-only activation-trigger probe for inactive workspace roots.

///|
#cfg(target="js")
const UI_COMPARE_ACTIVATION_TRIGGER_WORKSPACE_SIZE : Int = 256

///|
#cfg(target="js")
priv enum UiCompareActivationTriggerOwnership {
  UiCompareActivationTriggerSharedProgram
  UiCompareActivationTriggerIndependentPrograms
}

///|
#cfg(target="js")
fn ui_compare_activation_trigger_ownership(
  ownership : String,
) -> UiCompareActivationTriggerOwnership {
  match ownership.replace_all(old="_", new="-") {
    "shared" | "shared-program" => UiCompareActivationTriggerSharedProgram
    "independent" | "independent-programs" =>
      UiCompareActivationTriggerIndependentPrograms
    _ => abort("unknown activation-trigger ownership: \{ownership}")
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerOwnership::name(
  self : UiCompareActivationTriggerOwnership,
) -> String {
  match self {
    UiCompareActivationTriggerSharedProgram => "shared"
    UiCompareActivationTriggerIndependentPrograms => "independent"
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerOwnership::mount_roots(
  self : UiCompareActivationTriggerOwnership,
  renderer : BrowserRenderer[UiCompareWorkspaceMsg],
  runtime : @incr.Runtime,
  root_count : Int,
) -> Array[(DomElement, BrowserRoot[UiCompareWorkspaceMsg])] {
  match self {
    UiCompareActivationTriggerSharedProgram => {
      let program = ui_compare_incr_workspace_program(
        runtime,
        UI_COMPARE_ACTIVATION_TRIGGER_WORKSPACE_SIZE,
      )
      Array::makei(root_count, _ => {
        let host = dom_bench_create_host()
        let root = renderer.mount(host, program)
        (host, root)
      })
    }
    UiCompareActivationTriggerIndependentPrograms =>
      Array::makei(root_count, _ => {
        let host = dom_bench_create_host()
        let program = ui_compare_incr_workspace_program(
          runtime,
          UI_COMPARE_ACTIVATION_TRIGGER_WORKSPACE_SIZE,
        )
        let root = renderer.mount(host, program)
        (host, root)
      })
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerOwnership::click_action(
  self : UiCompareActivationTriggerOwnership,
  roots : Array[(DomElement, BrowserRoot[UiCompareWorkspaceMsg])],
  action : String,
) -> Unit {
  match self {
    UiCompareActivationTriggerSharedProgram =>
      ui_compare_dom_click_action(roots[0].0, action)
    UiCompareActivationTriggerIndependentPrograms =>
      for pair in roots {
        ui_compare_dom_click_action(pair.0, action)
      }
  }
}

///|
#cfg(target="js")
priv struct UiCompareActivationTriggerBenchHarness {
  renderer : BrowserRenderer[UiCompareWorkspaceMsg]
  controller : BrowserRootActivationController[UiCompareWorkspaceMsg]
  roots : Array[(DomElement, BrowserRoot[UiCompareWorkspaceMsg])]
  ownership : UiCompareActivationTriggerOwnership
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::UiCompareActivationTriggerBenchHarness(
  root_count : Int,
  ownership : UiCompareActivationTriggerOwnership,
) -> UiCompareActivationTriggerBenchHarness {
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
  let controller = BrowserRootActivationController(renderer)
  let roots = ownership.mount_roots(renderer, runtime, root_count)
  ownership.click_action(roots, "set-hidden-mounted")
  for pair in roots {
    pair.1.flush()
  }
  { renderer, controller, roots, ownership }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::reset_hidden_active(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  for pair in self.roots {
    self.renderer.activate(pair.1)
  }
  self.ownership.click_action(self.roots, "set-hidden-mounted")
  for pair in self.roots {
    pair.1.flush()
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::deactivate_all(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  for pair in self.roots {
    self.controller.hide(pair.1)
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::inactive_updates(
  self : UiCompareActivationTriggerBenchHarness,
  update_count : Int,
) -> Unit {
  for _ in 0..<update_count {
    self.ownership.click_action(self.roots, "hidden-mounted-update")
    for pair in self.roots {
      pair.1.flush_if_active()
    }
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::activate_one(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  self.renderer.activate(self.roots[0].1)
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::activate_all(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  for pair in self.roots {
    self.renderer.activate(pair.1)
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::show_one(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  self.controller.show(self.roots[0].1)
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::show_all(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  for pair in self.roots {
    self.controller.show(pair.1)
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::prewarm_one(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  self.controller.prewarm(self.roots[0].1)
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::prewarm_all(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  for pair in self.roots {
    self.controller.prewarm(pair.1)
  }
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::stats_json(
  self : UiCompareActivationTriggerBenchHarness,
) -> String {
  let stats = self.renderer.stats()
  (
    $|{"activationFlushes":\{stats.activation_flushes()},"inactiveSkippedFlushes":\{stats.inactive_skipped_flushes()},"frameFlushes":\{stats.frame_flushes()},"patchAttempts":\{stats.patch_attempts()}}
  )
}

///|
#cfg(target="js")
fn UiCompareActivationTriggerBenchHarness::dispose(
  self : UiCompareActivationTriggerBenchHarness,
) -> Unit {
  self.renderer.dispose()
  for pair in self.roots {
    dom_bench_remove_host(pair.0)
  }
}

///|
#cfg(target="js")
extern "js" fn dom_activation_trigger_install_api(
  setup : (Int, String) -> String,
  reset : () -> Unit,
  deactivate_all : () -> Unit,
  inactive_updates : (Int) -> Unit,
  activate_one : () -> Unit,
  activate_all : () -> Unit,
  show_one : () -> Unit,
  show_all : () -> Unit,
  prewarm_one : () -> Unit,
  prewarm_all : () -> Unit,
  host_count : () -> Int,
  host : (Int) -> DomElement,
  stats : () -> String,
  dispose : () -> Unit,
  observe : (Int, () -> Unit) -> Int,
  disconnect : (Int) -> Unit,
) -> Unit =
  #| (setup, reset, deactivateAll, inactiveUpdates, activateOne, activateAll, showOne, showAll, prewarmOne, prewarmAll, hostCount, host, stats, dispose, observe, disconnect) => {
  #|   const toInt = (value, fallback) => {
  #|     const parsed = Number(value);
  #|     return Number.isFinite(parsed) ? Math.trunc(parsed) : fallback;
  #|   };
  #|   const api = globalThis.__incrTeaActivationTriggerBench ?? {};
  #|   api.setup = (rootCount = 1, ownership = "shared") => JSON.parse(setup(toInt(rootCount, 1), String(ownership)));
  #|   api.reset = () => reset();
  #|   api.deactivateAll = () => deactivateAll();
  #|   api.inactiveUpdates = (count = 1) => inactiveUpdates(toInt(count, 1));
  #|   api.activateOne = () => activateOne();
  #|   api.activateAll = () => activateAll();
  #|   api.showOne = () => showOne();
  #|   api.showAll = () => showAll();
  #|   api.prewarmOne = () => prewarmOne();
  #|   api.prewarmAll = () => prewarmAll();
  #|   api.hostCount = () => hostCount();
  #|   api.host = index => host(toInt(index, 0));
  #|   api.stats = () => JSON.parse(stats());
  #|   api.dispose = () => dispose();
  #|   api.observe = (index, callback) => observe(toInt(index, 0), callback);
  #|   api.disconnect = handle => disconnect(toInt(handle, 0));
  #|   globalThis.__incrTeaActivationTriggerBench = api;
  #| }

///|
#cfg(target="js")
fn ui_compare_activation_current(
  harness : Ref[UiCompareActivationTriggerBenchHarness?],
) -> UiCompareActivationTriggerBenchHarness {
  match harness.val {
    Some(current) => current
    None => abort("activation-trigger bench harness is not set up")
  }
}

///|
#cfg(target="js")
fn ui_compare_incr_run_activation_trigger(
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  abort(
    "activation-trigger-overhead is measured through window.__incrTeaActivationTriggerBench, not the generic UI compare bench API; requested operation=\{operation}, n=\{n}, iterations=\{iterations}, sample_count=\{sample_count}",
  )
}

///|
/// Installs `window.__incrTeaActivationTriggerBench` for the Playwright probe.
#cfg(target="js")
pub fn install_activation_trigger_bench_api() -> Unit {
  let harness : Ref[UiCompareActivationTriggerBenchHarness?] = Ref(None)
  dom_activation_trigger_install_api(
    (root_count, ownership_name) => {
      match harness.val {
        Some(current) => current.dispose()
        None => ()
      }
      let ownership = ui_compare_activation_trigger_ownership(ownership_name)
      let current = UiCompareActivationTriggerBenchHarness(
        dom_bench_positive(root_count, 1),
        ownership,
      )
      harness.val = Some(current)
      let root_count = current.roots.length()
      let ownership = ownership.name()
      (
        $|{"rootCount":\{root_count},"ownership":"\{ownership}","workspaceSize":\{UI_COMPARE_ACTIVATION_TRIGGER_WORKSPACE_SIZE}}
      )
    },
    () => ui_compare_activation_current(harness).reset_hidden_active(),
    () => ui_compare_activation_current(harness).deactivate_all(),
    count => {
      ui_compare_activation_current(harness).inactive_updates(
        dom_bench_positive(count, 1),
      )
    },
    () => ui_compare_activation_current(harness).activate_one(),
    () => ui_compare_activation_current(harness).activate_all(),
    () => ui_compare_activation_current(harness).show_one(),
    () => ui_compare_activation_current(harness).show_all(),
    () => ui_compare_activation_current(harness).prewarm_one(),
    () => ui_compare_activation_current(harness).prewarm_all(),
    () => ui_compare_activation_current(harness).roots.length(),
    index => ui_compare_activation_current(harness).roots[index].0,
    () => ui_compare_activation_current(harness).stats_json(),
    () => {
      match harness.val {
        Some(current) => {
          current.dispose()
          harness.val = None
        }
        None => ()
      }
    },
    (index, callback) => {
      dom_create_intersection_observer(
        ui_compare_activation_current(harness).roots[index].0,
        callback,
      )
    },
    handle => dom_disconnect_intersection_observer(handle),
  )
}
