///|
/// K1.6a's generated slice deliberately keeps construction total: each recipe
/// selects a known-valid operation family and then varies only its values.
const SUITE_SEED : UInt64 = 0x6A_1601

///|
const SCENARIO_COUNT : Int = 21

///|
const CASE_COUNT : Int = 84

///|
priv struct Recipe {
  family : Int
  operation_limit : Int
  unrelated_retention : Int
  write_retention : Int
  graph_simplified : Bool
  key : Int
  value_salt : Int
  cycle_depth : Int
} derive(Debug)

///|
fn value(salt : Int, offset : Int) -> Int {
  let x = (salt + offset) % 19
  if x < 0 {
    x + 19
  } else {
    x
  }
}

///|
fn raw_recipe_script(recipe : Recipe) -> @model.Script {
  let a = value(recipe.value_salt, 0)
  let b = value(recipe.value_salt, 7) + 1
  match recipe.family % SCENARIO_COUNT {
    0 =>
      @model.Script::scenario(
        @model.Scenario::Source,
        [@model.SourceInit::{ id: 0, value: a }],
        [
          @model.Operation::Read(0),
          @model.Operation::Set(0, b),
          @model.Operation::Read(0),
        ],
      )
    1 =>
      @model.Script::scenario(
        @model.Scenario::UnitQuery,
        [@model.SourceInit::{ id: 0, value: a }],
        [
          @model.Operation::Read(0),
          @model.Operation::Set(0, b),
          @model.Operation::Read(0),
        ],
      )
    2 =>
      @model.Script::scenario(
        @model.Scenario::KeyedQuery,
        [
          @model.SourceInit::{ id: 0, value: a },
          @model.SourceInit::{ id: 1, value: b },
        ],
        [
          @model.Operation::ReadKey(0, a),
          @model.Operation::Set(1, b + 1),
          @model.Operation::ReadKey(1, a),
        ],
      )
    3 =>
      @model.Script::scenario(
        @model.Scenario::Chain,
        [@model.SourceInit::{ id: 0, value: a }],
        [
          @model.Operation::Read(0),
          @model.Operation::Set(0, b),
          @model.Operation::Read(0),
        ],
      )
    4 =>
      @model.Script::scenario(
        @model.Scenario::Diamond,
        [@model.SourceInit::{ id: 0, value: a }],
        [
          @model.Operation::Read(0),
          @model.Operation::Set(0, b),
          @model.Operation::Read(0),
        ],
      )
    5 =>
      @model.Script::scenario(
        @model.Scenario::UnrelatedPublication,
        [
          @model.SourceInit::{ id: 0, value: a },
          @model.SourceInit::{ id: 1, value: b },
        ],
        [
          @model.Operation::Read(0),
          @model.Operation::Set(1, a + 3),
          @model.Operation::Read(0),
        ],
      )
    6 =>
      @model.Script::scenario(
        @model.Scenario::SelectedPublication,
        [@model.SourceInit::{ id: 0, value: a }],
        [
          @model.Operation::Read(0),
          @model.Operation::Set(0, b),
          @model.Operation::Read(0),
        ],
      )
    7 =>
      @model.Script::scenario(
        @model.Scenario::DynamicBranch,
        [
          @model.SourceInit::{ id: 0, value: a },
          @model.SourceInit::{ id: 1, value: 0 },
        ],
        [
          @model.Operation::Read(0),
          @model.Operation::Set(1, b),
          @model.Operation::Read(0),
          @model.Operation::Set(0, a + 2),
          @model.Operation::Read(0),
        ],
      )
    8 =>
      @model.Script::scenario(
        @model.Scenario::RootSnapshot,
        [@model.SourceInit::{ id: 0, value: a }],
        [
          @model.Operation::Set(0, a + 1),
          @model.Operation::Read(0),
          @model.Operation::Set(0, b),
          @model.Operation::Read(0),
        ],
      )
    9 =>
      @model.Script::scenario(
        @model.Scenario::FailureRecovery,
        [@model.SourceInit::{ id: 0, value: 0 }],
        [
          @model.Operation::Read(0),
          @model.Operation::Set(0, 1),
          @model.Operation::Read(0),
          @model.Operation::Set(0, 2),
          @model.Operation::Read(0),
        ],
      )
    10 =>
      @model.Script::scenario(@model.Scenario::DomainFailure, [], [
        @model.Operation::DomainFailure(a + 1),
      ])
    11 =>
      @model.Script::scenario(@model.Scenario::StructuralError, [], [
        @model.Operation::StructuralFailure(a + 1),
      ])
    12 =>
      @model.Script::scenario(@model.Scenario::DirectCycle, [], [
        @model.Operation::ReadQuery(0, 0),
      ])
    13 =>
      @model.Script::scenario(@model.Scenario::MutualCycle, [], [
        @model.Operation::ReadQuery(0, 0),
      ])
    14 =>
      @model.Script::scenario(@model.Scenario::SameQueryKeyCycle, [], [
        @model.Operation::ReadQuery(0, 0),
      ])
    15 =>
      @model.Script::scenario(@model.Scenario::FiniteRecursion, [], [
        @model.Operation::ReadQuery(0, 3),
      ])
    16 =>
      @model.Script::scenario(@model.Scenario::UnequalKeyCrossQuery, [], [
        @model.Operation::ReadQuery(0, 0),
      ])
    17 =>
      @model.Script::scenario(
        @model.Scenario::DeadCycleBranch,
        [@model.SourceInit::{ id: 0, value: 0 }],
        [
          @model.Operation::ReadQuery(0, 0),
          @model.Operation::Set(0, 1),
          @model.Operation::ReadQuery(0, 0),
        ],
      )
    18 =>
      @model.Script::scenario(
        @model.Scenario::CycleRecovery,
        [@model.SourceInit::{ id: 0, value: 0 }],
        [
          @model.Operation::ReadQuery(0, 0),
          @model.Operation::Set(0, 1),
          @model.Operation::ReadQuery(0, 0),
          @model.Operation::Set(0, 2),
          @model.Operation::ReadQuery(0, 0),
        ],
      )
    19 =>
      @model.Script::scenario(
        @model.Scenario::OldTraceCycle,
        [@model.SourceInit::{ id: 0, value: 0 }],
        [
          @model.Operation::ReadQuery(1, 0),
          @model.Operation::Set(0, 1),
          @model.Operation::ReadQuery(0, 0),
        ],
      )
    _ =>
      @model.Script::scenario(@model.Scenario::SequentialDuplicateRead, [], [
        @model.Operation::ReadQuery(0, 0),
      ])
  }
}

