# Plan 003: Reconcile controlled DOM properties when virtual HTML is unchanged

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `rtk git diff --stat 31afb08..HEAD -- incr_tea/html.mbt incr_tea/html_attrs.mbt incr_tea/renderer.mbt incr_tea/renderer_js.mbt incr_tea/renderer_wbtest.mbt incr_tea/pkg.generated.mbti examples/incr_tea/scripts/test-keyed-dom.mjs incr_tea/README.mbt.md CHANGELOG.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `31afb08`, 2026-07-13

## Why this matters

`BrowserRoot::flush` treats equal `Html` as permission to do no DOM work. That is correct for ordinary attributes, child diffing, keyed movement, and listener identity, but it is incorrect for controlled form properties: the browser or user can change live `value`, `checked`, `disabled`, or `selected` state without changing the model's `Html`. If the application rejects that edit or an unrelated runtime change causes an equal-view flush, the stale browser state remains visible indefinitely. This plan keeps the equal-tree fast path while adding a narrow property-only repair that never rebuilds nodes, moves keyed children, or puts closures into `Html`.

## Current state

- `incr_tea/renderer.mbt` — `WatchedHtmlRoot` caches the last pure view and currently collapses both disposal and equality into `None` (lines 93–129):

  ```moonbit
  priv struct WatchedHtmlRoot[Msg] {
    program : Program[Msg, Html[Msg]]
    label : String
    stats : RenderStats
    mut last_view : Html[Msg]?
  }

  fn[Msg : Eq] WatchedHtmlRoot::read_changed(
    self : WatchedHtmlRoot[Msg],
  ) -> Html[Msg]? {
    guard self.program.read_view() is Some(next) else { return None }
    match self.last_view {
      Some(prev) =>
        if prev == next {
          self.stats.skipped_patches = self.stats.skipped_patches + 1
          None
        } else {
          self.stats.patch_attempts = self.stats.patch_attempts + 1
          self.last_view = Some(next)
          Some(next)
        }
      // ...initial-read branch...
    }
  }
  ```

- `incr_tea/renderer_js.mbt` — normal attribute diffing only writes equal static attributes when their direct resolver changes (lines 510–546), so browser-side property drift is invisible:

  ```moonbit
  fn patch_attrs(
    tag : String,
    old_attrs : Array[Attribute],
    new_attrs : Array[Attribute],
    element : DomElement,
    direct_resolvers : DirectPatchResolvers,
  ) -> Unit {
    // ...remove old attributes...
    for next in new_attrs {
      match attr_by_name(old_attrs, next.name) {
        None => patch_attr(tag, element, next, direct_resolvers)
        Some(prev) =>
          if prev != next {
            patch_attr(tag, element, next, direct_resolvers)
          } else {
            // Equal static attributes do nothing.
            match (prev.direct, next.direct) {
              (None, None) => ()
              // ...direct resolver comparison...
            }
          }
      }
    }
  }
  ```

- `incr_tea/renderer_js.mbt` — full patches already know that `input.value` and boolean form state are DOM properties, not merely attributes (lines 566–587):

  ```moonbit
  fn set_attr_value(
    tag : String,
    element : DomElement,
    name : String,
    value : String,
    is_bool? : Bool = false,
  ) -> Unit {
    if is_bool {
      dom_set_bool_property(element, name, true)
      dom_set_attr(element, name, "")
    } else {
      dom_set_attr(element, name, value)
    }
    if tag == "input" && name == "value" {
      dom_set_value_property(element, value)
    }
  }
  ```

- `incr_tea/renderer_js.mbt` — the equality result prevents `BrowserRoot::flush` from reaching the rendered tree at all (lines 1196–1212):

  ```moonbit
  fn[Msg : Eq] BrowserRoot::flush(self : BrowserRoot[Msg]) -> Unit {
    guard self.watched.read_changed() is Some(next) else { return }
    // ...build EventSink...
    self.rendered = Some(
      match self.rendered {
        None => { /* initial render */ }
        Some(old) => diff_rendered(old, next, self.host, sink)
      },
    )
  }
  ```

- `incr_tea/html.mbt` and `incr_tea/html_attrs.mbt` — `Attribute` is closure-free and derives `Eq`, but boolean helpers encode `false` by omitting the attribute. That makes a controlled false value indistinguishable from an uncontrolled missing property on an equal tree:

  ```moonbit
  pub struct Attribute {
    priv name : String
    priv value : String
    priv direct : DirectAttrId?
    priv is_bool : Bool
  } derive(Eq, Debug)

  pub fn Attrs::checked(self : Attrs, value : Bool) -> Attrs {
    if value { self.append(prop_bool("checked")) } else { self }
  }
  ```

- `incr_tea/renderer_js.mbt:374-392` caches a `DomElement` and attributes in every `RenderedElem` / `RenderedKeyedElem`. Use that existing rendered tree for reconciliation; do not query or recreate the DOM tree by selector.
- `incr_tea/renderer_wbtest.mbt:312-460` provides a test-only JavaScript DOM and animation-frame queue. Extend this harness rather than introducing a second fake DOM.
- `examples/incr_tea/scripts/test-keyed-dom.mjs:295-327` is the real Playwright regression pattern for controlled `value`; it currently covers a changed model value, not rejected browser mutation followed by equal output.
- Repository conventions: MoonBit uses 2-space formatting, `Type::method`, `snake_case` tests, and `///` on every public item. `Html` remains an opaque, defensively copied, closure-free value with derived `Eq`; see `incr_tea/html.mbt:302-329`. Tests in `*_wbtest.mbt` may inspect private renderer state. Generated `pkg.generated.mbti` files are changed only by `moon info`, never by hand.
- Architecture constraint from `AGENTS.md`: keep the desired-property classification and reconciliation decision deterministic; keep DOM reads/writes in the renderer's imperative shell. Local mutation while constructing private result arrays is acceptable, but do not expose mutable collections.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Targeted renderer tests | `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` | exit 0; all renderer white-box tests pass |
| Real browser regression | `rtk npm --prefix examples/incr_tea run test:dom` | exit 0; every line is `✓ ...`, including the new controlled equal-view case |
| Format | `rtk moon fmt` | exit 0; MoonBit sources are formatted |
| Regenerate interfaces | `rtk moon info` | exit 0; generated interfaces refresh |
| Check | `rtk moon check` | exit 0; no diagnostics |
| Package tests | `rtk moon test incr_tea --target js` | exit 0; all `incr_tea` tests pass |
| Full tests | `rtk moon test` | exit 0; full workspace suite passes |
| Interface drift | `rtk git diff --exit-code -- incr_tea/pkg.generated.mbti` | exit 0; no public API diff is expected |

