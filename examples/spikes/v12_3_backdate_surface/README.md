# V12.3 backdate surface spike

> **PROTOTYPE — evidence only. Do not merge this module into the public API.**

- **Reader:** maintainers resolving the V12.3 BackdateEq and non-Eq/no-backdate mapping in #453 and #457.
- **Decision:** determine whether callable View creation can preserve Eq, custom BackdateEq, and unconditional-change tiers without weakening the common path.
- **Keep until:** V12.3 records the target backdating mapping and any implementation no longer needs the compiler evidence.
- **Disposition:** preserve only on the evidence branch; do not merge the spike into `main`.

## Run

From the repository root:

```bash
./examples/spikes/v12_3_backdate_surface/check.sh
```

The command runs native positive probes, then activates each disabled negative probe and checks the expected compiler diagnostic.

## Verdict

**Pass with constraints.**

Use a three-tier target surface:

```moonbit
Store::derived[T : Eq](Store, () -> T raise ReadError, label?) -> View[T]
Store::derived_with_backdate[T : BackdateEq](Store, () -> T raise ReadError, label?) -> View[T]
Store::derived_no_backdate[T](Store, () -> T raise ReadError, label?) -> View[T]
```

`Store::derived` remains the only common-path creation name. The suffixes identify explicit advanced change-detection policies while preserving `derived` as the concept name. Current `map`, `map2`, and `map3` variants collapse into these Store constructors because callable Views carry no methods; callers read source Views inside the zero-argument compute.

Preserve `HasChangedAt` and `BackdateEq` as public target capabilities. Preserve the default revision comparison and custom override. The comparator closure remains a kernel detail rather than a public creation argument.

The spike reuses current `Runtime`, `Derived`, `Derived::with_backdate`, and `Derived::derived_no_backdate` as backing. It validates API shape and trait bounds, not replacement-kernel ownership or lifecycle behavior. Existing current-engine tests remain the semantic oracle for early cutoff and unconditional propagation.

## Named consumer evidence

`dowdiness/moondsp/pattern/pattern_doc.mbt`'s `PatternDoc[A]` is non-`Eq` because it carries closure fields. It implements `HasChangedAt` and overrides `BackdateEq::backdate_equal` to compare a full two-dimensional revision, including a fingerprint omitted by its one-dimensional `changed_at` projection. That override is load-bearing for `AcceptedDerived::accepted_memo` last-good behavior.

Moving this predicate into a raw creation-time callback would repeat type-owned identity at every call site and make omission possible. Keeping the trait attaches the invariant to the value type once.

## Positive state

```text
eq.value=42
backdate.value=7,revision=initial,fingerprint=11
backdate.same_identity=true
backdate.different_fingerprint=false
no_backdate.non_eq.value=5
positive_probes=PASS
```

`RevisionStamped` contains a function field and has no `Eq` implementation. It compiles through `derived_with_backdate` and its custom override distinguishes equal revision numbers with different fingerprints. Another non-Eq value compiles through `derived_no_backdate`.

## Negative compiler evidence

| Probe | Diagnostic | Meaning |
|---|---|---|
| non-Eq common `derived` | `[4018]` missing `Eq` | the ergonomic default retains equality cutoff |
| missing trait `derived_with_backdate` | `[4018]` missing `BackdateEq` | custom backdating remains type-owned and explicit |

## Alternatives rejected

| Alternative | Reason rejected |
|---|---|
| Mandatory policy parameter on `Store::derived` | taxes every common Eq call and weakens the selected minimal surface |
| Optional policy parameter | generic `None` cannot introduce conditional `T : Eq` evidence for the default path |
| Receiver wrappers such as `store.no_backdate().derived` | preserve one spelling at the cost of extra public types, call depth, and concepts |
| Raw `(T, T) -> Bool` argument | leaks kernel policy and repeats the named consumer's type invariant at call sites |
| Remove `BackdateEq` | breaks the `PatternDoc` consumer and the advanced AcceptedDerived mapping obligation |

## Constraints

The provider uses local `ProbeReadError`; V12.10 still owns the real `ReadError` effect representation. AcceptedDerived ownership and fold APIs remain a separate V12.3 blocker even though their BackdateEq dependency is preserved here.

## Reuse check

- Reused project APIs: `Runtime`, all three current `Derived` creation tiers, `HasChangedAt`, `BackdateEq`, and `Revision`.
- Checked MoonBit core APIs: `Eq`, function values, and `Option`. `Option` cannot supply conditional trait evidence for a defaulted policy.
- Checked but not exposed: the current kernel comparator callback is an implementation seam, not a target public capability.
- New helpers: two private adapters translate the probe effect and current Derived handle into callable View. They contain no domain transformation or mutable collection.
- Remaining imperative code: none beyond invoking function-valued test fields to prove the values are non-Eq.
