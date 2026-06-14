///|
/// Suite dispatch and public installer for the `incr_tea` mounted matrix.

///|
#cfg(target="js")
fn ui_compare_incr_run(
  suite : String,
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  match suite {
    "counter" =>
      ui_compare_incr_run_counter(operation, iterations, sample_count)
    "keyed-list" | "keyed_list" | "list" =>
      ui_compare_incr_run_keyed_list(operation, n, iterations, sample_count)
    "panel" | "hidden-panel" | "hidden_panel" =>
      ui_compare_incr_run_panel(operation, iterations, sample_count)
    _ => abort("unknown UI compare suite: \{suite}")
  }
}

///|
/// Installs the `incr_tea` side of `window.__incrTeaUiCompareDomBench`.
#cfg(target="js")
pub fn install_ui_compare_dom_bench_api() -> Unit {
  ui_compare_dom_install_incr_api(ui_compare_incr_run)
}
