///|
priv struct MachineViewRow {
  id : Int
  incarnation : Int
  text : String
  validation : MachineValidation
} derive(Eq)

///|
priv struct MachineView {
  rows : ReadOnlyArray[MachineViewRow]
  selected_id : Int?
} derive(Eq)

///|
priv struct MachineProgramObserver {
  decisions : Array[MachineDecision]
  issued : Array[MachineValidateText]
}

///|
fn MachineProgramObserver::MachineProgramObserver() -> MachineProgramObserver {
  { decisions: [], issued: [] }
}

///|
priv struct MachineProgramHooks {
  before_transition : () -> Unit
  after_transition : () -> Unit
  before_view : () -> Unit
  after_view : () -> Unit
}

///|
fn machine_view(model : MachineParentModel) -> MachineView {
  {
    rows: machine_readonly(
      [
        for child in model.children => {
          {
            id: child.id,
            incarnation: child.incarnation,
            text: child.text,
            validation: child.validation,
          }
        }
      ],
    ),
    selected_id: model.selected_id,
  }
}

///|
fn machine_program_cmds(
  commands : ReadOnlyArray[MachineValidateText],
  observer : MachineProgramObserver,
) -> Cmd[MachineAction] {
  Cmd::batch(
    [
      for command in commands => {
        Cmd::effect(_enqueue => observer.issued.push(command))
      }
    ],
  )
}

///|
fn[View : Eq] machine_program_with_view(
  runtime : @incr.Runtime,
  initial : MachineParentModel,
  observer : MachineProgramObserver,
  project : (MachineParentModel) -> View,
  hooks? : MachineProgramHooks,
) -> Program[MachineAction, View] {
  Program::stateful_cmd(
    runtime,
    initial,
    (action, model) => {
      match hooks {
        Some(value) => (value.before_transition)()
        None => ()
      }
      let result = machine_transition(model, action)
      match hooks {
        Some(value) => (value.after_transition)()
        None => ()
      }
      observer.decisions.push(result.decision)
      (result.model, machine_program_cmds(result.commands, observer))
    },
    model => {
      match hooks {
        Some(value) => (value.before_view)()
        None => ()
      }
      let view = project(model)
      match hooks {
        Some(value) => (value.after_view)()
        None => ()
      }
      view
    },
    label="machine_composition.view",
  )
}

///|
#warnings("-unused_value")
fn machine_program(
  runtime : @incr.Runtime,
  initial : MachineParentModel,
  observer : MachineProgramObserver,
  hooks? : MachineProgramHooks,
) -> Program[MachineAction, MachineView] {
  machine_program_with_view(runtime, initial, observer, machine_view, hooks?)
}
