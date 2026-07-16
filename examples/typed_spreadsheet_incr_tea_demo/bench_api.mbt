///|
fn install_typed_sheet_benchmark_api(
  app : TypedSheetApp,
  renderer : @tea.BrowserRenderer[Msg],
) -> Unit {
  if js_typed_sheet_benchmark_mode() {
    js_install_typed_sheet_benchmark_api(action => {
      benchmark_dispatch(app, renderer, action)
    })
  }
}

///|
fn benchmark_dispatch(
  app : TypedSheetApp,
  renderer : @tea.BrowserRenderer[Msg],
  action : String,
) -> Unit {
  match action {
    "select-c1" => ignore(app.prog_grid.dispatch(SelectCell("C1")))
    "draft-a1" => {
      ignore(app.prog_grid.dispatch(SelectCell("A1")))
      ignore(app.prog_grid.dispatch(UpdateDraft("A1", "15")))
    }
    "edit-a1" => {
      ignore(app.prog_grid.dispatch(SelectCell("A1")))
      ignore(app.prog_grid.dispatch(UpdateDraft("A1", "15")))
      ignore(app.prog_grid.dispatch(ApplySelected))
    }
    "edit-b1" => {
      ignore(app.prog_grid.dispatch(SelectCell("B1")))
      ignore(app.prog_grid.dispatch(UpdateDraft("B1", "=A1 * 2")))
      ignore(app.prog_grid.dispatch(ApplySelected))
    }
    "edit-ax50" => {
      ignore(app.prog_grid.dispatch(SelectCell("AX50")))
      ignore(app.prog_grid.dispatch(UpdateDraft("AX50", "17")))
      ignore(app.prog_grid.dispatch(ApplySelected))
    }
    _ => abort("unknown typed spreadsheet benchmark action: \\{action}")
  }
  renderer.flush_all()
}

///|
#cfg(target="js")
extern "js" fn js_typed_sheet_benchmark_mode() -> Bool =
  #| () => new URLSearchParams(globalThis.location.search).has("bench")

///|
#cfg(target="js")
extern "js" fn js_install_typed_sheet_benchmark_api(
  run : (String) -> Unit,
) -> Unit =
  #| (run) => {
  #|   globalThis.__typedSpreadsheetBench = {
  #|     dispatch: action => run(String(action)),
  #|   };
  #| }
