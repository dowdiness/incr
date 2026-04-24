///|
/// Import kernel-owned state types under short names so cells/*.mbt can
/// reference them without `@kernel.` prefixes at every use site.
/// Centralised here because `using @pkg { ... }` is package-scoped
/// (one declaration per package; duplicates produce error 4051).
using @kernel {
  type ActiveQuery,
  type BatchFrame,
  type DatalogState,
  type PropagationPhase,
  type PullState,
  type PushState,
  type RuntimeCore,
}
