///|
struct RootValue {
  value : Int
  nonce : Int
}

///|
impl @fresh.CutoffEq for RootValue with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
impl @incremental.CutoffEq for RootValue with fn cutoff_equal(self, other) {
  self.value == other.value
}

///|
fn mount_value(mount : @incremental.Mount[Int]) -> Int {
  match mount.current() {
    Ok(Ok(value)) => value
    _ => abort("unexpected mount value")
  }
}

///|
fn mount_root_value(mount : @incremental.Mount[RootValue]) -> RootValue {
  match mount.current() {
    Ok(Ok(value)) => value
    _ => abort("unexpected root mount value")
  }
}

///|
fn fresh_mount_root_value(mount : @fresh.Mount[RootValue]) -> RootValue {
  match mount.current() {
    Ok(Ok(value)) => value
    _ => abort("unexpected fresh root mount value")
  }
}

///|
fn fresh_region_or_abort(
  result : Result[@fresh.Region, @fresh.RegionError],
) -> @fresh.Region {
  match result {
    Ok(value) => value
    Err(_) => abort("fresh region")
  }
}

///|
fn[T] fresh_source_or_abort(
  result : Result[@fresh.Source[T], @fresh.RegionError],
) -> @fresh.Source[T] {
  match result {
    Ok(value) => value
    Err(_) => abort("fresh source")
  }
}

///|
fn mount_initial_and_selective() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = fresh_region_or_abort(fresh_store.region())
  let fresh_source = fresh_source_or_abort(fresh_region.source(1))
  let fresh_unrelated = fresh_source_or_abort(fresh_region.source(9))
  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_source = must_inc_source(inc_region.source(1))
  let inc_unrelated = must_inc_source(inc_region.source(9))
  let fresh_mount = must_fresh_mount(fresh_store.mount(fresh_source.view()))
  let mount = must_inc_mount(inc_store.mount(inc_source.view()))
  let fresh_initial = match fresh_mount.current() {
    Ok(Ok(value)) => value
    _ => -1
  }
  let initial = mount_value(mount) == fresh_initial
  let before = mount.debug()
  ignore(inc_store.transaction(tx => tx.set(inc_unrelated, 10)))
  let skipped = mount_value(mount) == 1 &&
    mount.debug().wake_count == before.wake_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_unrelated, 10)))
  let fresh_after = match fresh_mount.current() {
    Ok(Ok(value)) => value
    _ => -1
  }
  let parity = fresh_after == mount_value(mount)
  fresh_mount.dispose()
  mount.dispose()
  ignore(fresh_region.close())
  ignore(inc_region.close())
  initial && skipped && parity
}

