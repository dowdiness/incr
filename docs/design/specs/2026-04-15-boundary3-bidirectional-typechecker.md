# Boundary 3: Bidirectional Type-Checker for Lambda Calculus

**Status:** Design — ready for implementation planning

**Goal:** Infrastructure validation — exercise InternTable, MemoMap, Scope-managed Memo chains, and diagnostic collection in `incr`. The type system is intentionally minimal; correctness of the incremental architecture matters more than language expressiveness.

**Location:** `loom/examples/lambda/src/typecheck/`

## 1. Type System

### Type Definition

```
Type = TInt | TArrow(Type, Type) | TUnit | TError
```

No `TBool` (lambda uses Int for if-conditions, nonzero = true). No polymorphism, no type variables, no unification. `TError` represents a type error that has already been diagnosed — it poisons upward to suppress cascading.

### Type Annotation Syntax

New parser grammar for type expressions. `->` is **right-associative**: `Int -> Int -> Int` parses as `Int -> (Int -> Int)`.

```
type      ::= atom_type ("->" type)?
atom_type ::= "Int" | "Unit" | "(" type ")"
```

Lambda and let-def parameters gain optional `: type` annotations:

```
λx : Int. x + 1                    // annotated lambda
λx : Int -> Int. f                  // arrow annotation
let f(x : Int, y : Int) = x + y    // let-def params
λx. x + 1                          // unannotated (needs check-mode context)
```

### AST Change

`Lam` gains an optional type annotation field. This change is **local to the typecheck package** — the existing `Term::Lam(VarName, Term)` in `ast/ast.mbt` is unchanged. Instead, the typechecker works with its own `TypedTerm` that wraps or mirrors `Term` with annotation slots:

```moonbit
// In typecheck/types.mbt
enum TypedTerm {
  Int(Int)
  Unit
  Var(String)
  Lam(String, Type?, TypedTerm)      // annotation slot
  App(TypedTerm, TypedTerm)
  Bop(BinOp, TypedTerm, TypedTerm)
  If(TypedTerm, TypedTerm, TypedTerm)
  Module(Array[(String, TypedTerm)], TypedTerm)
  Unbound(String)
  Error(String)
  Hole(Int)
}
```

A conversion function `Term -> TypedTerm` bridges the gap. Initially all lambdas get `None` annotations (unannotated). Once parser support lands, annotations flow through CST → `TypedTerm` conversion.

**Rationale:** Introducing `TypedTerm` avoids a repo-wide migration of `Term::Lam`. The existing resolve, eval, sym, and test code continue to use the original `Term` unchanged. The typechecker owns its own AST representation.

**Tech debt:** `TypedTerm` duplicates `Term` 1:1 and `convert.mbt` is a recursive tree copy just to add one `None` field per `Lam`. Acceptable for infrastructure validation scope. If the typechecker expands beyond this, consider a side-table of annotations keyed by node identity instead of a parallel AST.

### Malformed Annotations

A malformed annotation (syntax error in the type position) parses as `Some(TError)` — distinct from `None` (no annotation written). The typechecker treats `Some(TError)` as a poison:

- **Infer mode:** `Lam(x, Some(TError), body)` → one diagnostic "malformed type annotation", return `TError` with `had_error = true`. Do NOT produce `TArrow(TError, bodyT)`.
- **Check mode:** same — diagnostic + propagate `had_error`.

## 2. Bidirectional Rules

### Infer Mode (bottom-up, returns `TypeResult`)

| Term | Rule |
|------|------|
| `Int(n)` | `TInt` |
| `Unit` | `TUnit` |
| `Var(name)` | lookup in type env; missing → diagnostic + `TError` |
| `Lam(x, Some(annot), body)` | if `annot` is `TError` → poison (see above); else bind `x : annot`, infer body → `TArrow(annot, bodyT)` |
| `Lam(x, None, body)` | diagnostic "missing type annotation" → `TError` |
| `App(f, arg)` | infer `f`; if `TArrow(paramT, retT)` → check `arg` against `paramT`, return `retT`; if `TError` → propagate `had_error`, no secondary diagnostic; else → diagnostic "not a function" |
| `Bop(op, l, r)` | check `l` against `TInt`, check `r` against `TInt` → `TInt` |
| `If(cond, then, else)` | check `cond` against `TInt`; infer `then` as `t1`; if `t1` is `TError` → infer `else` independently (suppress branch mismatch); else check `else` against `t1`; return `t1` |
| `Module(defs, body)` | type each def sequentially via env chain, infer body |
| `Hole(_)` | one diagnostic "incomplete expression" → `TError`, `had_error = true` |
| `Error(msg)` | one diagnostic from `msg` → `TError`, `had_error = true` |
| `Unbound(name)` | one diagnostic "unbound variable: name" → `TError`, `had_error = true` |

