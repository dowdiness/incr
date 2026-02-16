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

## Contributing

**For contributors:**

- [Roadmap](roadmap.md) — Phased future direction with Phase 2A (introspection), 2B (observability), 2C (ergonomics)
- [TODO](todo.md) — Concrete actionable tasks organized by priority
- [API Updates](api-updates.md) — Summary of recent API documentation changes

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

### Project Management

| Document | Purpose | Audience |
|----------|---------|----------|
| [roadmap.md](roadmap.md) | Future plans by phase | Contributors, users |
| [todo.md](todo.md) | Implementation tasks | Contributors |
| [api-updates.md](api-updates.md) | Change summary | Contributors, maintainers |

## Quick Links

**Most Common Paths:**

- **"How do I get started?"** → [Getting Started](getting-started.md)
- **"What's a Signal/Memo?"** → [Core Concepts](concepts.md)
- **"How do I use X method?"** → [API Reference](api-reference.md)
- **"How do I implement pattern Y?"** → [Cookbook](cookbook.md)
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
