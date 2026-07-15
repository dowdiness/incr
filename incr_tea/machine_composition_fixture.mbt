///|
priv struct MachineValidationToken {
  child_id : Int
  incarnation : Int
  request_seq : Int
} derive(Eq, Debug)

///|
priv enum MachineValidation {
  MachineIdle
  MachinePending(Int)
  MachineValid(Int)
  MachineInvalid(Int, String)
} derive(Eq, Debug)

///|
priv enum MachineValidationOutcome {
  MachineValidationValid
  MachineValidationInvalid(String)
} derive(Eq, Debug)

///|
priv struct MachineChild {
  id : Int
  incarnation : Int
  text : String
  validation : MachineValidation
} derive(Eq, Debug)

///|
priv struct MachineParentModel {
  children : ReadOnlyArray[MachineChild]
  selected_id : Int?
  next_incarnation : Int
} derive(Eq, Debug)

///|
priv struct MachineSnapshotChild {
  id : Int
  text : String
} derive(Eq, Debug)

///|
priv struct MachineHistorySnapshot {
  children : ReadOnlyArray[MachineSnapshotChild]
  selected_id : Int?
} derive(Eq, Debug)

///|
priv struct MachineValidateText {
  token : MachineValidationToken
  text : String
} derive(Eq, Debug)

///|
priv enum MachineDecision {
  MachineApplied
  MachineIgnoredMissingChild
  MachineIgnoredDuplicateId
  MachineIgnoredNoChange
  MachineIgnoredRetiredIncarnation
  MachineIgnoredSuperseded
  MachineIgnoredDuplicate
  MachineRejectedInvalidAction
  MachineRejectedUnexpected
} derive(Eq, Debug)

///|
priv enum MachineAction {
  MachineEdit(Int, String)
  MachineSelect(Int)
  MachineAdd(Int, String)
  MachineRemove(Int)
  MachineReorder(ReadOnlyArray[Int])
  MachineRestore(MachineHistorySnapshot)
  MachineComplete(MachineValidationToken, MachineValidationOutcome)
} derive(Eq)

///|
priv struct MachineTransitionResult {
  model : MachineParentModel
  commands : ReadOnlyArray[MachineValidateText]
  decision : MachineDecision
}

///|
fn[T] machine_readonly(items : Array[T]) -> ReadOnlyArray[T] {
  ReadOnlyArray::from_array(items)
}

///|
fn machine_initial_model() -> MachineParentModel {
  { children: machine_readonly([]), selected_id: None, next_incarnation: 1 }
}

///|
fn machine_child_index(model : MachineParentModel, id : Int) -> Int? {
  model.children.search_by(child => child.id == id)
}

///|
fn machine_child(model : MachineParentModel, id : Int) -> MachineChild? {
  match machine_child_index(model, id) {
    Some(index) => Some(model.children[index])
    None => None
  }
}

///|
fn machine_ids(model : MachineParentModel) -> Array[Int] {
  [
    for child in model.children => child.id
  ]
}

///|
fn machine_replace_child(
  model : MachineParentModel,
  index : Int,
  replacement : MachineChild,
) -> MachineParentModel {
  let children = [
    for i, child in model.children => {
      if i == index {
        replacement
      } else {
        child
      }
    }
  ]
  { ..model, children: machine_readonly(children) }
}

///|
fn machine_result(
  model : MachineParentModel,
  decision : MachineDecision,
  commands? : Array[MachineValidateText] = [],
) -> MachineTransitionResult {
  { model, commands: machine_readonly(commands), decision }
}

///|
fn machine_validation_command(child : MachineChild) -> MachineValidateText {
  let request_seq = match child.validation {
    MachinePending(seq) => seq
    _ => abort("validation command requires a pending child")
  }
  {
    token: { child_id: child.id, incarnation: child.incarnation, request_seq },
    text: child.text,
  }
}

///|
fn machine_validation_request_seq(validation : MachineValidation) -> Int {
  match validation {
    MachineIdle => 0
    MachinePending(seq) | MachineValid(seq) | MachineInvalid(seq, _) => seq
  }
}

