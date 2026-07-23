///|
/// A typed projection failure with operation context.
pub enum ProjectionApplyError {
  UnexpectedSetInput(@typed_spreadsheet.CellId, @typed_spreadsheet.CellResult)
  UnexpectedFormula(
    @typed_spreadsheet.CellId,
    @typed_spreadsheet.WorksheetError
  )
  UnexpectedDelete(@typed_spreadsheet.CellId, @typed_spreadsheet.CellResult)
} derive(Eq, Debug)

///|
priv suberror ProjectionBatchFailure {
  Projection(ProjectionApplyError)
}

///|
/// Result of applying an application command or projection frame.
pub(all) enum AdapterApplyResult {
  Rejected(@domain.CommandApplicability)
  SourceRejected(@demo.FormulaTextParseError)
  MutationNotLanded
  ProjectionFailed(ProjectionApplyError)
  NoSemanticChange(ProjectionReport)
  Applied(ProjectionReport)
}

///|
/// Counts for one application projection frame.
pub struct ProjectionReport {
  priv decisions : Int
  priv worksheet_operations : Int
  priv committed_updates : Int
  priv draft_updates : Int
  priv diagnostics : Int
} derive(Eq, Debug)

///|
pub fn ProjectionReport::decisions(self : ProjectionReport) -> Int {
  self.decisions
}

///|
pub fn ProjectionReport::worksheet_operations(self : ProjectionReport) -> Int {
  self.worksheet_operations
}

///|
pub fn ProjectionReport::committed_updates(self : ProjectionReport) -> Int {
  self.committed_updates
}

///|
pub fn ProjectionReport::draft_updates(self : ProjectionReport) -> Int {
  self.draft_updates
}

///|
pub fn ProjectionReport::diagnostics(self : ProjectionReport) -> Int {
  self.diagnostics
}

///|
/// Application callbacks for draft reconciliation and UI projection.
pub struct ProjectionBindings {
  priv drafts : () -> ReadOnlyArray[@core.DraftObservation]
  priv apply : (@core.ProjectionDecision) -> Unit
}

///|
/// Creates projection callbacks without exposing their mutable state.
pub fn ProjectionBindings::ProjectionBindings(
  drafts : () -> ReadOnlyArray[@core.DraftObservation],
  apply : (@core.ProjectionDecision) -> Unit,
) -> ProjectionBindings {
  { drafts, apply }
}

///|
/// Fresh authority allocated by the application shell for reset.
pub struct ResetAuthority {
  priv identity : @core.CollaborativeSheetId
  priv document : @container.Document
  priv node : @container.TreeNodeId
  priv sheet_id : @typed_spreadsheet.SheetId
}

///|
/// Constructs reset authority. The worksheet is owned by the adapter.
pub fn ResetAuthority::ResetAuthority(
  identity : @core.CollaborativeSheetId,
  document : @container.Document,
  node : @container.TreeNodeId,
  sheet_id : @typed_spreadsheet.SheetId,
) -> ResetAuthority {
  { identity, document, node, sheet_id }
}

///|
/// Caller-owned immutable bootstrap seed.
pub struct Seed {
  priv address : String
  priv register : @core.CellRegister
}

///|
/// Constructs a seed for a canonical cell address.
pub fn Seed::Seed(address : String, register : @core.CellRegister) -> Seed {
  { address, register }
}

///|
pub fn Seed::address(self : Seed) -> String {
  self.address
}

///|
pub fn Seed::register(self : Seed) -> @core.CellRegister {
  self.register
}

///|
/// Structured bootstrap failures.
pub enum AdapterStartError {
  InvalidSeedAddress(String)
  DeadAuthorityNode
  SeedMutationNotLanded(String)
  Projection(ProjectionApplyError)
} derive(Eq, Debug)

///|
/// Starting an authority always distinguishes a ready adapter from failure.
pub enum AdapterStartResult {
  Ready(EgwAdapter, AdapterApplyResult)
  Failed(AdapterStartError)
}

