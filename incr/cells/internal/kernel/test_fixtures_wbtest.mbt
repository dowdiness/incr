///|
/// Builds a bare `RuntimeCore` for kernel whitebox tests without going through
/// `cells/`'s `Runtime` constructor. Kernel tests must not import `cells/`
/// (the one-way isolation invariant enforced by
/// `scripts/check-engine-isolation.sh`), so the initialization of the `core`
/// sub-struct is mirrored here from `Runtime::Runtime`. Only the fields kernel
/// algorithms read/write are populated; engine SoA state lives on the sibling
/// structs and is constructed by tests that need it.
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
