///|
fn main {
  mount_typed_spreadsheet_incr_tea_demo("app")
}

///|
/// Mounts the side-by-side `incr_tea` typed spreadsheet proof with 5
/// independent watched roots (grid, formula bar, status, trace, evidence)
/// sharing model state via per-region InputFields.
pub fn mount_typed_spreadsheet_incr_tea_demo(mount_id : String) -> Unit {
  let runtime = @incr.Runtime()
  let app = TypedSheetApp(runtime) catch {
    error => {
      println(
        "Typed spreadsheet startup failed: \{format_authority_error(error)}",
      )
      return
    }
  }
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  // Mount each region as an independent root. All share the same update
  // handler (handle_msg) and the same InputFields, but each reads only
  // its own slice, so unchanged roots skip DOM patching.
  ignore(
    renderer.mount(
      @tea.dom_get_element_by_id(mount_id + "-formula"),
      app.prog_formula,
      label="formula-bar",
      on_value=resolve_value,
      on_key_event=resolve_key_event,
    ),
  )
  ignore(
    renderer.mount(
      @tea.dom_get_element_by_id(mount_id + "-grid"),
      app.prog_grid,
      label="grid",
      on_value=resolve_value,
      on_key_event=resolve_key_event,
    ),
  )
  ignore(
    renderer.mount(
      @tea.dom_get_element_by_id(mount_id + "-status"),
      app.prog_status,
      label="status",
    ),
  )
  ignore(
    renderer.mount(
      @tea.dom_get_element_by_id(mount_id + "-trace"),
      app.prog_trace,
      label="trace",
    ),
  )
  ignore(
    renderer.mount(
      @tea.dom_get_element_by_id(mount_id + "-evidence"),
      app.prog_evidence,
      label="evidence",
    ),
  )
  js_publish_ai_context_json(app._state.val.ai_context_json())
  install_typed_sheet_benchmark_api(app, renderer)
}
