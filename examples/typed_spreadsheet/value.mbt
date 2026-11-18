///|
/// A typed value for spreadsheet cells.
#derive(Eq, Debug)
pub enum CellValue {
  Int(Int32)
  Bool(Bool)
  Text(String)
  /// A first-class blank value, also returned for absent same-sheet cells.
  Blank
}

///|
pub extend CellValue with Eq::{not_equal, equal}

///|
pub extend CellValue with Debug::{to_repr}

///|
/// Creates an integer spreadsheet value.
pub fn CellValue::from_int(value : Int32) -> CellValue {
  Int(value)
}

///|
/// Creates a boolean spreadsheet value.
pub fn CellValue::from_bool(value : Bool) -> CellValue {
  Bool(value)
}

///|
/// Creates a text spreadsheet value.
pub fn CellValue::from_text(value : String) -> CellValue {
  Text(value)
}

///|
/// Creates a blank spreadsheet value.
pub fn CellValue::blank() -> CellValue {
  Blank
}

///|
/// The static kind of a spreadsheet value.
#derive(Eq, Debug)
pub enum CellType {
  TInt
  TBool
  TString
  TBlank
  TAny
}

///|
pub extend CellType with Eq::{not_equal, equal}

///|
pub extend CellType with Debug::{to_repr}

///|
/// Constructs the `TInt` cell type.
pub fn CellType::t_int() -> CellType {
  CellType::TInt
}

///|
/// Constructs the `TBool` cell type.
pub fn CellType::t_bool() -> CellType {
  CellType::TBool
}

///|
/// Constructs the `TString` cell type.
pub fn CellType::t_string() -> CellType {
  CellType::TString
}

///|
/// Constructs the `TBlank` cell type.
pub fn CellType::t_blank() -> CellType {
  CellType::TBlank
}

///|
/// Constructs the `TAny` cell type.
pub fn CellType::t_any() -> CellType {
  CellType::TAny
}

///|
/// Public result type for typed spreadsheet reads and evaluates.
#derive(Eq, Debug)
pub enum CellResult {
  Ok(CellValue)
  ParseError(String)
  TypeError(String)
  RefError(String)
  CycleError(String)
}

///|
pub extend CellResult with Eq::{not_equal, equal}

///|
pub extend CellResult with Debug::{to_repr}

///|
/// Errors returned by worksheet operations during installation.
#derive(Eq, Debug)
pub enum WorksheetError {
  RefError(String)
}

///|
pub extend WorksheetError with Eq::{not_equal, equal}

///|
pub extend WorksheetError with Debug::{to_repr}

///|
/// Constructs a successful cell result.
pub fn CellResult::ok(value : CellValue) -> CellResult {
  Ok(value)
}

///|
/// Constructs a worksheet-level reference error.
pub fn WorksheetError::ref_error(message : String) -> WorksheetError {
  RefError(message)
}

///|
/// Constructs a parse error result.
pub fn CellResult::parse_error(message : String) -> CellResult {
  ParseError(message)
}

///|
/// Constructs a type error result.
pub fn CellResult::type_error(message : String) -> CellResult {
  TypeError(message)
}

///|
/// Constructs a reference error result.
pub fn CellResult::ref_error(message : String) -> CellResult {
  RefError(message)
}

///|
/// Constructs a cycle error result.
pub fn CellResult::cycle_error(message : String) -> CellResult {
  CycleError(message)
}

///|
/// Returns the dynamic kind of a `CellValue`.
pub fn CellValue::cell_type(self : CellValue) -> CellType {
  match self {
    Int(_) => CellType::TInt
    Bool(_) => CellType::TBool
    Text(_) => CellType::TString
    Blank => CellType::TBlank
  }
}

///|
/// Returns whether this `CellType` accepts the given value.
pub fn CellType::accepts(self : CellType, value : CellValue) -> Bool {
  match self {
    CellType::TAny => true
    CellType::TInt => value is Int(_)
    CellType::TBool => value is Bool(_)
    CellType::TString => value is Text(_)
    CellType::TBlank => value is Blank
  }
}

///|
/// Human-readable name for diagnostics.
pub fn CellType::to_string(self : CellType) -> String {
  match self {
    CellType::TInt => "Int"
    CellType::TBool => "Bool"
    CellType::TString => "String"
    CellType::TBlank => "Blank"
    CellType::TAny => "Any"
  }
}

///|
/// Returns true when this result represents a valid value.
pub fn CellResult::is_ok(self : CellResult) -> Bool {
  match self {
    CellResult::Ok(_) => true
    _ => false
  }
}
