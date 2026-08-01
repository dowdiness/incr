///|
enum ApplicationLifecycle {
  Unmounted
  Mounted
  Disposed
}

///|
enum ApplicationStartError {
  AuthorityStartFailed(String)
}

///|
enum ApplicationLifecycleError {
  NotMounted
  AlreadyMounted
  Disposed
}

///|
struct DispatchOutcome {
  authority_changed : Bool
}

///|
struct TypedSheetHosts {
  grid : @tea.DomElement
  formula : @tea.DomElement
  status : @tea.DomElement
  trace : @tea.DomElement
  evidence : @tea.DomElement
}

///|
enum HostResolutionError {
  MissingRegion(String)
}

///|
#cfg(target="js")
extern "js" fn js_dom_element_exists(id : String) -> Bool =
  #| id => globalThis.document.getElementById(id) !== null

///|
#cfg(target="js")
fn resolve_typed_sheet_hosts(
  mount_id : String,
) -> Result[TypedSheetHosts, HostResolutionError] {
  let grid_id = mount_id + "-grid"
  let formula_id = mount_id + "-formula"
  let status_id = mount_id + "-status"
  let trace_id = mount_id + "-trace"
  let evidence_id = mount_id + "-evidence"
  let missing = if !js_dom_element_exists(grid_id) {
    Some(grid_id)
  } else if !js_dom_element_exists(formula_id) {
    Some(formula_id)
  } else if !js_dom_element_exists(status_id) {
    Some(status_id)
  } else if !js_dom_element_exists(trace_id) {
    Some(trace_id)
  } else if !js_dom_element_exists(evidence_id) {
    Some(evidence_id)
  } else {
    None
  }
  match missing {
    Some(id) => Err(MissingRegion(id))
    None =>
      Ok(TypedSheetHosts::{
        grid: @tea.dom_get_element_by_id(grid_id),
        formula: @tea.dom_get_element_by_id(formula_id),
        status: @tea.dom_get_element_by_id(status_id),
        trace: @tea.dom_get_element_by_id(trace_id),
        evidence: @tea.dom_get_element_by_id(evidence_id),
      })
  }
}

///|
struct RegionRenderStats {
  label : String
  view_recomputes : Int
  patch_attempts : Int
  skipped_patches : Int
}

///|
struct ApplicationSnapshot {
  ai_context : @demo.AiContextSnapshot
  status : String
}

///|
struct ApplicationObservation {
  lifecycle : ApplicationLifecycle
  snapshot : ApplicationSnapshot
  region_stats : ReadOnlyArray[RegionRenderStats]
}

///|
fn clone_ai_context_snapshot(
  snapshot : @demo.AiContextSnapshot,
) -> @demo.AiContextSnapshot {
  let clone_result = (result : @demo.AiContextResult) => {
    let value = match result.value {
      Some(value) =>
        Some(@demo.AiContextValue::{
          type_name: value.type_name,
          value: value.value,
          repr: value.repr,
        })
      None => None
    }
    @demo.AiContextResult::{
      status: result.status,
      value,
      error: result.error,
      repr: result.repr,
    }
  }
  let cells = snapshot.cells.map(cell => {
    let formula = match cell.formula {
      Some(formula) =>
        Some(@demo.AiContextFormula::{
          text: formula.text,
          ast_status: formula.ast_status,
          shape: formula.shape,
          error: formula.error,
        })
      None => None
    }
    @demo.AiContextCell::{
      id: cell.id,
      committed_text: cell.committed_text,
      draft_text: cell.draft_text,
      draft_dirty: cell.draft_dirty,
      present: cell.present,
      kind: cell.kind,
      result: clone_result(cell.result),
      dependency_shape: cell.dependency_shape,
      installed_dependencies: cell.installed_dependencies.copy(),
      static_references: cell.static_references.copy(),
      last_dynamic_dependencies: cell.last_dynamic_dependencies.copy(),
      formula,
    }
  })
  let latest_trace = match snapshot.latest_trace {
    Some(trace) =>
      Some(@demo.AiContextTrace::{
        edit: trace.edit,
        outcome: trace.outcome,
        recomputed: trace.recomputed.copy(),
        changed: trace.changed.copy(),
        unchanged: trace.unchanged.copy(),
      })
    None => None
  }
  let latest_evidence = match snapshot.latest_evidence {
    Some(evidence) =>
      Some(@demo.AiContextEvidence::{
        edit: evidence.edit,
        outcome: evidence.outcome,
        cells: evidence.cells.map(cell => @demo.AiContextEvidenceCell::{
          id: cell.id,
          classification: cell.classification,
          before: clone_result(cell.before),
          before_kind: cell.before_kind,
          after: clone_result(cell.after),
          after_kind: cell.after_kind,
        }),
      })
    None => None
  }
  {
    schema_version: snapshot.schema_version,
    selected_cell: snapshot.selected_cell,
    max_cells: snapshot.max_cells,
    truncated: snapshot.truncated,
    region: snapshot.region.copy(),
    cells,
    latest_trace,
    latest_evidence,
  }
}

