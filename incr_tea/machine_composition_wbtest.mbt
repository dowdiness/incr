///|
fn machine_test_add(
  model : MachineParentModel,
  id : Int,
  text : String,
) -> MachineTransitionResult {
  machine_transition(model, MachineAdd(id, text))
}

///|
fn machine_test_token(command : MachineValidateText) -> MachineValidationToken {
  command.token
}

///|
fn machine_test_child(model : MachineParentModel, id : Int) -> MachineChild {
  match machine_child(model, id) {
    Some(child) => child
    None => abort("missing test child")
  }
}

///|
test "machine core: routed edits, reorder, removal, and add preserve identity" {
  let added_one = machine_test_add(machine_initial_model(), 1, "one")
  let added_two = machine_test_add(added_one.model, 2, "two")
  let selected = machine_transition(added_two.model, MachineSelect(1))
  let edited = machine_transition(selected.model, MachineEdit(1, "ONE"))
  guard edited.decision == MachineApplied && edited.commands.length() == 1 else {
    fail("edit should apply and emit one validation")
  }
  guard machine_test_child(edited.model, 2) ==
    machine_test_child(selected.model, 2) else {
    fail("routed edit changed an unrelated child")
  }
  let one_before = machine_test_child(edited.model, 1)
  let two_before = machine_test_child(edited.model, 2)
  let reordered = machine_transition(
    edited.model,
    MachineReorder(machine_readonly([2, 1])),
  )
  guard machine_ids(reordered.model) == [2, 1] &&
    machine_test_child(reordered.model, 1) == one_before &&
    machine_test_child(reordered.model, 2) == two_before else {
    fail("reorder did not preserve child state")
  }
  let removed = machine_transition(reordered.model, MachineRemove(1))
  guard machine_ids(removed.model) == [2] &&
    removed.model.selected_id == Some(2) else {
    fail("removal did not repair selection deterministically")
  }
  let reused = machine_test_add(removed.model, 1, "reborn")
  let reborn = machine_test_child(reused.model, 1)
  guard reborn.incarnation != one_before.incarnation &&
    reborn.validation == MachinePending(1) &&
    reused.commands.length() == 1 else {
    fail("ID reuse did not create a fresh mounted lifetime")
  }
}

///|
test "machine core: validation result classification is exact" {
  let added = machine_test_add(machine_initial_model(), 1, "one")
  let first_token = machine_test_token(added.commands[0])
  let edited = machine_transition(added.model, MachineEdit(1, "ONE"))
  let current_token = machine_test_token(edited.commands[0])
  let missing = machine_transition(
    edited.model,
    MachineComplete({ ..current_token, child_id: 99 }, MachineValidationValid),
  )
  let retired = machine_transition(
    edited.model,
    MachineComplete(
      { ..current_token, incarnation: current_token.incarnation + 1 },
      MachineValidationValid,
    ),
  )
  let superseded = machine_transition(
    edited.model,
    MachineComplete(first_token, MachineValidationValid),
  )
  let future = machine_transition(
    edited.model,
    MachineComplete(
      { ..current_token, request_seq: current_token.request_seq + 1 },
      MachineValidationValid,
    ),
  )
  guard missing.decision == MachineIgnoredMissingChild &&
    retired.decision == MachineIgnoredRetiredIncarnation &&
    superseded.decision == MachineIgnoredSuperseded &&
    future.decision == MachineRejectedUnexpected else {
    fail("completion classification order is wrong")
  }
  guard missing.model == edited.model &&
    retired.model == edited.model &&
    superseded.model == edited.model &&
    future.model == edited.model else {
    fail("ignored or rejected completion mutated the model")
  }
  let applied = machine_transition(
    edited.model,
    MachineComplete(current_token, MachineValidationInvalid("reserved")),
  )
  guard applied.decision == MachineApplied &&
    machine_test_child(applied.model, 1).validation ==
    MachineInvalid(current_token.request_seq, "reserved") else {
    fail("current completion did not overwrite validation")
  }
  let duplicate = machine_transition(
    applied.model,
    MachineComplete(current_token, MachineValidationInvalid("reserved")),
  )
  guard duplicate.decision == MachineIgnoredDuplicate &&
    duplicate.model == applied.model else {
    fail("duplicate completion was not ignored")
  }
}

