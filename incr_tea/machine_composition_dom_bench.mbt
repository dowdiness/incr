///|
#cfg(target="js")
priv struct MachineTiming {
  mut started_ms : Double
  mut transition_ms : Double
  mut transition_calls : Int
  mut view_ms : Double
  mut view_calls : Int
}

///|
#cfg(target="js")
fn MachineTiming::MachineTiming() -> MachineTiming {
  {
    started_ms: 0.0,
    transition_ms: 0.0,
    transition_calls: 0,
    view_ms: 0.0,
    view_calls: 0,
  }
}

///|
#cfg(target="js")
fn MachineTiming::reset(self : MachineTiming) -> Unit {
  self.started_ms = 0.0
  self.transition_ms = 0.0
  self.transition_calls = 0
  self.view_ms = 0.0
  self.view_calls = 0
}

///|
#cfg(target="js")
fn MachineTiming::hooks(self : MachineTiming) -> MachineProgramHooks {
  {
    before_transition: () => self.started_ms = dom_bench_now_ms(),
    after_transition: () => {
      self.transition_ms = self.transition_ms +
        (dom_bench_now_ms() - self.started_ms)
      self.transition_calls = self.transition_calls + 1
    },
    before_view: () => self.started_ms = dom_bench_now_ms(),
    after_view: () => {
      self.view_ms = self.view_ms + (dom_bench_now_ms() - self.started_ms)
      self.view_calls = self.view_calls + 1
    },
  }
}

///|
#cfg(target="js")
#external
priv type MachineMutationProbe

///|
#cfg(target="js")
extern "js" fn machine_mutation_probe(
  host : DomElement,
) -> MachineMutationProbe =
  #| (host) => {
  #|   const probe = {
  #|     host,
  #|     propertyEvents: [],
  #|     observer: null,
  #|   };
  #|   probe.observer = new MutationObserver(() => {});
  #|   probe.observer.observe(host, {
  #|     subtree: true,
  #|     childList: true,
  #|     attributes: true,
  #|     characterData: true,
  #|   });
  #|   return probe;
  #| }

///|
#cfg(target="js")
extern "js" fn machine_mutation_reset(probe : MachineMutationProbe) -> Unit =
  #| (probe) => {
  #|   probe.observer.takeRecords();
  #|   probe.propertyEvents = [];
  #| }

///|
#cfg(target="js")
extern "js" fn machine_mutation_record_property(
  probe : MachineMutationProbe,
  element : DomElement,
  property : String,
) -> Unit =
  #| (probe, element, property) => {
  #|   probe.propertyEvents.push({ element, property });
  #| }

///|
#cfg(target="js")
fn machine_mutation_begin(probe : MachineMutationProbe) -> Unit {
  machine_mutation_reset(probe)
  dom_set_property_mutation_observer(
    Some((element, property) => {
      machine_mutation_record_property(probe, element, property)
    }),
  )
}

///|
#cfg(target="js")
extern "js" fn machine_mutation_finish(
  probe : MachineMutationProbe,
  iteration : Int,
  child_count : Int,
  transition_ms : Double,
  view_ms : Double,
  patch_ms : Double,
  flush_total_ms : Double,
  transition_calls : Int,
  view_calls : Int,
  patch_calls : Int,
) -> String =
  #| (probe, iteration, childCount, transitionMs, viewMs, patchMs, flushTotalMs, transitionCalls, viewCalls, patchCalls) => {
  #|   const records = probe.observer.takeRecords();
  #|   const targetName = node => {
  #|     const element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
  #|     const row = element?.closest?.(".machine-row[data-semantic-id]");
  #|     if (row) return String(row.dataset.semanticId);
  #|     if (element?.closest?.("[data-machine-inspector]")) return "inspector";
  #|     return "other";
  #|   };
  #|   const rowsIn = nodes => {
  #|     const rows = [];
  #|     for (const node of nodes) {
  #|       if (node.nodeType !== Node.ELEMENT_NODE) continue;
  #|       if (node.matches?.(".machine-row[data-semantic-id]")) rows.push(node);
  #|       rows.push(...node.querySelectorAll?.(".machine-row[data-semantic-id]") ?? []);
  #|     }
  #|     return rows;
  #|   };
  #|   const added = new Set();
  #|   const removed = new Set();
  #|   const propertyMutations = {};
  #|   const addMutation = node => {
  #|     const key = targetName(node);
  #|     propertyMutations[key] = (propertyMutations[key] ?? 0) + 1;
  #|   };
  #|   for (const record of records) {
  #|     if (record.type === "childList") {
  #|       for (const row of rowsIn(record.addedNodes)) added.add(row);
  #|       for (const row of rowsIn(record.removedNodes)) removed.add(row);
  #|     } else {
  #|       addMutation(record.target);
  #|     }
  #|   }
  #|   for (const event of probe.propertyEvents) addMutation(event.element);
  #|   let moved = 0;
  #|   let created = 0;
  #|   let removedCount = 0;
  #|   for (const row of added) {
  #|     if (removed.has(row)) moved += 1;
  #|     else created += 1;
  #|   }
  #|   for (const row of removed) if (!added.has(row)) removedCount += 1;
  #|   return JSON.stringify({
  #|     iteration,
  #|     child_count: childCount,
  #|     transition_us: transitionMs * 1000,
  #|     view_us: viewMs * 1000,
  #|     dom_patch_us: patchMs * 1000,
  #|     flush_total_us: flushTotalMs * 1000,
  #|     created_nodes: created,
  #|     removed_nodes: removedCount,
  #|     moved_nodes: moved,
  #|     property_mutations_by_target: propertyMutations,
  #|     transition_calls: transitionCalls,
  #|     view_calls: viewCalls,
  #|     patch_calls: patchCalls,
  #|   });
  #| }