///|
/// Separate EGW synchronization and application projection results.
pub struct RemoteApplyResult {
  priv sync_report : @container.SyncReport
  priv adapter_result : AdapterApplyResult
}

///|
pub fn RemoteApplyResult::sync_report(
  self : RemoteApplyResult,
) -> @container.SyncReport {
  self.sync_report
}

///|
pub fn RemoteApplyResult::adapter_result(
  self : RemoteApplyResult,
) -> AdapterApplyResult {
  self.adapter_result
}

///|
/// Application-owned EGW and projection boundary.
pub struct EgwAdapter {
  priv runtime : @incr.Runtime
  priv mut identity : @core.CollaborativeSheetId
  priv mut document : @container.Document
  priv mut node : @container.TreeNodeId
  priv mut worksheet : @typed_spreadsheet.Worksheet
  priv mut sheet_id : @typed_spreadsheet.SheetId
  priv mut generation : @domain.DocumentGeneration
  priv mut readback_override : String?
  priv mut state : @core.ProjectionState
  priv bindings : ProjectionBindings
  priv reset_factory : (@domain.DocumentGeneration) -> ResetAuthority raise @container.DocumentError
  priv addresses : ReadOnlyArray[String]
  priv seeds : ReadOnlyArray[Seed]
}

///|
fn property_key(address : String) -> String {
  "cell/\{address}"
}

///|
fn seed_document(
  document : @container.Document,
  node : @container.TreeNodeId,
  seeds : ReadOnlyArray[Seed],
) -> Result[Unit, AdapterStartError] {
  if !document.is_alive(node) {
    return Err(AdapterStartError::DeadAuthorityNode)
  }
  let addresses = @domain.grid_cells()
  for seed in seeds {
    if !addresses.contains(seed.address) {
      return Err(AdapterStartError::InvalidSeedAddress(seed.address))
    }
    let encoded = @core.encode_register(seed.register)
    document.set_property(node, property_key(seed.address), encoded)
    match document.get_property(node, property_key(seed.address)) {
      Some(value) if value == encoded => ()
      _ => return Err(AdapterStartError::SeedMutationNotLanded(seed.address))
    }
  }
  Ok(())
}

///|
fn snapshot_addresses(
  adapter : EgwAdapter,
  addresses : ArrayView[String],
) -> @core.RawRegisterSnapshot {
  let entries = addresses.map(address => {
    @core.RawRegisterEntry::RawRegisterEntry(
      address,
      adapter.document.get_property(adapter.node, property_key(address)),
    )
  })
  @core.RawRegisterSnapshot::RawRegisterSnapshot(addresses.to_owned(), entries)
}

///|
fn snapshot(adapter : EgwAdapter) -> @core.RawRegisterSnapshot {
  snapshot_addresses(adapter, adapter.addresses[:])
}

///|
fn apply_decision(
  adapter : EgwAdapter,
  decision : @core.ProjectionDecision,
) -> Unit raise ProjectionBatchFailure {
  match decision {
    @core.ProjectionDecision::ApplyWorksheet(operation) =>
      match operation {
        @demo.SheetOp::SetInput(id, value) =>
          match adapter.worksheet.set_input(id, value) {
            @typed_spreadsheet.CellResult::Ok(_) => ()
            result =>
              raise ProjectionBatchFailure::Projection(
                ProjectionApplyError::UnexpectedSetInput(id, result),
              )
          }
        @demo.SheetOp::SetFormulaAst(id, cell_type, formula) =>
          match adapter.worksheet.set_formula_ast(id, cell_type, formula) {
            Ok(_) => ()
            Err(error) =>
              raise ProjectionBatchFailure::Projection(
                ProjectionApplyError::UnexpectedFormula(id, error),
              )
          }
        @demo.SheetOp::Delete(id) =>
          match adapter.worksheet.delete(id) {
            @typed_spreadsheet.CellResult::Ok(_) => ()
            result =>
              raise ProjectionBatchFailure::Projection(
                ProjectionApplyError::UnexpectedDelete(id, result),
              )
          }
      }
    @core.ProjectionDecision::SetCommitted(_, _)
    | @core.ProjectionDecision::SetDraft(_, _)
    | @core.ProjectionDecision::SetDiagnostic(_, _) =>
      (adapter.bindings.apply)(decision)
  }
}

