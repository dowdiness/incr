///|
/// Caller-owned identity for a collaborative sheet. It is deliberately not
/// derived from any event-graph identity.
pub struct CollaborativeSheetId {
  value : String
}

///|
/// Constructs a sheet identity.
pub fn CollaborativeSheetId::CollaborativeSheetId(
  value : String,
) -> CollaborativeSheetId {
  CollaborativeSheetId::{ value, }
}

///|
/// Returns the caller-supplied identity string.
pub fn CollaborativeSheetId::value(self : CollaborativeSheetId) -> String {
  self.value
}

///|
/// The register value stored by the projection.
pub(all) enum CellRegister {
  Source(String)
  Deleted
} derive(Eq, Debug)

///|
/// A diagnostic produced while decoding or parsing a register.
pub(all) enum ProjectionDiagnostic {
  MalformedJson(String)
  NonObject(String)
  DuplicateFields(String)
  MissingField(String, String)
  InvalidFieldType(String, String)
  UnsupportedNumericVersion(String, Double)
  UnknownTag(String, String)
  ExtraFields(String, ReadOnlyArray[String])
  InvalidSource(String, String, @demo.FormulaTextParseError)
} derive(Eq, Debug)

///|
/// The complete observation of one register payload.
pub(all) enum RegisterObservation {
  Unset
  Decoded(CellRegister)
  Invalid(ProjectionDiagnostic)
} derive(Eq, Debug)

///|
/// An address/payload pair supplied by a transport adapter.
pub struct RawRegisterEntry {
  address : String
  payload : String?
}

///|
/// Constructs a raw register entry.
pub fn RawRegisterEntry::RawRegisterEntry(
  address : String,
  payload : String?,
) -> RawRegisterEntry {
  { address, payload }
}

///|
/// Returns the entry address.
pub fn RawRegisterEntry::address(self : RawRegisterEntry) -> String {
  self.address
}

///|
/// Returns the optional JSON payload.
pub fn RawRegisterEntry::payload(self : RawRegisterEntry) -> String? {
  self.payload
}

///|
/// An immutable canonical register snapshot.
pub struct RawRegisterSnapshot {
  addresses : ReadOnlyArray[String]
  entries : ReadOnlyArray[RawRegisterEntry]
}

///|
/// Builds a snapshot. Unknown entries are ignored and duplicate addresses use
/// the first entry in the supplied order.
pub fn RawRegisterSnapshot::RawRegisterSnapshot(
  addresses : Array[String],
  entries : Array[RawRegisterEntry],
) -> RawRegisterSnapshot {
  let unique_addresses = []
  let seen : Map[String, Bool] = Map::from_array([])
  for address in addresses {
    if seen.get(address) is None {
      seen[address] = true
      unique_addresses.push(address)
    }
  }
  let known : Map[String, Bool] = Map::from_array([])
  for address in unique_addresses {
    known[address] = true
  }
  let selected : Map[String, RawRegisterEntry] = Map::from_array([])
  for entry in entries {
    if known.get(entry.address) is Some(_) &&
      selected.get(entry.address) is None {
      selected[entry.address] = entry
    }
  }
  let canonical = []
  for address in unique_addresses {
    match selected.get(address) {
      Some(entry) => canonical.push(entry)
      None => canonical.push(RawRegisterEntry(address, None))
    }
  }
  {
    addresses: ReadOnlyArray::from_array(unique_addresses),
    entries: ReadOnlyArray::from_array(canonical),
  }
}

///|
/// Returns canonical addresses.
pub fn RawRegisterSnapshot::addresses(
  self : RawRegisterSnapshot,
) -> ReadOnlyArray[String] {
  self.addresses
}

///|
/// Returns entries in the same canonical order as `addresses`.
pub fn RawRegisterSnapshot::entries(
  self : RawRegisterSnapshot,
) -> ReadOnlyArray[RawRegisterEntry] {
  self.entries
}

///|
/// A local draft supplied by the editor.
pub struct DraftObservation {
  address : String
  text : String
}

///|
/// Constructs a draft observation.
pub fn DraftObservation::DraftObservation(
  address : String,
  text : String,
) -> DraftObservation {
  { address, text }
}