///|
fn keep_operation(
  operation : @model.Operation,
  scenario : @model.Scenario,
  recipe : Recipe,
  writes : Ref[Int],
) -> Bool {
  match operation {
    @model.Operation::Set(id, _) if scenario ==
      @model.Scenario::UnrelatedPublication &&
      id == 1 &&
      recipe.unrelated_retention == 0 => false
    @model.Operation::Set(_, _) =>
      if writes.val < recipe.write_retention {
        writes.val += 1
        true
      } else {
        false
      }
    _ => true
  }
}

///|
fn select_operations(
  operations : Array[@model.Operation],
  scenario : @model.Scenario,
  recipe : Recipe,
) -> Array[@model.Operation] {
  let retained = []
  let writes = Ref(0)
  for operation in operations {
    if keep_operation(operation, scenario, recipe, writes) {
      retained.push(operation)
    }
  }
  retained.truncate(recipe.operation_limit.max(0).min(retained.length()))
  retained
}

///|
fn rewrite_operation(
  operation : @model.Operation,
  recipe : Recipe,
) -> @model.Operation {
  match operation {
    @model.Operation::ReadKey(id, _) =>
      @model.Operation::ReadKey(id, recipe.key)
    @model.Operation::ReadQuery(id, key) =>
      @model.Operation::ReadQuery(
        id,
        if recipe.family % SCENARIO_COUNT == 15 {
          recipe.cycle_depth
        } else {
          key
        },
      )
    other => other
  }
}

