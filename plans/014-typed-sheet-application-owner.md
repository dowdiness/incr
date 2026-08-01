# Plan 014: Deepen the Typed-Sheet Application Owner

**Status:** TODO
**Priority:** P1
**Effort:** L
**Reader:** Implementer and reviewer of the typed-spreadsheet `incr_tea` application refactor.
**Decision:** Replace direct access to five `Program` values, `BrowserRenderer`, `SheetState`, and `EgwAdapter` with one private `TypedSheetApplication` module using explicit operations plus two real ports: `SessionTransport` and `AiContextPublisher`.
**Keep until:** The implementation is merged and the reconciliation evidence is recorded in `plans/README.md`.
**Disposition:** Delete this plan after completion; Git history is the recovery path.
**Depends on:** The accepted [typed-spreadsheet EGW register/projection decision](../docs/decisions/2026-07-20-typed-spreadsheet-egw-register-projection.md) and the completed Plan 013 adapter.

## Context

`TypedSheetApp` currently exposes its implementation to same-package callers: five `Program` fields, retained `SheetState`, authority operations, and manual disposal. `main.mbt`, `collab.mbt`, benchmarks, and white-box tests choose a program for dispatch, construct and flush a renderer, mount five roots, and inspect retained state or the EGW adapter directly. This interface is shallow: callers repeat orchestration and must know ordering that belongs to the application.

Deepen the application module without changing product behavior. The new module owns the fixed five-region cohort, dispatch, authority projection, AI-context publication policy, transport callback shutdown, renderer lifecycle, and teardown ordering. DOM lookup and pre-session collaboration remain thin adapters.

## Locked interface and ownership

The exact MoonBit spelling may adjust after the required `moon ide` preflight, but the interface shape is fixed:

- A private `TypedSheetApplication` is constructed from an injected `@incr.Runtime`, `SheetStartMode`, optional `SessionTransport`, and `AiContextPublisher`.
- `mount(hosts)` accepts one complete `TypedSheetHosts` value containing grid, formula, status, trace, and evidence `DomElement`s.
- `dispatch(msg)` is the only local-message seam.
- `flush_presentation()` synchronously settles the mounted presentation for benchmarks and deterministic tests without exposing the renderer.
- `observe()` returns an immutable/defensively copied `ApplicationObservation` containing semantic application state, lifecycle, per-region render statistics, and application-level collaboration/bootstrap outcomes.
- `dispose()` is idempotent.
- Remote sync enters through a callback registered by the application with `SessionTransport`; there is no caller-facing raw `EgwAdapter` or raw remote-apply operation.

The lifecycle is exactly `Unmounted -> Mounted -> Disposed`. Collaboration failure is an observation/outcome, not a fourth lifecycle state.

### Typed contract sketch

The implementation must begin from this private same-package contract rather than inventing types during caller migration. Names may change only when the Phase 0 `moon ide` preflight finds a concrete language/API conflict.

