# API Documentation Updates Summary

This document summarizes the documentation updates made based on the API Interface Analysis & Recommendations.

## New Documents Created

### 1. `docs/api-design-guidelines.md`

**Purpose:** Comprehensive guide on API design philosophy and planned improvements.

**Contents:**
- Design principles (Progressive Disclosure, Type-Driven Constraints, Explicit Over Implicit, Trait Composition)
- Current API strengths analysis
- Detailed planned improvements with code examples
- API style comparison with Salsa and alien-signals
- Recommended usage patterns (Database-centric API, Trait composition, Graceful cycle handling)
- Anti-patterns to avoid
- Future considerations and deferred features
- Documentation strategy
- API stability guarantees

**Why created:** Provides a central reference for API design decisions and helps contributors understand the reasoning behind API choices.

## Documents Updated

### 2. `ROADMAP.md`

**Changes:**
- Reorganized Phase 2 into subsections:
  - **Phase 2A: Introspection & Debugging** (High Priority)
    - Introspection API with detailed methods
    - Enhanced error diagnostics with cycle paths
    - Debug output methods
    - Graph visualization

  - **Phase 2B: Observability** (High Priority)
    - Per-cell change callbacks (`on_change`)
    - Fine-grained observation patterns

  - **Phase 2C: Ergonomics** (Medium Priority)
    - Builder pattern for Signal and Memo
    - Method chaining for Runtime
    - Convenience helpers

**Why updated:** Provides clearer prioritization and more detailed implementation guidance for upcoming API improvements.

### 3. `TODO.md`

**Changes:**
- Expanded API Improvements section with concrete tasks:
  - **Introspection API** (9 new tasks)
    - Per-cell methods (id, durability, dependencies, timestamps)
    - Runtime methods (cell_info)
    - Debug output methods

  - **Error Diagnostics** (4 new tasks)
    - Cycle path tracking
    - Human-readable error formatting

  - **Per-Cell Callbacks** (7 new tasks)
    - Implementation details
    - Type-erased callback storage
    - Execution order testing

  - **Builder Pattern** (8 new tasks)
    - SignalBuilder and MemoBuilder structs
    - Fluent configuration methods

  - **Ergonomics** (3 new tasks)
    - Method chaining
    - Convenience helpers

**Why updated:** Provides actionable checkboxes for implementing the planned API improvements.

### 4. `README.md`

**Changes:**
- **Quick Start section:** Now shows database pattern (Database) FIRST, with direct Runtime as an alternative
- **Documentation table:** Added link to new API Design Guidelines document
- **Updated contributor docs descriptions:** More specific about what each document contains

**Code example before:**
```moonbit
let rt = Runtime()
let x = Signal(rt, 10)
```

**Code example after:**
```moonbit
// Recommended: Database pattern (complete, runnable)
struct MyApp {
  rt : Runtime

  fn new() -> MyApp
}
impl Database for MyApp with runtime(self) { self.rt }

fn MyApp::new() -> MyApp {
  { rt: Runtime() }
}

let app = MyApp()
let x = create_signal(app, 10)
```

**Note:** Initial version had a bug where `MyApp::new()` was undefined. Fixed by adding the constructor definition.

**Why updated:** Promotes the recommended pattern upfront, making it easier for new users to adopt best practices.

### 5. `docs/getting-started.md`

**Changes:**
- **New section:** "Recommended Approach: Database Pattern" added before runtime creation
- **All code examples:** Now show BOTH database pattern and direct runtime pattern side-by-side
- **Step 1:** Explains Database trait and database encapsulation
- **Step 2 & 3:** Show `create_signal(app, ...)` alongside `Signal(rt, ...)`

**Why updated:** Teaches the recommended pattern from the start while still showing the direct approach for comparison.

### 6. `docs/api-reference.md`

**Changes:**
- **New introductory note:** Recommends Database pattern at the top of the document
- **New section: "Introspection (Planned - Phase 2A)"**
  - Signal introspection methods
  - Memo introspection methods
  - Runtime introspection with CellInfo struct
  - Example use case for debugging
- **New section: "Per-Cell Callbacks (Planned - Phase 2B)"**
  - Signal::on_change and Memo::on_change
  - Behavior specifications
  - Example usage

**Why updated:** Makes planned APIs discoverable and provides a reference for future implementation.