///|
fn clone_application_observation(
  observation : ApplicationObservation,
) -> ApplicationObservation {
  {
    lifecycle: observation.lifecycle,
    snapshot: {
      ai_context: clone_ai_context_snapshot(observation.snapshot.ai_context),
      status: observation.snapshot.status,
    },
    region_stats: observation.region_stats.map(row => RegionRenderStats::{
      label: row.label,
      view_recomputes: row.view_recomputes,
      patch_attempts: row.patch_attempts,
      skipped_patches: row.skipped_patches,
    }),
  }
}

///|
struct TypedSheetApplication {
  app : TypedSheetApp
  mut lifecycle : ApplicationLifecycle
  mut renderer : @tea.BrowserRenderer[Msg]?
  mut final_observation : ApplicationObservation?
}

///|
fn TypedSheetApplication::start(
  runtime : @incr.Runtime,
  mode : SheetStartMode,
) -> Result[TypedSheetApplication, ApplicationStartError] {
  let app = TypedSheetApp::with_mode(runtime, mode) catch {
    error => return Err(AuthorityStartFailed(format_authority_error(error)))
  }
  Ok({ app, lifecycle: Unmounted, renderer: None, final_observation: None })
}

///|
fn TypedSheetApplication::dispatch(
  self : TypedSheetApplication,
  msg : Msg,
) -> Result[DispatchOutcome, ApplicationLifecycleError] {
  match self.lifecycle {
    Disposed => Err(Disposed)
    Unmounted | Mounted => {
      let before = self.app._state.val.adapter.version()
      guard self.app.prog_grid.dispatch(msg) else {
        abort("TypedSheetApplication program disposed before its owner")
      }
      Ok({ authority_changed: self.app._state.val.adapter.version() != before })
    }
  }
}

///|
fn TypedSheetApplication::mount(
  self : TypedSheetApplication,
  hosts : TypedSheetHosts,
) -> Result[Unit, ApplicationLifecycleError] {
  match self.lifecycle {
    Disposed => Err(Disposed)
    Mounted => Err(AlreadyMounted)
    Unmounted => {
      let renderer = @tea.BrowserRenderer::BrowserRenderer(
        self.app.prog_grid.runtime(),
      )
      ignore(
        renderer.mount(
          hosts.formula,
          self.app.prog_formula,
          label="formula-bar",
          on_value=resolve_value,
          on_key_event=resolve_key_event,
        ),
      )
      ignore(
        renderer.mount(
          hosts.grid,
          self.app.prog_grid,
          label="grid",
          on_value=resolve_value,
          on_key_event=resolve_key_event,
        ),
      )
      ignore(renderer.mount(hosts.status, self.app.prog_status, label="status"))
      ignore(renderer.mount(hosts.trace, self.app.prog_trace, label="trace"))
      ignore(
        renderer.mount(hosts.evidence, self.app.prog_evidence, label="evidence"),
      )
      self.renderer = Some(renderer)
      self.lifecycle = Mounted
      Ok(())
    }
  }
}

///|
fn TypedSheetApplication::region_stats(
  self : TypedSheetApplication,
) -> ReadOnlyArray[RegionRenderStats] {
  match self.renderer {
    Some(renderer) =>
      ReadOnlyArray::from_array(
        renderer
        .root_stats()
        .map(row => RegionRenderStats::{
          label: row.label,
          view_recomputes: row.view_recomputes,
          patch_attempts: row.patch_attempts,
          skipped_patches: row.skipped_patches,
        }),
      )
    None => []
  }
}

///|
fn TypedSheetApplication::snapshot(
  self : TypedSheetApplication,
) -> ApplicationSnapshot {
  let state = self.app._state.val
  { ai_context: state.ai_context_snapshot(), status: state.status.peek() }
}

///|
fn TypedSheetApplication::observe(
  self : TypedSheetApplication,
) -> ApplicationObservation {
  match self.final_observation {
    Some(observation) => clone_application_observation(observation)
    None =>
      {
        lifecycle: self.lifecycle,
        snapshot: self.snapshot(),
        region_stats: self.region_stats(),
      }
  }
}

///|
fn TypedSheetApplication::flush_presentation(
  self : TypedSheetApplication,
) -> Result[ApplicationObservation, ApplicationLifecycleError] {
  match self.lifecycle {
    Unmounted => Err(NotMounted)
    Disposed => Err(Disposed)
    Mounted =>
      match self.renderer {
        Some(renderer) => {
          renderer.flush_all()
          Ok(self.observe())
        }
        None => abort("mounted TypedSheetApplication has no renderer")
      }
  }
}

///|
fn TypedSheetApplication::dispose(self : TypedSheetApplication) -> Unit {
  if self.lifecycle is Disposed {
    return
  }
  self.final_observation = Some({
    lifecycle: Disposed,
    snapshot: self.snapshot(),
    region_stats: self.region_stats(),
  })
  match self.renderer {
    Some(renderer) => renderer.dispose()
    None => ()
  }
  self.renderer = None
  self.app.dispose()
  self.lifecycle = Disposed
}
