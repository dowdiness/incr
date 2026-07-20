///|
fn draft_map(drafts : ReadOnlyArray[DraftObservation]) -> Map[String, String] {
  let map : Map[String, String] = Map::from_array([])
  for draft in drafts {
    if map.get(draft.address()) is None {
      map[draft.address()] = draft.text()
    }
  }
  map
}

///|
fn same_observation(a : RegisterObservation, b : RegisterObservation) -> Bool {
  a == b
}

///|
fn previous_cells(state : ProjectionState) -> Map[String, CellProjectionState] {
  let map : Map[String, CellProjectionState] = Map::from_array([])
  for cell in state.cells() {
    map[cell.address()] = cell
  }
  map
}

///|
/// Computes a deterministic transition without mutating the previous state.
pub fn compute_projection_transition(
  previous : ProjectionState,
  snapshot : RawRegisterSnapshot,
  sheet_id : @typed_spreadsheet.SheetId,
  drafts : ReadOnlyArray[DraftObservation],
) -> ProjectionTransition {
  let old = previous_cells(previous)
  let draft_by_address = draft_map(drafts)
  let next_cells = []
  let decisions = []
  for entry in snapshot.entries() {
    let address = entry.address()
    let prior = match old.get(address) {
      Some(cell) => cell
      None =>
        CellProjectionState::{
          address,
          last_seen_register: Unset,
          last_good_source: None,
          diagnostic: None,
        }
    }
    let observation = decode_register(address, entry.payload())
    if same_observation(observation, prior.last_seen_register()) {
      next_cells.push(prior)
    } else {
      let mut next_good = prior.last_good_source()
      let mut next_diagnostic : ProjectionDiagnostic? = None
      let mut changed_semantics = false
      match observation {
        Unset | Decoded(Deleted) => {
          changed_semantics = next_good is Some(_)
          if changed_semantics {
            decisions.push(
              ProjectionDecision::ApplyWorksheet(
                @demo.SheetOp::Delete(
                  @typed_spreadsheet.CellId::of(sheet_id, address),
                ),
              ),
            )
            decisions.push(ProjectionDecision::SetCommitted(address, None))
            next_good = None
          }
        }
        Invalid(diagnostic) => next_diagnostic = Some(diagnostic)
        Decoded(Source(text)) =>
          match
            @demo.parse_cell_text_op(
              @typed_spreadsheet.CellId::of(sheet_id, address),
              text,
            ) {
            Err(error) =>
              next_diagnostic = Some(
                ProjectionDiagnostic::InvalidSource(address, text, error),
              )
            Ok(operation) => {
              changed_semantics = next_good != Some(text)
              if changed_semantics {
                decisions.push(ProjectionDecision::ApplyWorksheet(operation))
                decisions.push(
                  ProjectionDecision::SetCommitted(address, Some(text)),
                )
                next_good = Some(text)
              }
            }
          }
      }
      if changed_semantics {
        let previous_text = match prior.last_good_source() {
          Some(text) => text
          None => ""
        }
        let clean = match draft_by_address.get(address) {
          None => true
          Some(text) => text == previous_text
        }
        if clean {
          decisions.push(ProjectionDecision::SetDraft(address, next_good))
        }
      }
      if prior.diagnostic() is Some(_) && next_diagnostic is None {
        decisions.push(ProjectionDecision::SetDiagnostic(address, None))
      }
      match next_diagnostic {
        Some(diagnostic) =>
          decisions.push(
            ProjectionDecision::SetDiagnostic(address, Some(diagnostic)),
          )
        None => ()
      }
      next_cells.push(CellProjectionState::{
        address,
        last_seen_register: observation,
        last_good_source: next_good,
        diagnostic: next_diagnostic,
      })
    }
  }
  let candidate = ProjectionState::{
    cells: ReadOnlyArray::from_array(next_cells),
  }
  let diagnostics = []
  for cell in candidate.cells() {
    match cell.diagnostic() {
      Some(d) => diagnostics.push(d)
      None => ()
    }
  }
  ProjectionTransition::{
    candidate_state: candidate,
    decisions: ReadOnlyArray::from_array(decisions),
    diagnostics: ReadOnlyArray::from_array(diagnostics),
  }
}