///|
fn mount_transaction_and_clock() -> Bool {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let left = must_inc_source(region.source(1))
  let right = must_inc_source(region.source(2))
  let unrelated = must_inc_source(region.source(100))
  let sum = must_inc_query(
    region.query((ctx, _ : Unit) => {
      match (ctx.read(left.view()), ctx.read(right.view())) {
        (Ok(a), Ok(b)) => Ok(a + b)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    }),
  )
  let mount = must_inc_mount(store.mount(sum.at(())))
  let initial = mount_value(mount) == 3 && mount.debug().evaluation_count == 1
  ignore(
    store.transaction(tx => {
      ignore(tx.set(left, 10))
      tx.set(right, 20)
    }),
  )
  let one_rerun = mount_value(mount) == 30 && mount.debug().wake_count == 2
  let before = mount.debug().wake_count
  ignore(store.transaction(_ => Ok(())))
  let empty = mount.debug().wake_count == before
  ignore(
    store.transaction(tx => {
      ignore(tx.set(unrelated, 101))
      Err(@incremental.TransactionError::CallbackRejected)
    }),
  )
  let rollback = mount.debug().wake_count == before
  let clock_query = must_inc_query(
    region.query((ctx, _ : Unit) => Ok(ctx.revision().value())),
  )
  let clock_mount = must_inc_mount(store.mount(clock_query.at(())))
  let clock_before = clock_mount.debug().wake_count
  ignore(store.transaction(tx => tx.set(unrelated, 102)))
  let clock_woke = clock_mount.debug().wake_count == clock_before + 1
  mount.dispose()
  clock_mount.dispose()
  ignore(region.close())
  initial && one_rerun && empty && rollback && clock_woke
}

///|
fn mount_region_lifetime() -> Bool {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let source = must_inc_source(region.source(1))
  let mount = must_inc_mount(store.mount(source.view()))
  let before_rejected = mount.debug().wake_count
  ignore(
    store.transaction(_ => {
      ignore(region.close())
      Ok(())
    }),
  )
  let rejected_quiet = mount.debug().wake_count == before_rejected
  let closed = region.close() == Ok(()) &&
    mount.debug().wake_count == before_rejected + 1 &&
    mount.current() is Ok(Err(@incremental.ReadError::ClosedRegion(_)))
  let after_close = mount.debug().wake_count
  let duplicate_quiet = region.close()
    is Err(@incremental.RegionError::ClosedRegion(_)) &&
    mount.debug().wake_count == after_close
  mount.dispose()
  rejected_quiet && closed && duplicate_quiet
}

///|
fn mount_region_dynamic_failure_cycle() -> Bool {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let mode = must_inc_source(region.source(0))
  let left = must_inc_source(region.source(2))
  let right = must_inc_source(region.source(4))
  let dynamic = must_inc_query(
    region.query_eq((ctx, _ : Unit) => {
      match ctx.read(mode.view()) {
        Ok(0) => ctx.read(left.view())
        Ok(_) => ctx.read(right.view())
        Err(error) => Err(error)
      }
    }),
  )
  let mount = must_inc_mount(store.mount(dynamic.at(())))
  let initial = mount_value(mount) == 2
  ignore(store.transaction(tx => tx.set(mode, 1)))
  let switched = mount_value(mount) == 4
  let before_left = mount.debug().wake_count
  ignore(store.transaction(tx => tx.set(left, 3)))
  let old_branch_skipped = mount.debug().wake_count == before_left
  ignore(store.transaction(tx => tx.set(right, 5)))
  let new_branch_woke = mount_value(mount) == 5

  let failing = must_inc_query(
    region.query((ctx, _ : Unit) => {
      match ctx.read(mode.view()) {
        Ok(1) =>
          Err(
            @incremental.ReadError::ClosedRegion(generation=region.generation()),
          )
        Ok(_) => Ok(7)
        Err(error) => Err(error)
      }
    }),
  )
  let failed_mount = must_inc_mount(store.mount(failing.at(())))
  let failed = failed_mount.current() is Ok(Err(_)) &&
    failed_mount.debug().failed_attempt_footprint_length > 0
  ignore(store.transaction(tx => tx.set(mode, 0)))
  let recovered = failed_mount.current() is Ok(Ok(7)) &&
    failed_mount.debug().failed_attempt_footprint_length == 0

  let cycle_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let cycle = must_inc_query(
    region.query((ctx, _ : Unit) => {
      match ctx.read(mode.view()) {
        Err(error) => Err(error)
        Ok(_) =>
          match cycle_ref.val {
            Some(query) => ctx.read(query.at(()))
            None => Ok(1)
          }
      }
    }),
  )
  cycle_ref.val = Some(cycle)
  let cycle_mount = must_inc_mount(store.mount(cycle.at(())))
  let cycle_seen = cycle_mount.current()
    is Ok(Err(@incremental.ReadError::Cycle(_)))
  cycle_ref.val = None
  ignore(store.transaction(tx => tx.set(mode, 0)))
  let cycle_recovered = cycle_mount.current() is Ok(Ok(1))
  mount.dispose()
  failed_mount.dispose()
  cycle_mount.dispose()
  ignore(region.close())
  let passed = initial &&
    switched &&
    old_branch_skipped &&
    new_branch_woke &&
    failed &&
    recovered &&
    cycle_seen &&
    cycle_recovered
  println(
    "dynamic initial=\{initial} switched=\{switched} old=\{old_branch_skipped} new=\{new_branch_woke} failed=\{failed} recovered=\{recovered} cycle=\{cycle_seen} cycle_recovered=\{cycle_recovered}",
  )
  passed
}

///|
fn mount_cutoff_eviction_dispose() -> Bool {
  let store = @incremental.Store()
  let region = must_inc_region(store.region())
  let source = must_inc_source(region.source(1))
  let root = must_inc_query(
    region.query_type_owned((ctx, _ : Unit) => {
      let value = match ctx.read(source.view()) {
        Ok(value) => value
        Err(_) => -1
      }
      Ok(RootValue::{ value, nonce: ctx.revision().value() })
    }),
  )
  let mount = must_inc_mount(store.mount(root.at(())))
  let initial = mount_root_value(mount).nonce == 0
  ignore(store.transaction(tx => tx.set(source, 1)))
  let newest = mount_root_value(mount).nonce == 1
  let root_wake_before = mount.debug().wake_count
  ignore(root.evict_memo(()))
  let root_eviction_quiet = mount.debug().wake_count == root_wake_before &&
    mount_root_value(mount).nonce == 1
  let child = must_inc_query(
    region.query_eq((ctx, _ : Unit) => ctx.read(source.view())),
  )
  let parent = must_inc_query(
    region.query_always_changed((ctx, _ : Unit) => ctx.read(child.at(()))),
  )
  let child_mount = must_inc_mount(store.mount(parent.at(())))
  let parent_before = parent.debug().compute_count
  ignore(store.transaction(tx => tx.set(source, 1)))
  let child_cutoff_skips_parent = child_mount.current() is Ok(Ok(1)) &&
    parent.debug().compute_count == parent_before
  let child_wake_before_evict = child_mount.debug().wake_count
  ignore(child.evict_memo(()))
  let eviction_quiet = child_mount.debug().wake_count == child_wake_before_evict &&
    store.debug().active_edge_count > 0
  ignore(store.transaction(tx => tx.set(source, 3)))
  let rematerialized = child_mount.current() is Ok(Ok(3)) &&
    parent.debug().compute_count == parent_before + 1
  let root_rematerialized = mount_root_value(mount).value == 3 &&
    mount.debug().wake_count == root_wake_before + 2
  let before_dispose = store.debug().mount_count
  mount.dispose()
  mount.dispose()
  child_mount.dispose()
  child_mount.dispose()
  let disposed = mount.current()
    is Err(@incremental.MountError::DisposedMount(_)) &&
    store.debug().mount_count == before_dispose - 2 &&
    store.debug().active_edge_count == 0
  ignore(region.close())
  let passed = initial &&
    newest &&
    root_eviction_quiet &&
    child_cutoff_skips_parent &&
    eviction_quiet &&
    rematerialized &&
    root_rematerialized &&
    disposed
  println(
    "cutoff initial=\{initial} newest=\{newest} root_evict=\{root_eviction_quiet} child_cutoff=\{child_cutoff_skips_parent} child_evict=\{eviction_quiet} remat=\{rematerialized} root_remat=\{root_rematerialized} dispose=\{disposed}",
  )
  passed
}

///|
/// Normalizes mounted Int outcomes for exact Fresh/Incremental parity.
fn fresh_mount_int(mount : @fresh.Mount[Int]) -> String {
  match mount.current() {
    Ok(Ok(value)) => "Ok(\{value})"
    Ok(Err(@fresh.ReadError::ClosedRegion(_))) => "Err(ClosedRegion)"
    Ok(Err(@fresh.ReadError::Cycle(_))) => "Err(Cycle)"
    Ok(Err(_)) => "Err(ReadError)"
    Err(@fresh.MountError::DisposedMount(_)) => "Err(DisposedMount)"
    Err(_) => "Err(MountError)"
  }
}

///|
fn inc_mount_int(mount : @incremental.Mount[Int]) -> String {
  match mount.current() {
    Ok(Ok(value)) => "Ok(\{value})"
    Ok(Err(@incremental.ReadError::ClosedRegion(_))) => "Err(ClosedRegion)"
    Ok(Err(@incremental.ReadError::Cycle(_))) => "Err(Cycle)"
    Ok(Err(_)) => "Err(ReadError)"
    Err(@incremental.MountError::DisposedMount(_)) => "Err(DisposedMount)"
    Err(_) => "Err(MountError)"
  }
}

///|
/// The Fresh oracle and Incremental scheduler agree after every turn.
fn mount_parity_turns() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = fresh_region_or_abort(fresh_store.region())
  let fresh_left = fresh_source_or_abort(fresh_region.source(1))
  let fresh_right = fresh_source_or_abort(fresh_region.source(2))
  let fresh_unrelated = fresh_source_or_abort(fresh_region.source(99))
  let fresh_sum = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => {
      match (ctx.read(fresh_left.view()), ctx.read(fresh_right.view())) {
        (Ok(a), Ok(b)) => Ok(a + b)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    }),
  )
  let fresh_mount = must_fresh_mount(fresh_store.mount(fresh_sum.at(())))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_left = must_inc_source(inc_region.source(1))
  let inc_right = must_inc_source(inc_region.source(2))
  let inc_unrelated = must_inc_source(inc_region.source(99))
  let inc_sum = must_inc_query(
    inc_region.query((ctx, _ : Unit) => {
      match (ctx.read(inc_left.view()), ctx.read(inc_right.view())) {
        (Ok(a), Ok(b)) => Ok(a + b)
        (Err(error), _) => Err(error)
        (_, Err(error)) => Err(error)
      }
    }),
  )
  let inc_mount = must_inc_mount(inc_store.mount(inc_sum.at(())))
  let initial = fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount) &&
    fresh_mount.debug().evaluation_count == 1 &&
    inc_mount.debug().evaluation_count == 1
  let fresh_before_unrelated = fresh_mount.debug().wake_count
  let inc_before_unrelated = inc_mount.debug().wake_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_unrelated, 100)))
  ignore(inc_store.transaction(tx => tx.set(inc_unrelated, 100)))
  let unrelated = fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount) &&
    fresh_mount.debug().wake_count == fresh_before_unrelated + 1 &&
    inc_mount.debug().wake_count == inc_before_unrelated
  let fresh_before_multi = fresh_mount.debug().wake_count
  let inc_before_multi = inc_mount.debug().wake_count
  ignore(
    fresh_store.transaction(tx => {
      ignore(tx.set(fresh_left, 10))
      tx.set(fresh_right, 20)
    }),
  )
  ignore(
    inc_store.transaction(tx => {
      ignore(tx.set(inc_left, 10))
      tx.set(inc_right, 20)
    }),
  )
  let multi_source = fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount) &&
    fresh_mount.debug().wake_count == fresh_before_multi + 1 &&
    inc_mount.debug().wake_count == inc_before_multi + 1
  let fresh_empty_before = fresh_mount.debug().wake_count
  let inc_empty_before = inc_mount.debug().wake_count
  ignore(fresh_store.transaction(_ => Ok(())))
  ignore(inc_store.transaction(_ => Ok(())))
  let empty = fresh_mount.debug().wake_count == fresh_empty_before &&
    inc_mount.debug().wake_count == inc_empty_before
  ignore(
    fresh_store.transaction(tx => {
      ignore(tx.set(fresh_left, 30))
      Err(@fresh.TransactionError::CallbackRejected)
    }),
  )
  ignore(
    inc_store.transaction(tx => {
      ignore(tx.set(inc_left, 30))
      Err(@incremental.TransactionError::CallbackRejected)
    }),
  )
  let rollback = fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount) &&
    fresh_mount.debug().wake_count == fresh_empty_before &&
    inc_mount.debug().wake_count == inc_empty_before
  let fresh_foreign_store = @fresh.Store()
  let fresh_foreign_region = fresh_region_or_abort(fresh_foreign_store.region())
  let fresh_foreign = fresh_source_or_abort(fresh_foreign_region.source(7))
  let inc_foreign_store = @incremental.Store()
  let inc_foreign_region = must_inc_region(inc_foreign_store.region())
  let inc_foreign = must_inc_source(inc_foreign_region.source(7))
  let fresh_poison_before = fresh_mount.debug().wake_count
  let inc_poison_before = inc_mount.debug().wake_count
  let fresh_poisoned = fresh_store.transaction(tx => {
    ignore(tx.set(fresh_foreign, 8))
    Ok(())
  }) is Err(@fresh.TransactionError::CrossStore(_))
  let inc_poisoned = inc_store.transaction(tx => {
    ignore(tx.set(inc_foreign, 8))
    Ok(())
  }) is Err(@incremental.TransactionError::CrossStore(_))
  let poisoned = fresh_poisoned &&
    inc_poisoned &&
    fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount) &&
    fresh_mount.debug().wake_count == fresh_poison_before &&
    inc_mount.debug().wake_count == inc_poison_before
  let fresh_clock = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => Ok(ctx.revision().value())),
  )
  let inc_clock = must_inc_query(
    inc_region.query((ctx, _ : Unit) => Ok(ctx.revision().value())),
  )
  let fresh_clock_mount = must_fresh_mount(
    fresh_store.mount(fresh_clock.at(())),
  )
  let inc_clock_mount = must_inc_mount(inc_store.mount(inc_clock.at(())))
  let fresh_clock_before = fresh_clock_mount.debug().wake_count
  let inc_clock_before = inc_clock_mount.debug().wake_count
  let fresh_sum_before_clock_turn = fresh_mount.debug().wake_count
  let inc_sum_before_clock_turn = inc_mount.debug().wake_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_unrelated, 101)))
  ignore(inc_store.transaction(tx => tx.set(inc_unrelated, 101)))
  let revision_clock = fresh_mount_int(fresh_clock_mount) ==
    inc_mount_int(inc_clock_mount) &&
    fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount) &&
    fresh_clock_mount.debug().wake_count == fresh_clock_before + 1 &&
    inc_clock_mount.debug().wake_count == inc_clock_before + 1 &&
    fresh_mount.debug().wake_count == fresh_sum_before_clock_turn + 1 &&
    inc_mount.debug().wake_count == inc_sum_before_clock_turn
  fresh_mount.dispose()
  inc_mount.dispose()
  fresh_clock_mount.dispose()
  inc_clock_mount.dispose()
  ignore(fresh_region.close())
  ignore(inc_region.close())
  ignore(fresh_foreign_region.close())
  ignore(inc_foreign_region.close())
  let passed = initial &&
    unrelated &&
    multi_source &&
    empty &&
    rollback &&
    poisoned &&
    revision_clock
  println(
    "mount_turns initial=\{initial} unrelated=\{unrelated} multi_source=\{multi_source} empty=\{empty} rollback=\{rollback} poisoned=\{poisoned} revision_clock=\{revision_clock}",
  )
  passed
}