## Suggested executor toolkit

- Invoke the `moonbit` skill if available for current syntax, package/test conventions, and `moon` verification discipline.
- Invoke `moonbit-verification` if available before finalizing; this plan changes JS-target MoonBit plus JavaScript FFI.
- Use `incr_tea/renderer_wbtest.mbt:312-460` as the fake-DOM exemplar and `examples/incr_tea/scripts/test-keyed-dom.mjs:295-327` as the Playwright exemplar.

## Scope

**In scope** (the only files you should modify):

- `incr_tea/html.mbt` — preserve explicit desired false values in pure attribute data if tests prove omission is ambiguous.
- `incr_tea/html_attrs.mbt` — make `checked`, `disabled`, and `selected` retain controlled intent for both booleans.
- `incr_tea/renderer.mbt` — distinguish changed, unchanged, and disposed watched-view reads.
- `incr_tea/renderer_js.mbt` — DOM property getters and narrow rendered-tree reconciliation.
- `incr_tea/renderer_wbtest.mbt` — fake-DOM regression and invariants.
- `examples/incr_tea/scripts/test-keyed-dom.mjs` — real browser regression for rejected `value` and `checked` mutations.
- `incr_tea/pkg.generated.mbti` — only if regenerated by `rtk moon info`; no diff is expected.
- `incr_tea/README.mbt.md` — correct the controlled-property behavior note if implementation changes false-value representation.
- `CHANGELOG.md` — add a concise Unreleased bug-fix entry.
- `plans/README.md` — status-row update only.

**Out of scope** (do NOT touch, even though they look related):

- Keyed diff planning, minimal DOM moves, event listener replacement, focus commands, subscriptions, or direct-patch performance.
- Any removal or weakening of `Html : Eq`, defensive array copies, or the closure-free event/payload boundary.
- Treating every ordinary HTML attribute as controlled or diffing the full tree on equal `Html`.
- Replacing DOM nodes to repair properties; reconciliation must preserve node identity, focus, selection, and keyed order.
- Adding selectors or production DOM fixtures solely for tests; the existing greet controls plus white-box fake DOM are sufficient.
- Public API signature changes. The opaque `Attribute` representation may change privately, but its generated public interface must not.

## Git workflow

- Branch: `advisor/003-controlled-dom-reconciliation`
- Commit logical units with conventional commits, matching recent history such as `fix: ...` and `feat: ...`. Recommended final commit: `fix(incr_tea): reconcile controlled DOM properties`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Pin the bug with failing Node and browser tests

