///|
fn install_typed_sheet_benchmark_api(app : TypedSheetApplication) -> Unit {
  if js_typed_sheet_benchmark_mode() {
    js_install_typed_sheet_benchmark_api(action => {
      benchmark_dispatch(app, action)
    })
  }
}

///|
fn benchmark_dispatch(app : TypedSheetApplication, action : String) -> Unit {
  match action {
    "select-c1" => ignore(app.dispatch(SelectCell("C1")))
    "draft-a1" => {
      ignore(app.dispatch(SelectCell("A1")))
      ignore(app.dispatch(UpdateDraft("A1", "15")))
    }
    "edit-a1" => {
      ignore(app.dispatch(SelectCell("A1")))
      ignore(app.dispatch(UpdateDraft("A1", "15")))
      ignore(app.dispatch(ApplySelected))
    }
    "edit-b1" => {
      ignore(app.dispatch(SelectCell("B1")))
      ignore(app.dispatch(UpdateDraft("B1", "=A1 * 2")))
      ignore(app.dispatch(ApplySelected))
    }
    "edit-ax50" => {
      ignore(app.dispatch(SelectCell("AX50")))
      ignore(app.dispatch(UpdateDraft("AX50", "17")))
      ignore(app.dispatch(ApplySelected))
    }
    _ => abort("unknown typed spreadsheet benchmark action: \\{action}")
  }
  ignore(app.flush_presentation())
}

///|
#cfg(target="js")
extern "js" fn js_typed_sheet_benchmark_mode() -> Bool =
  #| () =>
  #|   globalThis.__typedSpreadsheetBenchMode === true ||
  #|   new URLSearchParams(globalThis.location.search).has("bench")

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