///|
fn recipe_script(recipe : Recipe) -> @model.Script {
  if recipe.graph_simplified {
    return @model.Script::Script(
      [@model.SourceInit::{ id: 0, value: value(recipe.value_salt, 0) }],
      [@model.Operation::Read(0)],
    )
  }
  let raw = raw_recipe_script(recipe)
  let sources = []
  for init in raw.initial_sources() {
    if init.id != 1 ||
      recipe.unrelated_retention > 0 ||
      raw.scenario_tag() == @model.Scenario::KeyedQuery ||
      raw.scenario_tag() == @model.Scenario::DynamicBranch {
      sources.push(@model.SourceInit::{
        id: init.id,
        value: if raw.scenario_tag() == @model.Scenario::DeadCycleBranch ||
          raw.scenario_tag() == @model.Scenario::CycleRecovery ||
          raw.scenario_tag() == @model.Scenario::OldTraceCycle {
          init.value
        } else {
          init.value + recipe.value_salt
        },
      })
    }
  }
  let operations = select_operations(
    raw.operations().map(operation => rewrite_operation(operation, recipe)),
    raw.scenario_tag(),
    recipe,
  )
  @model.Script::scenario(raw.scenario_tag(), sources, operations)
}

///|
fn normalized(xs : Array[@model.Observation]) -> Array[@model.Observation] {
  xs.filter(observation => {
    match observation {
      @model.Observation::Counter(_) => false
      _ => true
    }
  })
}

///|
fn first_difference(
  left : Array[@model.Observation],
  right : Array[@model.Observation],
) -> Int {
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for i in 0..<limit {
    if left[i] != right[i] {
      return i
    }
  }
  if left.length() == right.length() {
    -1
  } else {
    limit
  }
}

///|
fn first_failing_operation_index(
  operation_count : Int,
  prefix_fails : (Int) -> Bool,
) -> Int {
  if prefix_fails(0) {
    return -1
  }
  for prefix_length in 1..<(operation_count + 1) {
    if prefix_fails(prefix_length) {
      return prefix_length - 1
    }
  }
  -1
}

///|
fn semantic_mismatch(script : @model.Script) -> Bool {
  normalized(@fresh.evaluate(script)) !=
  normalized(@incremental_adapter.evaluate(script))
}

///|
fn first_differing_operation_by(
  script : @model.Script,
  prefix_fails : (@model.Script) -> Bool,
) -> Int {
  let operations = script.operations()
  first_failing_operation_index(operations.length(), prefix_length => {
    let prefix = @model.Script::scenario(
      script.scenario_tag(),
      script.initial_sources(),
      operations[:prefix_length].to_owned(),
    )
    prefix_fails(prefix)
  })
}

///|
fn first_differing_operation(script : @model.Script) -> Int {
  first_differing_operation_by(script, prefix => semantic_mismatch(prefix))
}

///|
fn generated_recipes() -> Array[Recipe] {
  let draws : Array[Int] = @qcgen.Gen::spawn().samples(
    size=CASE_COUNT,
    seed=SUITE_SEED,
  )
  draws.mapi((i, draw) => Recipe::{
    family: i % SCENARIO_COUNT,
    operation_limit: 8,
    unrelated_retention: 1,
    write_retention: 2,
    graph_simplified: false,
    key: draw % 9 - 4,
    value_salt: draw % 11 - 5,
    cycle_depth: value(draw, 0) % 4,
  })
}

///|
priv enum ShrinkPhase {
  Suffix
  UnrelatedOperations
  Writes
  Graph
  Keys
  Values
  CyclePath
} derive(Eq, Debug)

///|
priv struct ShrinkCandidate {
  phase : ShrinkPhase
  recipe : Recipe
}

///|
fn candidate(phase : ShrinkPhase, recipe : Recipe) -> ShrinkCandidate {
  ShrinkCandidate::{ phase, recipe }
}

///|
fn same_script(left : @model.Script, right : @model.Script) -> Bool {
  left.scenario_tag() == right.scenario_tag() &&
  left.initial_sources() == right.initial_sources() &&
  left.operations() == right.operations()
}

///|
fn add_candidate(
  out : Array[ShrinkCandidate],
  phase : ShrinkPhase,
  original : @model.Script,
  recipe : Recipe,
) -> Unit {
  let item = candidate(phase, recipe)
  if !same_script(original, recipe_script(recipe)) &&
    !out.any(x => same_script(recipe_script(x.recipe), recipe_script(recipe))) {
    out.push(item)
  }
}

///|
fn change_suffix(r : Recipe, operation_count : Int) -> Recipe {
  Recipe::{ ..r, operation_limit: operation_count - 1 }
}

