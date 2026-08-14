# Incr Next roadmap

K1.1 is **ACCEPTED** at implementation head
`0ad8f5ae60082dfc6410aac781baa61f52c67d79`. Its local matrix, hosted CI,
boundary probes, native ownership evidence, generated-interface review,
independent reviews, and maintainer acceptance pass.

The accepted scope is Store, Region, Source, Query, opaque View, QueryContext,
Transaction, Revision, structural errors, and the independent testkit. Plan 015
remains **IN PROGRESS**.

K1.2 implementation is complete and its local gate passes, but it is
**NOT ACCEPTED**. K1.2a implements:

- Query-local typed memo ownership after a generated-interface compile probe
  selects the public `K : Hash + Eq` bound;
- Source, Query invocation, and Revision-clock trace ownership/metadata on
  successful memos;
- same-epoch hits, with stale epochs still recomputing unconditionally;
- close-time release and work-count evidence.

K1.2b implements forward trace verification and green reuse, including
unrelated publications, selected recomputation, dynamic trace replacement,
Revision-clock verification, and same-Store cross-Region branch-away. K1.2c
now implements target-local structural failure atomicity: initial failures do
not install memos, failed recomputes return the current error without stale
fallback, successful upstream work remains installed, and recovery preserves
memo identity while replacing value/trace and stamps.

The [K1.2 local validation record](k1-2-validation.md) captures the passing
local gate. Hosted CI, implementation PR creation or push, maintainer
acceptance, and merge remain pending separate authorization. K1.3 and later
work remains blocked and uncommissioned.

K1.2 accepts only acyclic invocation graphs and must preserve the K1.1 public
capability surface, Fresh import independence, backend matrix, and zero current
`incr/` diff.

Blocked and uncommissioned until separate maintainer decisions: invocation
cycles, cutoff/backdating, proof loss/eviction, Mount/Program, Canopy
integration, ADR, and publication.
