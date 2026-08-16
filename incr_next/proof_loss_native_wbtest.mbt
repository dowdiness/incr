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
  let region = store.region().unwrap()
  let child = region.query((_ctx, key : RcKey) => Ok(key.value)).unwrap()
  let parent = region
    .query((ctx, _unit : Unit) => {
      match ctx.read(child.at(RcKey(30, 7))) {
        Ok(value) => Ok(RcValue::{ token: rc_token_new(31), value })
        Err(error) => Err(error)
      }
    })
    .unwrap()
  let view = parent.at(())
  let held : Ref[RcValue?] = Ref(None)
  match store.read(view) {
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
  ignore(region.close())
}

///|
test "proof loss rematerializes native memo, trace, capture, and view ownership" {
  let store = Store::Store()
  let region = store.region().unwrap()
  let capture = rc_token_new(7)
  let query = region
    .query((_ctx, key : RcKey) => {
      ignore(capture)
      Ok(RcValue::{ token: rc_token_new(6), value: key.value })
    })
    .unwrap()
  let first_view = Ref(Some(query.at(RcKey(5, 41))))
  ignore(store.read(first_view.val.unwrap()))
  first_view.val = None
  assert_eq(rc_live(5), 1)
  assert_eq(rc_live(6), 1)
  assert_eq(rc_live(7), 1)
  assert_eq(query.drop_memo_evidence(RcKey(5, 41)), Ok(()))
  assert_eq(rc_live(5), 0)
  assert_true(rc_finalized(5) > 0)
  assert_eq(rc_live(6), 0)
  assert_eq(rc_finalized(6), 1)
  let view = Ref(Some(query.at(RcKey(5, 41))))
  match store.read(view.val.unwrap()) {
    Ok(value) => assert_eq(value.value, 41)
    Err(_) => abort("native rematerialization probe read failed")
  }
  assert_eq(rc_live(5), 1)
  assert_eq(rc_live(6), 1)
  assert_eq(rc_live(7), 1)
  ignore(region.close())
  assert_eq(rc_live(5), 1)
  assert_eq(rc_live(6), 0)
  assert_eq(rc_live(7), 0)
  view.val = None
  assert_eq(rc_live(5), 0)
}