///|
fn machine_pending_child(
  id : Int,
  incarnation : Int,
  text : String,
  request_seq : Int,
) -> MachineChild {
  { id, incarnation, text, validation: MachinePending(request_seq) }
}

///|
fn machine_snapshot(model : MachineParentModel) -> MachineHistorySnapshot {
  {
    children: machine_readonly(
      [
        for child in model.children => {
          MachineSnapshotChild::{ id: child.id, text: child.text }
        }
      ],
    ),
    selected_id: model.selected_id,
  }
}

///|
fn machine_snapshot_is_valid(snapshot : MachineHistorySnapshot) -> Bool {
  for i, child in snapshot.children {
    for j in 0..<i {
      if snapshot.children[j].id == child.id {
        return false
      }
    }
  }
  match snapshot.selected_id {
    None => true
    Some(selected) => snapshot.children.any(child => child.id == selected)
  }
}

///|
fn machine_reorder_is_valid(
  model : MachineParentModel,
  ids : ReadOnlyArray[Int],
) -> Bool {
  guard ids.length() == model.children.length() else { return false }
  for i, id in ids {
    guard machine_child(model, id) is Some(_) else { return false }
    for j in 0..<i {
      if ids[j] == id {
        return false
      }
    }
  }
  true
}

///|
fn machine_transition_edit(
  model : MachineParentModel,
  id : Int,
  text : String,
) -> MachineTransitionResult {
  guard machine_child_index(model, id) is Some(index) else {
    return machine_result(model, MachineIgnoredMissingChild)
  }
  let child = model.children[index]
  guard child.text != text else {
    return machine_result(model, MachineIgnoredNoChange)
  }
  let next_seq = machine_validation_request_seq(child.validation) + 1
  let replacement = { ..child, text, validation: MachinePending(next_seq) }
  machine_result(
    machine_replace_child(model, index, replacement),
    MachineApplied,
    commands=[machine_validation_command(replacement)],
  )
}

///|
fn machine_transition_select(
  model : MachineParentModel,
  id : Int,
) -> MachineTransitionResult {
  guard machine_child(model, id) is Some(_) else {
    return machine_result(model, MachineIgnoredMissingChild)
  }
  guard model.selected_id != Some(id) else {
    return machine_result(model, MachineIgnoredNoChange)
  }
  machine_result({ ..model, selected_id: Some(id) }, MachineApplied)
}

///|
fn machine_transition_add(
  model : MachineParentModel,
  id : Int,
  text : String,
) -> MachineTransitionResult {
  guard machine_child(model, id) is None else {
    return machine_result(model, MachineIgnoredDuplicateId)
  }
  let child = machine_pending_child(id, model.next_incarnation, text, 1)
  let children = [..model.children, child]
  machine_result(
    {
      children: machine_readonly(children),
      selected_id: model.selected_id,
      next_incarnation: model.next_incarnation + 1,
    },
    MachineApplied,
    commands=[machine_validation_command(child)],
  )
}

///|
fn machine_selection_after_remove(
  model : MachineParentModel,
  removed_index : Int,
) -> Int? {
  guard model.selected_id == Some(model.children[removed_index].id) else {
    return model.selected_id
  }
  if model.children.length() == 1 {
    None
  } else if removed_index + 1 < model.children.length() {
    Some(model.children[removed_index + 1].id)
  } else {
    Some(model.children[removed_index - 1].id)
  }
}

///|
fn machine_transition_remove(
  model : MachineParentModel,
  id : Int,
) -> MachineTransitionResult {
  guard machine_child_index(model, id) is Some(index) else {
    return machine_result(model, MachineIgnoredMissingChild)
  }
  let children = [ for i, child in model.children if i != index => child ]
  machine_result(
    {
      ..model,
      children: machine_readonly(children),
      selected_id: machine_selection_after_remove(model, index),
    },
    MachineApplied,
  )
}

