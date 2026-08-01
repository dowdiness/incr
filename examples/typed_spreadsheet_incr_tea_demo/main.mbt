///|
fn main {
  mount_typed_spreadsheet_incr_tea_demo("app")
}

///|
/// Standalone remains the original fixed seed application.
pub fn mount_typed_spreadsheet_incr_tea_demo(mount_id : String) -> Unit {
  match parse_startup(js_collab_startup_input()) {
    Ok(StartupMode::Standalone) => {
      let app = match
        TypedSheetApplication::start(
          @incr.Runtime(),
          SheetStartMode::Standalone,
          None,
          AiContextPublisher::production(),
        ) {
        Ok(app) => app
        Err(AuthorityStartFailed(error)) => {
          println("Typed spreadsheet startup failed: \{error}")
          return
        }
      }
      let hosts = match resolve_typed_sheet_hosts(mount_id) {
        Ok(hosts) => hosts
        Err(MissingRegion(id)) => {
          println("Typed spreadsheet region is missing: \{id}")
          app.dispose()
          return
        }
      }
      match app.mount(hosts) {
        Ok(_) => install_typed_sheet_benchmark_api(app)
        Err(_) => app.dispose()
      }
    }
    Ok(StartupMode::RoomChooser) => show_room_chooser()
    Ok(mode) => start_collaboration(mode)
    Err(error) => js_collab_show_status(format_startup_error(error))
  }
}
