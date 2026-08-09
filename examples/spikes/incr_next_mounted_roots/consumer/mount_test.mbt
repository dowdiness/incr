///|
fn[T] test_inc_mount(
  result : Result[@incremental.Mount[T], @incremental.MountError],
) -> @incremental.Mount[T] {
  match result {
    Ok(value) => value
    Err(_) => abort("incremental mount")
  }
}

///|
fn[T] test_fresh_mount(
  result : Result[@fresh.Mount[T], @fresh.MountError],
) -> @fresh.Mount[T] {
  match result {
    Ok(value) => value
    Err(_) => abort("fresh mount")
  }
}

///|
test "initial mount evaluates once" {
  let store = @incremental.Store()
  let region = match store.region() {
    Ok(value) => value
    Err(_) => abort("region")
  }
  let source = match region.source(1) {
    Ok(value) => value
    Err(_) => abort("source")
  }
  let mount = test_inc_mount(store.mount(source.view()))
  assert_true(mount.current() is Ok(Ok(1)))

  let fresh_store = @fresh.Store()
  let fresh_region = match fresh_store.region() {
    Ok(value) => value
    Err(_) => abort("fresh region")
  }
  let fresh_source = match fresh_region.source(1) {
    Ok(value) => value
    Err(_) => abort("fresh source")
  }
  let fresh_mount = test_fresh_mount(fresh_store.mount(fresh_source.view()))
  assert_true(fresh_mount.current() is Ok(Ok(1)))
}