///|
fn machine_transition_reorder(
  model : MachineParentModel,
  ids : ReadOnlyArray[Int],
) -> MachineTransitionResult {
  guard machine_reorder_is_valid(model, ids) else {
    return machine_result(model, MachineRejectedInvalidAction)
  }
  guard machine_ids(model) != [ for id in ids => id ] else {
    return machine_result(model, MachineIgnoredNoChange)
  }
  let children = [
    for id in ids => {
      match machine_child(model, id) {
        Some(child) => child
        None => abort("validated reorder lost a child")
      }
    }
  ]
  machine_result(
    { ..model, children: machine_readonly(children) },
    MachineApplied,
  )
}

///|
fn machine_transition_restore(
  model : MachineParentModel,
  snapshot : MachineHistorySnapshot,
) -> MachineTransitionResult {
  guard machine_snapshot_is_valid(snapshot) else {
    return machine_result(model, MachineRejectedInvalidAction)
  }
  guard machine_snapshot(model) != snapshot else {
    return machine_result(model, MachineIgnoredNoChange)
  }
  let commands : Array[MachineValidateText] = []
  let children : Array[MachineChild] = []
  let next_incarnation = Ref(model.next_incarnation)
  for snapshot_child in snapshot.children {
    let child = match machine_child(model, snapshot_child.id) {
      Some(current) if current.text == snapshot_child.text => current
      Some(current) => {
        let next_seq = machine_validation_request_seq(current.validation) + 1
        let changed = {
          ..current,
          text: snapshot_child.text,
          validation: MachinePending(next_seq),
        }
        commands.push(machine_validation_command(changed))
        changed
      }
      None => {
        let mounted = machine_pending_child(
          snapshot_child.id,
          next_incarnation.val,
          snapshot_child.text,
          1,
        )
        commands.push(machine_validation_command(mounted))
        next_incarnation.val = next_incarnation.val + 1
        mounted
      }
    }
    children.push(child)
  }
  machine_result(
    {
      children: machine_readonly(children),
      selected_id: snapshot.selected_id,
      next_incarnation: next_incarnation.val,
    },
    MachineApplied,
    commands~,
  )
}

///|
fn machine_transition_complete(
  model : MachineParentModel,
  token : MachineValidationToken,
  outcome : MachineValidationOutcome,
) -> MachineTransitionResult {
  guard machine_child_index(model, token.child_id) is Some(index) else {
    return machine_result(model, MachineIgnoredMissingChild)
  }
  let child = model.children[index]
  guard child.incarnation == token.incarnation else {
    return machine_result(model, MachineIgnoredRetiredIncarnation)
  }
  let current_seq = machine_validation_request_seq(child.validation)
  if token.request_seq < current_seq {
    return machine_result(model, MachineIgnoredSuperseded)
  }
  if token.request_seq > current_seq {
    return machine_result(model, MachineRejectedUnexpected)
  }
  guard child.validation is MachinePending(seq) && seq == token.request_seq else {
    return machine_result(model, MachineIgnoredDuplicate)
  }
  let validation = match outcome {
    MachineValidationValid => MachineValid(token.request_seq)
    MachineValidationInvalid(diagnostic) =>
      MachineInvalid(token.request_seq, diagnostic)
  }
  machine_result(
    machine_replace_child(model, index, { ..child, validation, }),
    MachineApplied,
  )
}

///|
fn machine_transition(
  model : MachineParentModel,
  action : MachineAction,
) -> MachineTransitionResult {
  match action {
    MachineEdit(id, text) => machine_transition_edit(model, id, text)
    MachineSelect(id) => machine_transition_select(model, id)
    MachineAdd(id, text) => machine_transition_add(model, id, text)
    MachineRemove(id) => machine_transition_remove(model, id)
    MachineReorder(ids) => machine_transition_reorder(model, ids)
    MachineRestore(snapshot) => machine_transition_restore(model, snapshot)
    MachineComplete(token, outcome) =>
      machine_transition_complete(model, token, outcome)
  }
}
