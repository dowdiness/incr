# Incremental TEA controlled form-property semantics

**Date:** 2026-07-15  
**Status:** Accepted  
**Amended:** 2026-07-20 — controlled `value` semantics now include `<textarea>`<br>
**Issue:** [#286](https://github.com/dowdiness/incr/issues/286)

## Context

`incr_tea` stores cacheable views as closure-free `Html` values. Browser-owned
form state can therefore drift between equal-view flushes: users edit inputs,
select options, and range/date controls without changing the virtual value that
the renderer compares. Serialized attributes alone do not repair those live DOM
properties.

## Decision

1. `attr("value", value)` is an explicit controlled live `value` intent on
   `<input>`, `<select>`, and `<textarea>` elements. The renderer writes the DOM
   property during mount and value-changing diffs, and repairs drift during
   equal-view flushes. Omitting `attr("value", ...)` leaves the live value
   browser-owned.
2. Select value repair is parent-authoritative and post-order. The renderer
   reconciles option children first, then applies the select's controlled value.
   This preserves a selected value when options are mounted, keyed-diffed, or
   added in the same render. Equal-view traversal uses the same child-first
   ordering.
3. `Attrs::checked`, `Attrs::disabled`, and `Attrs::selected` remain explicit
   controlled boolean properties. `prop_bool(name)` is the escape hatch for a
   one-off `true` boolean property; use the `Attrs` helpers when both `true` and
   `false` need to remain explicit. Omitting the helper leaves the property
   browser-owned.
4. `on_input(tag=...)` and `on_change(tag=...)` remain pure descriptors. They
   store typed ids in `Html`; `BrowserRenderer::mount` extracts DOM payloads and
   resolves them into messages.
5. Other properties and static attributes remain uncontrolled unless explicitly
   covered above. No closure-valued handlers or generic mutable DOM-property map
   is added to `Html`.

## Consequences

- Equal-view repair remains bounded to the existing controlled-property families
  and does not count as a virtual-tree patch.
- Select/date/range behavior can be exercised without storing DOM objects or
  closures in tracked views.
- Contenteditable regions, custom elements, and other live DOM properties still
  require a concrete consumer and a separate semantics decision rather than
  silently widening controlled-property handling.

## Amendment rationale

The original boundary covered only the controls exercised by #286. The public
`node("textarea", ...)` constructor and `on_input` descriptor can also express a
controlled textarea without changing `Html : Eq`; treating an explicit
`attr("value", value)` as model-owned keeps that control consistent with input
and select. This remains a narrow tag-and-property contract, not a generic
mutable DOM-property map.

## Verification

The browser smoke suite covers non-first initial select values, `on_change`
selection, a same-render option addition with selection, date/range values,
DOM-node identity, and equal-view drift repair. The MoonBit suite covers the
existing checked/disabled/selected reconciliation tests plus initial textarea
value assignment and equal-view textarea drift repair.
