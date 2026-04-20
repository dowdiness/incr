# Analysis: alien-signals vs Salsa-style Incremental Computation

## The Two Frameworks Solve Different (Overlapping) Problems

**Salsa/incr**: Designed for *incremental recomputation* in compilers and IDEs — large, deep dependency graphs where reads are infrequent relative to the graph size, and the cost of recomputation dwarfs the cost of verification. The canonical use case is rust-analyzer recomputing type information after a file edit.

**alien-signals**: Designed for *fine-grained UI reactivity* — shallow, wide dependency graphs where reads are frequent (every render frame), nodes are small (a counter, a string), and the overhead of the framework itself must be minimal. The canonical use case is Vue 3.6's reactivity system.

These are the same *class* of problem (dependency graph with change propagation) but with very different performance profiles, which leads to fundamentally different architectural decisions.

## What We Adopted and What We Learned

### 1. Array-based cell storage (adopted) — Good fit ✓

**alien-signals insight**: Use integer IDs as direct array indices instead of hash-based lookups.

**Fit for incr**: Excellent. `CellId` is already a monotonic integer. Replacing `HashMap[CellId, CellMeta]` with `Array[CellMeta?]` gives O(1) lookup with no hashing overhead. This is a universal optimization that benefits both UI reactivity and compiler incrementality.

**What Salsa lacked**: Salsa uses interned keys with hash-based storage because its keys can be complex (e.g., file paths, function signatures). incr's simpler `CellId` model makes array indexing trivial.

### 2. HashSet deduplication (adopted) — Good fit ✓

**alien-signals insight**: Avoid O(n) scans during dependency recording.

**Fit for incr**: Good. The linear scan in `ActiveQuery::record` was a known bottleneck for memos with many dependencies. A HashSet gives O(1) amortized dedup. alien-signals goes further with its Link-based approach (see §4 below), but HashSet is the right level of complexity for incr's architecture.

### 3. Batch updates with two-phase commit (adopted) — Good fit ✓

**alien-signals insight**: Buffer signal writes during a batch, defer effect execution until batch end.

**Fit for incr**: Good, but the semantics differ importantly. In alien-signals, batching defers *effect execution* (side effects). In incr, batching defers *revision bumps* (the logical clock). Both enable multiple writes to coalesce into a single "transaction."

The two-phase commit (pending_value → commit with equality check → conditional revision bump) is where incr goes beyond what alien-signals does. alien-signals' signals don't do revert detection at the signal level — they propagate `Pending` flags immediately. incr's approach is more conservative: it delays all propagation until batch end, then checks if values actually changed. This is a better fit for the Salsa model where reads are infrequent and you want to minimize the verification surface.

### 4. Iterative graph walking (adopted) — Good fit ✓

**alien-signals insight**: Use explicit stacks instead of recursive calls for graph traversal.

**Fit for incr**: Essential for correctness. Deep dependency chains (250+ levels in our stress test) would overflow the call stack with recursion. alien-signals uses linked-list stacks with label-based continue for maximum performance; incr uses `Array[VerifyFrame]` which is simpler and sufficient.

## What We Deferred and Why

### 5. Subscriber (reverse) links — Deferred, would change the architecture fundamentally

**alien-signals design**: Every node stores both `deps` (what I depend on) and `subs` (who depends on me) as interleaved doubly-linked lists. Each edge is a `Link` node that participates in two lists simultaneously.

**Why it doesn't fit incr today**: This is the biggest architectural difference. incr only stores forward edges (dependencies). Adding subscriber links would:

- Double the edge storage
- Require maintaining bidirectional consistency when dependencies change dynamically
- Change the meaning of `Signal::set()` from "bump a counter" to "walk subscriber graph and propagate flags"

**What Salsa does instead**: Salsa avoids subscriber links entirely. Its pull-based verification walks the *dependency* direction (from consumer to producer) at read time. This is simpler, uses less memory, and is correct — but it means every `Memo::get()` on a stale memo must walk its entire dependency tree.

**When subscriber links would help incr**: If the library is used in scenarios with many reads per revision (e.g., rendering a UI), the cost of repeated verification walks becomes dominant. Subscriber links enable the push-pull hybrid (see §6), which eliminates most verification walks by eagerly marking dirty nodes.

