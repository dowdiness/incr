///|
suberror CallbackTestError {
  CallbackDepthStop
}

///|
fn new_runtime_core_for_wbtest() -> RuntimeCore {
  {
    runtime_id: alloc_runtime_id(),
    revision: {
      current_revision: Revision::initial(),
      durability_last_changed: FixedArray::make(
        @incr_types.DURABILITY_COUNT,
        Revision::initial(),
      ),
    },
    next_cell_id: 0,
    tracking: { stack: [] },
    batch: { depth: 0, pending: [], frames: [], max_durability: Low },
    callback_depth: 0,
    on_change_listeners: ListenerRegistry::new(),
    next_listener_id: 0,
    cell_index: [],
    cell_ops: [],
    phase: Idle,
    gc_root_counts: @hashmap.HashMap([]),
  }
}

///|
test "run_callback restores callback_depth when callback raises" {
  let core = new_runtime_core_for_wbtest()
  let mut callback_failed = false
  try
    run_callback(core, fn() raise { raise CallbackTestError::CallbackDepthStop })
  catch {
    _ => callback_failed = true
  } noraise {
    _ => ()
  }
  inspect(callback_failed, content="true")
  inspect(core.callback_depth, content="0")
}