///|
fn change_unrelated(r : Recipe) -> Recipe {
  Recipe::{ ..r, unrelated_retention: 0 }
}

///|
fn change_writes(r : Recipe, retained_writes : Int) -> Recipe {
  Recipe::{ ..r, write_retention: retained_writes - 1 }
}

///|
fn change_graph(r : Recipe) -> Recipe {
  Recipe::{ ..r, graph_simplified: true }
}

///|
fn change_key(r : Recipe) -> Recipe {
  Recipe::{ ..r, key: 0 }
}

///|
fn change_values(r : Recipe) -> Recipe {
  Recipe::{ ..r, value_salt: 0 }
}

///|
fn change_cycle(r : Recipe) -> Recipe {
  Recipe::{ ..r, cycle_depth: 0 }
}

///|
fn phase_rank(phase : ShrinkPhase) -> Int {
  match phase {
    ShrinkPhase::Suffix => 0
    ShrinkPhase::UnrelatedOperations => 1
    ShrinkPhase::Writes => 2
    ShrinkPhase::Graph => 3
    ShrinkPhase::Keys => 4
    ShrinkPhase::Values => 5
    ShrinkPhase::CyclePath => 6
  }
}

///|
fn shrink_candidates(recipe : Recipe) -> Array[ShrinkCandidate] {
  let out = []
  let original = recipe_script(recipe)
  let operation_count = original.operations().length()
  if operation_count > 0 {
    add_candidate(
      out,
      ShrinkPhase::Suffix,
      original,
      change_suffix(recipe, operation_count),
    )
  }
  if recipe.unrelated_retention > 0 &&
    original.scenario_tag() == @model.Scenario::UnrelatedPublication {
    add_candidate(
      out,
      ShrinkPhase::UnrelatedOperations,
      original,
      change_unrelated(recipe),
    )
  }
  let retained_writes = original
    .operations()
    .filter(operation => operation is @model.Operation::Set(_, _))
    .length()
  if retained_writes > 0 {
    add_candidate(
      out,
      ShrinkPhase::Writes,
      original,
      change_writes(recipe, retained_writes),
    )
  }
  if !recipe.graph_simplified {
    add_candidate(out, ShrinkPhase::Graph, original, change_graph(recipe))
  }
  if recipe.key != 0 {
    add_candidate(out, ShrinkPhase::Keys, original, change_key(recipe))
  }
  if recipe.value_salt != 0 {
    add_candidate(out, ShrinkPhase::Values, original, change_values(recipe))
  }
  if recipe.cycle_depth > 0 {
    add_candidate(out, ShrinkPhase::CyclePath, original, change_cycle(recipe))
  }
  out
}

///|
fn minimize_failure(recipe : Recipe, predicate : (Recipe) -> Bool) -> Recipe {
  let mut current = recipe
  let mut changed = true
  while changed {
    changed = false
    for item in shrink_candidates(current) {
      if predicate(item.recipe) {
        current = item.recipe
        changed = true
        break
      }
    }
  }
  current
}

///|
priv struct GeneratedCutoff {
  kind : @model.CutoffKind
  steps : Array[Int]
}

///|
priv enum CutoffShrinkPhase {
  Suffix
  Values
} derive(Eq, Debug)

///|
priv struct CutoffShrinkCandidate {
  phase : CutoffShrinkPhase
  generated : GeneratedCutoff
}

///|
fn cutoff_script(generated : GeneratedCutoff) -> @model.CutoffScript {
  @model.CutoffScript::CutoffScript(generated.kind, generated.steps)
}

///|
fn cutoff_shrink_candidates(
  generated : GeneratedCutoff,
) -> Array[CutoffShrinkCandidate] {
  let candidates = []
  if generated.steps.length() > 0 {
    candidates.push(CutoffShrinkCandidate::{
      phase: CutoffShrinkPhase::Suffix,
      generated: GeneratedCutoff::{
        kind: generated.kind,
        steps: generated.steps[:generated.steps.length() - 1].to_owned(),
      },
    })
  }
  for index, step in generated.steps {
    if step != 0 {
      let steps = generated.steps.copy()
      steps[index] = 0
      candidates.push(CutoffShrinkCandidate::{
        phase: CutoffShrinkPhase::Values,
        generated: GeneratedCutoff::{ kind: generated.kind, steps },
      })
    }
  }
  candidates
}