In `incr_tea/renderer_wbtest.mbt`, extend the existing fake `Element` with live `checked`, `disabled`, and `selected` boolean properties plus test-only helpers that mutate/read a node by an `id`. Add one stable-view renderer test that:

1. mounts a tree containing an `input` with `value="accepted"`, a checkbox with `.checked(false)`, a control with `.disabled(false)`, and an `option` with `.selected(false)`;
2. records the relevant DOM-node identities and focuses the text input;
3. mutates the four live properties to rejected values without changing model inputs;
4. calls `renderer.flush_all()`, producing equal model `Html`;
5. expects all properties to return to the model values while identities, focus, child order, and `patch_attempts` remain unchanged and `skipped_patches` increments.

Use the public `Attrs` helpers for boolean properties; this ensures the test exposes the current false-by-omission ambiguity. Add a second positive test for controlled `true` boolean values so reconciliation does not only handle false.

In `examples/incr_tea/scripts/test-keyed-dom.mjs`, use the existing greet text input and checkbox. Mutate their live `value` / `checked` properties directly without firing their input/change handlers, click the counter's `touch unread field` button to cause the shared renderer to flush while greet `Html` remains equal, wait for the frame counter to advance, and assert both live properties are restored. Also assert the text input is the same node and remains focused.

Run both tests before implementation and record the expected baseline failure. The new assertions must fail because equal `Html` returns before DOM property reconciliation; existing tests must remain green. Do not weaken the assertions to make baseline pass.

**Verify**: `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` → exits nonzero only at the new controlled equal-view assertions, with the live properties still holding the rejected values.

**Verify**: `rtk npm --prefix examples/incr_tea run test:dom` → exits nonzero only at the new rejected-mutation test; all earlier keyed identity/focus tests print `✓`.

### Step 2: Preserve explicit controlled-boolean intent in pure virtual data

In `incr_tea/html.mbt`, replace the one-bit `is_bool` representation with a private representation that distinguishes string attributes from a controlled boolean whose desired value is either `true` or `false` (for example, `bool_value : Bool?`). Keep `Attribute` closure-free and deriving `Eq, Debug`. Preserve `prop_bool(name)` as the public presence-means-true constructor; add a private constructor for explicit controlled booleans if needed.

In `incr_tea/html_attrs.mbt`, make `.checked(value)`, `.disabled(value)`, and `.selected(value)` append an explicit pure controlled-boolean descriptor for both values. Update full attribute application/removal in `incr_tea/renderer_js.mbt` so:

- desired true sets the DOM property true and keeps the empty HTML attribute;
- desired false sets the property false and removes the HTML attribute;
- removing a formerly boolean descriptor also sets the property false;
- ordinary string and direct attributes keep current behavior.

Keep the decision about desired property state pure; only the existing JS renderer boundary may touch `DomElement`. Do not add callbacks, elements, or mutable browser objects to `Attribute` / `Html`.

Update `incr_tea/README.mbt.md` only where it currently says false is represented solely by absence; document that the public helper still produces normal absent HTML attributes while retaining private controlled intent for DOM repair.

**Verify**: `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` → existing initial-render and changed-tree boolean tests pass; the equal-view test may still fail until Step 3.

**Verify**: `rtk moon check` → exit 0 with `Attribute : Eq` and `Html : Eq` intact.

### Step 3: Add the narrow equal-view controlled-property repair

In `incr_tea/renderer.mbt`, replace the ambiguous optional return of `WatchedHtmlRoot::read_changed` with a private outcome that distinguishes at least `Disposed`, `Changed(Html[Msg])`, and `Unchanged`. Preserve the exact stats contract: an equal view increments `skipped_patches`, a changed/initial view increments `patch_attempts`, and controlled-property repair is not a virtual-DOM patch attempt.

In `incr_tea/renderer_js.mbt`:

1. add private JS FFI getters for the live string `value` and named boolean property;
2. add a deterministic predicate/classifier limited to `input.value` and explicit `checked`, `disabled`, and `selected` boolean descriptors;
3. add a recursive `Rendered` traversal that visits `RenderedElem` and `RenderedKeyedElem`, compares only those live properties with cached desired values, writes only mismatches, and recursively visits existing rendered children without changing their order;
4. change `BrowserRoot::flush` so `Changed(next)` keeps the existing initial/full diff path, `Disposed` returns, and `Unchanged` runs only this controlled-property traversal against `self.rendered`.

Use cached `Rendered` nodes/attributes rather than traversing `Html` alongside DOM. Do not call `diff_rendered`, `patch_attrs`, `dom_replace_*`, keyed planners, or event attachment from the unchanged branch. Do not reset text selection when the live value already equals the desired value; compare before assigning.