### Check Mode (top-down, given expected `Type`, returns `TypeResult`)

| Term | Expected | Rule |
|------|----------|------|
| `Lam(x, None, body)` | `TArrow(paramT, retT)` | bind `x : paramT`, check body against `retT` — annotation inferred from context |
| `Lam(x, Some(annot), body)` | `TArrow(paramT, retT)` | if `annot != paramT` → diagnostic "annotation X doesn't match expected Y", bind `x : paramT` (use expected for better downstream diagnostics); check body against `retT` |
| `Lam(_, _, _)` | non-arrow | diagnostic "expected X, got function" |
| `Hole(_)` / `Error(_)` | any | silently succeed check, `had_error = true` — primary diagnostic already emitted at leaf |
| anything else | `expected` | infer; if `had_error` → propagate, no mismatch diagnostic; if `typ != expected` → diagnostic "expected X, got Y" |

### Error Propagation

`TError` with `had_error = true` poisons the result upward. Each error source (Hole, Error, Unbound, missing annotation, malformed annotation) emits exactly one primary diagnostic. Parents check `had_error` and suppress secondary diagnostics (mismatches, "not a function") for that subtree.

**Annotation mismatch recovery:** When `Lam(x, Some(annot), body)` is checked against `TArrow(paramT, retT)` and `annot != paramT`, bind `x : paramT` (the expected type) rather than `x : annot`. This prevents cascading type errors in the body from the wrong parameter type.

## 3. Data Types

### TypeResult

```moonbit
struct TypeResult {
  typ : Type
  had_error : Bool
  diagnostics : Array[TypeDiagnostic]
} derive(Eq)
```

`Eq` is required for memo backdating. Two `TypeResult`s are equal if they have the same `typ`, `had_error`, and `diagnostics` — so unchanged type results backdate and stop invalidation cascades.

### TypeDiagnostic

```moonbit
struct TypeDiagnostic {
  message : String
  def_name : String?        // which definition, if applicable
} derive(Eq)
```

No position info — the AST doesn't carry spans and this is infrastructure validation. `def_name` provides enough context for test assertions. Span support can be added when wiring to the editor.

### TypeEnv

Plain immutable linked list — NOT a Signal or Memo:

```moonbit
enum TypeEnv {
  Empty
  Bind(TypeEnv, String, Type)
}
```

Lookup walks the chain. `extend` creates a new `Bind` node. Immutability ensures cached envs are never corrupted by later mutations.

## 4. InternTable (New incr Infrastructure)

Lives in `incr/types/`. ~30-40 lines of implementation.

### Types

```moonbit
pub struct InternId {
  index : Int
} derive(Eq, Hash, Debug, Compare)

pub struct InternTable[T] {
  to_id : HashMap[T, InternId]
  values : Array[T]
}
```

### API

```moonbit
InternTable::new[T]() -> InternTable[T]
InternTable::intern[T : Hash + Eq](self, value : T) -> InternId
InternTable::get[T](self, id : InternId) -> T
InternTable::len(self) -> Int
```

### Design Decisions

- **Grow-only, no GC** — deferred until concrete need. Acceptable for this validation scope.
- **No generation counter** — `incr/docs/semantic-interning.md` defines a generational `InternId { index, generation }`, but defers the generation field until slot-reuse/GC is implemented. Since this table is grow-only, generation is vestigial — add it when implementing InternTable GC.
- **`T : Hash + Eq` required** for dedup in `to_id` HashMap.

## 5. DefId and Interning

> **Update (2026-04-20):** The trade-off described below was resolved. `DefEntry`
> shrunk to `{ name }` and position lookup moved to a `name_to_idx : HashMap[String, Int]`
> on `PipelineState`. Inserting a def at position 0 no longer changes any existing
> `InternId`, so caller-side caches keyed off `DefId` keep hitting across the edit.
> `MemoMap::clear()` still fires on structural rebuild — identity stability is the
> API guarantee, not wrapper reuse. See `examples/lambda/src/typecheck/typecheck.mbt`
> and the "MemoMap: DefId stays stable after prepending a def at position 0" whitebox test.
> The paragraphs below are the original design and are retained for context.