///|
fn minimize_cutoff_failure(
  generated : GeneratedCutoff,
  predicate : (GeneratedCutoff) -> Bool,
) -> GeneratedCutoff {
  let mut current = generated
  let mut changed = true
  while changed {
    changed = false
    for candidate in cutoff_shrink_candidates(current) {
      if predicate(candidate.generated) {
        current = candidate.generated
        changed = true
        break
      }
    }
  }
  current
}

///|
fn cutoff_mismatch(generated : GeneratedCutoff) -> Bool {
  let script = cutoff_script(generated)
  normalized(@fresh.evaluate_cutoff(script)) !=
  normalized(@incremental_adapter.evaluate_cutoff(script))
}

///|
fn first_differing_cutoff_step(generated : GeneratedCutoff) -> Int {
  first_failing_operation_index(generated.steps.length(), prefix_length => {
    cutoff_mismatch(GeneratedCutoff::{
      kind: generated.kind,
      steps: generated.steps[:prefix_length].to_owned(),
    })
  })
}

///|
fn cutoff_phase_rank(phase : CutoffShrinkPhase) -> Int {
  match phase {
    CutoffShrinkPhase::Suffix => 0
    CutoffShrinkPhase::Values => 1
  }
}

///|
test "generated differential recipes cover every public scenario" {
  let recipes = generated_recipes()
  for family in 0..<SCENARIO_COUNT {
    assert_true(recipes.any(r => r.family == family))
    ignore(recipe_script(recipes[family]))
  }
  assert_eq(recipes.length(), CASE_COUNT)
}

///|
test "generated differential observations match at a fixed seed" {
  let commissioned = @scenarios.all()
  for _, script in commissioned {
    assert_eq(
      normalized(@fresh.evaluate(script)),
      normalized(@incremental_adapter.evaluate(script)),
    )
  }
  for i, recipe in generated_recipes() {
    let script = recipe_script(recipe)
    let fresh = normalized(@fresh.evaluate(script))
    let incremental = normalized(@incremental_adapter.evaluate(script))
    let difference = first_difference(fresh, incremental)
    if difference >= 0 {
      let minimized = minimize_failure(recipe, candidate => {
        let script = recipe_script(candidate)
        first_difference(
          normalized(@fresh.evaluate(script)),
          normalized(@incremental_adapter.evaluate(script)),
        ) >=
        0
      })
      let script = recipe_script(minimized)
      let fresh_min = normalized(@fresh.evaluate(script))
      let incremental_min = normalized(@incremental_adapter.evaluate(script))
      abort(
        "seed=0x6A1601 case=\{i} recipe=\{@debug.to_string(minimized)} sources=\{@debug.to_string(script.initial_sources())} operations=\{@debug.to_string(script.operations())} Fresh=\{@debug.to_string(fresh_min)} Incremental=\{@debug.to_string(incremental_min)} first_operation=\{first_differing_operation(script)} first_observation=\{first_difference(fresh_min, incremental_min)}",
      )
    }
  }
}

///|
test "cutoff generator covers every kind with bounded varied steps" {
  let kinds = @scenarios.cutoff_all()
  for i, base in kinds {
    let generated = GeneratedCutoff::{
      kind: base.kind(),
      steps: Array::makei(5, j => (i + j) % 3 - 1),
    }
    let script = cutoff_script(generated)
    let fresh = normalized(@fresh.evaluate_cutoff(script))
    let incremental = normalized(@incremental_adapter.evaluate_cutoff(script))
    let difference = first_difference(fresh, incremental)
    if difference >= 0 {
      let minimized = minimize_cutoff_failure(generated, candidate => {
        cutoff_mismatch(candidate)
      })
      let minimized_script = cutoff_script(minimized)
      let minimized_fresh = normalized(@fresh.evaluate_cutoff(minimized_script))
      let minimized_incremental = normalized(
        @incremental_adapter.evaluate_cutoff(minimized_script),
      )
      abort(
        "seed=0x6A1601 kind=\{@debug.to_string(minimized.kind)} steps=\{@debug.to_string(minimized.steps)} Fresh=\{@debug.to_string(minimized_fresh)} Incremental=\{@debug.to_string(minimized_incremental)} first_step=\{first_differing_cutoff_step(minimized)} first_observation=\{first_difference(minimized_fresh, minimized_incremental)}",
      )
    }
  }
}

