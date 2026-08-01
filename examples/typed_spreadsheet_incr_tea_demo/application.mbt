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
enum ApplicationRemoteError {
  ProjectionFailed
  MutationNotLanded
  SynchronizationFailed(String)
  Disposed
} derive(Eq, Debug)

///|
struct DispatchOutcome {
  authority_changed : Bool
}

///|
struct AiContextPublisher {
  publish : (@demo.AiContextSnapshot) -> Unit
}

///|
fn AiContextPublisher::AiContextPublisher(
  publish : (@demo.AiContextSnapshot) -> Unit,
) -> AiContextPublisher {
  { publish, }
}

///|
fn AiContextPublisher::production() -> AiContextPublisher {
  AiContextPublisher(snapshot => {
    js_publish_ai_context_json(snapshot.to_json().stringify(indent=2))
  })
}

///|
struct SessionTransport {
  bind : (
    (@container.SyncMessage) -> Result[Unit, ApplicationRemoteError],
    (String) -> Unit,
  ) -> Unit
  publish : (@container.SyncMessage) -> Unit
  stop : () -> Unit
}

///|
fn SessionTransport::SessionTransport(
  bind : (
    (@container.SyncMessage) -> Result[Unit, ApplicationRemoteError],
    (String) -> Unit,
  ) -> Unit,
  publish : (@container.SyncMessage) -> Unit,
  stop : () -> Unit,
) -> SessionTransport {
  { bind, publish, stop }
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
  drafts : ReadOnlyArray[CellDraft]
  editing_cell : String?
  error : String?
  last_edit : String
}

///|
enum ApplicationCollaborationResult {
  Disabled
  BootstrapReady(BootstrapData)
  Active
  LocalOnly(String)
}

///|
struct ApplicationObservation {
  lifecycle : ApplicationLifecycle
  snapshot : ApplicationSnapshot
  region_stats : ReadOnlyArray[RegionRenderStats]
  collaboration : ApplicationCollaborationResult
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
      drafts: ReadOnlyArray::from_array(
        observation.snapshot.drafts.map(draft => CellDraft::{
          cell: draft.cell,
          text: draft.text,
        }),
      ),
      editing_cell: observation.snapshot.editing_cell,
      error: observation.snapshot.error,
      last_edit: observation.snapshot.last_edit,
    },
    region_stats: observation.region_stats.map(row => RegionRenderStats::{
      label: row.label,
      view_recomputes: row.view_recomputes,
      patch_attempts: row.patch_attempts,
      skipped_patches: row.skipped_patches,
    }),
    collaboration: observation.collaboration,
  }
}

///|
fn acquire_ai_context_snapshot(
  state : Ref[SheetState],
  cache : Ref[@demo.AiContextSnapshot?],
  dirty : Ref[Bool],
  capture_count : Ref[Int],
) -> @demo.AiContextSnapshot {
  match cache.val {
    Some(snapshot) if !dirty.val => snapshot
    _ => {
      let snapshot = state.val.ai_context_snapshot()
      capture_count.val += 1
      cache.val = Some(snapshot)
      dirty.val = false
      snapshot
    }
  }
}

///|
fn publish_cached_ai_context(
  state : Ref[SheetState],
  cache : Ref[@demo.AiContextSnapshot?],
  dirty : Ref[Bool],
  capture_count : Ref[Int],
  publisher : AiContextPublisher,
) -> Unit {
  let snapshot = acquire_ai_context_snapshot(state, cache, dirty, capture_count)
  (publisher.publish)(clone_ai_context_snapshot(snapshot))
}

///|
struct TypedSheetApplication {
  prog_grid : @tea.Program[Msg, @tea.Html[Msg]]
  prog_formula : @tea.Program[Msg, @tea.Html[Msg]]
  prog_status : @tea.Program[Msg, @tea.Html[Msg]]
  prog_trace : @tea.Program[Msg, @tea.Html[Msg]]
  prog_evidence : @tea.Program[Msg, @tea.Html[Msg]]
  state : Ref[SheetState]
  publisher : AiContextPublisher
  ai_context_cache : Ref[@demo.AiContextSnapshot?]
  ai_context_dirty : Ref[Bool]
  ai_context_capture_count : Ref[Int]
  transport : SessionTransport?
  collaboration : Ref[ApplicationCollaborationResult]
  mut lifecycle : ApplicationLifecycle
  mut renderer : @tea.BrowserRenderer[Msg]?
  mut final_observation : ApplicationObservation?
}

///|
fn TypedSheetApplication::dispose_owned_resources(
  state : Ref[SheetState],
  prog_grid : @tea.Program[Msg, @tea.Html[Msg]],
  prog_formula : @tea.Program[Msg, @tea.Html[Msg]],
  prog_status : @tea.Program[Msg, @tea.Html[Msg]],
  prog_trace : @tea.Program[Msg, @tea.Html[Msg]],
  prog_evidence : @tea.Program[Msg, @tea.Html[Msg]],
) -> Unit {
  state.val.adapter.dispose()
  prog_grid.dispose()
  prog_formula.dispose()
  prog_status.dispose()
  prog_trace.dispose()
  prog_evidence.dispose()
  state.val._scope.dispose()
}