///|
test "machine core: request sequence has one source of truth" {
  let added = machine_test_add(machine_initial_model(), 1, "one")
  let first = machine_test_token(added.commands[0])
  guard first.request_seq == 1 &&
    machine_test_child(added.model, 1).validation ==
    MachinePending(first.request_seq) else {
    fail("initial command and validation sequence diverged")
  }
  let completed = machine_transition(
    added.model,
    MachineComplete(first, MachineValidationValid),
  )
  let edited = machine_transition(completed.model, MachineEdit(1, "ONE"))
  let second = machine_test_token(edited.commands[0])
  guard second.request_seq == first.request_seq + 1 &&
    machine_test_child(edited.model, 1).validation ==
    MachinePending(second.request_seq) else {
    fail("edit did not derive the next sequence from validation state")
  }
  let snapshot = machine_snapshot(completed.model)
  let restored = machine_transition(edited.model, MachineRestore(snapshot))
  let third = machine_test_token(restored.commands[0])
  guard third.request_seq == second.request_seq + 1 &&
    machine_test_child(restored.model, 1).validation ==
    MachinePending(third.request_seq) else {
    fail("restore did not preserve the single sequence source")
  }
}

///|
test "machine core: restore reconciles semantic identity and reissues validation" {
  let first = machine_test_add(machine_initial_model(), 1, "one")
  let second = machine_test_add(first.model, 2, "two")
  let selected = machine_transition(second.model, MachineSelect(1))
  let snapshot = machine_snapshot(selected.model)
  let historical_one = machine_test_child(selected.model, 1)
  let historical_token = machine_test_token(first.commands[0])
  let removed = machine_transition(selected.model, MachineRemove(1))
  let edited_two = machine_transition(removed.model, MachineEdit(2, "TWO"))
  let restored = machine_transition(edited_two.model, MachineRestore(snapshot))
  let restored_one = machine_test_child(restored.model, 1)
  let restored_two = machine_test_child(restored.model, 2)
  guard restored.decision == MachineApplied && restored.commands.length() == 2 else {
    fail("restore should validate the reborn and changed records")
  }
  guard restored_one.incarnation != historical_one.incarnation &&
    restored_one.validation == MachinePending(1) &&
    restored_two.incarnation ==
    machine_test_child(edited_two.model, 2).incarnation &&
    machine_validation_request_seq(restored_two.validation) ==
    machine_validation_request_seq(
      machine_test_child(edited_two.model, 2).validation,
    ) +
    1 else {
    fail("restore lifecycle reconciliation is wrong")
  }
  let historical = machine_transition(
    restored.model,
    MachineComplete(historical_token, MachineValidationValid),
  )
  guard historical.decision == MachineIgnoredRetiredIncarnation else {
    fail("historical incarnation completion was accepted")
  }
}

///|
test "machine core: every user-action decision preserves rejected models" {
  let added = machine_test_add(machine_initial_model(), 1, "one")
  let missing_edit = machine_transition(added.model, MachineEdit(9, "x"))
  let duplicate_add = machine_transition(added.model, MachineAdd(1, "again"))
  let no_change = machine_transition(added.model, MachineEdit(1, "one"))
  let malformed = machine_transition(
    added.model,
    MachineReorder(machine_readonly([1, 1])),
  )
  let cases = [missing_edit, duplicate_add, no_change, malformed]
  let expected = [
    MachineIgnoredMissingChild,
    MachineIgnoredDuplicateId,
    MachineIgnoredNoChange,
    MachineRejectedInvalidAction,
  ]
  for index, result in cases {
    guard result.decision == expected[index] &&
      result.model == added.model &&
      result.commands.is_empty() else {
      fail("ignored or rejected user action changed state")
    }
  }
}