**Verdict**: Subscriber links are a prerequisite for several advanced features (push-pull, GC, effects) but represent a fundamental architecture change. Worth doing only if incr's use cases shift toward UI reactivity.

### 6. Push-pull hybrid invalidation — Deferred, requires subscriber links

**alien-signals design**: Two-phase flag propagation:
1. **Push phase** (`propagate`): When a signal changes, walk subscribers and set `Pending` flags. This is cheap — just bit flags, no computation.
2. **Pull phase** (`checkDirty`): When a computed is read, walk its dependencies to check if `Pending` should become `Dirty`. Only recompute if truly dirty.

The key insight is separating `Pending` (might be dirty) from `Dirty` (known dirty). If a computed recomputes to the same value, its downstream subscribers stay `Pending` but never get upgraded to `Dirty`. This is alien-signals' version of backdating.

**How incr handles this differently**: incr uses revision-based verification instead of flag propagation:
- `changed_at` / `verified_at` timestamps replace `Dirty` / `Pending` flags
- The durability shortcut (`durability_last_changed[level] <= after_revision?`) replaces the push phase — it's a coarse-grained "did anything in this class of inputs change?" check
- Backdating (keeping `changed_at` old when a memo recomputes to the same value) replaces the `Pending → Dirty` upgrade check

**Trade-offs**:

| Aspect | incr (pure pull) | alien-signals (push-pull) |
|--------|-----------------|--------------------------|
| Cost of `Signal::set()` | O(1) — bump revision counter | O(subscribers) — walk and set flags |
| Cost of `Memo::get()` on stale memo | O(dep tree depth) — full verification walk | O(1) if already `Dirty` or `Clean`; O(deps) if `Pending` |
| Cost of `Memo::get()` on clean memo | O(1) if `verified_at == current_revision`, or O(1) via durability shortcut | O(1) — check flags |
| Memory per edge | 1 CellId (forward only) | 1 Link node with 6 pointers (bidirectional) |
| Memory per node | `changed_at` + `verified_at` (2 ints) | flags (1 int, bit field) |

**When push-pull would help**: Large graphs where many memos are read after a single signal change. The push phase pre-marks which subtree might be dirty, so memos outside that subtree don't need any verification walk at all. incr's durability shortcut achieves a similar effect but at a coarser granularity.

**What Salsa lacked that push-pull addresses**: Salsa's verification walk is O(dep tree depth) even when only one leaf signal changed and the rest of the tree is clean. Push-pull narrows the verification to only the affected path. However, Salsa's durability shortcut mitigates this for the common case where changes cluster by stability class.

### 7. Link-based edge storage — Deferred, alien-signals-specific optimization

**alien-signals design**: Each dependency edge is a `Link` struct with 6 pointers (prevSub, nextSub, prevDep, nextDep, dep, sub). This enables O(1) insertion and removal without arrays or sets.

**Why it doesn't fit incr**: This is an extreme optimization for UI reactivity where dependency sets change frequently (every render cycle). incr's dependency sets change only when a memo recomputes, which is infrequent. Array-based dependency storage with HashSet dedup is simpler and fast enough.

**What Salsa does**: Salsa stores dependency lists as `Vec` (arrays), same as incr. The Link approach is alien-signals' most distinctive innovation but also what makes its code notoriously hard to read.

### 8. Effect system — Deferred, out of scope

**alien-signals design**: First-class `Effect` nodes that subscribe to computeds and trigger side-effect callbacks when values change. Effects are terminal subscribers (they have deps but no subs).

**Why it doesn't fit incr**: incr is a pure computation framework — it models the dependency graph of values, not side effects. In the Salsa model, the "effect" is the IDE responding to a query result, which happens outside the framework. Adding effects would change incr from a computation library to a reactive system.

### 9. Automatic cleanup/GC — Deferred, requires subscriber links

**alien-signals design**: When a node loses its last subscriber, the `unwatched()` callback fires. This enables reference-counting-based garbage collection of unused computed nodes.