///|
/// Every Region has its own close turn; Incremental selects by preseal token.
fn mount_region_close_selectivity() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_a = fresh_region_or_abort(fresh_store.region())
  let fresh_b = fresh_region_or_abort(fresh_store.region())
  let fresh_source_a = fresh_source_or_abort(fresh_a.source(1))
  let fresh_source_b = fresh_source_or_abort(fresh_b.source(2))
  let fresh_mount_a = must_fresh_mount(fresh_store.mount(fresh_source_a.view()))
  let fresh_mount_b = must_fresh_mount(fresh_store.mount(fresh_source_b.view()))
  let inc_store = @incremental.Store()
  let inc_a = must_inc_region(inc_store.region())
  let inc_b = must_inc_region(inc_store.region())
  let inc_source_a = must_inc_source(inc_a.source(1))
  let inc_source_b = must_inc_source(inc_b.source(2))
  let inc_mount_a = must_inc_mount(inc_store.mount(inc_source_a.view()))
  let inc_mount_b = must_inc_mount(inc_store.mount(inc_source_b.view()))
  let fresh_a_before = fresh_mount_a.debug().wake_count
  let fresh_b_before = fresh_mount_b.debug().wake_count
  let inc_a_before = inc_mount_a.debug().wake_count
  let inc_b_before = inc_mount_b.debug().wake_count
  let first_close = fresh_a.close() == Ok(()) && inc_a.close() == Ok(())
  let selective = fresh_mount_int(fresh_mount_a) == inc_mount_int(inc_mount_a) &&
    fresh_mount_int(fresh_mount_b) == inc_mount_int(inc_mount_b) &&
    fresh_mount_a.debug().wake_count == fresh_a_before + 1 &&
    fresh_mount_b.debug().wake_count == fresh_b_before + 1 &&
    inc_mount_a.debug().wake_count == inc_a_before + 1 &&
    inc_mount_b.debug().wake_count == inc_b_before
  let fresh_after = fresh_mount_a.debug().wake_count
  let inc_after = inc_mount_a.debug().wake_count
  let duplicate = fresh_a.close() is Err(@fresh.RegionError::ClosedRegion(_)) &&
    inc_a.close() is Err(@incremental.RegionError::ClosedRegion(_)) &&
    fresh_mount_a.debug().wake_count == fresh_after &&
    inc_mount_a.debug().wake_count == inc_after
  ignore(fresh_b.close())
  ignore(inc_b.close())
  fresh_mount_a.dispose()
  fresh_mount_b.dispose()
  inc_mount_a.dispose()
  inc_mount_b.dispose()
  let passed = first_close && selective && duplicate
  println(
    "mount_region first=\{first_close} selective=\{selective} duplicate=\{duplicate}",
  )
  passed
}