### 7. `CLAUDE.md`

**Changes:**
- **Documentation Hierarchy section:** Added descriptions for updated documents
- **User docs:** Added note about Database pattern in getting-started.md
- **Contributor docs:**
  - Updated ROADMAP description to mention Phase 2 details
  - Updated TODO description to note priority organization
  - Added api-design-guidelines.md to both user and contributor sections

**Why updated:** Keeps the AI/contributor guide current with the new documentation structure.

## Key Themes Across Updates

### 1. **Promote Database-Centric Pattern**

**Before:** Direct Runtime usage was shown as the primary approach
**After:** Database trait pattern is recommended first, with Runtime as an alternative

**Rationale:** Encapsulating Runtime in a database type is better for real applications:
- Cleaner API (no Runtime passing)
- Domain-driven design
- Easier to test and mock

### 2. **Make Planned Features Discoverable**

**Before:** Planned features only in ROADMAP (high-level)
**After:** Detailed specifications in:
- API Design Guidelines (philosophy + examples)
- API Reference (signature + use cases)
- TODO (concrete implementation tasks)

**Rationale:** Users can see what's coming, contributors know what to build.

### 3. **Explicit Prioritization**

**Before:** Phase 2 was a flat list
**After:** Phase 2A (High), 2B (High), 2C (Medium) with clear priorities

**Rationale:** Focus development effort on high-impact features first.

### 4. **Examples Everywhere**

**Before:** Some APIs had minimal examples
**After:** Every planned feature has:
- Code example showing usage
- Use case explaining "why"
- Implementation notes for contributors

**Rationale:** Makes documentation useful for both users and implementers.

## Migration Path for Users

### Current Users (No Changes Needed)

Existing code continues to work:
```moonbit
let rt = Runtime()
let sig = Signal(rt, 10)
```

**All updates are additive.** No breaking changes.

### Recommended for New Code

Adopt the database pattern:
```moonbit
struct MyApp {
  rt : Runtime

  fn new() -> MyApp
}
impl Database for MyApp with runtime(self) { self.rt }

fn MyApp::new() -> MyApp {
  { rt: Runtime() }
}

let app = MyApp()
let sig = create_signal(app, 10)
```

### Adopting New APIs

Use the implemented features:
```moonbit
// Introspection
let deps = memo.dependencies()
let info = rt.cell_info(cell_id)

// Per-cell callbacks
sig.on_change(v => println("Changed to " + v.to_string()))

// Unified constructors with optional params
let sig = Signal(rt, 100, durability=High, label="config")
let m = Memo(rt, () => sig.get() * 2, label="doubled")
```

## Benefits of These Updates

### For New Users
- **Clearer onboarding:** Database pattern shown from the start
- **Better examples:** Both patterns shown side-by-side
- **Design rationale:** Understand why the API is shaped this way

### For Existing Users
- **Preview of features:** See what's coming in Phase 2
- **Best practices:** Learn recommended patterns
- **No disruption:** Existing code still works

### For Contributors
- **Clear roadmap:** Know what to build and when
- **Concrete tasks:** Checkboxes for each feature
- **Design guidance:** Understand API philosophy
- **Implementation specs:** Detailed function signatures

### For the Project
- **Coherent vision:** All docs align on recommended patterns
- **Maintainability:** Design rationale documented
- **Community clarity:** Users and contributors aligned

## Next Steps

1. **Review:** Get feedback on the new API Design Guidelines
2. **Prioritize:** Confirm Phase 2A tasks are the next focus
3. **Implement:** Start with introspection API (highest priority)
4. **Iterate:** Update docs as implementation reveals edge cases

## Files Changed Summary

| File | Type | Changes |
|------|------|---------|
| `docs/api-design-guidelines.md` | **New** | Comprehensive API design guide |
| `ROADMAP.md` | Updated | Reorganized Phase 2 with priorities |
| `TODO.md` | Updated | Added 30+ concrete tasks |
| `README.md` | Updated | Promote Database pattern first |
| `docs/getting-started.md` | Updated | Show both patterns side-by-side |
| `docs/api-reference.md` | Updated | Added planned API sections |
| `CLAUDE.md` | Updated | Reference new docs structure |

**Total:** 1 new document, 6 updated documents

All changes maintain backward compatibility while promoting best practices.