### DefEntry

```moonbit
struct DefEntry {
  name : String
  encounter_order : Int
} derive(Eq, Hash)
```

`DefId = InternId` from `InternTable[DefEntry]`.

### Assignment Strategy: Encounter-Order Counter

A monotonic counter incremented during top-down tree walk assigns each definition a unique encounter order. On re-typecheck after edit, the counter resets and re-interns the same `DefEntry` values. Since `InternTable` deduplicates by value (`Hash + Eq`), unchanged definitions get the same `InternId`.

**Trade-off:** Inserting a new def at position 0 shifts encounter-order for all subsequent defs → new `DefEntry` values → new `InternId`s → MemoMap cache misses. This is acceptable for infrastructure validation. Stable identity schemes (content-hashing, position-independent naming) are deferred.

**Memory:** Stale InternTable entries from shifted encounter-orders are never cleaned up (grow-only). For a small example language with short editing sessions, this is acceptable. For production use, InternTable GC would be needed.

## 6. Incremental Architecture

### Why Not MemoMap for the Env Chain

`MemoMap` takes a single `compute: (K) -> V` closure at construction, shared across all keys. `MemoMap::get` is untracked — reads don't record dependencies. This means:

1. The compute closure cannot close over a mutable env that changes per-def (all closures see the final env).
2. Even with value-capture, changing def 0's type wouldn't invalidate def 1's MemoMap entry because the read isn't tracked.

> **[Correction 2026-04-19]** Point 2 is factually wrong. `MemoMap::get`
> via `get_untracked` → `get_result_inner` DOES call `record_dependency`
> whenever a tracking frame is active (see `cells/memo.mbt:238,247,255`
> and `cells/tracking.mbt:60-65`); `get_untracked` only bypasses the
> abort guard. The shared-closure limitation in point 1 is still valid
> and remains sufficient motivation for the Scope-managed Memo chain
> design below. See `docs/reactive-map-design.md` for the full
> correction.

### Scope-Managed Memo Chain

Instead, model the per-def type-check graph as stable `Memo` objects owned by a `Scope`. Each def gets:

- An **env Memo** that reads the previous env Memo + the previous def's type Memo
- A **type Memo** that reads its env Memo and the source term

```
// Pseudocode — actual implementation uses Scope::memo()

let scope = Scope::new(rt)

// env_memo[0] reads parent_env (a Memo or Signal)
// env_memo[i] = scope.memo(fn() {
//   env_memo[i-1].get().extend(name_i, type_memo[i-1].get().typ)
// })
//
// type_memo[i] = scope.memo(fn() {
//   let env = env_memo[i].get()
//   infer(env, typed_term_i)
// })
```

All `.get()` calls are inside memo compute closures (tracked context), so dependencies are recorded automatically. When def `i` changes:

1. `type_memo[i]` recomputes (source term changed)
2. `env_memo[i+1]` reads `type_memo[i]` → revalidates
3. `type_memo[i+1]` reads `env_memo[i+1]` → revalidates
4. Cascade propagates through incr dependency tracking
5. If `type_memo[i]` produces the same `TypeResult` as before → backdating stops the cascade

### MemoMap Usage

`MemoMap` is still used, but for a different purpose: **query-by-id access** to type results, providing the `MemoMap` integration test point. The primary incremental benefit comes from the Scope-managed Memo chain.

A `MemoMap[DefId, TypeResult]` serves as an index. Its `compute` closure captures the Memo chain's result array and performs a lookup by DefId → array index (maintained via a side-table from DefId to chain position). This means MemoMap entries are lazily created on first query and each entry's internal Memo reads the corresponding `type_memo[i]` from the chain, inheriting its dependency tracking.

**Alternative considered:** A plain `HashMap[DefId, TypeResult]` populated eagerly after the chain runs would be simpler but wouldn't exercise MemoMap's lazy-per-key Memo creation — the feature we want to validate. If the compute closure proves awkward during implementation, fall back to the HashMap approach and test MemoMap separately.

### Scope Lifecycle

