///|
/// Pure keyed-child diff planner tests (#211).
///
/// `plan_keyed_diff` is DOM-free, so these run in Node under `--target js`. The
/// expected plans are reasoned by hand from the old/new key orders, not computed
/// by formula. The companion DOM applier (`diff_keyed_children`) is exercised by
/// the browser demo, since it needs a real `document`.

///|
#cfg(target="js")
test "keyed plan: unchanged list reuses every child in order" {
  let plan = plan_keyed_diff(["a", "b", "c"], ["a", "b", "c"])
  debug_inspect(plan.steps, content="[Some(0), Some(1), Some(2)]")
  debug_inspect(plan.removals, content="[]")
}

///|
#cfg(target="js")
test "keyed plan: insertion in the middle creates only the new key" {
  let plan = plan_keyed_diff(["a", "b"], ["a", "x", "b"])
  debug_inspect(plan.steps, content="[Some(0), None, Some(1)]")
  debug_inspect(plan.removals, content="[]")
}

///|
#cfg(target="js")
test "keyed plan: removal in the middle reuses survivors, removes the gap" {
  let plan = plan_keyed_diff(["a", "b", "c"], ["a", "c"])
  debug_inspect(plan.steps, content="[Some(0), Some(2)]")
  debug_inspect(plan.removals, content="[1]")
}

///|
#cfg(target="js")
test "keyed plan: reorder reuses every node in the new order" {
  let plan = plan_keyed_diff(["a", "b", "c"], ["c", "a", "b"])
  debug_inspect(plan.steps, content="[Some(2), Some(0), Some(1)]")
  debug_inspect(plan.removals, content="[]")
}

///|
#cfg(target="js")
test "keyed plan: mixed insert + reorder" {
  let plan = plan_keyed_diff(["a", "b", "c"], ["b", "a", "x", "c"])
  debug_inspect(plan.steps, content="[Some(1), Some(0), None, Some(2)]")
  debug_inspect(plan.removals, content="[]")
}

///|
#cfg(target="js")
test "keyed plan: fully disjoint keys create all, remove all" {
  let plan = plan_keyed_diff(["a", "b"], ["x", "y"])
  debug_inspect(plan.steps, content="[None, None]")
  debug_inspect(plan.removals, content="[0, 1]")
}

///|
#cfg(target="js")
test "keyed plan: empty new clears every old child" {
  let plan = plan_keyed_diff(["a", "b"], [])
  debug_inspect(plan.steps, content="[]")
  debug_inspect(plan.removals, content="[0, 1]")
}

///|
#cfg(target="js")
test "keyed plan: empty old creates every new child" {
  let plan = plan_keyed_diff([], ["a", "b"])
  debug_inspect(plan.steps, content="[None, None]")
  debug_inspect(plan.removals, content="[]")
}

///|
#cfg(target="js")
test "keyed plan: duplicate NEW key reuses once, then creates (usage error degrades)" {
  // Keys must be unique; a duplicate new key cannot reuse the same node twice,
  // so the second occurrence falls back to None instead of crashing.
  let plan = plan_keyed_diff(["a"], ["a", "a"])
  debug_inspect(plan.steps, content="[Some(0), None]")
  debug_inspect(plan.removals, content="[]")
}

///|
#cfg(target="js")
test "keyed plan: duplicate OLD key reuses the first, removes the rest" {
  let plan = plan_keyed_diff(["a", "a"], ["a"])
  debug_inspect(plan.steps, content="[Some(0)]")
  debug_inspect(plan.removals, content="[1]")
}

///|
#cfg(target="js")
test "keyed plan: duplicate OLD and NEW keys consume each old occurrence once" {
  let plan = plan_keyed_diff(["a", "a"], ["a", "a", "a"])
  debug_inspect(plan.steps, content="[Some(0), Some(1), None]")
  debug_inspect(plan.removals, content="[]")
}

///|
#cfg(target="js")
test "keyed plan: large unique-key path matches first-available scan" {
  let old_keys = [ for i in 0..<40 => "item-\{i}" ]
  let new_keys = ["missing", "item-39", "item-0", "item-20", "item-39"]
  let plan = plan_keyed_diff(old_keys, new_keys)
  let scan = plan_keyed_diff_by_first_available_scan(old_keys, new_keys)
  inspect(plan.steps == scan.steps, content="true")
  inspect(plan.removals == scan.removals, content="true")
}

///|
#cfg(target="js")
test "keyed plan: large duplicate-old path preserves scan degradation" {
  let old_keys = [
    for i in 0..<40 => if i == 0 || i == 35 { "dup" } else { "item-\{i}" }
  ]
  let new_keys = ["dup", "dup", "item-39"]
  let plan = plan_keyed_diff(old_keys, new_keys)
  let scan = plan_keyed_diff_by_first_available_scan(old_keys, new_keys)
  inspect(plan.steps == scan.steps, content="true")
  inspect(plan.removals == scan.removals, content="true")
}

///|
#cfg(target="js")
test "event spec: text bindings are equal iff their pure tag matches" {
  let name1 : EventBinding[RendererMsg] = on_input(tag="name")
  let name2 : EventBinding[RendererMsg] = on_input(tag="name")
  let email : EventBinding[RendererMsg] = on_input(tag="email")
  inspect(name1 == name2, content="true")
  inspect(name1 == email, content="false")
}

///|
#cfg(target="js")
test "event spec: const click bindings stay Eq, differ from text bindings" {
  let click1 : EventBinding[RendererMsg] = on_click(Increment)
  let click2 : EventBinding[RendererMsg] = on_click(Increment)
  let text_binding : EventBinding[RendererMsg] = on_input(tag="name")
  inspect(click1 == click2, content="true")
  inspect(click1 == text_binding, content="false")
}

///|
#cfg(target="js")
test "keyed view value stays cacheable: equal trees are Eq, reorder/rekey differ" {
  let a : Html[RendererMsg] = keyed_node("ul", [
    ("1", text("one")),
    ("2", text("two")),
  ])
  let same : Html[RendererMsg] = keyed_node("ul", [
    ("1", text("one")),
    ("2", text("two")),
  ])
  // Equal keyed trees compare equal, so an unchanged view is skipped (backdating).
  inspect(a == same, content="true")
  // Reordering the same keys is a real change at the value layer.
  let reordered : Html[RendererMsg] = keyed_node("ul", [
    ("2", text("two")),
    ("1", text("one")),
  ])
  inspect(a == reordered, content="false")
  // Changing a key is also a value change (old node dropped, new node created).
  let rekeyed : Html[RendererMsg] = keyed_node("ul", [
    ("1", text("one")),
    ("9", text("two")),
  ])
  inspect(a == rekeyed, content="false")
}
