# Phase 0 Ideal API Rename Language-Mechanics Spike

This directory is throwaway probe code for
`docs/archive/completed-phases/2026-05-21-ideal-api-rename-migration.md` Phase 0. It is not a
public API implementation.

Findings from `moon check`:

- Public `#alias` on a custom constructor compiles and is callable across a
  package boundary as `Type::new(...)`.
- Public `#alias` on a method compiles and is callable across a package
  boundary.
- `#deprecated` on a public `pub type Alias[T] = Target[T]` compiles, and the
  alias can be used from another package.
- Methods on a public type alias resolve through to the target type.
- Constructor syntax through a public type alias is rejected. The compiler error
  for `RenamedCell(3)` was `Value RenamedCell not found in package`.
- Arbitrary blanket compatibility impls are rejected. The compiler error for
  `pub impl[T : CurrentFreshness] CompatReadable for T` was `Invalid type for
  "self": must be a type constructor`.
- Same-receiver overloads by parameter type are rejected. The compiler error for
  a second `ReadRuntime::read` method was `The method read for type ReadRuntime
  has been defined`.

Implications for the migration plan:

- Alias-only type renames do not provide target constructor syntax like
  `Input(...)`; wrappers/facades are needed if constructor syntax is required.
- `DerivedMap` should not be a plain alias if `DerivedMap::get` needs strict
  `Result` semantics, because alias method resolution would expose the target
  type's current methods.
- Do not plan a blanket old-trait/new-trait compatibility bridge. Use per-type
  impls and downstream dual-impl guidance instead.
- Do not add future `Runtime::read(...)` overloads while the current
  `Runtime::read(memo) -> T` compatibility method exists.
