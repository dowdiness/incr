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
  recipe : Recipe,
  writes : Ref[Int],
) -> Bool {
  match operation {
    @model.Operation::Set(id, _) if id == 1 && recipe.unrelated_retention == 0 =>
      false
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
  recipe : Recipe,
) -> Array[@model.Operation] {
  let retained = []
  let writes = Ref(0)
  for operation in operations {
    if keep_operation(operation, recipe, writes) {
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
fn change_writes(r : Recipe) -> Recipe {
  Recipe::{ ..r, write_retention: r.write_retention - 1 }
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
  if recipe.unrelated_retention > 0 {
    add_candidate(
      out,
      ShrinkPhase::UnrelatedOperations,
      original,
      change_unrelated(recipe),
    )
  }
  if recipe.write_retention > 0 {
    add_candidate(out, ShrinkPhase::Writes, original, change_writes(recipe))
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
        "seed=0x6A1601 case=\{i} recipe=\{@debug.to_string(minimized)} sources=\{@debug.to_string(script.initial_sources())} operations=\{@debug.to_string(script.operations())} Fresh=\{@debug.to_string(fresh_min)} Incremental=\{@debug.to_string(incremental_min)} first_observation=\{first_difference(fresh_min, incremental_min)}",
      )
    }
  }
}

///|
test "cutoff generator covers every kind with bounded varied steps" {
  let kinds = @scenarios.cutoff_all()
  for i, base in kinds {
    let steps = Array::makei(5, j => (i + j) % 3 - 1)
    let script = @model.CutoffScript::CutoffScript(base.kind(), steps)
    let fresh = normalized(@fresh.evaluate_cutoff(script))
    let incremental = normalized(@incremental_adapter.evaluate_cutoff(script))
    let difference = first_difference(fresh, incremental)
    if difference >= 0 {
      abort(
        "seed=0x6A1601 kind=\{@debug.to_string(base.kind())} steps=\{@debug.to_string(steps)} Fresh=\{@debug.to_string(fresh)} Incremental=\{@debug.to_string(incremental)} first_observation=\{difference}",
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
  let cycle_candidates = shrink_candidates(recipes[2])
  assert_eq(
    cycle_candidates[cycle_candidates.length() - 1].phase,
    ShrinkPhase::CyclePath,
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