///|
/// Returns the draft address.
pub fn DraftObservation::address(self : DraftObservation) -> String {
  self.address
}

///|
/// Returns draft text.
pub fn DraftObservation::text(self : DraftObservation) -> String {
  self.text
}

///|
/// State retained for one canonical cell.
pub struct CellProjectionState {
  address : String
  last_seen_register : RegisterObservation
  last_good_source : String?
  diagnostic : ProjectionDiagnostic?
} derive(Eq, Debug)

///|
/// Returns the address.
pub fn CellProjectionState::address(self : CellProjectionState) -> String {
  self.address
}

///|
/// Returns the last authoritative register observation.
pub fn CellProjectionState::last_seen_register(
  self : CellProjectionState,
) -> RegisterObservation {
  self.last_seen_register
}

///|
/// Returns the last successfully parsed source.
pub fn CellProjectionState::last_good_source(
  self : CellProjectionState,
) -> String? {
  self.last_good_source
}

///|
/// Returns the current diagnostic.
pub fn CellProjectionState::diagnostic(
  self : CellProjectionState,
) -> ProjectionDiagnostic? {
  self.diagnostic
}

///|
/// Immutable projection state.
pub struct ProjectionState {
  cells : ReadOnlyArray[CellProjectionState]
} derive(Eq, Debug)

///|
/// Creates an empty canonical state.
pub fn ProjectionState::empty(addresses : Array[String]) -> ProjectionState {
  ProjectionState::canonical(addresses, None)
}

///|
/// Creates state from canonical addresses and optional prior cells.
fn ProjectionState::canonical(
  addresses : Array[String],
  prior : Array[CellProjectionState]?,
) -> ProjectionState {
  let unique_addresses = []
  let seen : Map[String, Bool] = Map::from_array([])
  for address in addresses {
    if seen.get(address) is None {
      seen[address] = true
      unique_addresses.push(address)
    }
  }
  let old : Map[String, CellProjectionState] = Map::from_array([])
  match prior {
    Some(xs) =>
      for x in xs {
        old[x.address] = x
      }
    None => ()
  }
  let cells = []
  for address in unique_addresses {
    match old.get(address) {
      Some(cell) => cells.push(cell)
      None =>
        cells.push({
          address,
          last_seen_register: RegisterObservation::Unset,
          last_good_source: None,
          diagnostic: None,
        })
    }
  }
  ProjectionState::{ cells: ReadOnlyArray::from_array(cells) }
}

///|
/// Returns cells in canonical order.
pub fn ProjectionState::cells(
  self : ProjectionState,
) -> ReadOnlyArray[CellProjectionState] {
  self.cells
}

///|
/// Looks up a cell by address.
pub fn ProjectionState::cell(
  self : ProjectionState,
  address : String,
) -> CellProjectionState? {
  for cell in self.cells {
    if cell.address == address {
      return Some(cell)
    }
  }
  None
}

///|
/// A command emitted for an adapter shell.
pub(all) enum ProjectionDecision {
  ApplyWorksheet(@demo.SheetOp)
  SetCommitted(String, String?)
  SetDraft(String, String?)
  SetDiagnostic(String, ProjectionDiagnostic?)
}

///|
/// Pure result of one projection pass.
pub struct ProjectionTransition {
  candidate_state : ProjectionState
  decisions : ReadOnlyArray[ProjectionDecision]
  diagnostics : ReadOnlyArray[ProjectionDiagnostic]
}

///|
/// Returns the candidate state.
pub fn ProjectionTransition::candidate_state(
  self : ProjectionTransition,
) -> ProjectionState {
  self.candidate_state
}

///|
/// Returns ordered decisions.
pub fn ProjectionTransition::decisions(
  self : ProjectionTransition,
) -> ReadOnlyArray[ProjectionDecision] {
  self.decisions
}

///|
/// Returns current diagnostics in canonical order.
pub fn ProjectionTransition::diagnostics(
  self : ProjectionTransition,
) -> ReadOnlyArray[ProjectionDiagnostic] {
  self.diagnostics
}
