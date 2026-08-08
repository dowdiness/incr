#cfg(target="native")
type CutoffPolicyToken

#cfg(target="native")
extern "C" fn cutoff_policy_token_new() -> CutoffPolicyToken =
  "incr_next_cutoff_policy_token_new"

#cfg(target="native")
#borrow(token)
extern "C" fn cutoff_policy_token_touch(token : CutoffPolicyToken) -> Unit =
  "incr_next_cutoff_policy_token_touch"

#cfg(target="native")
extern "C" fn cutoff_policy_live() -> Int = "incr_next_cutoff_policy_live"

#cfg(target="native")
extern "C" fn cutoff_policy_finalized() -> Int =
  "incr_next_cutoff_policy_finalized"

#cfg(target="native")
fn make_capturing_policy_query() -> (Store, Region, Query[Unit, Int], View[Int]) {
  let token = cutoff_policy_token_new()
  let store = Store()
  let region = match store.region() {
    Ok(value) => value
    Err(_) => abort("policy probe region")
  }
  let query = match region.register_query(
    (_ctx, _key : Unit) => Ok(1),
    Compare((old, next) => {
      cutoff_policy_token_touch(token)
      old == next
    }),
  ) {
    Ok(value) => value
    Err(_) => abort("policy probe query")
  }
  (store, region, query, query.at(()))
}

#cfg(target="native")
test "Region close clears a Query-owned capturing cutoff policy" {
  let (store, region, query, surviving_view) = make_capturing_policy_query()
  inspect(cutoff_policy_live(), content="1")
  inspect(store.read(surviving_view) is Ok(1), content="true")
  inspect(query.debug().cutoff_available, content="true")
  ignore(region.close())
  inspect(query.debug().cutoff_available, content="false")
  inspect(cutoff_policy_live(), content="0")
  inspect(cutoff_policy_finalized(), content="1")
}