```moonbit
enum ApplicationLifecycle {
  Unmounted
  Mounted
  Disposed
} derive(Eq, Debug)

enum ApplicationStartError {
  AuthorityStartFailed(String)
} derive(Eq, Debug)

enum ApplicationLifecycleError {
  NotMounted
  AlreadyMounted
  Disposed
} derive(Eq, Debug)

enum HostResolutionError {
  MissingRegion(String)
} derive(Eq, Debug)

enum ApplicationRemoteError {
  ProjectionFailed
  MutationNotLanded
  SynchronizationFailed(String)
  Disposed
} derive(Eq, Debug)

struct TypedSheetHosts {
  grid : @tea.DomElement
  formula : @tea.DomElement
  status : @tea.DomElement
  trace : @tea.DomElement
  evidence : @tea.DomElement
}

struct DispatchOutcome {
  authority_changed : Bool
}

struct RegionRenderStats {
  label : String
  view_recomputes : Int
  patch_attempts : Int
  skipped_patches : Int
}

enum ApplicationCollaborationResult {
  Disabled
  BootstrapReady(BootstrapData)
  Active
  LocalOnly(String)
}

struct ApplicationSnapshot {
  ai_context : @demo.AiContextSnapshot
  drafts : ReadOnlyArray[CellDraft]
  editing_cell : String?
  status : String
  error : String?
  last_edit : String
}

struct ApplicationObservation {
  lifecycle : ApplicationLifecycle
  snapshot : ApplicationSnapshot
  region_stats : ReadOnlyArray[RegionRenderStats]
  collaboration : ApplicationCollaborationResult
}

struct AiContextPublisher {
  publish : (String) -> Unit
}

struct SessionTransport {
  bind : (
    (@container.SyncMessage) -> Result[Unit, ApplicationRemoteError],
    (String) -> Unit,
  ) -> Unit
  publish : (@container.SyncMessage) -> Unit
  stop : () -> Unit
}

fn TypedSheetApplication::TypedSheetApplication(
  runtime : @incr.Runtime,
  mode : SheetStartMode,
  transport : SessionTransport?,
  ai_context_publisher : AiContextPublisher,
) -> Result[TypedSheetApplication, ApplicationStartError]

fn TypedSheetApplication::mount(
  self : TypedSheetApplication,
  hosts : TypedSheetHosts,
) -> Result[Unit, ApplicationLifecycleError]

fn TypedSheetApplication::dispatch(
  self : TypedSheetApplication,
  msg : Msg,
) -> Result[DispatchOutcome, ApplicationLifecycleError]

fn TypedSheetApplication::flush_presentation(
  self : TypedSheetApplication,
) -> Result[ApplicationObservation, ApplicationLifecycleError]

fn TypedSheetApplication::observe(
  self : TypedSheetApplication,
) -> ApplicationObservation

fn TypedSheetApplication::dispose(self : TypedSheetApplication) -> Unit
```

`DispatchOutcome.authority_changed` reports only the before/after authoritative-version fact already used to decide local publication. It is not a new applicability taxonomy: parse/type/reference/cycle and local-precondition results remain in the semantic snapshot/status. The transport `bind` operation is registration-only and infallible; it must not invoke either callback synchronously. Its remote handler returns `Ok(())` for both applied and semantic-no-change outcomes and a typed `ApplicationRemoteError` for the reducer to classify as `RemoteApplyFailed`. The second callback is invoked only after the reducer has entered its failed/local-only path. Transport opening/URL/protocol failures remain in the collaboration shell and reducer.

`ApplicationSnapshot` is a closed field set for this refactor. Its `ai_context` reuses the current bounded schema-v3 semantic projection. Because `@demo.AiContextSnapshot` contains nested mutable `Array` values, the owner keeps a private canonical owned snapshot and returns a fresh deep defensive clone of the complete AI context/trace/evidence tree on every `observe()` or `flush_presentation()` result; callers never receive an array aliased with retained state. `drafts` is copied before conversion to `ReadOnlyArray`. The snapshot contains no adapter, runtime, program, renderer, callback, transport phase, raw protocol message, or raw authority version. `ApplicationObservation` may grow only after revisiting this plan boundary, not as a convenience during migration. Before teardown the owner captures its final private canonical observation; disposed observation deep-clones that canonical value and never reads dead handles.

Observation materialization must not silently invalidate the benchmark. Keep a private dirty/canonical observation cache: dispatch and remote application mark it dirty; the existing mounted after-flush AI publication path refreshes it once from the same bounded semantic projection; unmounted `observe()` and remote `flush_presentation()` refresh it on demand. Returning an observation deep-clones the canonical value but must not trigger a second worksheet/EGW projection traversal. Characterize the benchmark before this change and preserve its existing dispatch-plus-flush timing boundary.

## Non-goals

- Do not change the five regions, their labels, watched-view dependencies, DOM output, or locality behavior.
- Do not change `CollabMessage`, startup URL parsing, room selection, host/join wire flow, EGW register encoding, projection rules, or local/remote convergence behavior.
- Do not change AI-context schema version, bounded-region semantics, or production publication timing.
- Do not add a package, publish the application owner, generalize it into `incr_tea`, or change public `incr`/`incr_tea` interfaces.
- Do not redesign `Program`, `BrowserRenderer`, the pure collaboration reducer, command planning, or the EGW adapter.
- Do not optimize draft lookup, rendering, transport, or projection as part of this refactor.
- Do not open or update a pull request without separate operator instruction.

