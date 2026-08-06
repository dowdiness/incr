///|
priv struct NonEqValue {
  tag : Int
  callback : () -> Unit
}

///|
fn[T] read_view(view : @capability.View[T]) -> T {
  view() catch {
    _ => abort("unexpected prototype read failure")
  }
}

///|
fn set_int(write : @capability.Write[Int], value : Int) -> Unit {
  write.set(value)
}

///|
fn force_non_eq(
  write : @capability.Write[NonEqValue],
  value : NonEqValue,
) -> Unit {
  write.force_set(value)
}

///|
fn main {
  println("PROTOTYPE V12.3 nominal Write capability")
  let store = @capability.Store()
  let (int_view, int_write) = store.input(1)
  println("int.initial=\{read_view(int_view)}")
  set_int(int_write, 1)
  println("int.after_equal_set=\{read_view(int_view)}")
  set_int(int_write, 2)
  println("int.after_changed_set=\{read_view(int_view)}")
  int_write.force_set(2)
  println("int.after_equal_force_set=\{read_view(int_view)}")
  let initial_non_eq = { tag: 10, callback: () => () }
  let (non_eq_view, non_eq_write) = store.input(initial_non_eq)
  println("non_eq.initial.tag=\{read_view(non_eq_view).tag}")
  force_non_eq(non_eq_write, { tag: 20, callback: () => () })
  let current_non_eq = read_view(non_eq_view)
  (current_non_eq.callback)()
  println("non_eq.after_force_set.tag=\{current_non_eq.tag}")
  println("positive_probes=PASS")
}
