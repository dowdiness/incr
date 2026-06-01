///|
struct GridCellSnapshot {
  present : Bool
  kind : @typed_spreadsheet.CellKind?
  result : @typed_spreadsheet.CellResult
}

///|
fn grid_snapshot_for(model : Model, cell : String) -> GridCellSnapshot {
  match model.grid_snapshot_cache.get(cell) {
    Some(snapshot) => snapshot
    None => missing_grid_cell_snapshot()
  }
}

///|
fn missing_grid_cell_snapshot() -> GridCellSnapshot {
  {
    present: false,
    kind: None,
    result: @typed_spreadsheet.CellResult::ok(
      @typed_spreadsheet.CellValue::blank(),
    ),
  }
}

///|
fn grid_cell_snapshot_from(
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> GridCellSnapshot {
  { present: snapshot.present, kind: snapshot.kind, result: snapshot.result }
}

///|
fn refresh_grid_snapshot_cache(
  model : Model,
  result : @demo.WorksheetStepResult,
) -> @hashmap.HashMap[String, GridCellSnapshot] {
  let next = model.grid_snapshot_cache.copy()
  for change in result.cell_snapshots {
    update_grid_snapshot(next, change.after)
  }
  for id in result.trace.changed {
    update_grid_snapshot(next, model.sheet.inspect_cell(id))
  }
  next
}

///|
fn update_grid_snapshot(
  cache : @hashmap.HashMap[String, GridCellSnapshot],
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> Unit {
  let cell = @demo.cell_id_to_string(snapshot.id)
  if snapshot.present {
    cache.set(cell, grid_cell_snapshot_from(snapshot))
  } else {
    cache.remove(cell)
  }
}