## Behavioral boundary matrix

### Lifecycle and presentation

| Current state | Operation | Required result |
|---|---|---|
| Unmounted | `dispatch` | Apply the same application transition without touching DOM; retain current `Program` command semantics. |
| Unmounted | `observe` | Return current semantic state, five zeroed region-stat entries, and `Unmounted`. |
| Unmounted | `mount(complete_hosts)` | Mount all five roots, perform the current initial flush/publication, then transition to `Mounted`. |
| Unmounted | `flush_presentation` | Typed `NotMounted` rejection. |
| Unmounted | `dispose` | Stop an attached transport if present, dispose authority/program scopes, transition to `Disposed`. |
| Mounted | `dispatch` | Preserve current scheduling and after-flush behavior. |
| Mounted | `mount` | Typed `AlreadyMounted` rejection with no mutation. |
| Mounted | `flush_presentation` | Flush all roots and return the resulting observation. |
| Mounted | `dispose` | Stop callbacks first, then dispose presentation and application state; transition to `Disposed`. |
| Disposed | `mount`, `dispatch`, `flush_presentation` | Typed `Disposed` rejection with no mutation. |
| Disposed | `observe` | Return the final owned observation without accessing disposed handles. |
| Disposed | `dispose` | Successful no-op. |

`TypedSheetHosts` makes an incomplete host set unrepresentable. The DOM adapter resolves all five hosts before `mount`; missing-host lookup is a typed adapter error and cannot leave a partially mounted application.

Atomicity applies to every expected failure: lifecycle checks and complete-host resolution finish before renderer mutation. The owner creates a fresh renderer in a local variable and all five programs are constructed from the injected runtime, so `BrowserRenderer::mount`'s only explicit guards—disposed renderer and runtime mismatch—are internal invariant checks, not typed mount failures. Assign the renderer to the owner and change lifecycle to `Mounted` only after the fifth mount returns. If Phase 0 discovers another recoverable failure channel, mount into the local renderer, dispose it on that error, and return a typed error; otherwise do not invent catch/rollback around `abort`. An invariant abort can leave temporary process memory but has no recoverable application observer and is outside expected all-or-nothing behavior.

### Modes and collaboration

| Mode/event | Required result |
|---|---|
| Standalone start | No transport; same seed worksheet and initial AI context. |
| Host start | Authority bootstrap remains obtainable as an application-level observation; no raw adapter access. |
| Join start | Attach the supplied synchronized document through the existing EGW path. |
| Accepted local edit | Publish sync only when the authoritative version changed. |
| Rejected/no-op local edit | Preserve existing status/error and publish nothing. |
| Remote sync | Apply through the same observed projection path, update trace/evidence/status, flush when mounted, never republish as local. |
| Transport failure | Stop delivery, record the existing “local only” outcome/status, keep the mounted application usable. |
| Page close/dispose | Disable callbacks and stop retry/lifecycle/transport effects before renderer, authority, programs, and scope teardown. |
| Re-entrant or repeated stop/dispose | At-most-once effects and idempotent final state. |

Room chooser, URL parsing, initial join retry, raw message decoding, and the pure `reduce_collab` state machine stay in the collaboration adapter. After the application exists, that adapter delivers typed remote sync/failure events through the registered transport callbacks.

### AI context, errors, and observations

| Case | Required result |
|---|---|
| Initial mount | Publish one current schema-v3 snapshot at the same production point as today. |
| Mounted dispatch | Preserve unconditional `Cmd::after_flush` publication. |
| Unmounted dispatch | Preserve the current command queue behavior; pin the exact first-mount drain behavior with a characterization test before changing wiring. |
| Parse/type/reference/cycle result | Remain semantic worksheet values/status, not lifecycle errors. |
| Authority bootstrap failure | Map to a typed application-start error at the construction catch site. |
| Remote projection failure | Record a typed application-level collaboration outcome and stop collaboration as today. |
| Observation collections | Return `ReadOnlyArray` values built from owned copies; callers cannot mutate retained application state. |
| Region stats | Always ordered formula, grid, status, trace, evidence (matching current mount/measurement labels). |