///|
fn project_authority_with_drafts(
  adapter : EgwAdapter,
  drafts : ReadOnlyArray[@core.DraftObservation],
) -> AdapterApplyResult {
  let transition = @core.compute_projection_transition(
    adapter.state,
    snapshot(adapter),
    adapter.sheet_id,
    drafts,
  )
  let decisions = transition.decisions()
  let report = ProjectionReport::{
    decisions: decisions.length(),
    worksheet_operations: decisions
    .filter(d => d is @core.ProjectionDecision::ApplyWorksheet(_))
    .length(),
    committed_updates: decisions
    .filter(d => d is @core.ProjectionDecision::SetCommitted(_, _))
    .length(),
    draft_updates: decisions
    .filter(d => d is @core.ProjectionDecision::SetDraft(_, _))
    .length(),
    diagnostics: transition.diagnostics().length(),
  }
  let applied : Result[Unit, ProjectionApplyError] = try {
    adapter.runtime.batch(() => {
      for decision in decisions {
        apply_decision(adapter, decision)
      }
    })
    Ok(())
  } catch {
    ProjectionBatchFailure::Projection(error) => Err(error)
  }
  match applied {
    Ok(_) => {
      adapter.state = transition.candidate_state()
      if decisions.is_empty() {
        AdapterApplyResult::NoSemanticChange(report)
      } else {
        AdapterApplyResult::Applied(report)
      }
    }
    Err(error) => AdapterApplyResult::ProjectionFailed(error)
  }
}

///|
fn project_authority(adapter : EgwAdapter) -> AdapterApplyResult {
  project_authority_with_drafts(adapter, (adapter.bindings.drafts)())
}

///|
fn start_authority(
  runtime : @incr.Runtime,
  identity : @core.CollaborativeSheetId,
  sheet_id : @typed_spreadsheet.SheetId,
  generation : @domain.DocumentGeneration,
  document : @container.Document,
  node : @container.TreeNodeId,
  seeds : Array[Seed],
  bindings : ProjectionBindings,
  reset_factory : (@domain.DocumentGeneration) -> ResetAuthority raise @container.DocumentError,
) -> AdapterStartResult {
  if !document.is_alive(node) {
    return AdapterStartResult::Failed(AdapterStartError::DeadAuthorityNode)
  }
  let adapter = EgwAdapter::{
    runtime,
    identity,
    document,
    node,
    worksheet: @typed_spreadsheet.Worksheet(runtime, sheet_id),
    sheet_id,
    generation,
    readback_override: None,
    state: @core.ProjectionState::empty(@domain.grid_cells()),
    bindings,
    reset_factory,
    addresses: ReadOnlyArray::from_array(@domain.grid_cells()),
    seeds: ReadOnlyArray::from_array(seeds.copy()),
  }
  match project_authority(adapter) {
    AdapterApplyResult::ProjectionFailed(error) => {
      adapter.worksheet.dispose()
      AdapterStartResult::Failed(AdapterStartError::Projection(error))
    }
    result => AdapterStartResult::Ready(adapter, result)
  }
}

///|
/// Creates a fresh authority, writes caller-owned seeds, then projects it.
pub fn EgwAdapter::bootstrap(
  runtime : @incr.Runtime,
  replica_id : String,
  identity : @core.CollaborativeSheetId,
  sheet_id : @typed_spreadsheet.SheetId,
  seeds : Array[Seed],
  bindings : ProjectionBindings,
  reset_factory : (@domain.DocumentGeneration) -> ResetAuthority raise @container.DocumentError,
) -> AdapterStartResult raise @container.DocumentError {
  let document = @container.Document::new(replica_id)
  let node = document.create_node(parent=@container.root_id)
  let owned_seeds = ReadOnlyArray::from_array(seeds.copy())
  match seed_document(document, node, owned_seeds) {
    Err(error) => AdapterStartResult::Failed(error)
    Ok(_) =>
      start_authority(
        runtime,
        identity,
        sheet_id,
        @domain.DocumentGeneration::initial(),
        document,
        node,
        seeds,
        bindings,
        reset_factory,
      )
  }
}

