///|
/// Number of columns in the canonical worksheet grid.
pub fn grid_column_count() -> Int {
  50
}

///|
/// Number of rows in the canonical worksheet grid.
pub fn grid_row_count() -> Int {
  50
}

///|
/// Canonical spreadsheet column labels.
pub fn column_labels() -> Array[String] {
  [
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
    "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "AA", "AB", "AC", "AD", "AE",
    "AF", "AG", "AH", "AI", "AJ", "AK", "AL", "AM", "AN", "AO", "AP", "AQ", "AR",
    "AS", "AT", "AU", "AV", "AW", "AX",
  ]
}

///|
/// Returns all canonical addresses in row-major order.
pub fn grid_cells() -> Array[String] {
  let cells = []
  for row in 1..<=grid_row_count() {
    for column in column_labels() {
      cells.push("\{column}\{row}")
    }
  }
  cells
}