///|
/// A failed active attempt unions its new Source footprint for retry, then replaces it.
fn mount_failed_attempt_retry() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = fresh_region_or_abort(fresh_store.region())
  let fresh_mode = fresh_source_or_abort(fresh_region.source(false))
  let fresh_old = fresh_source_or_abort(fresh_region.source(1))
  let fresh_new = fresh_source_or_abort(fresh_region.source(2))
  let fresh_cycle = fresh_source_or_abort(fresh_region.source(true))
  let fresh_ref : Ref[@fresh.Query[Unit, Int]?] = Ref(None)
  let fresh_query = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => {
      match ctx.read(fresh_mode.view()) {
        Err(error) => Err(error)
        Ok(false) => ctx.read(fresh_old.view())
        Ok(true) =>
          match ctx.read(fresh_new.view()) {
            Err(error) => Err(error)
            Ok(value) =>
              match ctx.read(fresh_cycle.view()) {
                Err(error) => Err(error)
                Ok(true) =>
                  match fresh_ref.val {
                    Some(self) => ctx.read(self.at(()))
                    None => Ok(value)
                  }
                Ok(false) => Ok(value)
              }
          }
      }
    }),
  )
  fresh_ref.val = Some(fresh_query)
  let fresh_mount = must_fresh_mount(fresh_store.mount(fresh_query.at(())))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_mode = must_inc_source(inc_region.source(false))
  let inc_old = must_inc_source(inc_region.source(1))
  let inc_new = must_inc_source(inc_region.source(2))
  let inc_cycle = must_inc_source(inc_region.source(true))
  let inc_ref : Ref[@incremental.Query[Unit, Int]?] = Ref(None)
  let inc_query = must_inc_query(
    inc_region.query((ctx, _ : Unit) => {
      match ctx.read(inc_mode.view()) {
        Err(error) => Err(error)
        Ok(false) => ctx.read(inc_old.view())
        Ok(true) =>
          match ctx.read(inc_new.view()) {
            Err(error) => Err(error)
            Ok(value) =>
              match ctx.read(inc_cycle.view()) {
                Err(error) => Err(error)
                Ok(true) =>
                  match inc_ref.val {
                    Some(self) => ctx.read(self.at(()))
                    None => Ok(value)
                  }
                Ok(false) => Ok(value)
              }
          }
      }
    }),
  )
  inc_ref.val = Some(inc_query)
  let inc_mount = must_inc_mount(inc_store.mount(inc_query.at(())))
  let initial = fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount)
  ignore(fresh_store.transaction(tx => tx.set(fresh_mode, true)))
  ignore(inc_store.transaction(tx => tx.set(inc_mode, true)))
  let exact_cycle = match (fresh_mount.current(), inc_mount.current()) {
    (
      Ok(Err(@fresh.ReadError::Cycle(fresh_witness))),
      Ok(Err(@incremental.ReadError::Cycle(inc_witness))),
    ) =>
      fresh_witness.path.length() == 2 &&
      fresh_witness.path.all(id => id == fresh_query.id()) &&
      inc_witness.path.length() == 2 &&
      inc_witness.path.all(id => id == inc_query.id())
    _ => false
  }
  let failed = fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount) &&
    exact_cycle &&
    inc_mount.debug().failure_count == 1 &&
    inc_mount.debug().failed_attempt_footprint_length > 0
  let before_old_failed = inc_mount.debug().wake_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_old, 8)))
  ignore(inc_store.transaction(tx => tx.set(inc_old, 8)))
  let successful_union_woke = inc_mount.debug().wake_count ==
    before_old_failed + 1 &&
    fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount)
  let before_new = inc_mount.debug().wake_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_new, 3)))
  ignore(inc_store.transaction(tx => tx.set(inc_new, 3)))
  let retried = inc_mount.debug().wake_count == before_new + 1 &&
    fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount)
  ignore(fresh_store.transaction(tx => tx.set(fresh_cycle, false)))
  ignore(inc_store.transaction(tx => tx.set(inc_cycle, false)))
  let recovered = fresh_mount_int(fresh_mount) == "Ok(3)" &&
    inc_mount_int(inc_mount) == "Ok(3)" &&
    inc_mount.debug().failed_attempt_footprint_length == 0
  let before_old = inc_mount.debug().wake_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_old, 9)))
  ignore(inc_store.transaction(tx => tx.set(inc_old, 9)))
  let old_quiet = inc_mount.debug().wake_count == before_old &&
    fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount)
  ignore(fresh_store.transaction(tx => tx.set(fresh_new, 4)))
  ignore(inc_store.transaction(tx => tx.set(inc_new, 4)))
  let new_wakes = inc_mount.debug().wake_count == before_old + 1 &&
    fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount)
  fresh_mount.dispose()
  inc_mount.dispose()
  ignore(fresh_region.close())
  ignore(inc_region.close())
  let passed = initial &&
    failed &&
    successful_union_woke &&
    retried &&
    recovered &&
    old_quiet &&
    new_wakes
  println(
    "mount_failed initial=\{initial} exact_cycle=\{exact_cycle} failed=\{failed} success_union=\{successful_union_woke} retried=\{retried} recovered=\{recovered} old_quiet=\{old_quiet} new_wakes=\{new_wakes}",
  )
  passed
}