///|
/// Attaches a local projection to an existing synchronized authority.
pub fn EgwAdapter::attach(
  runtime : @incr.Runtime,
  identity : @core.CollaborativeSheetId,
  sheet_id : @typed_spreadsheet.SheetId,
  generation : @domain.DocumentGeneration,
  document : @container.Document,
  node : @container.TreeNodeId,
  seeds : Array[Seed],
  bindings : ProjectionBindings,
  reset_factory : (@domain.DocumentGeneration) -> ResetAuthority raise @container.DocumentError,
) -> AdapterStartResult {
  start_authority(
    runtime, identity, sheet_id, generation, document, node, seeds, bindings, reset_factory,
  )
}

///|
/// Executes a validated local command.
pub fn EgwAdapter::apply_command(
  self : EgwAdapter,
  command : @domain.SheetCommand,
  context : @domain.SheetExecutionContext,
) -> AdapterApplyResult raise @container.DocumentError {
  let command_generation = match command {
    @domain.SheetCommand::ApplyFromSelection(_, _, generation)
    | @domain.SheetCommand::ApplyFromEditor(_, _, generation)
    | @domain.SheetCommand::DeleteFromSelection(_, generation)
    | @domain.SheetCommand::ResetDocument(generation) => generation
  }
  if command_generation != self.generation {
    return AdapterApplyResult::Rejected(
      @domain.CommandApplicability::StaleGeneration,
    )
  }
  match @domain.validate_sheet_command(command, context) {
    @domain.CommandApplicability::Applicable => ()
    rejection => return AdapterApplyResult::Rejected(rejection)
  }
  match command {
    @domain.SheetCommand::ResetDocument(_) => self.reset()
    @domain.SheetCommand::ApplyFromSelection(id, text, _)
    | @domain.SheetCommand::ApplyFromEditor(id, text, _) => {
      if !self.owns_target(id) {
        return AdapterApplyResult::Rejected(
          @domain.CommandApplicability::LocalPreconditionFailed,
        )
      }
      match @demo.parse_cell_text_op(id, text.trim().to_owned()) {
        Ok(_) =>
          self.write_and_project(
            id,
            @core.CellRegister::Source(text.trim().to_owned()),
          )
        Err(error) => AdapterApplyResult::SourceRejected(error)
      }
    }
    @domain.SheetCommand::DeleteFromSelection(id, _) => {
      if !self.owns_target(id) {
        return AdapterApplyResult::Rejected(
          @domain.CommandApplicability::LocalPreconditionFailed,
        )
      }
      self.write_and_project(id, @core.CellRegister::Deleted)
    }
  }
}

///|
fn EgwAdapter::owns_target(
  self : EgwAdapter,
  id : @typed_spreadsheet.CellId,
) -> Bool {
  let address = @demo.cell_id_to_string(id)
  @typed_spreadsheet.CellId::of(self.sheet_id, address) == id &&
  self.addresses.contains(address)
}

///|
fn EgwAdapter::write_and_project(
  self : EgwAdapter,
  id : @typed_spreadsheet.CellId,
  register : @core.CellRegister,
) -> AdapterApplyResult {
  let address = @demo.cell_id_to_string(id)
  if !self.owns_target(id) {
    return AdapterApplyResult::Rejected(
      @domain.CommandApplicability::LocalPreconditionFailed,
    )
  }
  if !self.document.is_alive(self.node) {
    return AdapterApplyResult::MutationNotLanded
  }
  let desired = @core.encode_register(register)
  self.document.set_property(self.node, property_key(address), desired)
  let readback = match self.readback_override {
    Some(value) => Some(value)
    None => self.document.get_property(self.node, property_key(address))
  }
  match readback {
    Some(value) if value == desired => project_authority(self)
    _ => AdapterApplyResult::MutationNotLanded
  }
}