///|
fn TypedSheetApplication::start(
  runtime : @incr.Runtime,
  mode : SheetStartMode,
  transport : SessionTransport?,
  publisher : AiContextPublisher,
) -> Result[TypedSheetApplication, ApplicationStartError] {
  let ai_context_cache : Ref[@demo.AiContextSnapshot?] = Ref(None)
  let ai_context_dirty = Ref(true)
  let ai_context_capture_count = Ref(0)
  let state = Ok(Ref(SheetState::new(runtime, mode))) catch {
    error => Err(AuthorityStartFailed(format_authority_error(error)))
  }
  let state = match state {
    Ok(state) => state
    Err(error) => return Err(error)
  }
  let update : (Msg) -> @tea.Cmd[Msg] = msg => {
    ai_context_dirty.val = true
    handle_msg(runtime, state, msg, fn() {
      publish_cached_ai_context(
        state, ai_context_cache, ai_context_dirty, ai_context_capture_count, publisher,
      )
    })
  }
  // Shared update; each program gets its own scope for the view Derived +
  // Watch. Disposing any one program only tears down its view tracking, not
  // the shared InputFields owned by `state.val._scope`.
  let prog_grid = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_grid(state.val) },
    label="typed-sheet.grid",
  )
  let prog_formula = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_formula_bar(state.val) },
    label="typed-sheet.formula-bar",
  )
  let prog_status = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_status(state.val) },
    label="typed-sheet.status",
  )
  let prog_trace = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_trace(state.val) },
    label="typed-sheet.trace",
  )
  let prog_evidence = @tea.Program::Program(
    runtime,
    @incr.Scope::new(runtime),
    update,
    fn() { state_evidence(state.val) },
    label="typed-sheet.evidence",
  )
  let collaboration = match transport {
    None => ApplicationCollaborationResult::Disabled
    Some(_) =>
      match mode {
        SheetStartMode::Host(_, _) => {
          let bootstrap = Ok(BootstrapData::{
            identity: state.val.adapter.identity(),
            sheet_id: state.val.adapter.sheet_id(),
            generation: state.val.adapter.generation(),
            node: state.val.adapter.node(),
            sync: state.val.adapter.export_all(),
          }) catch {
            error => Err(error)
          }
          match bootstrap {
            Ok(bootstrap) =>
              ApplicationCollaborationResult::BootstrapReady(bootstrap)
            Err(error) => {
              TypedSheetApplication::dispose_owned_resources(
                state, prog_grid, prog_formula, prog_status, prog_trace, prog_evidence,
              )
              return Err(AuthorityStartFailed(format_authority_error(error)))
            }
          }
        }
        SheetStartMode::Join(_, _) | SheetStartMode::Standalone =>
          ApplicationCollaborationResult::Active
      }
  }
  let application = {
    prog_grid,
    prog_formula,
    prog_status,
    prog_trace,
    prog_evidence,
    state,
    publisher,
    ai_context_cache,
    ai_context_dirty,
    ai_context_capture_count,
    transport,
    collaboration: Ref(collaboration),
    lifecycle: Unmounted,
    renderer: None,
    final_observation: None,
  }
  match transport {
    Some(transport) => {
      state.val.publish_sync = Some(sync => (transport.publish)(sync))
      (transport.bind)(sync => application.apply_remote(sync), error => {
        application.record_transport_failure(error)
      })
    }
    None => ()
  }
  Ok(application)
}

///|
fn TypedSheetApplication::dispatch(
  self : TypedSheetApplication,
  msg : Msg,
) -> Result[DispatchOutcome, ApplicationLifecycleError] {
  match self.lifecycle {
    Disposed => Err(Disposed)
    Unmounted | Mounted => {
      let before = self.state.val.adapter.version()
      guard self.prog_grid.dispatch(msg) else {
        abort("TypedSheetApplication program disposed before its owner")
      }
      Ok({ authority_changed: self.state.val.adapter.version() != before })
    }
  }
}