///|
/// A cutoff-green child refreshes a parent footprint from branch A to B.
fn mount_child_cutoff_refresh() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = fresh_region_or_abort(fresh_store.region())
  let fresh_mode = fresh_source_or_abort(fresh_region.source(false))
  let fresh_a = fresh_source_or_abort(fresh_region.source(1))
  let fresh_b = fresh_source_or_abort(fresh_region.source(1))
  let fresh_child = must_fresh_query(
    fresh_region.query_eq((ctx, _ : Unit) => {
      match ctx.read(fresh_mode.view()) {
        Err(error) => Err(error)
        Ok(false) => ctx.read(fresh_a.view())
        Ok(true) => ctx.read(fresh_b.view())
      }
    }),
  )
  let fresh_parent = must_fresh_query(
    fresh_region.query_always_changed((ctx, _ : Unit) => {
      ctx.read(fresh_child.at(()))
    }),
  )
  let fresh_mount = must_fresh_mount(fresh_store.mount(fresh_parent.at(())))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_mode = must_inc_source(inc_region.source(false))
  let inc_a = must_inc_source(inc_region.source(1))
  let inc_b = must_inc_source(inc_region.source(1))
  let inc_child = must_inc_query(
    inc_region.query_eq((ctx, _ : Unit) => {
      match ctx.read(inc_mode.view()) {
        Err(error) => Err(error)
        Ok(false) => ctx.read(inc_a.view())
        Ok(true) => ctx.read(inc_b.view())
      }
    }),
  )
  let inc_parent = must_inc_query(
    inc_region.query_always_changed((ctx, _ : Unit) => {
      ctx.read(inc_child.at(()))
    }),
  )
  let inc_mount = must_inc_mount(inc_store.mount(inc_parent.at(())))
  let parent_before = inc_parent.debug().compute_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_mode, true)))
  ignore(inc_store.transaction(tx => tx.set(inc_mode, true)))
  let switched = fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount) &&
    inc_parent.debug().compute_count == parent_before
  let before_a = inc_mount.debug().wake_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_a, 3)))
  ignore(inc_store.transaction(tx => tx.set(inc_a, 3)))
  let old_branch_quiet = inc_mount.debug().wake_count == before_a &&
    fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount)
  ignore(fresh_store.transaction(tx => tx.set(fresh_b, 3)))
  ignore(inc_store.transaction(tx => tx.set(inc_b, 3)))
  let new_branch_wakes = inc_mount.debug().wake_count == before_a + 1 &&
    fresh_mount_int(fresh_mount) == inc_mount_int(inc_mount)
  fresh_mount.dispose()
  inc_mount.dispose()
  ignore(fresh_region.close())
  ignore(inc_region.close())
  let passed = switched && old_branch_quiet && new_branch_wakes
  println(
    "mount_child_cutoff switched=\{switched} old_branch_quiet=\{old_branch_quiet} new_branch_wakes=\{new_branch_wakes}",
  )
  passed
}