///|
/// Applies a remote sync message and projects it.
pub fn EgwAdapter::apply_sync(
  self : EgwAdapter,
  message : @container.SyncMessage,
) -> RemoteApplyResult raise @container.DocumentError {
  let report = self.document.sync().apply(message)
  RemoteApplyResult::{
    sync_report: report,
    adapter_result: project_authority(self),
  }
}

///|
fn EgwAdapter::reset(
  self : EgwAdapter,
) -> AdapterApplyResult raise @container.DocumentError {
  let next_generation = self.generation.next()
  let replacement = (self.reset_factory)(next_generation)
  let worksheet = @typed_spreadsheet.Worksheet(
    self.runtime,
    replacement.sheet_id,
  )
  let candidate = EgwAdapter::{
    runtime: self.runtime,
    identity: replacement.identity,
    document: replacement.document,
    node: replacement.node,
    worksheet,
    sheet_id: replacement.sheet_id,
    generation: next_generation,
    readback_override: None,
    state: @core.ProjectionState::empty(@domain.grid_cells()),
    bindings: self.bindings,
    reset_factory: self.reset_factory,
    addresses: self.addresses,
    seeds: self.seeds,
  }
  if !replacement.document.is_alive(replacement.node) {
    worksheet.dispose()
    return AdapterApplyResult::MutationNotLanded
  }
  match seed_document(replacement.document, replacement.node, self.seeds) {
    Err(_) => {
      worksheet.dispose()
      AdapterApplyResult::MutationNotLanded
    }
    Ok(_) =>
      match
        project_authority_with_drafts(candidate, ReadOnlyArray::from_array([])) {
        AdapterApplyResult::ProjectionFailed(error) => {
          worksheet.dispose()
          AdapterApplyResult::ProjectionFailed(error)
        }
        result => {
          let old = self.worksheet
          self.identity = candidate.identity
          self.document = candidate.document
          self.node = candidate.node
          self.worksheet = candidate.worksheet
          self.sheet_id = candidate.sheet_id
          self.generation = next_generation
          self.state = candidate.state
          old.dispose()
          result
        }
      }
  }
}

///|
#warnings("-unused_value")
fn EgwAdapter::set_readback_override_for_test(
  self : EgwAdapter,
  value : String?,
) -> Unit {
  self.readback_override = value
}

///|
pub fn EgwAdapter::generation(self : EgwAdapter) -> @domain.DocumentGeneration {
  self.generation
}

///|
pub fn EgwAdapter::identity(self : EgwAdapter) -> @core.CollaborativeSheetId {
  self.identity
}

///|
pub fn EgwAdapter::sheet_id(self : EgwAdapter) -> @typed_spreadsheet.SheetId {
  self.sheet_id
}

///|
pub fn EgwAdapter::projection_state(self : EgwAdapter) -> @core.ProjectionState {
  self.state
}

///|
pub fn EgwAdapter::version(self : EgwAdapter) -> @container.Version {
  self.document.version()
}

///|
/// Reads one projected cell without exposing the mutable Worksheet.
pub fn EgwAdapter::read_cell(
  self : EgwAdapter,
  address : String,
) -> @typed_spreadsheet.CellResult {
  self.worksheet.read(@typed_spreadsheet.CellId::of(self.sheet_id, address))
}

///|
/// Returns an owned inspection snapshot for one projected cell.
pub fn EgwAdapter::inspect_cell(
  self : EgwAdapter,
  address : String,
) -> @typed_spreadsheet.CellSnapshot {
  self.worksheet.inspect_cell(
    @typed_spreadsheet.CellId::of(self.sheet_id, address),
  )
}

///|
pub fn EgwAdapter::export_all(
  self : EgwAdapter,
) -> @container.SyncMessage raise @container.DocumentError {
  self.document.sync().export_all()
}

///|
pub fn EgwAdapter::export_since(
  self : EgwAdapter,
  version : @container.Version,
) -> @container.SyncMessage raise @container.DocumentError {
  self.document.sync().export_since(version)
}