///|
fn TypedSheetApplication::apply_remote(
  self : TypedSheetApplication,
  message : @container.SyncMessage,
) -> Result[Unit, ApplicationRemoteError] {
  if self.lifecycle is ApplicationLifecycle::Disposed {
    return Err(ApplicationRemoteError::Disposed)
  }
  self.ai_context_dirty.val = true
  let applied = Ok(
    {
      let observed = self.state.val.adapter.apply_sync_observed(
        message,
        capture_limit=evidence_capture_limit(),
        trace_cells=state_visible_cell_ids(self.state),
      )
      let result = observed.result()
      match result.adapter_result() {
        @egw_adapter.AdapterApplyResult::Applied(_) =>
          record_remote_observed_sync(self.state, observed)
        @egw_adapter.AdapterApplyResult::NoSemanticChange(_) => {
          self.state.val.status.set("Remote update had no semantic changes.")
          self.state.val.error.set(None)
        }
        _ => ()
      }
      result
    },
  ) catch {
    error => Err(error)
  }
  let result = match applied {
    Err(error) =>
      Err(
        ApplicationRemoteError::SynchronizationFailed(
          format_authority_error(error),
        ),
      )
    Ok(result) =>
      match result.adapter_result() {
        @egw_adapter.AdapterApplyResult::Applied(_)
        | @egw_adapter.AdapterApplyResult::NoSemanticChange(_) => Ok(())
        @egw_adapter.AdapterApplyResult::MutationNotLanded =>
          Err(ApplicationRemoteError::MutationNotLanded)
        @egw_adapter.AdapterApplyResult::ProjectionFailed(_)
        | @egw_adapter.AdapterApplyResult::Rejected(_)
        | @egw_adapter.AdapterApplyResult::SourceRejected(_) =>
          Err(ApplicationRemoteError::ProjectionFailed)
      }
  }
  match result {
    Ok(_) =>
      match self.lifecycle {
        Mounted => {
          match self.renderer {
            Some(renderer) => renderer.flush_all()
            None => abort("mounted TypedSheetApplication has no renderer")
          }
          publish_cached_ai_context(
            self.state,
            self.ai_context_cache,
            self.ai_context_dirty,
            self.ai_context_capture_count,
            self.publisher,
          )
        }
        Unmounted =>
          publish_cached_ai_context(
            self.state,
            self.ai_context_cache,
            self.ai_context_dirty,
            self.ai_context_capture_count,
            self.publisher,
          )
        Disposed => ()
      }
    Err(_) => ()
  }
  result
}

///|
fn TypedSheetApplication::record_collaboration_status(
  self : TypedSheetApplication,
  status : String,
) -> Unit {
  if self.lifecycle is ApplicationLifecycle::Disposed {
    return
  }
  self.state.val.status.set(status)
  match self.lifecycle {
    Mounted =>
      match self.renderer {
        Some(renderer) => renderer.flush_all()
        None => abort("mounted TypedSheetApplication has no renderer")
      }
    Unmounted | Disposed => ()
  }
}

///|
fn TypedSheetApplication::record_transport_failure(
  self : TypedSheetApplication,
  error : String,
) -> Unit {
  if self.lifecycle is ApplicationLifecycle::Disposed {
    return
  }
  self.state.val.publish_sync = None
  self.collaboration.val = ApplicationCollaborationResult::LocalOnly(error)
  self.record_collaboration_status(
    "Collaboration unavailable; edits are now local only: \{error}",
  )
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
        self.prog_grid.runtime(),
      )
      ignore(
        renderer.mount(
          hosts.formula,
          self.prog_formula,
          label="formula-bar",
          on_value=resolve_value,
          on_key_event=resolve_key_event,
        ),
      )
      ignore(
        renderer.mount(
          hosts.grid,
          self.prog_grid,
          label="grid",
          on_value=resolve_value,
          on_key_event=resolve_key_event,
        ),
      )
      ignore(renderer.mount(hosts.status, self.prog_status, label="status"))
      ignore(renderer.mount(hosts.trace, self.prog_trace, label="trace"))
      ignore(
        renderer.mount(hosts.evidence, self.prog_evidence, label="evidence"),
      )
      self.renderer = Some(renderer)
      self.lifecycle = Mounted
      if self.collaboration.val
        is ApplicationCollaborationResult::BootstrapReady(_) {
        self.collaboration.val = ApplicationCollaborationResult::Active
      }
      publish_cached_ai_context(
        self.state,
        self.ai_context_cache,
        self.ai_context_dirty,
        self.ai_context_capture_count,
        self.publisher,
      )
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
  let state = self.state.val
  let ai_context = acquire_ai_context_snapshot(
    self.state,
    self.ai_context_cache,
    self.ai_context_dirty,
    self.ai_context_capture_count,
  )
  {
    ai_context: clone_ai_context_snapshot(ai_context),
    status: state.status.peek(),
    drafts: ReadOnlyArray::from_array(
      state.drafts
      .peek()
      .map(draft => CellDraft::{ cell: draft.cell, text: draft.text }),
    ),
    editing_cell: state.editing_cell.peek(),
    error: state.error.peek(),
    last_edit: state.last_edit.peek(),
  }
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
        collaboration: self.collaboration.val,
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
  self.state.val.publish_sync = None
  match self.transport {
    Some(transport) => (transport.stop)()
    None => ()
  }
  self.final_observation = Some({
    lifecycle: Disposed,
    snapshot: self.snapshot(),
    region_stats: self.region_stats(),
    collaboration: self.collaboration.val,
  })
  match self.renderer {
    Some(renderer) => renderer.dispose()
    None => ()
  }
  self.renderer = None
  TypedSheetApplication::dispose_owned_resources(
    self.state,
    self.prog_grid,
    self.prog_formula,
    self.prog_status,
    self.prog_trace,
    self.prog_evidence,
  )
  self.lifecycle = Disposed
}