///|
#cfg(target="js")
extern "js" fn machine_dom_row(host : DomElement, id : Int) -> DomElement =
  #| (host, id) => {
  #|   const row = host.querySelector(`.machine-row[data-semantic-id="${CSS.escape(String(id))}"]`);
  #|   if (!row) throw new Error(`missing machine row ${id}`);
  #|   return row;
  #| }

///|
#cfg(target="js")
extern "js" fn machine_dom_same_node(
  left : DomElement,
  right : DomElement,
) -> Bool =
  #| (left, right) => left === right

///|
#cfg(target="js")
extern "js" fn machine_dom_records_json(records : Array[String]) -> String =
  #| (records) => JSON.stringify(records.map(JSON.parse))

///|
#cfg(target="js")
extern "js" fn machine_dom_structural_json(
  edit : String,
  reorder : String,
  stale : String,
  duplicate : String,
  edit_identity : Bool,
  reorder_identity : Bool,
) -> String =
  #| (edit, reorder, stale, duplicate, editIdentity, reorderIdentity) => JSON.stringify({
  #|   edit: JSON.parse(edit),
  #|   reorder: JSON.parse(reorder),
  #|   stale: JSON.parse(stale),
  #|   duplicate: JSON.parse(duplicate),
  #|   edit_identity: editIdentity,
  #|   reorder_identity: reorderIdentity,
  #| })

///|
#cfg(target="js")
extern "js" fn machine_dom_install_api(
  structural : (Int) -> String,
  benchmark : (Int, Int, Int) -> String,
) -> Unit =
  #| (structural, benchmark) => {
  #|   globalThis.__incrTeaMachineComposition = {
  #|     structural(n = 8) {
  #|       return JSON.parse(structural(Math.max(2, Math.trunc(Number(n) || 8))));
  #|     },
  #|     benchmark(n = 256, warmup = 200, iterations = 1000) {
  #|       return JSON.parse(benchmark(
  #|         Math.max(2, Math.trunc(Number(n) || 256)),
  #|         Math.max(0, Math.trunc(Number(warmup) || 0)),
  #|         Math.max(1, Math.trunc(Number(iterations) || 1000)),
  #|       ));
  #|     },
  #|   };
  #| }

///|
#cfg(target="js")
fn machine_dom_initial_model(child_count : Int) -> MachineParentModel {
  let model = Ref(machine_initial_model())
  for id in 0..<child_count {
    model.val = machine_transition(model.val, MachineAdd(id, "row \{id}")).model
  }
  machine_transition(model.val, MachineSelect(0)).model
}

///|
#cfg(target="js")
fn machine_validation_label(validation : MachineValidation) -> String {
  match validation {
    MachinePending(seq) => "pending \{seq}"
    MachineValid(seq) => "valid \{seq}"
    MachineInvalid(seq, diagnostic) => "invalid \{seq}: \{diagnostic}"
  }
}

///|
#cfg(target="js")
fn machine_dom_view(model : MachineParentModel) -> Html[MachineAction] {
  let rows = [
    for child in model.children => {
      let id = "\{child.id}"
      (
        id,
        li(
          attrs=[
            class_attr("machine-row"),
            attr("data-semantic-id", id),
            attr("aria-selected", "\{model.selected_id == Some(child.id)}"),
          ],
          [
            input(attrs=[
              class_attr("machine-input"),
              attr("data-semantic-id", id),
              attr("value", child.text),
            ]),
            span(attrs=[class_attr("machine-validation")], [
              text(machine_validation_label(child.validation)),
            ]),
          ],
        ),
      )
    }
  ]
  let selected_label = match model.selected_id {
    Some(id) =>
      match machine_child(model, id) {
        Some(child) => "selected \{id}: \{child.text}"
        None => "selected child missing"
      }
    None => "no selection"
  }
  article(attrs=[class_attr("machine-composition-editor")], [
    keyed_ol(attrs=[class_attr("machine-rows")], rows),
    div(attrs=[attr("data-machine-inspector", "true")], [text(selected_label)]),
  ])
}