### Existing test ownership

- New `application_wbtest.mbt` tests the application interface: lifecycle, host cohort, ports, observations, and teardown.
- `model_wbtest.mbt` keeps application behavior cases but migrates from `_state`/`prog_grid` to `dispatch`/`observe`.
- `locality_wbtest.mbt` keeps locality expectations but obtains stats through the application interface.
- `sheet_command_wbtest.mbt` keeps pure planning tests. Its current stateful interpreter block (`sheet_command_wbtest.mbt:112-250`) is classified case by case: unique command-validation/projection invariants move to the owning `domain` or `egw_adapter` tests, browser/application orchestration moves to `application_wbtest.mbt`, and only demonstrated duplicates are deleted.
- `collab_protocol_wbtest.mbt`, `room_selection_wbtest.mbt`, `egw_adapter/*_wbtest.mbt`, and typed-spreadsheet package tests keep their current ownership and do not retest the application module.

## Existing API First / reuse check

### Project interfaces to reuse

| Candidate | Location | Covers | Decision |
|---|---|---|---|
| `TypedSheetApp` construction and five region-specific `Program` values | `app.mbt` | Existing state/program assembly | **Reuse initially** as private implementation behind the new owner; fold or remove only after callers migrate. `source-verified`. |
| `Program::Program`, `dispatch`, `dispose` | `incr_tea/program.mbt` | Reactive views, message queue, commands, after-flush scheduling | **Reuse.** Do not duplicate a command runner. `source-verified`. |
| `BrowserRenderer::BrowserRenderer`, `mount`, `flush_all`, `root_stats`, `dispose` | `incr_tea/renderer_js.mbt` | Fixed-root rendering and lifecycle | **Reuse internally.** Never expose renderer/root handles. `source-verified`. |
| `Runtime::batch`, `Scope`, `InputField` | `incr` facade | Atomic application mutation and resource ownership | **Reuse through current handlers/state.** `source-verified`. |
| `EgwAdapter` observed command/sync operations and owned inspection | `egw_adapter/adapter.mbt`, `observed.mbt` | Authority, projection, trace/evidence | **Reuse unchanged.** `source-verified`. |
| `plan_sheet_command`, `interpret_sheet_command`, `reduce_collab` | `sheet_command.mbt`, `collab_protocol.mbt` | Existing functional cores | **Reuse unchanged.** `source-verified`. |
| `SheetState::ai_context_snapshot/json` | `ai_context.mbt` | Stable AI/tool observation | **Reuse inside `ApplicationObservation` and publisher.** `source-verified`. |

Checked but not used:

- `Program::stateful` / `stateful_cmd`: they introduce a version-cell model that does not match the existing per-field reactive state; keep direct `Program::Program` construction.
- A configurable region registry: fixed five regions are a locked invariant, so no extension seam is justified.
- Renderer/page-lifecycle traits: only one implementation exists; keep them internal rather than creating hypothetical ports.
- A generic `ApplicationAction` command bus: it reduces method count but enlarges the variant interface and obscures caller intent.

### MoonBit core interfaces checked

- `Option` represents the absent standalone transport and optional collaboration/bootstrap observations.
- `Result` and `map`/`map_err` carry typed start/lifecycle/adapter failures without broad `Error` channels.
- `ReadOnlyArray::from_array` plus an owned `Array::copy()`/`ArrayView::to_owned()` prevents mutable alias leakage from observations.
- `ArrayView` is preferred for read-only internal inputs; `Array` remains appropriate for owning copies and current renderer results.
- `Ref` remains justified only for callback registration/circular construction already required by the JS transport shell and current reactive state.
- `Queue`, `String`/`Bytes` conversion, `Map`, and `Set` add no value here: `Program` owns message queues, and the existing protocol adapter owns serialization.

### Unavoidable new private definitions

