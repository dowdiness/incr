///|
fn main {
  mount_typed_spreadsheet_incr_tea_demo("app")
}

///|
/// Mounts the side-by-side `incr_tea` typed spreadsheet proof.
pub fn mount_typed_spreadsheet_incr_tea_demo(mount_id : String) -> Unit {
  let runtime = @incr.Runtime()
  let app = TypedSheetApp(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(
    renderer.mount(
      @tea.dom_get_element_by_id(mount_id),
      app.program,
      on_input=resolve_text_input,
      on_key_event=resolve_key_event,
    ),
  )
}
