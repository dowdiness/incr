# Plan 008: Extend controlled `value` reconciliation to `<textarea>` in incr_tea

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat f839477..HEAD -- incr_tea/renderer_js.mbt incr_tea/renderer_wbtest.mbt`
> If either file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `f839477`, 2026-07-19

## Why this matters

incr_tea's controlled-form reconciliation (PRs #403–#408) re-asserts the live
DOM `value`/boolean properties of controlled elements so the DOM cannot drift
from the model, even on flushes where the view is unchanged. That logic only
recognizes `input` and `select` as value-bearing tags. `<textarea>` — the
third standard value-bearing form control — is excluded from both the initial
property write and the `ViewUnchanged` re-assert path, even though it is
expressible today via the public generic constructor `node("textarea", ...)`
(`incr_tea/html.mbt:538`) and `on_input` (`incr_tea/html.mbt:457`) attaches to
any tag. A controlled textarea therefore silently drifts: setting only the
`value` HTML attribute does not control a textarea's live `.value`. This is
exactly the drift class the controlled-form work exists to prevent, missing
for one tag.

## Current state

Relevant files (module `dowdiness/incr_tea`, `preferred_target = "js"`; all
renderer code is `#cfg(target="js")`):

- `incr_tea/renderer_js.mbt` — JS renderer; the two tag predicates to extend
  are at lines 581 and 723.
- `incr_tea/renderer_wbtest.mbt` — whitebox tests; the controlled-form tests
  to model new tests after are `test "#003: equal Html flush restores
  controlled false properties without patching"` (line 1023) and `test "#003:
  equal Html flush restores controlled true booleans"` (line 1172).
- `incr_tea/html.mbt` — public Html constructors; `node` (line 538) is the
  generic tag constructor, `on_input` (line 457). No `textarea` helper exists
  and this plan does not add one.

Excerpt 1 — `incr_tea/renderer_js.mbt:575-597` (`classify_controlled_property`):

```moonbit
fn classify_controlled_property(
  tag : String,
  attr : Attribute,
) -> ControlledProperty? {
  if (tag == "input" || tag == "select") &&
    attr.name == "value" &&
    attr.bool_value is None {
    Some(ControlledValue(attr.value))
  } else {
    match attr.bool_value {
      Some(value) =>
        if is_controlled_bool_property(attr.name) {
          Some(ControlledBool(name=attr.name, value~))
        } else {
          None
        }
      None => None
    }
  }
}
```

Excerpt 2 — `incr_tea/renderer_js.mbt:700-728` (`set_attr_value`, tail):

```moonbit
  match bool_value {
    Some(true) => {
      dom_set_bool_property(element, name, true)
      dom_set_attr(element, name, "")
    }
    Some(false) => {
      dom_set_bool_property(element, name, false)
      dom_remove_attr(element, name)
    }
    None => dom_set_attr(element, name, value)
  }
  if (tag == "input" || tag == "select") && name == "value" {
    dom_set_value_property(element, value)
  }
}
```

How the pieces connect: `set_attr_value` runs on initial render and on
attribute patches; `classify_controlled_property` feeds
`reconcile_controlled_attr` (`renderer_js.mbt:~599`), which the
`ViewUnchanged` flush branch reaches via `reconcile_controlled_rendered`
(`renderer_js.mbt:~1355`). Adding `textarea` to BOTH predicates covers both
paths; there is no third site (verified at planning time — these are the only
two `tag == "input" || tag == "select"` occurrences in the file).

Repo conventions that apply:

- After every edit run `NEW_MOON_MOD=0 moon check` (hook-enforced; plain
  `moon ...` without the prefix is blocked in this environment).
- Before committing: `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt`,
  then inspect `git diff incr_tea/pkg.generated.mbti` — this plan changes no
  public API, so the `.mbti` diff must be empty.
- Tests use `inspect(...)`/`assert_true(...)`; the `#003` tests use a
  `__recordPropertyWrite` JS harness to assert which DOM property writes
  happened — reuse that harness, do not invent a new one.

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---|---|---|
| Typecheck | `NEW_MOON_MOD=0 moon check` | exit 0, no errors |
| Full tests | `NEW_MOON_MOD=0 moon test` | all pass (~1205+ blocks) |
| Format/interfaces | `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt` | exit 0; empty `.mbti` diff |

Note: `moon test -f <file>` filtering is unreliable in this toolchain — run
the full suite rather than a file filter.

## Scope

**In scope** (the only files you may modify):

- `incr_tea/renderer_js.mbt`
- `incr_tea/renderer_wbtest.mbt`

