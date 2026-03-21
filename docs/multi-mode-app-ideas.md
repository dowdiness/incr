# Multi-Mode Application Ideas

Application concepts that leverage incr's combination of pull, push, hybrid, and Datalog modes in a single computation graph.

## Reactive Modes Summary

| Mode | Cell Types | Behaviour |
|------|-----------|-----------|
| Pull (lazy) | Signal, Memo, MemoMap | Verify-on-read, backdating, durability skipping |
| Push (eager) | Reactive, Effect | Level-sorted glitch-free propagation, immediate side effects |
| Hybrid | HybridMemo | Push dirty flags + pull verification on read |
| Datalog | Relation, FunctionalRelation, Rule, fixpoint() | Semi-naive fixpoint evaluation over derived facts |

---

# Showcase Examples

Smaller, self-contained ideas that demonstrate the library's multi-mode power.

## Incremental Type Checker

Extend the existing lambda calculus parser with a type system.

**Mode mapping:**
- **Pull Memo** — parsing (reuse subtrees via backdating; most edits don't change the full AST)
- **Datalog fixpoint** — type inference / constraint solving (unification as fact derivation: `HasType(expr, ty)` rules propagate until fixpoint)
- **HybridMemo** — error diagnostics (dirty-flagged eagerly when types change, lazily materialized only for visible editor range)
- **Effect** — diagnostic rendering / LSP-style push

**Why interesting:** Type inference is naturally Datalog (derive facts until stable), but you don't want to re-run fixpoint on every keystroke — durability + backdating on the parse layer gates when fixpoint actually fires. Extends existing lambda parser work.

---

## Live Dataflow Spreadsheet

A spreadsheet where cells contain formulas.

**Mode mapping:**
- **Signal** — user-entered values (durability=High for constants, Low for frequently edited)
- **Memo** — formula evaluation with automatic dep tracking (A1 references B2, etc.)
- **Datalog** — cross-sheet queries like `SUM WHERE column > 10` expressed as relations over row data
- **Reactive + Effect** — chart/sparkline rendering that eagerly updates for visible cells
- **HybridMemo** — off-screen cells get dirty flags but don't recompute until scrolled into view

**Why interesting:** Spreadsheets are the canonical incremental computation problem. The viewport optimization (hybrid for off-screen, push for on-screen) is a natural fit hard to express in single-mode systems.

---

## Reactive Build System (mini-Bazel)

A build graph where targets have dependencies.

**Mode mapping:**
- **Signal** — file mtimes / content hashes (durability=High for vendored deps, Low for source)
- **Memo** — per-target "needs rebuild?" check with backdating (if output hash unchanged, downstream skips)
- **Datalog** — transitive dependency resolution (`Depends(a, b), Depends(b, c) => Depends(a, c)`), visibility rules
- **Effect** — execute build commands when a target is dirty
- **MemoMap** — keyed by target name, lazily creates per-target computation nodes

**Why interesting:** Build systems are Salsa's origin story. Adding Datalog for dep resolution shows something Salsa itself can't do. Backdating is critical — rebuilding a `.o` file that produces identical output shouldn't trigger downstream linking.

---

## Access Control Policy Engine

Evaluate authorization policies over a changing set of users, roles, and resources.

**Mode mapping:**
- **Datalog** — core policy rules (`HasRole(user, role)`, `CanAccess(user, resource)` derived via role inheritance, group membership, transitive grants)
- **Signal** — user/role/resource CRUD events
- **HybridMemo** — per-user permission summary (dirty-flagged when upstream role changes, materialized only when that user makes a request)
- **Effect** — audit log emission on permission changes
- **Durability** — role hierarchy (High) vs session tokens (Low); changing a session token doesn't re-derive the entire role graph

**Why interesting:** RBAC is the textbook Datalog application. The hybrid layer adds a practical optimization — millions of users but only hundreds active means push-dirty + pull-verify beats eager recomputation.

---

## Reactive Circuit Simulator

A digital logic simulator.

**Mode mapping:**
- **Signal** — input pins (switches, clocks)
- **Reactive** — combinational gates (AND, OR, NOT) — must propagate eagerly and glitch-free (level-sorted guarantees no hazards)
- **Datalog + fixpoint** — sequential logic / feedback loops (SR latches, flip-flops) — fixpoint converges to stable state
- **Memo** — timing analysis / critical path computation (lazy, only when inspector panel is open)
- **Effect** — waveform trace recording, LED output display

**Why interesting:** One of the few domains where push (combinational), fixpoint (sequential feedback), and pull (analysis) all have clear, non-overlapping roles. Level-sorted propagation maps directly to gate-level simulation semantics.

---

## Knowledge Graph Explorer

An interactive graph of entities and relationships (personal wiki / Obsidian-style).

**Mode mapping:**
- **Datalog** — derived relationships (`Reachable(a, b)` via link chains, `RelatedTo(a, b)` via shared tags, clustering)
- **Signal** — node content edits, tag additions
- **MemoMap** — per-node rendered view, lazily created on navigation
- **HybridMemo** — search index (dirty-flagged on edits, rebuilt only when user opens search)
- **Effect** — auto-save, sync to disk

**Why interesting:** Graph traversal queries are Datalog's sweet spot. The hybrid search index is a realistic optimization — no need to rebuild full-text index on every keystroke, just mark stale and rebuild on demand.

---

# Real-World Applications

Practical, production-scale applications where incr's multi-mode reactivity solves problems that single-mode systems handle poorly.

## 1. Supply Chain BOM Management

**Problem:** Manufacturing companies manage bills of materials (BOMs) with thousands of parts, each sourced from multiple suppliers. A single component price change can cascade through hundreds of assemblies. Today this is done with batch recalculation (slow) or manual tracking (error-prone).

**Why multi-mode matters:**
- **Datalog fixpoint** — BOM explosion is inherently recursive. `Contains(assembly, part)` propagates transitively: if Assembly A contains Sub-Assembly B which contains Part C, then A transitively contains C. Country-of-origin compliance works the same way — if any transitive component is from a restricted country, the top-level product is non-compliant. Writing this as hand-rolled graph traversal is fragile; Datalog makes the rules declarative and the fixpoint handles arbitrary nesting depth.
- **Pull Memo with backdating** — Cost rollup for an assembly is the sum of its components' costs. When a supplier changes a raw material price by $0.001, the rounded per-unit cost of the sub-assembly may not actually change. Backdating stops the cascade there — the 47 assemblies that use that sub-assembly don't recompute. Without backdating, every price change triggers a full re-rollup of the entire product tree.
- **HybridMemo** — A procurement dashboard showing 10,000 products. Only ~50 are visible on screen. All products get dirty-flagged when a supplier price changes (push), but only the visible ones actually recompute their cost summaries (pull on scroll/render). Without hybrid mode, you either eagerly recompute all 10,000 (wasteful) or poll each one for staleness (no way to know which changed).
- **Batch** — End-of-quarter supplier renegotiation touches 200 prices simultaneously. `Runtime::batch()` ensures all 200 are applied atomically as a single revision. Downstream cost rollups see a consistent snapshot, not a half-updated mix.
- **Durability** — Product structure (High) rarely changes vs. spot prices (Low) that change daily. When only prices change, memos that depend solely on product structure skip verification entirely.
- **Effect** — Trigger purchase order alerts when a recomputed cost exceeds budget thresholds.

**Real-world parallel:** SAP BOM explosion, Arena PLM cost rollups. These are enterprise-critical systems where incremental recalculation with correct propagation semantics directly saves money.

---

## 2. Infrastructure Observability Platform

**Problem:** Monitor thousands of services with millions of metrics. When something breaks, determine root cause through a dependency graph, not just "which alert fired first." Current tools (Datadog, PagerDuty) treat alert correlation and dependency analysis as separate systems bolted together.

**Why multi-mode matters:**
- **Signal + push Reactive** — Metric streams (CPU, latency, error rate) feed in as signals. Threshold checks (`error_rate > 5%`) must be push-mode because alert latency matters — you can't wait for someone to poll. Level-sorted propagation prevents glitches like "CPU alert fires, then composite health check fires, then CPU alert clears" in a single propagation cycle.
- **Datalog fixpoint** — Service dependency topology is a graph with transitive impact. `DependsOn(frontend, api-gateway)`, `DependsOn(api-gateway, auth-service)` derives `Impacted(frontend, auth-service-outage)`. More powerfully: root cause analysis. If auth-service is down and api-gateway is down, Datalog can derive that api-gateway's failure is *caused by* auth-service (because the dependency exists and auth-service failed first). This is a fixpoint computation over the causal graph — hand-coding it is where incident response tools get buggy.
- **HybridMemo** — Per-service health summaries for 10,000 services. When a metric changes, the affected services get dirty-flagged immediately (push). But the actual health summary (aggregating 50 metrics into a composite score) only computes when an operator opens that service's dashboard page (pull). This is the difference between O(metrics × services) eager work vs. O(metrics + viewed_services) hybrid work.
- **Durability** — Service topology (High) changes during deploys. Metric thresholds (Medium) change during tuning. Metric values (Low) change every 10 seconds. When only metric values change, all memos that depend solely on topology or thresholds skip verification. This is significant — topology-derived computations like "transitive dependencies of service X" are expensive and shouldn't reverify on every metric tick.
- **MemoMap** — Keyed by service ID. When an operator navigates to a service they've never viewed, MemoMap lazily creates the computation graph for that service's dashboard. Previously viewed services hit the cache.
- **Batch** — Deploy events change the topology of 30 services simultaneously. Batch ensures the dependency graph sees a consistent post-deploy snapshot, not a partial update where some services point to old versions and others to new.

**Real-world parallel:** Combines what Datadog (metrics), PagerDuty (alerting), and ServiceNow (dependency mapping) do as three separate products into a single reactive graph.

---

## 3. Collaborative Design Tool with Constraint Layout

**Problem:** Multi-user design tools (Figma, Sketch) need constraint-based auto-layout, real-time collaboration, and on-demand export — three fundamentally different computation patterns running over the same document model.

**Why multi-mode matters:**
- **Signal** — Every design property (position, size, color, text content) is a signal. The CRDT layer (from the parent `crdt` project) resolves conflicts and writes merged values into signals. This is the natural integration point with the eg-walker CRDT that the parent project already implements.
- **Datalog fixpoint** — Auto-layout constraints. "Element A is 16px right of Element B", "Element C fills remaining width of container D" — these are constraint equations that must reach a stable solution. When circular constraints exist (A depends on B's width, B depends on A's height), Datalog fixpoint converges to a stable layout or detects the cycle. CSS Flexbox and Grid layout are essentially constraint solvers — expressing them as Datalog rules makes the layout engine extensible (add new constraint types by adding rules, not code).
- **Push Reactive** — Multi-user cursor positions and selections must propagate immediately. When User A moves their cursor, all other users' views must update in the same frame. This is pure push — no laziness, no verification, just immediate level-sorted propagation.
- **Memo with backdating** — Rendering a design element involves computing its final visual properties (resolved colors, computed fonts, flattened transforms). When a parent container moves, all children's absolute positions change but their *appearance* (relative layout, colors, shadows) doesn't. Backdating at the "visual properties" memo layer means the renderer doesn't re-rasterize elements that look identical — it just translates them.
- **HybridMemo** — Code export / asset export. Generating React components or SVG from the design tree is expensive. It's dirty-flagged on every edit (push), but only actually runs when the user opens the export panel (pull). Same for accessibility audit, design token extraction, and handoff specs.
- **Durability** — Design system tokens (colors, typography scales — High) vs. individual element properties (Low). When an element moves, none of the design-system-derived memos (like "all instances of this component") need to reverify.

**Real-world parallel:** Figma's rendering pipeline does something similar with ad-hoc caching, but the constraint solver, collaboration layer, and rendering pipeline are separate systems. A unified reactive graph would eliminate the consistency bugs that arise when these systems disagree about document state.

---

## 4. Incremental Static Analysis Framework

**Problem:** Static analyzers (ESLint, rust-clippy, Semgrep) re-analyze entire files or projects on every change. IDE integrations are either slow (re-run everything) or incomplete (only analyze the current file). Building an incremental multi-pass analyzer that shares work across passes is a research-level challenge.

**Why multi-mode matters:**
- **Pull Memo + MemoMap** — Per-file parsing keyed by file path. When a file changes, only that file's AST re-parses. MemoMap lazily creates parser instances for files as they're first referenced. Backdating is critical: reformatting a file (whitespace changes) re-parses but produces the same AST, so all downstream analyses skip.
- **Datalog fixpoint** — The core analysis passes. Points-to analysis: `PointsTo(var, heap_obj)` propagates through assignments. Taint analysis: `Tainted(var)` propagates through data flow. Call graph construction: `Calls(fn_a, fn_b)` with indirect calls resolved through points-to results. These are mutually recursive — the call graph affects points-to (which function body to analyze), and points-to affects the call graph (resolving indirect calls). Semi-naive fixpoint handles this mutual recursion naturally. Hand-coding the iteration order is the primary source of bugs in real static analyzers.
- **HybridMemo** — Per-file diagnostic summaries. When any analysis pass updates its results, affected files get dirty-flagged (push). But the diagnostic list only materializes for files currently open in the editor (pull). A project with 5,000 files might have 500 with findings, but only 3 are open — hybrid avoids formatting diagnostics for the other 497.
- **Push Reactive + Effect** — Severity-level alerts. When a new critical finding is derived (e.g., SQL injection), an effect immediately pushes a notification to the IDE. This can't wait for the user to open the file — it's a security issue.
- **Durability** — Third-party library type stubs (High) change on dependency updates. Source files (Low) change on every keystroke. When only source changes, all memos derived from library types skip verification. In a real project, 90% of the type information comes from libraries — this is a massive optimization.
- **Batch** — Refactoring operations (rename symbol, extract function) touch many files atomically. Batch ensures the analysis sees a consistent post-refactor snapshot and doesn't produce spurious "undefined reference" findings for the half-completed rename.

**Real-world parallel:** rust-analyzer (built on Salsa, but without Datalog or push mode), Infer (Facebook's static analyzer, uses hand-rolled fixpoint), Doop (Datalog-based pointer analysis for Java, but batch-only with no incrementality).

---

## 5. Financial Portfolio Risk Engine

**Problem:** Trading desks need real-time P&L on every market tick, but also need expensive risk metrics (VaR, stress tests, Greeks) that shouldn't recompute on every tick — only when a trader actually looks at a position or when limits are breached. Current systems split this into a real-time streaming layer and a batch risk engine, creating consistency gaps.

**Why multi-mode matters:**
- **Signal** — Market data (prices, rates, volatilities) stream in as signals. Durability distinguishes: spot prices (Low, change every 100ms), yield curves (Medium, recalculated every few minutes), market conventions like day-count fractions (High, change quarterly).
- **Push Reactive** — Real-time P&L = position × current_price. This must be eager — traders need to see their P&L update on every tick. Level-sorted propagation ensures that portfolio-level P&L (sum of position P&Ls) never shows an intermediate state where some positions reflect the new price and others don't.
- **Datalog fixpoint** — Counterparty exposure netting. Regulatory frameworks (e.g., SA-CCR) require computing net exposure across multiple trades with the same counterparty, considering netting agreements, collateral, and margin. Netting rules are transitive and conditional: `NetsWith(trade_a, trade_b)` if they share a netting agreement, and exposure aggregation follows these netting sets. Master netting agreements can themselves be nested. Expressing this as Datalog rules makes the computation auditable and the rules can be updated by risk officers without touching code.
- **HybridMemo** — Greeks (delta, gamma, vega) for each position. Expensive to compute (involves option pricing models). Dirty-flagged on every market tick (push), but only computed when the trader opens a position's detail view or when a risk limit check is triggered (pull). A desk with 2,000 positions gets 2,000 dirty flags per tick, but only the ~20 visible positions recompute Greeks.
- **Memo with backdating** — Interest rate sensitivity bucketing. When a yield curve shifts in parallel (all tenors up 1bp), the *bucketed* sensitivity profile might not change (same shape, slightly different magnitude that rounds to the same bucket). Backdating skips the expensive downstream VaR recalculation in this case.
- **Batch** — End-of-day official close: all market data signals update to closing prices simultaneously. Risk reports computed on this batch see a consistent snapshot. Also used for what-if scenarios: "what happens to our portfolio if the Fed raises rates 50bp?" — batch-set all rate signals, read the results, then revert.
- **Effect** — Limit breach alerts. When computed exposure exceeds a regulatory limit, an effect fires immediately (push all the way to notification), regardless of whether anyone is viewing that position.

**Real-world parallel:** Combines what Murex (risk analytics), Kdb+ (real-time market data), and regulatory engines (FRTB, SA-CCR) do as separate systems. The consistency gap between "real-time P&L says we're fine" and "batch risk engine says we breached a limit 20 minutes ago" is a real operational risk.

---

## 6. Game World Simulation Engine

**Problem:** Game engines need frame-rate-critical reactive systems (rendering, physics) alongside expensive analytics (AI planning, procedural generation) and rule-based systems (mod scripting, crafting recipes). These typically live in separate subsystems with manual cache invalidation between them — the primary source of "stale state" bugs in games.

**Why multi-mode matters:**
- **Signal** — Entity properties: position, health, inventory contents, status effects. TrackedCell groups related properties (a character's stats) so that changing only `health` doesn't invalidate memos that only read `attack_power`.
- **Push Reactive** — Physics-derived properties and rendering state. Collision results, visibility determination, animation blending — these must propagate within the frame, glitch-free. When an entity moves, its collision bounds, shadow volume, and audio listener position all update in a single level-sorted pass. No frame should render an entity at its new position with its old shadow.
- **Datalog fixpoint** — Crafting and recipe systems. `CanCraft(player, item)` if `HasItem(player, ingredient)` for all ingredients, and `HasItem` includes items `CanCraft`-ed from other items (recursive). Mod systems add new rules: a mod that adds a new recipe is a new Datalog rule, not a code change. Quest prerequisite chains are also naturally Datalog: `CanStartQuest(player, quest)` requires `CompletedQuest(player, prereq)` for all prerequisites, and some quests unlock items that are prerequisites for other quests.
- **Memo with backdating** — AI behavior evaluation. An NPC's current behavior (patrol, chase, flee) is a memo over world state. When the player moves slightly, most NPCs' behavior doesn't change (player is still out of range). Backdating means the behavior tree memo recomputes but returns the same `Patrol` value, so the animation state machine and pathfinding system don't re-trigger.
- **HybridMemo** — Per-NPC detailed AI planning. All NPCs get dirty-flagged when world state changes (push), but only NPCs within the active simulation radius actually re-plan (pull). A world with 10,000 NPCs might have 200 active — hybrid avoids planning for the other 9,800 while ensuring they'll have fresh plans the instant they enter the active radius.
- **Durability** — World terrain and static geometry (High) vs. entity positions (Low). Pathfinding navmesh queries that depend only on terrain skip verification when entities move. Level geometry changes (destroying a wall) are rare and High-durability, so when they do happen, the system knows to reverify navmesh-dependent memos.
- **Batch** — Loading a save game sets hundreds of signals (entity positions, inventory states, quest flags) atomically. The game world sees a consistent loaded state, not a partially loaded one where some entities are at save positions and others at defaults.
- **Effect** — Sound triggers, particle spawns, UI notifications. When a computed condition becomes true (enemy enters aggro range), the effect fires immediately.

**Real-world parallel:** Unity's ECS (DOTS) handles the push/reactive part well but has no equivalent of pull verification (everything is eagerly system-scheduled) or Datalog (game logic is imperative). Unreal's Gameplay Ability System hand-rolls the equivalent of backdating and dependency tracking for stat modifiers. A unified reactive graph would eliminate the "stale buff" and "phantom quest marker" bugs that plague shipped games.

---

## Cross-Cutting Themes

**Why single-mode systems fail at these problems:**

| Problem | Push-only failure | Pull-only failure |
|---------|------------------|-------------------|
| BOM cost rollup | Recomputes 10,000 products when one price changes | No way to know which products are affected without polling all of them |
| Incident root cause | Can't lazily compute expensive forensics | Alerts arrive late because they wait for polling |
| Design constraint layout | Can't defer export computation | Cursors/selections lag behind edits |
| Static analysis | Formats diagnostics for 5,000 files on every keystroke | No immediate notification for critical findings |
| Portfolio risk | Computes Greeks for 2,000 positions on every tick | P&L lags behind market data |
| Game AI | Plans for 10,000 NPCs every frame | Physics and rendering are inconsistent within a frame |

**Why Datalog specifically (not just "graph traversal"):**

In all six applications, the recursive/transitive computation isn't a nice-to-have — it's the core domain logic. BOM explosion, service dependency impact, constraint propagation, points-to analysis, netting agreements, and crafting recipes are all naturally expressed as recursive rules over relations. Hand-coding the fixpoint iteration is where bugs hide. Datalog makes the rules auditable and the termination guaranteed.

**Why hybrid specifically (not just "cache with TTL"):**

Hybrid mode's value is that it gives you O(1) "is this stale?" checks (dirty flag, set by push) combined with on-demand recomputation (pull). A cache with TTL either recomputes too eagerly (short TTL) or serves stale data (long TTL). Hybrid never serves stale data and never recomputes unnecessarily — it recomputes exactly when read after becoming dirty.
