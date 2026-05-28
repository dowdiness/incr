///|
/// A typed value for spreadsheet cells.
pub enum CellValue {
  Int(Int)
  Bool(Bool)
  Text(String)
  Blank
} derive(Eq, Debug)

///|
/// Creates an integer spreadsheet value.
pub fn CellValue::from_int(value : Int) -> CellValue {
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
pub enum CellType {
  TInt
  TBool
  TString
  TBlank
  TAny
} derive(Eq, Debug)

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
pub enum CellResult {
  Ok(CellValue)
  ParseError(String)
  TypeError(String)
  RefError(String)
  CycleError(String)
} derive(Eq, Debug)

///|
/// Errors returned by worksheet operations during installation.
pub enum WorksheetError {
  RefError(String)
} derive(Eq, Debug)

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
