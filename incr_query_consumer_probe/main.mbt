///|
fn run_consumer_probe() -> Unit raise {
  let store = @incr_query.Store::Store()
  let region = store.region()
  let left = region.source(2)
  let right = region.source(11)
  let select_right = region.source(false)
  let selected_view = region.derived(ctx => {
    if ctx.get(select_right.view()) {
      ctx.get(right.view())
    } else {
      ctx.get(left.view())
    }
  })
  let doubled_view = region.derived(ctx => ctx.get(selected_view) * 2)

  let initial_doubled = store.get(doubled_view)
  let initial_selected = store.get(selected_view)
  guard initial_selected == 2 && initial_doubled == 4 else {
    abort("unexpected initial snapshot")
  }
  println("initial.selected=\{initial_selected}")
  println("initial.doubled=\{initial_doubled}")
  println("")

  ignore(
    (
      store.transaction(tx => {
        tx.set(left, 3)
        tx.set(right, 13)
        tx.set(select_right, true)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let switched_doubled = store.get(doubled_view)
  let switched_selected = store.get(selected_view)
  guard switched_selected == 13 && switched_doubled == 26 else {
    abort("unexpected atomic switch snapshot")
  }
  println("atomic_switch.selected=\{switched_selected}")
  println("atomic_switch.doubled=\{switched_doubled}")
  println("")

  ignore(
    (
      store.transaction(tx => {
        tx.set(left, 5)
        tx.set(right, 17)
        tx.set(select_right, false)
        Ok(())
      }) : Result[Unit, Unit]),
  )
  let restored_doubled = store.get(doubled_view)
  let restored_selected = store.get(selected_view)
  guard restored_selected == 5 && restored_doubled == 10 else {
    abort("unexpected switch-back snapshot")
  }
  println("switch_back.selected=\{restored_selected}")
  println("switch_back.doubled=\{restored_doubled}")
  println("")

  region.close()
  let selected_after_close : Result[Int, @incr_query.ReadError] = Ok(
    store.get(selected_view),
  ) catch {
    error => Err(error)
  }
  guard selected_after_close is Err(@incr_query.ReadError::ClosedRegion(_)) else {
    abort("selected View remained readable after Region close")
  }
  let doubled_after_close : Result[Int, @incr_query.ReadError] = Ok(
    store.get(doubled_view),
  ) catch {
    error => Err(error)
  }
  match doubled_after_close {
    Err(@incr_query.ReadError::ClosedRegion(_)) =>
      println("close.result=ClosedRegion")
    _ => abort("doubled View did not report ClosedRegion")
  }
}

///|
fn main raise {
  run_consumer_probe()
}

///|
test "public-only consumer behavior" {
  run_consumer_probe()
}