**Why it doesn't fit incr today**: Without subscriber links, incr cannot know when a memo has no consumers. Memos are held by user code via `Memo[T]` references; the framework has no visibility into their lifetimes.

**What Salsa does**: Salsa also lacks automatic GC. The caller manages lifetimes by holding references. This is appropriate for compiler use cases where the query graph persists for the lifetime of the analysis session.

## Summary: Are alien-signals Ideas a Good Fit?

| Idea | Fit? | Why |
|------|------|-----|
| Array-based storage | ✓ Adopted | Universal optimization, no trade-offs |
| HashSet dedup | ✓ Adopted | Universal optimization, simple |
| Batch updates | ✓ Adopted | Good for atomic multi-signal updates |
| Two-phase signal values | ✓ Adopted | Enables revert detection, elegant |
| Iterative verification | ✓ Adopted | Prevents stack overflow, essential for deep graphs |
| Subscriber links | ◐ Future | Prerequisite for push-pull; significant architecture change |
| Push-pull hybrid | ◐ Future | Major perf win for read-heavy workloads; needs subscriber links |
| Link-based edge storage | ✗ Not needed | Over-optimized for incr's use case |
| Effect system | ✗ Out of scope | incr is a computation framework, not a reactive system |
| Automatic GC | ◐ Future | Useful but needs subscriber links |

## What Salsa Has That alien-signals Lacks

Salsa-style computation has several features that alien-signals does *not* implement, because they're designed for different domains:

1. **Durability levels**: Salsa/incr classifies inputs by change frequency, enabling coarse-grained verification skipping. alien-signals has no equivalent — every signal is treated uniformly.

2. **Revision-based verification**: The `changed_at`/`verified_at` timestamp pair gives precise information about *when* changes happened, enabling the durability shortcut. alien-signals uses transient bit flags that carry no temporal information.

3. **Cross-session persistence**: Salsa can serialize its dependency graph for cross-session incrementality (e.g., between IDE restarts). alien-signals is purely in-memory and ephemeral.

4. **Complex query keys**: Salsa supports queries parameterized by complex types (file paths, AST nodes). alien-signals' signals are simple value containers with no notion of query parameters.

5. **Backdating with value preservation**: incr's backdating is more powerful than alien-signals' same-value check. In incr, `changed_at` remains at the old revision, which can prevent verification of entire subtrees in future reads. In alien-signals, the `Pending` → `Dirty` upgrade check only prevents propagation in the current cycle.

## Conclusion

The ideas that transferred well from alien-signals to incr are **implementation-level optimizations** (array storage, HashSet dedup, iterative walking, batch buffering) that don't change the fundamental computation model.

The ideas that *didn't* transfer are **architectural choices** (subscriber links, push-pull hybrid, effects, GC) that reflect alien-signals' design for a fundamentally different use case (fine-grained UI reactivity with frequent reads and shallow graphs) versus incr's design for (incremental recomputation with infrequent reads and deep graphs).

The most impactful future change would be **subscriber links + push-pull hybrid**, which would make incr competitive for read-heavy workloads while preserving its existing strengths (durability, backdating, persistence-readiness). But this is a large architectural change that should be driven by actual use-case needs rather than theoretical appeal.

## Trade-off

❯ Does it difficult to make a algorithm that is cheap on both write and read? Is there any trade-off between these features?

This is a great question that gets at a fundamental trade-off in computer science. The short answer is: no, you cannot make both truly O(1) in the general case. There is a conservation law at work.

### The Conservation Law

When an input changes and a derived value is later read, the system must answer: "did anything in this node's dependency cone change?" That answer requires work proportional to the structure of the graph. The only choice is when that work happens:

こちらがMarkdown形式のテーブルです:

| Strategy | Write cost | Read cost | Who pays |
|---|---|---|---|
| Pure push (eager) | O(affected nodes) | O(1) | Writer |
| Pure pull (lazy) | O(1) | O(dep tree depth) | Reader |
| Push-pull hybrid | O(direct subscribers) | O(dirty path length) | Split |

The total work per write-then-read cycle has a lower bound of Ω(k) where k is the number of derived nodes transitively affected by the input change. You can shift this work between write and read, but you cannot eliminate it.