///|
/// Direct cutoff observation and root/child eviction retain exact parity.
fn mount_cutoff_eviction_parity() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = fresh_region_or_abort(fresh_store.region())
  let fresh_source = fresh_source_or_abort(fresh_region.source(1))
  let fresh_root = must_fresh_query(
    fresh_region.query_type_owned((ctx, _ : Unit) => {
      match ctx.read(fresh_source.view()) {
        Ok(value) => Ok(RootValue::{ value, nonce: ctx.revision().value() })
        Err(error) => Err(error)
      }
    }),
  )
  let fresh_mount = must_fresh_mount(fresh_store.mount(fresh_root.at(())))

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_source = must_inc_source(inc_region.source(1))
  let inc_root = must_inc_query(
    inc_region.query_type_owned((ctx, _ : Unit) => {
      match ctx.read(inc_source.view()) {
        Ok(value) => Ok(RootValue::{ value, nonce: ctx.revision().value() })
        Err(error) => Err(error)
      }
    }),
  )
  let inc_mount = must_inc_mount(inc_store.mount(inc_root.at(())))
  let root_equal = () => {
    let fresh = fresh_mount_root_value(fresh_mount)
    let incremental = mount_root_value(inc_mount)
    fresh.value == incremental.value && fresh.nonce == incremental.nonce
  }
  let initial = root_equal() && fresh_mount_root_value(fresh_mount).nonce == 0
  ignore(fresh_store.transaction(tx => tx.set(fresh_source, 1)))
  ignore(inc_store.transaction(tx => tx.set(inc_source, 1)))
  let newest_equivalent = root_equal() &&
    fresh_mount_root_value(fresh_mount).nonce == 1
  let fresh_root_wakes = fresh_mount.debug().wake_count
  let inc_root_wakes = inc_mount.debug().wake_count
  let root_evicted = fresh_root.evict_memo(()) == Ok(false) &&
    inc_root.evict_memo(()) == Ok(true) &&
    inc_root.memo_debug(()) is None &&
    fresh_mount.debug().wake_count == fresh_root_wakes &&
    inc_mount.debug().wake_count == inc_root_wakes &&
    root_equal()
  ignore(fresh_store.transaction(tx => tx.set(fresh_source, 3)))
  ignore(inc_store.transaction(tx => tx.set(inc_source, 3)))
  let root_rematerialized = root_equal() &&
    fresh_mount_root_value(fresh_mount).value == 3

  let fresh_child = must_fresh_query(
    fresh_region.query_eq((ctx, _ : Unit) => ctx.read(fresh_source.view())),
  )
  let fresh_parent = must_fresh_query(
    fresh_region.query_always_changed((ctx, _ : Unit) => {
      ctx.read(fresh_child.at(()))
    }),
  )
  let fresh_child_mount = must_fresh_mount(
    fresh_store.mount(fresh_parent.at(())),
  )
  let inc_child = must_inc_query(
    inc_region.query_eq((ctx, _ : Unit) => ctx.read(inc_source.view())),
  )
  let inc_parent = must_inc_query(
    inc_region.query_always_changed((ctx, _ : Unit) => {
      ctx.read(inc_child.at(()))
    }),
  )
  let inc_child_mount = must_inc_mount(inc_store.mount(inc_parent.at(())))
  let fresh_child_wakes = fresh_child_mount.debug().wake_count
  let inc_child_wakes = inc_child_mount.debug().wake_count
  let child_evicted = fresh_child.evict_memo(()) == Ok(false) &&
    inc_child.evict_memo(()) == Ok(true) &&
    inc_child.memo_debug(()) is None &&
    fresh_child_mount.debug().wake_count == fresh_child_wakes &&
    inc_child_mount.debug().wake_count == inc_child_wakes &&
    fresh_mount_int(fresh_child_mount) == inc_mount_int(inc_child_mount)
  ignore(fresh_store.transaction(tx => tx.set(fresh_source, 4)))
  ignore(inc_store.transaction(tx => tx.set(inc_source, 4)))
  let child_rematerialized = fresh_mount_int(fresh_child_mount) == "Ok(4)" &&
    inc_mount_int(inc_child_mount) == "Ok(4)"
  let parent_compute = inc_parent.debug().compute_count
  ignore(fresh_store.transaction(tx => tx.set(fresh_source, 4)))
  ignore(inc_store.transaction(tx => tx.set(inc_source, 4)))
  let child_cutoff_green = fresh_mount_int(fresh_child_mount) ==
    inc_mount_int(inc_child_mount) &&
    inc_parent.debug().compute_count == parent_compute &&
    root_equal() &&
    fresh_mount_root_value(fresh_mount).nonce == 4

  let fresh_root_count = fresh_mount.debug().evaluation_count
  let inc_root_count = inc_mount.debug().evaluation_count
  fresh_mount.dispose()
  fresh_mount.dispose()
  inc_mount.dispose()
  inc_mount.dispose()
  fresh_child_mount.dispose()
  inc_child_mount.dispose()
  ignore(fresh_store.transaction(tx => tx.set(fresh_source, 5)))
  ignore(inc_store.transaction(tx => tx.set(inc_source, 5)))
  let disposed_quiet = fresh_mount.current()
    is Err(@fresh.MountError::DisposedMount(_)) &&
    inc_mount.current() is Err(@incremental.MountError::DisposedMount(_)) &&
    fresh_mount.debug().evaluation_count == fresh_root_count &&
    inc_mount.debug().evaluation_count == inc_root_count
  ignore(fresh_region.close())
  ignore(inc_region.close())
  let passed = initial &&
    newest_equivalent &&
    root_evicted &&
    root_rematerialized &&
    child_evicted &&
    child_rematerialized &&
    child_cutoff_green &&
    disposed_quiet
  println(
    "mount_cutoff_eviction initial=\{initial} newest=\{newest_equivalent} root_evict=\{root_evicted} root_remat=\{root_rematerialized} child_evict=\{child_evicted} child_remat=\{child_rematerialized} child_green=\{child_cutoff_green} disposed=\{disposed_quiet}",
  )
  passed
}

