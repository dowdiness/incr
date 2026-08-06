///|
priv struct NonEqValue {
  value : Int
  callback : () -> Unit
}

///|
fn[T] read_view(view : @surface.View[T]) -> T {
  view() catch {
    _ => abort("unexpected prototype read failure")
  }
}

///|
fn[T] eager_or_abort(
  store : @surface.Store,
  view : @surface.View[T],
  label? : String,
) -> @surface.Stop {
  store.eager(view, label?) catch {
    _ => abort("unexpected prototype eager creation failure")
  }
}

///|
fn main {
  println("PROTOTYPE V12.3 eager owner/API")
  let store = @surface.Store()
  let (source, write) = store.input(1)
  let runs = Ref(0)
  let counted : @surface.View[Int] = () => {
    runs.val += 1
    source()
  }
  guard runs.val == 0 else { abort("mount ran before creation") }
  println("before_mount.runs=\{runs.val}")
  let stop = eager_or_abort(store, counted, label="counted")
  guard runs.val == 1 && read_view(source) == 1 else {
    abort("mount did not materialize exactly once")
  }
  println("after_mount.runs=\{runs.val},value=\{read_view(source)}")
  write.set(2)
  guard runs.val == 2 && read_view(source) == 2 else {
    abort("write did not run eager mount")
  }
  println("after_write.runs=\{runs.val},value=\{read_view(source)}")
  store.batch(() => {
    write.set(3)
    write.set(4)
    guard runs.val == 2 else { abort("eager mount ran inside batch") }
    println("inside_batch.runs=\{runs.val}")
  })
  guard runs.val == 3 && read_view(source) == 4 else {
    abort("batch did not coalesce eager mount")
  }
  println("after_batch.runs=\{runs.val},value=\{read_view(source)}")
  stop.stop()
  stop.stop()
  guard stop.is_stopped() && runs.val == 3 else {
    abort("Stop was not idempotent")
  }
  println("after_stop.stopped=\{stop.is_stopped()},runs=\{runs.val}")
  write.set(5)
  guard runs.val == 3 else { abort("stopped mount ran after write") }
  println("after_stopped_write.runs=\{runs.val}")
  let passive_value = read_view(counted)
  guard passive_value == 5 && runs.val == 4 else {
    abort("stopped View did not remain passively readable")
  }
  println("passive_read.value=\{passive_value},runs=\{runs.val}")

  let (non_eq_view, non_eq_write) = store.input(NonEqValue::{
    value: 10,
    callback: () => (),
  })
  let non_eq_runs = Ref(0)
  let counted_non_eq : @surface.View[NonEqValue] = () => {
    non_eq_runs.val += 1
    non_eq_view()
  }
  let non_eq_stop = eager_or_abort(store, counted_non_eq)
  non_eq_write.force_set(NonEqValue::{ value: 20, callback: () => () })
  let current_non_eq = read_view(non_eq_view)
  (current_non_eq.callback)()
  guard current_non_eq.value == 20 && non_eq_runs.val == 2 else {
    abort("non-Eq View was not mounted eagerly")
  }
  println("non_eq.value=\{current_non_eq.value},runs=\{non_eq_runs.val}")

  let close_runs = Ref(0)
  let close_view : @surface.View[Int] = () => {
    close_runs.val += 1
    source()
  }
  let close_stop = eager_or_abort(store, close_view, label="close-owned")
  guard close_runs.val == 1 else { abort("close-owned mount did not run") }
  println("before_close.runs=\{close_runs.val}")
  store.close()
  store.close()
  guard close_stop.is_stopped() && non_eq_stop.is_stopped() else {
    abort("Store close did not stop every mount")
  }
  println(
    "after_close.counted_stopped=\{close_stop.is_stopped()},non_eq_stopped=\{non_eq_stop.is_stopped()}",
  )
  println("positive_probes=PASS")
}