- `TypedSheetApplication`: the deep owner and only application seam.
- `TypedSheetHosts`: complete five-host value; responsibility ends at mount input validation.
- `ApplicationLifecycle`: encodes only the three legal lifecycle states.
- `ApplicationStartError`, `ApplicationLifecycleError`, and `ApplicationRemoteError`: semantic errors grouped by their construction and operation catch sites; they do not expose EGW/renderer implementation variants.
- `ApplicationSnapshot`, `RegionRenderStats`, `ApplicationObservation`, and collaboration outcome values: caller/test observations with deep defensive copies and no alias to retained mutable arrays.
- One private AI-context deep-clone helper: its sole responsibility is to clone every nested array in the existing schema-v3 value when crossing the application observation boundary; no project/core helper currently provides that domain-shaped clone.
- `SessionTransport`: private capability record for callback registration, local publication, and at-most-once stop. Production and deterministic recording adapters make this a real seam.
- `AiContextPublisher`: private capability record for publishing one JSON string. Production JS and deterministic capture adapters make this a real seam.

Prefer private structs of closures over new traits unless `moon ide` reveals an existing owning trait. The ports vary by adapter, not by open application extension.

## Implementation plan

### Phase 0 — exact baseline and worktree

1. After this plan change is committed or otherwise available on the implementation branch, fetch `origin/main`; create a dedicated implementation worktree whose HEAD contains current `origin/main` and the plan commit. Run `git submodule status --recursive` and record whether this standalone repository has submodules. Confirm a clean status and capture the base SHA. Do not update the parent Canopy submodule pointer in this work.

2. From the `incr` root, run the exact preflight inventory: `NEW_MOON_MOD=0 moon ide outline incr_tea`, outlines for the demo root and `egw_adapter`, and `find-references` for `TypedSheetApp`, `mount_typed_sheet_app`, `CollabOwner`, `js_publish_ai_context_json`, `BrowserRenderer::root_stats`, and every direct `_state`/`prog_*` access. Save the current `pkg.generated.mbti` and targeted test output as the compatibility baseline.

3. Verify existing project/core candidates with `moon ide doc`/`peek-def`, including `Program`, `BrowserRenderer`, `Option`, `Result`, `ReadOnlyArray`, and `ArrayView`. Confirm whether JS exceptions from `dom_get_element_by_id` are catchable; if not, plan a checked DOM-adapter lookup using a presence preflight before the existing lookup. Do not put DOM lookup inside `TypedSheetApplication`.

### Phase 1 — establish the deep interface without moving effects

4. **RED 1:** add `application_wbtest.mbt` with one tracer test that constructs an unmounted application using the existing standalone authority, dispatches `SelectCell("C1")`, and observes selection/status only through the new interface. Confirm the test fails because `TypedSheetApplication` does not exist.

5. **GREEN 1:** add `application.mbt` with the minimum private owner, three-state lifecycle, start/lifecycle errors, and defensively copied semantic observation. Initially wrap the existing `TypedSheetApp` implementation and route `dispatch` through its canonical program. Run `moon check --target js examples/typed_spreadsheet_incr_tea_demo` and the single new test.

6. **RED/GREEN 2:** add lifecycle slices one at a time: unmounted observation, unmounted dispose, disposed operation rejection, and repeated dispose. Implement only enough transition logic per failing test. Preserve a final owned observation before disposing handles; do not add a `Failed` lifecycle variant.

### Phase 2 — fixed host cohort and renderer ownership

7. **RED 3:** reuse/extract the existing fake-DOM host setup and add one test that passes a complete `TypedSheetHosts`, mounts once, observes exactly five ordered zero/baseline stat entries, and receives typed rejection on a second mount. Add a separate DOM-adapter test for a missing host that proves resolution fails before application mutation.

8. **GREEN 3:** move `BrowserRenderer` construction and all five `mount` calls behind the owner. Store no public `BrowserRoot`; the renderer owns roots. Set lifecycle to `Mounted` only after the fixed cohort is installed. Add `flush_presentation()` as the synchronous application operation used by tests/benchmarks, returning an observation. Keep rAF scheduling unchanged for ordinary dispatch.

9. Migrate the existing locality tests vertically: first draft-only, then apply, selection, begin-edit, and inline-apply cases. For each, replace raw renderer/program use with `dispatch`, `flush_presentation`, and `observe`, verify the old deltas, then remove the obsolete setup path. Do not change expected labels or counters.