Why O(1) for Both is Impossible in General

Consider this graph:

signal → memo_1 → memo_2 → ... → memo_n → reader

When signal changes, the system must eventually determine that reader is stale. This requires
propagating information across n edges. Whether you do it eagerly (at write time) or lazily (at read
time), someone traverses those edges. You can't teleport the "changed" information across the graph
in O(1).

The formal connection is to dynamic graph reachability: "is there a path from this changed input to
this queried node where every edge represents an actual value change?" This problem has known lower
bounds in the cell-probe model.

### The Real Trade-Offs

The interesting engineering question isn't "can we avoid work?" but "can we avoid unnecessary work?"
Both Salsa and alien-signals have innovations here:

#### Trade-off 1: Write amplification vs Read amplification

- Push-based write amplification: Signal::set() walks all subscribers, including ones that will never be read. In a wide graph where only one leaf is read, most flag-setting is wasted.
- Pull-based read amplification: Memo::get() walks the entire dependency tree, including branches that didn't change. In a graph where only one input changed, most verification is wasted.

Neither is universally better — it depends on the ratio of writes to reads and the graph shape.

#### Trade-off 2: Memory vs Time

More stored information enables faster decisions:

| What you store | Memory cost | What it buys |
|---|---|---|
| Forward deps only (incr) | 1 int per edge | Must walk deps at read time |
| Bidirectional links (alien-signals) | ~6 pointers per edge | Can push flags at write time |
| Per-durability timestamps (incr) | 3 ints per runtime | Skip entire subgraphs in O(1) |
| Per-node dirty flags (alien-signals) | 1 byte per node | Skip clean nodes in O(1) |

You're buying time with space. There's no free lunch.

#### Trade-off 3: Precision vs Overhead

- Fine-grained (per-node flags): Precisely identifies which nodes are dirty. But maintaining flags costs O(subscribers) per write.
- Coarse-grained (durability levels): Cheaply eliminates large stable subgraphs. But sometimes over-verifies nodes within the same durability class.

incr's durability shortcut is an interesting middle ground — it gives near-O(1) read cost for the common case (most inputs are stable) without paying the per-write cost of subscriber links.

#### Trade-off 4: Worst-case vs Amortized

Batching amortizes across multiple writes: n writes in a batch cost the same as 1 write from the reader's perspective. But this only helps when writes are batchable.

The Closest Thing to "Cheap on Both Sides"

The push-pull hybrid (alien-signals' approach) is the closest practical design:

1. Write: Push Pending flags to direct subscribers — O(direct subscribers), not O(all transitive dependents)
2. Read: Check flags, only verify along the Pending path — O(dirty path), not O(entire dep tree)

The key insight is that the push phase does minimal work (just set bit flags, no computation), and the pull phase only walks the affected path (not the whole tree). So both sides avoid most unnecessary work.

But it still has costs:
- Writes are O(direct subscribers), not O(1)
- It requires bidirectional edges (6x memory per edge)
- Code complexity is significantly higher

### What Both Frameworks Do to Reduce Unnecessary Work

Both Salsa and alien-signals attack the real enemy: wasted work on nodes that didn't actually change.

- Backdating (Salsa/incr): If a memo recomputes to the same value, keep old changed_at. This cuts off downstream verification. Entire subtrees are skipped.
- Pending/Dirty separation (alien-signals): Only promote Pending to Dirty when the intermediate node's value actually changed. Same principle, different mechanism.

These don't reduce the theoretical lower bound, but they massively reduce the practical work by exploiting the fact that in real dependency graphs, most changes are absorbed by intermediate nodes that compute to the same value.

### Bottom Line

The write/read cost trade-off is inherent to the problem structure. What makes a framework good isn't avoiding this trade-off but choosing the right point on the curve for its use case:

- Compilers (Salsa/incr): Writes are rare, reads are batched after writes. Pure pull with durability shortcuts is optimal — O(1) writes matter more than O(dep tree) reads.
- UI frameworks (alien-signals): Writes and reads interleave rapidly. Push-pull hybrid is optimal —paying O(subscribers) at write time to get near-O(1) reads.

There is no single algorithm that dominates both use cases.
