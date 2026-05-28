///|
/// Identifier for a logical sheet in a workbook.
///
/// Keep sheet ids stable for the same logical sheet so cell ids can be compared
/// or stored without reconstructing the sheet wrapper.
pub struct SheetId {
  value : Int
} derive(Eq, Debug)

///|
/// Creates a `SheetId`.
pub fn SheetId::SheetId(value : Int) -> SheetId {
  { value, }
}

///|
/// Hash for `SheetId` so it can be used in `HashMap` keys.
pub impl Hash for SheetId with fn hash(self) {
  self.value.hash()
}

///|
/// Hash combine for `SheetId`.
pub impl Hash for SheetId with fn hash_combine(self, hasher) {
  self.value.hash_combine(hasher)
}

///|
/// Identifier for a typed spreadsheet cell.
///
/// A `CellId` is stable for a given sheet+address pair and can be used as a
/// map key for cell registration and cache lookups.
pub struct CellId {
  sheet_id : SheetId
  address : String
} derive(Eq, Debug)

///|
/// Creates a `CellId`.
pub fn CellId::CellId(sheet_id : SheetId, address : String) -> CellId {
  { sheet_id, address }
}

///|
/// Returns a convenience identifier for a sheet-local textual address.
pub fn CellId::of(sheet_id : SheetId, address : String) -> CellId {
  CellId::CellId(sheet_id, address)
}

///|
/// Hash for `CellId`.
pub impl Hash for CellId with fn hash(self) {
  self.sheet_id.hash() * 31 + self.address.hash()
}

///|
/// Hash combine for `CellId`.
pub impl Hash for CellId with fn hash_combine(self, hasher) {
  self.hash().hash_combine(hasher)
}