### Phase 3 — AI publisher port

10. **RED 4:** introduce a recording `AiContextPublisher` adapter test for initial mount and one mounted dispatch. Characterize unmounted dispatch followed by first mount before changing current `Cmd::after_flush` wiring; the accepted assertion must preserve production timing and avoid a new publication path.

11. **GREEN 4:** inject a private publisher capability into the owner/program update closure. Keep `SheetState::ai_context_snapshot/json` and `Cmd::after_flush`; replace only the direct JS effect with the port. Resolve all five hosts, mount, publish the initial snapshot, then install the benchmark adapter in the same order as today. Production uses `js_publish_ai_context_json`; tests capture JSON.

### Phase 4 — transport port and collaboration ownership

12. **RED 5:** add a deterministic `SessionTransport` adapter test covering: accepted local edit publishes once; no-op/rejected edit publishes nothing; remote sync applies but never republishes; the remote handler returns `Ok(())` for applied/no-semantic-change and typed `Err` for projection/mutation/synchronization failure; each return causes exactly one matching reducer success/failure event; transport failure records local-only status/outcome; dispose stops callbacks before application handles; repeated stop/dispose is harmless.

13. **GREEN 5:** define the private transport capability record with three responsibilities only: register typed remote/failure callbacks, publish committed local `SyncMessage`, and stop delivery at most once. Keep raw `CollabMessage` parsing/encoding and `reduce_collab` in `collab.mbt`. The production adapter must feed every local publication through exactly one `CollabEvent::LocalCommitted` reduction and every transport failure through exactly one `CollabEvent::TransportFailed` reduction; it must not send or fail around the reducer. Bind callbacks only after the owner value is fully constructed, before it can receive delivery.

14. Split current `CollabOwner` teardown into an idempotent I/O-stop operation and application disposal. Preserve `CollabOwner` as the pre-session/browser adapter; do not delete the reducer owner. Use this exact registration sequence: (a) create the collaboration owner/reducer and empty callback slots; (b) create the registration-only `SessionTransport`; (c) construct the application, whose callbacks capture its already-created internal state `Ref`; (d) return from construction and store the application in `CollabOwner.app` before yielding to the JS event loop; (e) only later may reducer decisions invoke the registered callbacks. `bind` must never synchronously deliver, and deterministic adapters must require an explicit `deliver_remote`/`fail` test action after construction. During teardown, first disable and clear callback slots, then stop retry/transport effects, then dispose the renderer/application. Transport stop must never recursively call application dispose.

15. Route each `CollabDecision::Apply` through the bound remote-sync callback exactly once, match its `Result`, and feed exactly one `CollabEvent::RemoteApplySucceeded` or `CollabEvent::RemoteApplyFailed` back into the reducer. The callback maps raw adapter/document failures to `ApplicationRemoteError`; `collab.mbt` formats that private application error without inspecting adapter variants. Reducer `Fail` decisions continue to own collaboration phase changes before the bound application failure callback records local-only status. Host startup obtains `BootstrapData` from `ApplicationObservation`; join startup supplies existing bootstrap/document inputs. Remove direct `_state.status`, `publish_sync`, `adapter.export_all/generation/node`, renderer, and raw remote-apply access from `collab.mbt` only after equivalent application observations/operations are green.

16. Run targeted MoonBit tests for `application_wbtest`, `collab_protocol_wbtest`, `room_selection_wbtest`, and existing EGW observed tests after each collaboration slice. Then run `npm run test:room` and `npm run test:collab` from the demo directory.

### Phase 5 — caller and test migration, then deletion

17. Migrate `main.mbt` to resolve a complete host bundle, construct the standalone application with the production AI publisher and no transport, and call `mount`. Preserve the sole public `mount_typed_spreadsheet_incr_tea_demo(String)` entry and startup routing.

18. Migrate `bench_api.mbt` to accept only the application owner and use `dispatch` plus `flush_presentation`. Preserve operation names and measurement boundaries. Run `npm run bench:dom` as a smoke comparison only; do not claim or pursue optimization.

