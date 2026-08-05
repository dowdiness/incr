///|
test "transparent getter and updater compile" {
  inspect(probe_transparent_input(), content="5")
}

///|
test "opaque View and writer compile" {
  inspect(probe_opaque_input(), content="5")
}

///|
test "two-layer product getter and kernel handle compile" {
  inspect(probe_two_layer_input(), content="5")
}

///|
test "opaque handles preserve metadata and provenance" {
  inspect(probe_opaque_metadata(), content="true")
}

///|
test "recoverable cycle remains available through honest reads" {
  inspect(probe_recoverable_cycle(), content="41")
}

///|
test "two-layer getter fits a UI-shaped binding" {
  inspect(probe_ui_binding(), content="7")
}
