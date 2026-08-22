///|
fn run_consumer_probe() -> Unit {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let left = region.source(2).unwrap()
  let right = region.source(11).unwrap()
  let select_right = region.source(false).unwrap()
  let selected = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(select_right.view()) {
        Ok(false) => ctx.read(left.view())
        Ok(true) => ctx.read(right.view())
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let selected_view = selected.at(())
  let doubled = region
    .query((ctx, _unit : Unit) => {
      ctx.read(selected_view).map(value => value * 2)
    })
    .unwrap()
  let doubled_view = doubled.at(())

  let initial_doubled = store.read(doubled_view).unwrap()
  let initial_selected = store.read(selected_view).unwrap()
  guard initial_selected == 2 && initial_doubled == 4 else {
    abort("unexpected initial snapshot")
  }
  println("initial.selected=\{initial_selected}")
  println("initial.doubled=\{initial_doubled}")
  println("")

  ignore(
    store
    .transaction(tx => {
      match tx.set(left, 3) {
        Err(error) => Err(error)
        Ok(_) =>
          match tx.set(right, 13) {
            Err(error) => Err(error)
            Ok(_) => tx.set(select_right, true)
          }
      }
    })
    .unwrap(),
  )
  let switched_doubled = store.read(doubled_view).unwrap()
  let switched_selected = store.read(selected_view).unwrap()
  guard switched_selected == 13 && switched_doubled == 26 else {
    abort("unexpected atomic switch snapshot")
  }
  println("atomic_switch.selected=\{switched_selected}")
  println("atomic_switch.doubled=\{switched_doubled}")
  println("")

  ignore(
    store
    .transaction(tx => {
      match tx.set(left, 5) {
        Err(error) => Err(error)
        Ok(_) =>
          match tx.set(right, 17) {
            Err(error) => Err(error)
            Ok(_) => tx.set(select_right, false)
          }
      }
    })
    .unwrap(),
  )
  let restored_doubled = store.read(doubled_view).unwrap()
  let restored_selected = store.read(selected_view).unwrap()
  guard restored_selected == 5 && restored_doubled == 10 else {
    abort("unexpected switch-back snapshot")
  }
  println("switch_back.selected=\{restored_selected}")
  println("switch_back.doubled=\{restored_doubled}")
  println("")

  region.close().unwrap()
  guard store.read(selected_view) is Err(@incr_next.ReadError::ClosedRegion(..)) else {
    abort("selected View remained readable after Region close")
  }
  match store.read(doubled_view) {
    Err(@incr_next.ReadError::ClosedRegion(..)) =>
      println("close.result=ClosedRegion")
    _ => abort("doubled View did not report ClosedRegion")
  }
}

///|
fn main {
  run_consumer_probe()
}

///|
test "public-only consumer behavior" {
  run_consumer_probe()
}