19. Migrate `model_wbtest.mbt` case by case from `TypedSheetApp`, `prog_grid`, `_state`, and adapter inspection to the application interface. Move the useful `ModelSnapshot` behavior into the source-owned `ApplicationSnapshot`; delete the test-only duplicate when no caller remains.

20. Classify `sheet_command_wbtest.mbt:112-250` before removing raw owner access. Move unique submitted-target, stale-generation, and command-precondition invariants to the owning `domain`/`egw_adapter` test seam when they are not already covered; move the browser-authority/application orchestration case to `application_wbtest.mbt`; keep pure planner tests in place; delete only cases proven duplicate by that inventory. Do not force these stateful interpreter tests through an interface that cannot express delayed commands.

21. Use `moon ide find-references` and `rg` to prove no caller outside `application.mbt` reaches `Program`, `BrowserRenderer`, `BrowserRoot`, `SheetState`, or `EgwAdapter` through the application. Fold or delete `TypedSheetApp`, `mount_typed_sheet_app`, `_model_marker`, raw publisher mutation, raw remote apply, and obsolete test helpers only after the compiler identifies every remaining caller.

22. Update `examples/typed_spreadsheet_incr_tea_demo/README.md` only where it describes the old ownership/dispatch path. State that the fixed five-root locality and collaboration protocol remain unchanged. Keep `plans/README.md` at `IN PROGRESS` during execution.

Use these green commit boundaries; do not combine them merely to reduce commit count:

| Commit | Complete vertical slice |
|---|---|
| 1 | Private typed contract, unmounted dispatch/observation, lifecycle rejection, idempotent disposal |
| 2 | Complete host bundle, renderer ownership, mount/flush, locality tests |
| 3 | `AiContextPublisher`, initial/after-flush timing, owned observation cache |
| 4 | `SessionTransport`, reducer-preserving delivery, callback-first teardown, deterministic transport tests |
| 5 | Production `main`/collaboration/benchmark migration and browser collaboration validation |
| 6 | Stateful-test ownership moves, obsolete surface deletion, README and plan reconciliation |

Each commit must be independently green for its affected package. Before creating it, run `moon fmt`, `moon info`, inspect the generated `.mbti` diff, and rerun the slice's targeted `moon check`/`moon test`. If a slice needs a framework, EGW adapter, protocol, or public-interface change, stop instead of hiding the scope expansion in the same commit.

### Phase 6 — review, synchronization, and final evidence

23. Run the targeted green gate from the repository root: enumerate every `moon.pkg` under `examples/typed_spreadsheet_incr_tea_demo` exactly as CI does, with `moon check --target js <pkg>` and `moon test --target js <pkg>`. Also run `moon build --target js --release examples/typed_spreadsheet_incr_tea_demo`.

24. Run an independent `moonbit-reviewer` against the locked interface, functional-core/imperative-shell split, port count, defensive observations, teardown ordering, FFI-reachable error handling, test ownership, and `.mbti` risk. Resolve findings with another targeted red/green slice; rerun affected checks.

25. Fetch `origin/main` again. If the implementation HEAD does not contain it, synchronize the worktree and repeat affected targeted tests and independent review. Confirm `git diff --stat` contains only intended demo, test, README, generated interface, and plan-index changes.

26. Run the repository pre-PR order: `moon fmt`, `moon info`, inspect all changed `pkg.generated.mbti` files for unintended public values or widened bounds, `moon check`, then `moon test`. The demo package is executable; the expected public value remains `mount_typed_spreadsheet_incr_tea_demo`. Opaque private type roster changes are acceptable only when no callable public surface leaks them.

27. Reproduce the CI web gate from the demo directory: `npm ci`, `npx playwright install chromium --with-deps` when the environment needs it, `npm run build`, `npm run smoke`, `npm run test:dom`, and `npm run test:collab`. Because browser collaboration wiring changes, also run the Cloudflare worker browser collaboration commands from `.github/workflows/ci.yml` when credentials/environment permit; otherwise record the exact unrun gate without claiming success.