///|
test "validity-preserving shrink stream is ordered and admissible" {
  let generated = generated_recipes()
  let suffix_before = recipe_script(generated[7])
  let suffix_candidate = shrink_candidates(generated[7])[0]
  let suffix_after = recipe_script(suffix_candidate.recipe)
  let before_operations = suffix_before.operations()
  assert_eq(suffix_candidate.phase, ShrinkPhase::Suffix)
  assert_eq(suffix_after.scenario_tag(), suffix_before.scenario_tag())
  assert_eq(suffix_after.initial_sources(), suffix_before.initial_sources())
  assert_eq(
    suffix_after.operations(),
    before_operations[:before_operations.length() - 1].to_owned(),
  )
  let recipes = [
    Recipe::{ ..generated[5], value_salt: 3 },
    Recipe::{ ..generated[7], value_salt: 3 },
    Recipe::{ ..generated[2], key: 3 },
    Recipe::{ ..generated[15], cycle_depth: 3 },
  ]
  let all_candidates = []
  for recipe in recipes {
    let candidates = shrink_candidates(recipe)
    for i in 1..<candidates.length() {
      assert_true(
        phase_rank(candidates[i - 1].phase) <= phase_rank(candidates[i].phase),
      )
    }
    for item in candidates {
      ignore(recipe_script(item.recipe))
      all_candidates.push(item)
    }
  }
  let expected = [
    ShrinkPhase::Suffix,
    ShrinkPhase::UnrelatedOperations,
    ShrinkPhase::Writes,
    ShrinkPhase::Graph,
    ShrinkPhase::Keys,
    ShrinkPhase::Values,
    ShrinkPhase::CyclePath,
  ]
  for phase in expected {
    assert_true(
      all_candidates.any(candidate => candidate.phase == phase),
      msg="missing shrink phase: \{@debug.to_string(phase)}",
    )
  }
  let cycle_candidates = shrink_candidates(recipes[3])
  assert_eq(
    cycle_candidates[cycle_candidates.length() - 1].phase,
    ShrinkPhase::CyclePath,
  )
}

///|
test "unrelated-operation shrinking is scenario-aware" {
  let generated = generated_recipes()
  let unrelated = Recipe::{
    ..generated[5],
    operation_limit: 8,
    unrelated_retention: 1,
    write_retention: 2,
  }
  let dynamic = Recipe::{
    ..generated[7],
    operation_limit: 8,
    unrelated_retention: 1,
    write_retention: 2,
  }
  let keyed = Recipe::{
    ..generated[2],
    operation_limit: 8,
    unrelated_retention: 1,
    write_retention: 2,
  }
  let unrelated_after = recipe_script(change_unrelated(unrelated))
  assert_false(
    unrelated_after
    .operations()
    .any(operation => operation is @model.Operation::Set(1, _)),
  )
  assert_eq(
    recipe_script(change_unrelated(dynamic)).operations(),
    recipe_script(dynamic).operations(),
  )
  assert_eq(
    recipe_script(change_unrelated(keyed)).operations(),
    recipe_script(keyed).operations(),
  )
  assert_true(
    shrink_candidates(unrelated).any(candidate => {
      candidate.phase == ShrinkPhase::UnrelatedOperations
    }),
  )
  assert_false(
    shrink_candidates(dynamic).any(candidate => {
      candidate.phase == ShrinkPhase::UnrelatedOperations
    }),
  )
  assert_false(
    shrink_candidates(keyed).any(candidate => {
      candidate.phase == ShrinkPhase::UnrelatedOperations
    }),
  )
  assert_true(
    shrink_candidates(dynamic).any(candidate => {
      candidate.phase == ShrinkPhase::Writes
    }),
  )
  assert_true(
    shrink_candidates(keyed).any(candidate => {
      candidate.phase == ShrinkPhase::Writes
    }),
  )
}

///|
test "injected failure predicate executes deterministic minimization" {
  let minimized = minimize_failure(generated_recipes()[15], candidate => {
    candidate.cycle_depth == 0
  })
  assert_eq(minimized.cycle_depth, 0)
  ignore(recipe_script(minimized))
}