///|
fn machine_test_replay(
  initial : MachineParentModel,
  actions : ArrayView[MachineAction],
) -> (MachineParentModel, Array[MachineValidateText], Array[MachineDecision]) {
  let commands : Array[MachineValidateText] = []
  let decisions : Array[MachineDecision] = []
  let model = Ref(initial)
  for action in actions {
    let result = machine_transition(model.val, action)
    for command in result.commands {
      commands.push(command)
    }
    decisions.push(result.decision)
    model.val = result.model
  }
  (model.val, commands, decisions)
}

///|
test "machine core: identical complete event streams replay deterministically" {
  let first = machine_test_add(machine_initial_model(), 1, "one")
  let token = machine_test_token(first.commands[0])
  let actions = [
    MachineAdd(1, "one"),
    MachineSelect(1),
    MachineEdit(1, "ONE"),
    MachineComplete(
      { ..token, request_seq: token.request_seq + 1 },
      MachineValidationValid,
    ),
  ]
  let left = machine_test_replay(machine_initial_model(), actions)
  let right = machine_test_replay(machine_initial_model(), actions)
  guard left == right else { fail("identical replay diverged") }
}

///|
fn machine_test_completion_permutations() -> Array[Array[Int]] {
  [
    [0, 1, 2, 3],
    [0, 1, 3, 2],
    [0, 2, 1, 3],
    [0, 2, 3, 1],
    [0, 3, 1, 2],
    [0, 3, 2, 1],
    [1, 0, 2, 3],
    [1, 0, 3, 2],
    [1, 2, 0, 3],
    [1, 2, 3, 0],
    [1, 3, 0, 2],
    [1, 3, 2, 0],
    [2, 0, 1, 3],
    [2, 0, 3, 1],
    [2, 1, 0, 3],
    [2, 1, 3, 0],
    [2, 3, 0, 1],
    [2, 3, 1, 0],
    [3, 0, 1, 2],
    [3, 0, 2, 1],
    [3, 1, 0, 2],
    [3, 1, 2, 0],
    [3, 2, 0, 1],
    [3, 2, 1, 0],
  ]
}

///|
test "machine core: generated legal completion permutations converge" {
  let added_one = machine_test_add(machine_initial_model(), 1, "one")
  let token_one_old = machine_test_token(added_one.commands[0])
  let edited_one = machine_transition(added_one.model, MachineEdit(1, "ONE"))
  let token_one_new = machine_test_token(edited_one.commands[0])
  let added_two = machine_test_add(edited_one.model, 2, "two")
  let token_two_old = machine_test_token(added_two.commands[0])
  let edited_two = machine_transition(added_two.model, MachineEdit(2, "TWO"))
  let token_two_new = machine_test_token(edited_two.commands[0])
  let completions = [
    MachineComplete(token_one_old, MachineValidationInvalid("old-one")),
    MachineComplete(token_one_new, MachineValidationValid),
    MachineComplete(token_two_old, MachineValidationInvalid("old-two")),
    MachineComplete(token_two_new, MachineValidationValid),
  ]
  let permutations = machine_test_completion_permutations()
  let generated : Array[Int] = @quickcheck.samples(128)
  let mut baseline : MachineParentModel? = None
  let seen = Array::make(24, false)
  for choice in generated {
    let index = (choice % 24 + 24) % 24
    seen[index] = true
    let actions = [
      for completion_index in permutations[index] => {
        completions[completion_index]
      }
    ]
    let (final_model, _, _) = machine_test_replay(edited_two.model, actions)
    match baseline {
      None => baseline = Some(final_model)
      Some(expected) => {
        guard final_model == expected else {
          fail("legal completion permutation changed quiescent state")
        }
      }
    }
  }
  guard seen.filter(value => value).length() >= 4 && seen[0] && seen[23] else {
    fail("quickcheck distribution missed required permutation classes")
  }
}