///|
/// Rejection is atomic, and disposal is idempotent and quiet.
fn mount_rejection_and_dispose() -> Bool {
  let fresh = @fresh.Store()
  let fresh_region = fresh_region_or_abort(fresh.region())
  let fresh_source = fresh_source_or_abort(fresh_region.source(1))
  let other_fresh = @fresh.Store()
  let fresh_cross = other_fresh.mount(fresh_source.view())
    is Err(@fresh.MountError::CrossStore(_))
  ignore(fresh_region.close())
  let fresh_closed = fresh.mount(fresh_source.view())
    is Err(@fresh.MountError::ClosedRegion(_))

  let inc = @incremental.Store()
  let inc_region = must_inc_region(inc.region())
  let inc_source = must_inc_source(inc_region.source(1))
  let other_inc = @incremental.Store()
  let inc_cross = other_inc.mount(inc_source.view())
    is Err(@incremental.MountError::CrossStore(_))
  ignore(inc_region.close())
  let inc_closed = inc.mount(inc_source.view())
    is Err(@incremental.MountError::ClosedRegion(_))

  let fresh_live = @fresh.Store()
  let fresh_live_region = fresh_region_or_abort(fresh_live.region())
  let fresh_live_source = fresh_source_or_abort(fresh_live_region.source(1))
  let fresh_view = fresh_live_source.view()
  let fresh_eval_rejection : Ref[Result[@fresh.Mount[Int], @fresh.MountError]?] = Ref(
    None,
  )
  let fresh_trigger = must_fresh_query(
    fresh_live_region.query((_ctx, _ : Unit) => {
      fresh_eval_rejection.val = Some(fresh_live.mount(fresh_view))
      Ok(1)
    }),
  )
  ignore(fresh_live.read(fresh_trigger.at(())))
  let fresh_eval = fresh_eval_rejection.val
    is Some(Err(@fresh.MountError::MountDuringEvaluation(_))) &&
    fresh_live.debug().mount_count == 0
  let fresh_tx_rejection : Ref[Result[@fresh.Mount[Int], @fresh.MountError]?] = Ref(
    None,
  )
  ignore(
    fresh_live.transaction(_ => {
      fresh_tx_rejection.val = Some(fresh_live.mount(fresh_view))
      Ok(())
    }),
  )
  let fresh_tx = fresh_tx_rejection.val
    is Some(Err(@fresh.MountError::MountDuringTransaction(_))) &&
    fresh_live.debug().mount_count == 0

  let inc_live = @incremental.Store()
  let inc_live_region = must_inc_region(inc_live.region())
  let inc_live_source = must_inc_source(inc_live_region.source(1))
  let inc_view = inc_live_source.view()
  let inc_eval_rejection : Ref[
    Result[@incremental.Mount[Int], @incremental.MountError]?,
  ] = Ref(None)
  let inc_trigger = must_inc_query(
    inc_live_region.query((_ctx, _ : Unit) => {
      inc_eval_rejection.val = Some(inc_live.mount(inc_view))
      Ok(1)
    }),
  )
  ignore(inc_live.read(inc_trigger.at(())))
  let inc_eval = inc_eval_rejection.val
    is Some(Err(@incremental.MountError::MountDuringEvaluation(_))) &&
    inc_live.debug().mount_count == 0
  let inc_tx_rejection : Ref[
    Result[@incremental.Mount[Int], @incremental.MountError]?,
  ] = Ref(None)
  ignore(
    inc_live.transaction(_ => {
      inc_tx_rejection.val = Some(inc_live.mount(inc_view))
      Ok(())
    }),
  )
  let inc_tx = inc_tx_rejection.val
    is Some(Err(@incremental.MountError::MountDuringTransaction(_))) &&
    inc_live.debug().mount_count == 0

  let fresh_mount = must_fresh_mount(fresh_live.mount(fresh_view))
  let inc_mount = must_inc_mount(inc_live.mount(inc_view))
  let fresh_count = fresh_mount.debug().evaluation_count
  let inc_count = inc_mount.debug().evaluation_count
  fresh_mount.dispose()
  fresh_mount.dispose()
  inc_mount.dispose()
  inc_mount.dispose()
  ignore(fresh_live.transaction(tx => tx.set(fresh_live_source, 2)))
  ignore(inc_live.transaction(tx => tx.set(inc_live_source, 2)))
  let disposed = fresh_mount.current()
    is Err(@fresh.MountError::DisposedMount(_)) &&
    inc_mount.current() is Err(@incremental.MountError::DisposedMount(_)) &&
    fresh_mount.debug().evaluation_count == fresh_count &&
    inc_mount.debug().evaluation_count == inc_count &&
    fresh_live.debug().mount_count == 0 &&
    inc_live.debug().mount_count == 0
  ignore(fresh_live_region.close())
  ignore(inc_live_region.close())
  let passed = fresh_cross &&
    fresh_closed &&
    inc_cross &&
    inc_closed &&
    fresh_eval &&
    fresh_tx &&
    inc_eval &&
    inc_tx &&
    disposed
  println(
    "mount_rejections cross=\{fresh_cross && inc_cross} closed=\{fresh_closed && inc_closed} eval=\{fresh_eval && inc_eval} tx=\{fresh_tx && inc_tx} dispose=\{disposed}",
  )
  passed
}

