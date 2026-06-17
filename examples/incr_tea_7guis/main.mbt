///|
fn main {
  mount_incr_tea_7guis("app")
}

///|
/// Mounts each 7GUIs task into its own `incr_tea` root.
pub fn mount_incr_tea_7guis(mount_id : String) -> Unit {
  let app = @tea.dom_get_element_by_id(mount_id)
  @counter.mount(@tea.dom_query_child_by_id(app, "counter-root"))
  @temperature_converter.mount(
    @tea.dom_query_child_by_id(app, "temperature-root"),
  )
  @flight_booker.mount(@tea.dom_query_child_by_id(app, "flight-root"))
  @timer.mount(@tea.dom_query_child_by_id(app, "timer-root"))
  @crud.mount(@tea.dom_query_child_by_id(app, "crud-root"))
  @circle_drawer.mount(@tea.dom_query_child_by_id(app, "circle-root"))
  @cells.mount(@tea.dom_query_child_by_id(app, "cells-root"))
}