///|
test "failure localization replays admissible scenario prefixes" {
  let scripts = [
    @model.Script::scenario(
      @model.Scenario::Source,
      [@model.SourceInit::{ id: 0, value: 1 }],
      [
        @model.Operation::Read(0),
        @model.Operation::Set(0, 2),
        @model.Operation::Read(0),
      ],
    ),
    @model.Script::scenario(
      @model.Scenario::KeyedQuery,
      [
        @model.SourceInit::{ id: 0, value: 1 },
        @model.SourceInit::{ id: 1, value: 2 },
      ],
      [
        @model.Operation::ReadKey(0, 3),
        @model.Operation::Set(1, 4),
        @model.Operation::ReadKey(1, 3),
      ],
    ),
    @model.Script::scenario(@model.Scenario::DomainFailure, [], [
      @model.Operation::DomainFailure(17),
    ]),
    @model.Script::scenario(@model.Scenario::StructuralError, [], [
      @model.Operation::StructuralFailure(23),
    ]),
  ]
  for script in scripts {
    let expected_scenario = script.scenario_tag()
    let expected_sources = script.initial_sources()
    let operation_count = script.operations().length()
    let first_operation = first_differing_operation_by(script, prefix => {
      if prefix.scenario_tag() != expected_scenario ||
        prefix.initial_sources() != expected_sources {
        abort("operation-prefix replay changed immutable graph setup")
      }
      let fresh = normalized(@fresh.evaluate(prefix))
      let incremental = normalized(@incremental_adapter.evaluate(prefix))
      if fresh != incremental {
        abort("injected localization fixture has a baseline mismatch")
      }
      prefix.operations().length() == operation_count
    })
    assert_eq(first_operation, operation_count - 1)
  }
  assert_eq(normalized(@fresh.evaluate(scripts[0])).length(), 2)
  assert_eq(first_differing_operation_by(scripts[0], _prefix => false), -1)

  let writes_only = @model.Script::scenario(
    @model.Scenario::Source,
    [@model.SourceInit::{ id: 0, value: 0 }],
    [@model.Operation::Set(0, 1), @model.Operation::Set(0, 2)],
  )
  let injected_operation = first_differing_operation_by(writes_only, prefix => {
    let fresh = normalized(@fresh.evaluate(prefix))
    let incremental = normalized(@incremental_adapter.evaluate(prefix))
    if fresh != incremental {
      abort("write-localization fixture has a baseline mismatch")
    }
    if prefix.operations().length() < 2 {
      false
    } else {
      incremental.push(@model.Observation::Value(999))
      fresh != incremental
    }
  })
  let injected_fresh = normalized(@fresh.evaluate(writes_only))
  let injected_incremental = normalized(
    @incremental_adapter.evaluate(writes_only),
  )
  injected_incremental.push(@model.Observation::Value(999))
  let injected_observation = first_difference(
    injected_fresh, injected_incremental,
  )
  assert_eq(injected_operation, 1)
  assert_eq(injected_observation, 0)
  assert_true(injected_operation != injected_observation)
}

///|
test "cutoff shrinker minimizes suffixes before values" {
  let generated = GeneratedCutoff::{
    kind: @model.CutoffKind::EqEquivalent,
    steps: [-1, 0, 2],
  }
  let candidates = cutoff_shrink_candidates(generated)
  assert_eq(candidates[0].phase, CutoffShrinkPhase::Suffix)
  assert_eq(candidates[0].generated.steps, [-1, 0])
  for index in 1..<candidates.length() {
    assert_true(
      cutoff_phase_rank(candidates[index - 1].phase) <=
      cutoff_phase_rank(candidates[index].phase),
    )
  }
  for candidate in candidates {
    ignore(cutoff_script(candidate.generated))
  }
  let suffix_min = minimize_cutoff_failure(generated, candidate => {
    candidate.steps.length() >= 2 && candidate.steps[0] == -1
  })
  assert_eq(suffix_min.steps, [-1, 0])
  let value_min = minimize_cutoff_failure(generated, candidate => {
    candidate.steps.length() == 3
  })
  assert_eq(value_min.steps, [0, 0, 0])
}
