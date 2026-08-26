///|
priv type RcToken

///|
extern "C" fn rc_token_new(kind : Int) -> RcToken = "incr_next_rc_token_new"

///|
extern "C" fn rc_live(kind : Int) -> Int = "incr_next_rc_live"

///|
extern "C" fn rc_finalized(kind : Int) -> Int = "incr_next_rc_finalized"

///|
struct RcKey {
  token : RcToken
  value : Int
}

///|
fn RcKey::RcKey(kind : Int, value : Int) -> RcKey {
  { token: rc_token_new(kind), value }
}

///|
impl Eq for RcKey with fn equal(self, other) -> Bool {
  self.value == other.value
}

///|
impl Hash for RcKey with fn hash(self) {
  self.value.hash()
}

///|
impl Hash for RcKey with fn hash_combine(self, hasher) {
  self.value.hash_combine(hasher)
}

///|
struct RcValue {
  token : RcToken
  value : Int
}

///|
test "proof loss releases memo value and installed trace-only key" {
  let store = Store::Store()
  let region = store.region()
  let child = region.query((_ctx, key : RcKey) => key.value)
  let parent = region.query((ctx, _unit : Unit) => {
    let value = ctx.get(child.view(RcKey(30, 7)))
    RcValue::{ token: rc_token_new(31), value }
  })

  let view = parent.view(())
  let held : Ref[RcValue?] = Ref(None)
  match (Ok(store.get(view)) catch { error => Err(error) }) {
    Ok(value) => held.val = Some(value)
    Err(_) => abort("native proof-loss probe read failed")
  }
  assert_eq(held.val.unwrap().value, 7)
  assert_eq(rc_live(30), 1)
  assert_eq(rc_live(31), 1)
  assert_eq(child.drop_memo_evidence(RcKey(30, 7)), Ok(()))
  assert_eq(rc_live(30), 1)
  assert_eq(parent.drop_memo_evidence(()), Ok(()))
  assert_eq(rc_live(30), 0)
  assert_eq(rc_finalized(30), 2)
  assert_eq(rc_live(31), 1)
  held.val = None
  assert_eq(rc_live(31), 0)
  assert_eq(rc_finalized(31), 1)
  region.close()
}

///|
test "proof loss rematerializes native memo, trace, capture, and view ownership" {
  let store = Store::Store()
  let region = store.region()
  let capture = rc_token_new(7)
  let query = region.query((_ctx, key : RcKey) => {
    ignore(capture)
    RcValue::{ token: rc_token_new(6), value: key.value }
  })

  let first_view = Ref(Some(query.view(RcKey(5, 41))))
  ignore(Ok(store.get(first_view.val.unwrap())) catch { error => Err(error) })
  first_view.val = None
  assert_eq(rc_live(5), 1)
  assert_eq(rc_live(6), 1)
  assert_eq(rc_live(7), 1)
  assert_eq(query.drop_memo_evidence(RcKey(5, 41)), Ok(()))
  assert_eq(rc_live(5), 0)
  assert_true(rc_finalized(5) > 0)
  assert_eq(rc_live(6), 0)
  assert_eq(rc_finalized(6), 1)
  let view = Ref(Some(query.view(RcKey(5, 41))))
  match (Ok(store.get(view.val.unwrap())) catch { error => Err(error) }) {
    Ok(value) => assert_eq(value.value, 41)
    Err(_) => abort("native rematerialization probe read failed")
  }
  assert_eq(rc_live(5), 1)
  assert_eq(rc_live(6), 1)
  assert_eq(rc_live(7), 1)
  region.close()
  assert_eq(rc_live(5), 1)
  assert_eq(rc_live(6), 0)
  assert_eq(rc_live(7), 0)
  view.val = None
  assert_eq(rc_live(5), 0)
}
