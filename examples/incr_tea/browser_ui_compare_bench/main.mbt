///|
/// Entry point and suite dispatch for the adjacent-framework mounted matrix.

///|
fn ui_compare_adjacent_run(
  system : String,
  suite : String,
  operation : String,
  n : Int,
  iterations : Int,
  sample_count : Int,
) -> String {
  match suite {
    "counter" =>
      ui_compare_adjacent_run_counter(
        system, operation, iterations, sample_count,
      )
    "keyed-list" | "keyed_list" | "list" =>
      ui_compare_adjacent_run_keyed_list(
        system, operation, n, iterations, sample_count,
      )
    "panel" | "hidden-panel" | "hidden_panel" =>
      ui_compare_adjacent_run_panel(system, operation, iterations, sample_count)
    _ => abort("unknown UI compare suite: \{suite}")
  }
}

///|
fn main {
  ui_compare_install_adjacent_api(ui_compare_adjacent_run)
}