///|
#cfg(target="js")
priv struct MachineDomHarness {
  host : DomElement
  observer : MachineProgramObserver
  timing : MachineTiming
  patch_timing : DomBenchTiming
  probe : MachineMutationProbe
  root : DomBenchRoot[MachineAction]
}

///|
#cfg(target="js")
fn MachineDomHarness::MachineDomHarness(child_count : Int) -> MachineDomHarness {
  let host = dom_bench_create_host()
  let observer = MachineProgramObserver()
  let timing = MachineTiming()
  let patch_timing = DomBenchTiming()
  let runtime = @incr.Runtime()
  let program = machine_program_with_view(
    runtime,
    machine_dom_initial_model(child_count),
    observer,
    machine_dom_view,
    hooks=timing.hooks(),
  )
  let root = DomBenchRoot(program, host, KeyedDomPatch, timing=patch_timing)
  root.flush()
  timing.reset()
  patch_timing.reset()
  {
    host,
    observer,
    timing,
    patch_timing,
    probe: machine_mutation_probe(host),
    root,
  }
}

///|
#cfg(target="js")
fn MachineDomHarness::reset_timing(self : MachineDomHarness) -> Unit {
  self.timing.reset()
  self.patch_timing.reset()
}

///|
#cfg(target="js")
fn MachineDomHarness::record(
  self : MachineDomHarness,
  iteration : Int,
  child_count : Int,
  action : MachineAction,
) -> String {
  self.reset_timing()
  machine_mutation_begin(self.probe)
  let started = dom_bench_now_ms()
  ignore(self.root.program.dispatch(action))
  self.root.flush()
  let total = dom_bench_now_ms() - started
  dom_set_property_mutation_observer(None)
  machine_mutation_finish(
    self.probe,
    iteration,
    child_count,
    self.timing.transition_ms,
    self.timing.view_ms,
    self.patch_timing.patch_ms,
    total,
    self.timing.transition_calls,
    self.timing.view_calls,
    self.patch_timing.patch_calls,
  )
}

///|
#cfg(target="js")
fn MachineDomHarness::dispose(self : MachineDomHarness) -> Unit {
  self.root.program.dispose()
  dom_bench_remove_host(self.host)
}

///|
#cfg(target="js")
fn machine_dom_run_structural(child_count : Int) -> String {
  let harness = MachineDomHarness(child_count)
  let before = [
    for id in 0..<child_count => machine_dom_row(harness.host, id)
  ]
  let edit = harness.record(0, child_count, MachineEdit(0, "row 0 edited"))
  let edit_identity = for id, node in before {
    guard machine_dom_same_node(node, machine_dom_row(harness.host, id)) else {
      break false
    }
  } nobreak {
    true
  }
  let reorder = harness.record(
    1,
    child_count,
    MachineReorder(
      machine_readonly([ for id in 0..<child_count => child_count - id - 1 ]),
    ),
  )
  let reorder_identity = for id, node in before {
    guard machine_dom_same_node(node, machine_dom_row(harness.host, id)) else {
      break false
    }
  } nobreak {
    true
  }
  let old = harness.observer.issued[0].token
  ignore(harness.root.program.dispatch(MachineEdit(0, "row 0 latest")))
  harness.root.flush()
  let current = harness.observer.issued[1].token
  let stale = harness.record(
    2,
    child_count,
    MachineComplete(old, MachineValidationValid),
  )
  ignore(
    harness.root.program.dispatch(
      MachineComplete(current, MachineValidationValid),
    ),
  )
  harness.root.flush()
  let duplicate = harness.record(
    3,
    child_count,
    MachineComplete(current, MachineValidationValid),
  )
  harness.dispose()
  machine_dom_structural_json(
    edit, reorder, stale, duplicate, edit_identity, reorder_identity,
  )
}

///|
#cfg(target="js")
fn machine_dom_run_benchmark(
  child_count : Int,
  warmup : Int,
  iterations : Int,
) -> String {
  let harness = MachineDomHarness(child_count)
  harness.observer.set_enabled(false)
  for iteration in 0..<warmup {
    ignore(harness.root.program.dispatch(MachineEdit(0, "warm \{iteration}")))
    harness.root.flush()
  }
  let records = [
    for iteration in 0..<iterations => {
      harness.record(
        iteration,
        child_count,
        MachineEdit(0, "measured \{iteration}"),
      )
    }
  ]
  harness.dispose()
  machine_dom_records_json(records)
}

///|
#cfg(target="js")
fn install_machine_composition_dom_api() -> Unit {
  machine_dom_install_api(machine_dom_run_structural, machine_dom_run_benchmark)
}
