///|
enum ApplicationLifecycle {
  Unmounted
  Disposed
}

///|
enum ApplicationStartError {
  AuthorityStartFailed(String)
}

///|
enum ApplicationLifecycleError {
  Disposed
}

///|
struct DispatchOutcome {
  authority_changed : Bool
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
  }
}

///|
struct TypedSheetApplication {
  app : TypedSheetApp
  mut lifecycle : ApplicationLifecycle
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
  Ok({ app, lifecycle: Unmounted, final_observation: None })
}

///|
fn TypedSheetApplication::dispatch(
  self : TypedSheetApplication,
  msg : Msg,
) -> Result[DispatchOutcome, ApplicationLifecycleError] {
  match self.lifecycle {
    Disposed => Err(Disposed)
    Unmounted => {
      let before = self.app._state.val.adapter.version()
      guard self.app.prog_grid.dispatch(msg) else {
        abort("TypedSheetApplication program disposed before its owner")
      }
      Ok({ authority_changed: self.app._state.val.adapter.version() != before })
    }
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
    None => { lifecycle: self.lifecycle, snapshot: self.snapshot() }
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
  })
  self.app.dispose()
  self.lifecycle = Disposed
}