///|
test "machine Program: dispatch matches pure replay and carries exact tokens" {
  let runtime = @incr.Runtime()
  let observer = MachineProgramObserver()
  let program = machine_program(runtime, machine_initial_model(), observer)
  let actions = [
    MachineAdd(1, "one"),
    MachineAdd(2, "two"),
    MachineSelect(1),
    MachineEdit(1, "ONE"),
    MachineReorder(machine_readonly([2, 1])),
  ]
  let direct = machine_test_replay(machine_initial_model(), actions)
  for action in actions {
    guard program.dispatch(action) else {
      fail("Program rejected live dispatch")
    }
  }
  guard program.read_view_or_abort() == machine_view(direct.0) &&
    observer.issued == direct.1 &&
    observer.decisions == direct.2 else {
    fail("Program shell diverged from pure replay")
  }
  let current = observer.issued[2]
  guard current.token.child_id == 1 &&
    current.token.incarnation == 1 &&
    current.token.request_seq == 2 &&
    current.text == "ONE" else {
    fail("Program shell reconstructed or altered an issued token")
  }
  program.dispose()
}

///|
test "machine Program: completion decisions flow through dispatch" {
  let runtime = @incr.Runtime()
  let observer = MachineProgramObserver()
  let program = machine_program(runtime, machine_initial_model(), observer)
  ignore(program.dispatch(MachineAdd(1, "one")))
  let old = observer.issued[0].token
  ignore(program.dispatch(MachineEdit(1, "ONE")))
  let current = observer.issued[1].token
  let completions = [
    MachineComplete(old, MachineValidationValid),
    MachineComplete(current, MachineValidationValid),
    MachineComplete(current, MachineValidationValid),
    MachineComplete(
      { ..current, incarnation: current.incarnation + 1 },
      MachineValidationValid,
    ),
    MachineComplete(
      { ..current, request_seq: current.request_seq + 1 },
      MachineValidationValid,
    ),
  ]
  for completion in completions {
    ignore(program.dispatch(completion))
  }
  let decisions = observer.decisions
  guard decisions[2] == MachineIgnoredSuperseded &&
    decisions[3] == MachineApplied &&
    decisions[4] == MachineIgnoredDuplicate &&
    decisions[5] == MachineIgnoredRetiredIncarnation &&
    decisions[6] == MachineRejectedUnexpected else {
    fail("Program completion classification diverged from the core")
  }
  program.dispose()
}

///|
test "machine Program: GC, churn, and disposal keep one bounded graph" {
  let runtime = @incr.Runtime()
  let observer = MachineProgramObserver()
  let program = machine_program(runtime, machine_initial_model(), observer)
  let view_id = program._view_id
  let initial_info = match runtime.cell_info(view_id) {
    Some(info) => info
    None => fail("primed Program view missing from introspection")
  }
  guard initial_info.dependencies.length() == 1 &&
    runtime.gc_root_count(view_id) == 1 else {
    fail("Program view should have one version dependency and one GC root")
  }
  runtime.gc()
  for wave in 0..<64 {
    ignore(program.dispatch(MachineAdd(wave, "row")))
    if wave >= 8 {
      ignore(program.dispatch(MachineRemove(wave - 8)))
    }
    guard program._view_id == view_id else {
      fail("Program replaced its view root")
    }
    let info = match runtime.cell_info(view_id) {
      Some(value) => value
      None => fail("view root disappeared during churn")
    }
    guard info.dependencies.length() == initial_info.dependencies.length() &&
      runtime.gc_root_count(view_id) == 1 else {
      fail("Program reactive graph grew during child churn")
    }
    let view = program.read_view_or_abort()
    guard view.rows.length() <= 8 else { fail("retired child remained live") }
    if wave % 16 == 0 {
      runtime.gc()
    }
  }
  runtime.gc()
  guard program.read_view_or_abort().rows.length() == 8 else {
    fail("live child cardinality diverged after churn")
  }
  program.dispose()
  program.dispose()
  runtime.gc()
  guard runtime.gc_root_count(view_id) == 0 &&
    runtime.cell_info(view_id) is None else {
    fail("Program disposal did not release the watched graph")
  }
  let decisions_before = observer.decisions.length()
  guard !program.dispatch(MachineAdd(99, "disposed")) &&
    observer.decisions.length() == decisions_before &&
    program.read_view() is None else {
    fail("disposed Program accepted work")
  }
}
