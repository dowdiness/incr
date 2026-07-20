# ADR: Datalog Relation-Rule Lifecycle Integrity

**Date:** 2026-07-18
**Status:** Accepted
**Implementation plan:** Plan 005 (deleted after completion; recoverable via Git history per the documentation retention policy)

---

## Context

Rules retain declared input and output relation IDs in `RuleData`. Before this
lifecycle contract, disposing a declared relation could leave a live rule whose
closure aborted on a disposed output or silently treated a cleared input as
empty. The existing declaration metadata is sufficient to enforce teardown
order without inferring closure captures or introducing ownership machinery.

## Decision

1. `Runtime::new_rule` validates declarations and stores defensive snapshots of
   the input and output arrays. Caller-owned arrays are not retained.
2. A live rule pins every relation it declares as an input, output, or both.
   Callers must dispose all declaring rules before disposing those relations.
3. Relation disposal rejects rather than cascades. The shared lifecycle path
   scans rules in registration order, ignores disposed rules, and reports the
   first live declaration and its role. Only then may relation metadata and
   typed storage be cleared; repeated disposal remains idempotent.
4. The same guard applies to typed relation disposal and generic
   `Runtime::dispose_cell`. A failed disposal leaves the relation intact.
5. Creating a rule with a disposed declared relation aborts with the relevant
   input or output role.
6. After disposal, the only supported relation reads are strict: `Relation`
   `contains`, `iter`, and `delta_iter`, and `MapRelation` `get`, `iter`, and
   `delta_iter` all abort. Fixpoint skips disposed relation slots in every
   phase and never reports them as changed.
7. Declaration metadata is the sole lifecycle authority. There is no cascade,
   reverse index, closure-capture inference, reference counting, or public
   lifecycle/dependency query API.
8. The declaration scan and role classification are a deterministic functional
   core: explicit runtime state in, structured result or `None` out, with no
   abort or mutation. Lifecycle aborts and mutation remain in the imperative
   coordinator shell; the kernel boundary remains one-way.
9. RuleData closure retention and free-list/SoA compaction remain separate,
   unchanged debt and are not addressed by this decision.
10. A fixpoint evaluates a stable rule/relation program. Rule and relation
    disposal during `InFixpoint` is rejected before lifecycle dispatch. The
    disposed-slot guards in the fixpoint loops handle tombstones created before
    evaluation; they do not authorize structural mutation by rule callbacks.

## Rationale

- First-live-rule selection and explicit input/output/both classification make
  diagnostics deterministic.
- Rejecting disposal preserves the invariant without silently destroying rule
  state or requiring a reverse dependency structure.
- Declared IDs are an explicit caller contract. Inferring undeclared relation
  captures would be a separate design problem.
- Keeping query logic pure and lifecycle effects in the coordinator preserves
  the functional-core/imperative-shell boundary and engine isolation.

## Consequences

- Callers use `rt.dispose_rule(rule_id)` before disposing any relation declared
  by that rule.
- Current and frontier reads consistently reject disposed relation handles.
- No public signature or public lifecycle query is added.
- Relation compaction, rule scheduling, retraction, transaction semantics, and
  GC policy remain out of scope.
- Teardown and same-runtime rebuild happen between fixpoints. A rule callback
  that needs teardown must hand that request to an outer lifecycle shell rather
  than disposing rules or relations during evaluation.

## Cross-engine lifecycle follow-up

The broader cross-engine Runtime resource lifecycle model is preserved as gated
research in the [Bonsai-informed core direction note](../research/2026-07-14-bonsai-informed-incr-core-direction.md).
This ADR proves a local lifecycle contract within Datalog; it is not part of
any accepted Runtime-wide lifecycle abstraction. The Datalog contract's
pattern (declaration snapshots, rule-first teardown, pure preflight plus
lifecycle shell) is recorded there as candidate evidence for a shared
mechanism, should an evidence gate fire.

## Verification

The implementation tests cover declaration classification and snapshots,
live-rule disposal rejection, legal teardown and idempotence, strict current
and frontier reads, rejection of relation/rule disposal from rule callbacks,
skipping pre-existing disposed slots during fixpoint, and same-runtime rebuild
after full teardown. The engine-isolation check passes and generated public
interfaces remain unchanged.