When the source text changes and produces a structurally different Module (defs added/removed), the Scope is disposed and rebuilt. The InternTable persists across rebuilds — unchanged DefEntries get the same InternIds, so the MemoMap index preserves cache hits for stable defs.

**Rebuild detection:** The top-level `typecheck.mbt` wiring maintains a `prev_def_keys : Array[(String, Int)]` (name + encounter_order per def). On each recomputation of the `Memo[TypedTerm]`, compare the new Module's def list against `prev_def_keys`. If lengths differ or any name changed → dispose old Scope, rebuild chain. If identical → reuse existing chain (individual term Memos detect their own changes). This comparison runs once per source edit, outside the Memo chain.

When the source changes but Module structure is the same (same number of defs, same names), the existing Memo chain is reused — only changed terms trigger recomputation.

### Full Pipeline

```
Signal[String]
  ↓ (existing parser)
Memo[Term]                              // existing — untyped AST
  ↓ (conversion)
Memo[TypedTerm]                         // NEW — with annotation slots
  ↓ (whole-tree, coarse but cached)
Memo[ResolvedModule]                    // NEW — name resolution as Memo
  ↓
Scope-managed Memo chain:
  Array[Memo[TypeEnv]]                  // env chain — one per def
  Array[Memo[TypeResult]]               // type result — one per def
  Memo[TypeResult]                      // body type
  ↓
MemoMap[DefId, TypeResult]              // index by DefId (for query pattern)
  ↓
Memo[ModuleTypeResult]                  // top-level aggregation
```

### ResolvedModule

```moonbit
struct ResolvedModule {
  defs : Array[(String, TypedTerm)]   // resolved definitions
  body : TypedTerm                    // resolved body
} derive(Eq)
```

Name resolution transforms `Var(name)` → `Var(name)` (bound) or `Unbound(name)` (free), walking the Module's def list to determine scope. This is the same logic currently in `resolve.mbt` but applied to `TypedTerm`. The result is memoized as a single coarse `Memo[ResolvedModule]`; per-def incremental resolution is out of scope (§10).

### ModuleTypeResult

```moonbit
struct ModuleTypeResult {
  body_type : TypeResult
  def_types : Array[(String, TypeResult)]    // name + type per def
  all_diagnostics : Array[TypeDiagnostic]    // merged from all defs + body
} derive(Eq)
```

## 7. Parser Changes

### Scope

These changes are in `loom/examples/lambda/`:

| File | Change |
|------|--------|
| `src/token/token.mbt` | Add `Colon` token, `Arrow` token (`->`) |
| `src/lexer/lexer.mbt` | Lex `:` as `Colon`, `->` as `Arrow` |
| `src/syntax/syntax.mbt` | Add `TypeAnnot`, `TypeInt`, `TypeUnit`, `TypeArrow` syntax kinds |
| `src/cst_parser.mbt` | Parse type annotations after param names; parse type expressions |
| `src/views.mbt` | Add `TypeAnnotView` for typed CST node access |
| `src/term_convert.mbt` | Convert type annotations to `TypedTerm` annotation slots |

### Token Details

- `:` → `Colon` (new single-char token)
- `->` → `Arrow` (new two-char token; `-` is currently `Minus`, so the lexer needs a lookahead for `>`)
- `Int`, `Unit` as type keywords are context-sensitive — they remain valid identifiers in expression position. The parser distinguishes by syntactic context (after `:` = type position).

