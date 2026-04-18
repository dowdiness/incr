# Documentation Index

All documentation for the `incr` incremental computation library.

## Getting Started

**New to `incr`? Start here:**

1. [Getting Started](getting-started.md) — Step-by-step tutorial from first signal to advanced patterns
2. [Core Concepts](concepts.md) — Understand signals, memos, revisions, durability, and backdating
3. [API Reference](api-reference.md) — Complete reference for all public types and methods
4. [Cookbook](cookbook.md) — Common patterns, recipes, and anti-patterns

## Design & Architecture

**Understanding how `incr` works:**

- [Design](design.md) — Deep dive into verification algorithm, backdating, type erasure, and implementation
- [API Design Guidelines](api-design-guidelines.md) — Design philosophy, principles, patterns, and planned improvements
- [Comparison with alien-signals](comparison-with-alien-signals.md) — Analysis of trade-offs between Salsa-style and alien-signals approaches
- [Multi-Mode App Ideas](multi-mode-app-ideas.md) — App concepts leveraging pull, push, hybrid, and Datalog modes together
- [Semantic Interning](semantic-interning.md) — Design exploration for revision-aware semantic interning (`InternTable[T]`)

## Performance

- [Benchmarks](performance/benchmarks.md) — Microbenchmark results for core operations (signal, memo, hybrid, batch)

## Contributing

**For contributors:**

- [Roadmap](roadmap.md) — Phased future direction (Phases 1–4D complete, Phase 4E: Salsa-style query API)
- [TODO](todo.md) — Concrete actionable tasks organized by priority

**See also:** [CLAUDE.md](../CLAUDE.md) in the root directory for AI/contributor guidance on commands and architecture.

## Document Organization

### User Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| [getting-started.md](getting-started.md) | Tutorial with runnable examples | New users |
| [concepts.md](concepts.md) | Conceptual explanations | Users learning the model |
| [api-reference.md](api-reference.md) | Complete API specification | All users |
| [cookbook.md](cookbook.md) | Practical patterns | Intermediate users |

### Technical Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| [design.md](design.md) | Implementation internals | Contributors, advanced users |
| [api-design-guidelines.md](api-design-guidelines.md) | API philosophy | Library authors, contributors |
| [comparison-with-alien-signals.md](comparison-with-alien-signals.md) | Framework comparison | Library authors, researchers |
| [multi-mode-app-ideas.md](multi-mode-app-ideas.md) | App ideas using multiple reactive modes | Contributors, users |
| [semantic-interning.md](semantic-interning.md) | Revision-aware semantic interning design | Contributors, library authors |

### Performance

| Document | Purpose | Audience |
|----------|---------|----------|
| [performance/benchmarks.md](performance/benchmarks.md) | Microbenchmark results and history | Contributors, users |

### Project Management

| Document | Purpose | Audience |
|----------|---------|----------|
| [roadmap.md](roadmap.md) | Future plans by phase | Contributors, users |
| [todo.md](todo.md) | Implementation tasks | Contributors |

### Active Plans

(No active plans)

### Specs

| Document | Purpose |
|----------|---------|
| [superpowers/specs/2026-04-12-dispose-gc-layer4b-push-suspension.md](superpowers/specs/2026-04-12-dispose-gc-layer4b-push-suspension.md) | Layer 4b: push suspension, Scope::add_observer, MemoMap::sweep |
| [superpowers/specs/2026-04-15-boundary3-bidirectional-typechecker.md](superpowers/specs/2026-04-15-boundary3-bidirectional-typechecker.md) | Boundary 3: bidirectional type-checker for lambda calculus (incr infrastructure validation) |
| [superpowers/specs/2026-04-18-incr-stage5-internal-split-design.md](superpowers/specs/2026-04-18-incr-stage5-internal-split-design.md) | Stage 5: internal package split — `cells/internal/{shared,pull,push,datalog}/` |

### Archive

| Document | Purpose |
|----------|---------|
| [archive/2026-04-08-dispose-gc-design.md](archive/2026-04-08-dispose-gc-design.md) | Dispose/GC design spec — all 5 layers complete (PRs #28–#33) |
| [archive/completed-phases/2026-03-24-kernel-mode-engines.md](archive/completed-phases/2026-03-24-kernel-mode-engines.md) | Kernel + Mode Engines: publish_cell_changes, in_fixpoint to RuntimeCore, remove dead dirty field |
| [archive/completed-phases/2026-03-07-cells-simplification-design.md](archive/completed-phases/2026-03-07-cells-simplification-design.md) | Split runtime.mbt, deduplicate validation, extract dispose cleanup |
| [archive/completed-phases/2026-03-08-cells-simplification-impl.md](archive/completed-phases/2026-03-08-cells-simplification-impl.md) | Implementation plan for cells simplification |
| [archive/completed-phases/2026-03-06-runtime-modularization-design.md](archive/completed-phases/2026-03-06-runtime-modularization-design.md) | Runtime modularization via refunctionalized CellOps + sub-structs |
| [archive/completed-phases/2026-03-03-datalog-primitives.md](archive/completed-phases/2026-03-03-datalog-primitives.md) | Datalog primitives: Relation, Rule, Fixpoint |
| [archive/completed-phases/2026-03-08-hybrid-dirty-separation.md](archive/completed-phases/2026-03-08-hybrid-dirty-separation.md) | Separate hybrid dirty-marking from push propagation |
| [archive/incr-unified-design.md](archive/incr-unified-design.md) | Unified reactive runtime design specification (SoA + multi-mode) |
| [archive/analytical-report.md](archive/analytical-report.md) | Detailed analytical report of execution flow and internals |
| [archive/defect-analysis.md](archive/defect-analysis.md) | Defect and structural analysis (known issues) |
| [archive/api-updates.md](archive/api-updates.md) | Summary of past API documentation changes |

## Quick Links

**Most Common Paths:**

- **"How do I get started?"** → [Getting Started](getting-started.md)
- **"What's a Signal/Memo?"** → [Core Concepts](concepts.md)
- **"How do I use X method?"** → [API Reference](api-reference.md)
- **"How do I implement pattern Y?"** → [Cookbook](cookbook.md)
- **"How do I memoize per key?"** → [Cookbook](cookbook.md#pattern-keyed-queries-with-memomap)
- **"Why does backdating work this way?"** → [Design](design.md)
- **"What's planned for the future?"** → [Roadmap](roadmap.md)
- **"What can I work on?"** → [TODO](todo.md)

## External Resources

- **Main README**: [../README.md](../README.md) — Project overview and quick start
- **Contributor Guide**: [../CLAUDE.md](../CLAUDE.md) — Commands, architecture map, conventions
- **Source Code**: Root directory `.mbt` files
- **Tests**: `*_test.mbt` and `*_wbtest.mbt` files

---

**Tip:** If you're looking for something specific, try the browser's search (Ctrl+F / Cmd+F) on this page to find the right document quickly.