**Out of scope** (do NOT touch, even though they look related):

- `incr_tea/html.mbt` / `html_attrs.mbt` — no new `textarea` convenience
  helper in this plan; `node("textarea", ...)` is the supported spelling.
- `incr_tea/pkg.generated.mbti` — regenerated by `moon info` only; a nonempty
  diff means you changed public API, which is out of scope.
- `incr_tea/controlled_reconcile_dom_bench.mbt` and other bench files.
- `examples/**` — no demo updates in this plan.

## Git workflow

- Branch: `advisor/008-controlled-textarea-value` (do not commit to `main`).
- Commit style: conventional commits, e.g. `fix(incr_tea): control textarea
  value like input/select`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Extend both tag predicates

In `incr_tea/renderer_js.mbt`, change both occurrences of

```moonbit
(tag == "input" || tag == "select")
```

to

```moonbit
(tag == "input" || tag == "select" || tag == "textarea")
```

— one in `classify_controlled_property` (line 581 area), one in
`set_attr_value` (line 723 area). No other logic changes.

**Verify**: `NEW_MOON_MOD=0 moon check` → exit 0.
**Verify**: `grep -cn 'tag == "textarea"' incr_tea/renderer_js.mbt` → `2`.

### Step 2: Add controlled-textarea regression tests

In `incr_tea/renderer_wbtest.mbt`, add two tests modeled structurally on the
`#003` tests at lines 1023 and 1172 (same setup/teardown, same
`__recordPropertyWrite` harness where they use it):

1. `test "controlled textarea value is asserted on initial render"` — render
   a view containing `node("textarea", [attr("value", "hello")], [])` (adjust
   to the exact `node` signature at `html.mbt:538`), flush, and assert the
   live DOM value property equals `"hello"` (the existing tests show how the
   harness reads back property state; mirror the input-value equivalent).
2. `test "equal Html flush restores controlled textarea value"` — after
   initial render, mutate the DOM value out-of-band the same way the `#003`
   tests simulate user interaction for inputs, dispatch a message that
   produces an EQUAL view (ViewUnchanged path), flush, and assert the value
   was re-asserted to the model's value.

Before writing expectations, read the two `#003` tests fully — copy their
program/scheduler bootstrap verbatim rather than reconstructing it.

**Verify**: `NEW_MOON_MOD=0 moon test` → all pass, including the 2 new tests.

### Step 3: Format and interface check

Run `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt`.

**Verify**: `git diff --stat -- '*.mbti'` → empty (no public API change).

## Test plan

Covered in Step 2. Cases: initial-render property write for textarea;
ViewUnchanged re-assert after out-of-band DOM drift. Pattern:
`incr_tea/renderer_wbtest.mbt` `#003` tests (lines 1023, 1172). Verification:
`NEW_MOON_MOD=0 moon test` all green with 2 added tests.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `NEW_MOON_MOD=0 moon check` exits 0
- [ ] `NEW_MOON_MOD=0 moon test` exits 0; 2 new textarea tests present and pass
- [ ] `grep -c 'tag == "textarea"' incr_tea/renderer_js.mbt` returns `2`
- [ ] `git diff --stat -- '*.mbti'` is empty
- [ ] `git status` shows modifications only to the two in-scope files
- [ ] `plans/README.md` status row for 008 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The two predicates are not at/near lines 581 and 723, or there are more
  than two `tag == "input" || tag == "select"` occurrences in
  `renderer_js.mbt` (a third site means the connect-the-paths analysis above
  is stale).
- The `#003` test harness cannot express an out-of-band textarea value
  mutation (would require extending the JS test harness — report instead).
- Any pre-existing test fails after Step 1 (would mean some caller depends on
  textarea being UNcontrolled — that's a design decision for the maintainer,
  not a test to update).
- `moon info` produces a nonempty `.mbti` diff.

## Maintenance notes

- If a `textarea` convenience helper is later added to `html.mbt` (deferred
  from this plan to keep the public surface decision with the maintainer),
  its docs should state that `value` is controlled, matching `input`.
- Reviewer should scrutinize: that the ViewUnchanged re-assert test really
  exercises `reconcile_controlled_rendered` (equal view), not the
  attr-patch path — the `#003` tests are the authority on how to force that.
- Related recorded item (not this plan): the index's R22 records the
  measurement question about the ViewUnchanged full-tree controlled scan
  cost; adding textarea slightly widens that scan's hit set, which is fine at
  current scale but relevant if R22 is ever picked up.