**Incremental lexer note:** Changing `-` from always-`Minus` to a two-char prefix requires care with the incremental reuse protocol. An edit inserting `>` after an existing `-` must invalidate the `-` token so it can re-lex as `->`. Verify that the existing damage-overlap check in `ReuseCursor` handles this (the edit range should overlap the `-` token's span, triggering re-lexing).

### Type Parsing

Right-associative, standard recursive descent:

```
fn parse_type(self) -> Unit {
  self.parse_atom_type()
  if self.at(Arrow) {
    self.bump()           // consume ->
    self.parse_type()     // right-recursive
  }
}

fn parse_atom_type(self) -> Unit {
  match self.current() {
    Ident("Int")  => { self.bump() }    // TypeInt
    Ident("Unit") => { self.bump() }    // TypeUnit
    LParen => { self.bump(); self.parse_type(); self.expect(RParen) }
    _ => { self.error("expected type") }
  }
}
```

### Lambda Param Parsing

After parsing the parameter name, optionally parse `: type`:

```
fn parse_lambda_param(self) -> Unit {
  self.expect(Ident)         // param name
  if self.at(Colon) {
    self.bump()              // consume :
    self.parse_type()        // type annotation
  }
}
```

## 8. Package Structure

```
loom/examples/lambda/src/typecheck/
  moon.pkg                  // imports: @ast, @incr
  types.mbt                 // Type, TypedTerm, TypeResult, TypeDiagnostic,
                            //   TypeEnv, DefEntry, ModuleTypeResult
  convert.mbt               // Term -> TypedTerm conversion
  infer.mbt                 // bidirectional infer/check (pure, non-incremental core)
  typecheck.mbt             // incremental wiring: Scope, Memo chain, MemoMap, InternTable
  typecheck_test.mbt        // unit tests for type system + incremental behavior
```

## 9. Test Plan

### Type System Correctness

| Input | Expected Type | Diagnostics |
|-------|---------------|-------------|
| `1 + 2` | `TInt` | none |
| `λx:Int. x + 1` | `TArrow(TInt, TInt)` | none |
| `λx. x + 1` (standalone) | `TError` | "missing type annotation" |
| `(λx:Int. λy:Int. x + y) 1 2` | `TInt` | none |
| `if 1 then 2 else 3` | `TInt` | none |
| `if (λx:Int. x) then 1 else 2` | — | "expected TInt, got function" |
| `1 2` | — | "not a function" |
| `let f(x:Int) = x + 1 in f 3` | `TInt` | none |
| `let f(x:Int) = x + 1 in f (λy:Int. y)` | — | "expected TInt, got function" |

### Check Mode (annotation inference from context)

| Input | Expected Type | Diagnostics |
|-------|---------------|-------------|
| `let f(g : Int -> Int) = g 1 in f (λx. x + 1)` | `TInt` | none (λx infers param from `Int -> Int`) |

### Error Suppression

| Input | Expected | Diagnostics |
|-------|----------|-------------|
| `1 + _` | `TInt` | 1 diagnostic: "incomplete expression" (no secondary) |
| `_ 1` | `TError` | 1 diagnostic: "incomplete expression" (no "not a function" cascade) |
| `if _ then 1 else 2` | `TInt` | 1 diagnostic (no condition mismatch) |

### Incremental Behavior

- **Def change propagation:** Change one def in a module → only that def and dependents re-typecheck. Verify via recomputation counter on Memos.
- **Backdating cutoff:** Change def that produces same `TypeResult` → cascade stops at next def.
- **Structural change:** Add/remove def → Scope rebuilds, InternTable preserves stable DefIds for unchanged defs.
- **Source unchanged:** Same source text → all Memos cache-hit, zero recomputation.

### InternTable Integration

- `intern` same `DefEntry` twice → same `InternId`
- `intern` different `DefEntry` → different `InternId`
- `get` round-trips: `table.get(table.intern(x)) == x`
- `MemoMap[DefId, TypeResult]` cache hit for stable DefIds across edits

## 10. Out of Scope

- **Accumulators** — diagnostics are returned as data in `TypeResult`. Accumulator pattern deferred until this typechecker provides a concrete workload to validate against.
- **Polymorphism / type variables / unification** — not needed for infrastructure validation.
- **Position/span tracking** — the AST doesn't carry spans. Defer to editor integration.
- **Incremental name resolution** — resolution stays whole-tree as a single Memo. Per-def resolution is a follow-up.
- **InternTable GC / generation counters** — grow-only is sufficient for this example.
- **Stable identity across insertions** — encounter-order shifts on insertion. Content-hashing or path-independent identity schemes are deferred.

## 11. Implementation Order

Suggested phasing (each phase is independently testable):

1. **InternTable** — new incr infrastructure in `incr/types/`. Unit tests. ~30-40 lines.
2. **Type system core** — `types.mbt` + `infer.mbt` in typecheck/. Pure functions, no incr. Unit tests for all bidirectional rules.
3. **Parser changes** — lexer, tokens, syntax kinds, parser, views, term_convert. Tests for parsing type annotations.
4. **TypedTerm conversion** — `convert.mbt`. Bridge from `Term` to `TypedTerm`.
5. **Incremental wiring** — `typecheck.mbt`. Scope-managed Memo chain + MemoMap index. Integration tests for incremental behavior.