///|
/// Disposal from a running recipe cannot mutate iteration or resurrect state.
fn mount_dispose_during_wake() -> Bool {
  let fresh_store = @fresh.Store()
  let fresh_region = fresh_region_or_abort(fresh_store.region())
  let fresh_trigger = fresh_source_or_abort(fresh_region.source(false))
  let fresh_ref : Ref[@fresh.Mount[Int]?] = Ref(None)
  let fresh_query = must_fresh_query(
    fresh_region.query((ctx, _ : Unit) => {
      match ctx.read(fresh_trigger.view()) {
        Err(error) => Err(error)
        Ok(dispose) => {
          if dispose {
            match fresh_ref.val {
              Some(mount) => mount.dispose()
              None => ()
            }
          }
          Ok(1)
        }
      }
    }),
  )
  let fresh_mount = must_fresh_mount(fresh_store.mount(fresh_query.at(())))
  fresh_ref.val = Some(fresh_mount)

  let inc_store = @incremental.Store()
  let inc_region = must_inc_region(inc_store.region())
  let inc_trigger = must_inc_source(inc_region.source(false))
  let inc_ref : Ref[@incremental.Mount[Int]?] = Ref(None)
  let inc_query = must_inc_query(
    inc_region.query((ctx, _ : Unit) => {
      match ctx.read(inc_trigger.view()) {
        Err(error) => Err(error)
        Ok(dispose) => {
          if dispose {
            match inc_ref.val {
              Some(mount) => mount.dispose()
              None => ()
            }
          }
          Ok(1)
        }
      }
    }),
  )
  let inc_mount = must_inc_mount(inc_store.mount(inc_query.at(())))
  inc_ref.val = Some(inc_mount)
  ignore(fresh_store.transaction(tx => tx.set(fresh_trigger, true)))
  ignore(inc_store.transaction(tx => tx.set(inc_trigger, true)))
  let disposed = fresh_mount.current()
    is Err(@fresh.MountError::DisposedMount(_)) &&
    inc_mount.current() is Err(@incremental.MountError::DisposedMount(_)) &&
    fresh_store.debug().mount_count == 0 &&
    inc_store.debug().mount_count == 0 &&
    inc_store.debug().active_edge_count == 0 &&
    !fresh_mount.debug().runner_registered &&
    !inc_mount.debug().runner_registered
  fresh_ref.val = None
  inc_ref.val = None
  ignore(fresh_region.close())
  ignore(inc_region.close())
  println("mount_dispose_during_wake disposed=\{disposed}")
  disposed
}

///|
fn mount_workloads() -> Bool {
  let initial_selective = mount_initial_and_selective()
  let transaction_clock = mount_transaction_and_clock()
  let region_lifetime = mount_region_lifetime()
  let dynamic_failure_cycle = mount_region_dynamic_failure_cycle()
  let cutoff_eviction_dispose = mount_cutoff_eviction_dispose()
  let parity_turns = mount_parity_turns()
  let region_selectivity = mount_region_close_selectivity()
  let failed_retry = mount_failed_attempt_retry()
  let child_refresh = mount_child_cutoff_refresh()
  let cutoff_eviction_parity = mount_cutoff_eviction_parity()
  let rejection_dispose = mount_rejection_and_dispose()
  let dispose_during_wake = mount_dispose_during_wake()
  let passed = initial_selective &&
    transaction_clock &&
    region_lifetime &&
    dynamic_failure_cycle &&
    cutoff_eviction_dispose &&
    parity_turns &&
    region_selectivity &&
    failed_retry &&
    child_refresh &&
    cutoff_eviction_parity &&
    rejection_dispose &&
    dispose_during_wake
  println(
    "mount initial_selective=\{initial_selective} transaction_clock=\{transaction_clock} region_lifetime=\{region_lifetime} dynamic_failure_cycle=\{dynamic_failure_cycle} cutoff_eviction_dispose=\{cutoff_eviction_dispose} parity_turns=\{parity_turns} region_selectivity=\{region_selectivity} failed_retry=\{failed_retry} child_refresh=\{child_refresh} cutoff_eviction_parity=\{cutoff_eviction_parity} rejection_dispose=\{rejection_dispose} dispose_during_wake=\{dispose_during_wake} passed=\{passed}",
  )
  passed
}

///|
test "mounted roots preserve direct observer semantics" {
  assert_true(mount_workloads())
}