28. Commit the candidate result, then rerun the full final gate on that clean HEAD. Capture HEAD, `origin/main`, raw command results, and `git status --short`. This standalone repository has no `scripts/validate-pr-ready.sh`; use its documented pre-PR checklist and CI fan-out rather than inventing that command. A later parent Canopy pointer update is a separate task requiring its own parent validation and submodule push order.

## Expected files

New:

- `examples/typed_spreadsheet_incr_tea_demo/application.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/application_wbtest.mbt`

Likely modified:

- `examples/typed_spreadsheet_incr_tea_demo/app.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/main.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/model.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/observed_model.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/ai_context.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/collab.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/bench_api.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/model_wbtest.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/locality_wbtest.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/sheet_command_wbtest.mbt`
- `examples/typed_spreadsheet_incr_tea_demo/README.md`
- `examples/typed_spreadsheet_incr_tea_demo/pkg.generated.mbti` only through `moon info`
- `plans/README.md`
- `docs/README.md` while this active plan is indexed

No changes are expected in `incr_tea`, `egw_adapter`, `collab_protocol.mbt`, the Cloudflare worker, or public library packages. If implementation pressure requires one, stop and revisit the plan rather than widening scope silently.

## Mutation justification

- Mutable application lifecycle is necessary state-machine shell state; decisions remain explicit and tested.
- Existing `SheetState`, `BrowserRenderer`, EGW `Document`, transport handles, and callback slots remain imperative-shell mutation.
- Callback `Ref`s are necessary for JS interop and two-phase collaboration construction; they must be cleared/stopped during disposal.
- Local mutation used to assemble owned observations or fixed stats arrays is allowed only when the result does not alias retained state.
- No new manual indexing/`while` loop is planned; use existing project operations and core `map`, `filter`, `Option`, `Result`, `ReadOnlyArray`, and views.

## Acceptance criteria

- [ ] All callers use `TypedSheetApplication`; none select `prog_grid`, retain `BrowserRenderer`, or inspect `_state`/`EgwAdapter` through the application.
- [ ] The complete five-host value and fixed five-root cohort are internal invariants; expected failures occur before renderer mutation, and the renderer is assigned only after all five mounts return.
- [ ] Unmounted dispatch/observe, one successful mount, duplicate-mount rejection, disposed-operation rejection, final observation, and idempotent dispose are tested through the application interface.
- [ ] The implemented private types and method signatures match the typed contract sketch, or a Phase 0 language/API conflict and its narrow correction are recorded.
- [ ] `SessionTransport` and `AiContextPublisher` each have production and deterministic test adapters; `bind` is registration-only/non-delivering, and no renderer/lifecycle port is added.
- [ ] Local publish, remote no-republish, typed remote apply result -> exactly one reducer success/failure event, transport failure/local-only fallback, and callback-first teardown are covered.
- [ ] Every returned observation deep-clones all nested mutable AI-context/trace/evidence arrays from the private canonical snapshot; mutating one returned value cannot change the application or a later observation.
- [ ] Observation caching causes no second worksheet/EGW projection traversal inside the existing benchmark dispatch-plus-flush boundary.
- [ ] Existing locality counters, AI context schema/timing, benchmark operation names, protocol bytes, authority projection, and DOM behavior remain unchanged.
- [ ] Pure command/reducer and EGW adapter tests remain with their owning modules; obsolete implementation-coupled tests are deleted.
- [ ] Targeted MoonBit, full workspace, JS build, smoke, DOM, and collaboration gates pass on the final clean HEAD, or any environment-blocked gate is reported exactly.
- [ ] `moon info` shows no unintended callable public surface or trait-bound drift.
- [ ] Independent MoonBit review is resolved before final evidence.

## Decision record and closure

Anticipated decision record:

- **No ADR needed:** this is a private, behavior-preserving, application-local deepening that implements existing EGW, `incr_tea`, and AI-context decisions without changing their contracts.

If implementation changes a public contract, collaboration protocol, authority semantics, AI-context policy, or reusable design rule, stop and update/create the appropriate ADR instead of using the no-ADR disposition.

On completion, delete this file, change Plan 014 to `DONE` in `plans/README.md`, add the merge/commit and validation reconciliation, remove the active-plan link from `docs/README.md`, and state the final ADR/no-ADR path in the completion response.