**Verify**: `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` → exit 0; the new four-property regression and all existing stats, focus, keyed, lifecycle, and after-flush tests pass.

**Verify**: `rtk npm --prefix examples/incr_tea run test:dom` → exit 0; rejected text/checkbox mutations are repaired and every existing identity/focus test remains green.

### Step 4: Document and run the repository gates

Add an Unreleased `CHANGELOG.md` entry stating that equal-view renderer flushes now restore controlled form properties without running a virtual-tree patch. Keep docs behavior-focused; do not expose private representation names.

Run the repository pre-PR sequence in order. Inspect generated interfaces rather than editing them. Because all new types/helpers should be private and public signatures are unchanged, `incr_tea/pkg.generated.mbti` must have no diff.

**Verify**: `rtk moon fmt` → exit 0.

**Verify**: `rtk moon info` → exit 0, then `rtk git diff --exit-code -- incr_tea/pkg.generated.mbti` → exit 0.

**Verify**: `rtk moon check` → exit 0 with no diagnostics.

**Verify**: `rtk moon test incr_tea --target js` → exit 0.

**Verify**: `rtk npm --prefix examples/incr_tea run test:dom` → exit 0.

**Verify**: `rtk moon test` → exit 0; full workspace suite passes.

## Test plan

- `incr_tea/renderer_wbtest.mbt`:
  - rejected `input.value` mutation plus equal model output restores the desired string;
  - explicit false `checked`, `disabled`, and `selected` are restored after live mutation;
  - explicit true boolean values are restored after live mutation;
  - no write occurs when a controlled property already equals the desired value (instrument the fake setter count if necessary);
  - ordinary equal-tree attributes/text do not run a patch;
  - node identity, keyed order, focus, `patch_attempts`, and `skipped_patches` retain current semantics.
- `examples/incr_tea/scripts/test-keyed-dom.mjs`:
  - real Chromium rejects direct live mutations of the greet `value` and `checked` properties on an unrelated equal-view frame;
  - the focused input remains the identical DOM node.
- Model white-box structure after `renderer root: patch attempts only when watched Html changes` and the fake DOM at `incr_tea/renderer_wbtest.mbt:312-460`.
- Model browser structure after `semantic editor controlled input patches dirty value property` at `examples/incr_tea/scripts/test-keyed-dom.mjs:295-327`.
- Verification: `rtk moon test incr_tea -f renderer_wbtest.mbt --target js` and `rtk npm --prefix examples/incr_tea run test:dom` → all pass, including the new cases.

## Done criteria

- [ ] The new tests demonstrably failed before the implementation and pass afterward.
- [ ] Equal `Html` restores rejected `value`, `checked`, `disabled`, and `selected` live property mutations.
- [ ] `Html : Eq`, closure-free virtual data, defensive attribute arrays, ordinary equal-tree patch skipping, keyed identity/order, and focus are preserved.
- [ ] Equal-view property repair performs no node replacement, child movement, listener attachment, or ordinary attribute/text diff.
- [ ] `rtk moon fmt`, `rtk moon info`, `rtk moon check`, `rtk moon test incr_tea --target js`, `rtk npm --prefix examples/incr_tea run test:dom`, and `rtk moon test` all exit 0.
- [ ] `rtk git diff --exit-code -- incr_tea/pkg.generated.mbti` exits 0.
- [ ] `rtk git diff --name-only` lists only in-scope files plus the permitted `plans/README.md` status edit.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" no longer matches the excerpts or another change already introduced an unchanged-tree reconciliation contract.
- Correct false-value repair appears to require a public `Attribute`, `Attrs`, `Html`, or renderer signature change; this plan permits private representation changes only.
- The implementation cannot distinguish a controlled false boolean from an uncontrolled missing attribute without changing semantics for callers that never use `Attrs::checked/disabled/selected`.
- Any solution requires full-tree diffing, node replacement, keyed child movement, listener reattachment, or storing DOM objects/closures in `Html`.
- A live property assignment when the value already matches moves the caret or changes focus; add the specified getter comparison rather than accepting that regression.
- `moon info` produces a public interface diff.
- A verification command fails twice after a reasonable fix attempt, or the fix requires an out-of-scope file.

## Maintenance notes

- Any future controlled property must opt into the explicit controlled descriptor and the narrow classifier; do not infer control from every ordinary attribute name.
- Reviewers should scrutinize explicit false representation, attribute-vs-property behavior, and whether the unchanged branch can reach any DOM structural operation.
- This traversal is intentionally correctness-first and bounded to four properties. Do not fold direct-patch or general attribute performance work into it without a benchmark and separate plan.
- Real-browser coverage is load-bearing because fake DOM property semantics are simpler than Chromium's form-control behavior.
