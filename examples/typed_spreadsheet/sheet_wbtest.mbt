///|
test "typed spreadsheet tombstones: repeated create/delete retains slots until compaction" {
  let rt = @incr.Runtime()
  let sheet = Worksheet(rt, SheetId(130))

  for i in 0..<5 {
    let id = CellId(sheet.sheet_id(), "A" + i.to_string())
    ignore(sheet.set_input(id, CellValue::from_int(i)))
    match sheet.delete(id) {
      CellResult::Ok(_) => ()
      _ => abort("delete should leave a tombstone")
    }
  }

  inspect(sheet.cells.length(), content="5")
  inspect(sheet.cell_presence.length(), content="5")

  inspect(sheet.compact_deleted_cells(), content="5")
  inspect(sheet.cells.length(), content="0")
  inspect(sheet.cell_presence.length(), content="5")
}

///|
test "typed spreadsheet tombstones: compaction keeps presence anchor for recreation" {
  let rt = @incr.Runtime()
  let sheet = Worksheet(rt, SheetId(131))
  let cell = CellId(sheet.sheet_id(), "A1")

  ignore(sheet.set_input(cell, CellValue::from_int(1)))
  let anchor_before = match sheet.cell_presence.get(cell) {
    Some(anchor) => anchor.id()
    None => abort("expected presence anchor after creation")
  }
  match sheet.delete(cell) {
    CellResult::Ok(_) => ()
    _ => abort("delete should leave a tombstone")
  }

  inspect(sheet.compact_deleted_cells(), content="1")
  inspect(sheet.cells.length(), content="0")
  inspect(sheet.cell_presence.length(), content="1")

  ignore(sheet.set_input(cell, CellValue::from_int(2)))
  let anchor_after = match sheet.cell_presence.get(cell) {
    Some(anchor) => anchor.id()
    None => abort("expected presence anchor after recreation")
  }
  inspect(anchor_before == anchor_after, content="true")
  inspect(sheet.cells.length(), content="1")
  inspect(sheet.cell_presence.length(), content="1")
  match sheet.read(cell) {
    CellResult::Ok(CellValue::Int(value)) => inspect(value, content="2")
    _ => abort("expected recreated cell value")
  }
}
