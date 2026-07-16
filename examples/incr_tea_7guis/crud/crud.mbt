///|
priv struct Person {
  name : String
  surname : String
}

///|
priv struct Model {
  filter : String
  name : String
  surname : String
  people : Array[Person]
  selected : Int?
}

///|
enum Msg {
  SetFilter(String)
  SetName(String)
  SetSurname(String)
  Select(Int)
  Create
  Update
  Delete
} derive(Eq)

///|
priv struct App {
  program : @tea.Program[Msg, @tea.Html[Msg]]
  _state : Ref[Model]
}

///|
fn App::App(runtime : @incr.Runtime) -> App {
  let scope = @incr.Scope::new(runtime)
  let state = Ref({
    filter: "",
    name: "Hans",
    surname: "Emil",
    people: [
      { name: "Hans", surname: "Emil" },
      { name: "Max", surname: "Mustermann" },
      { name: "Roman", surname: "Tisch" },
    ],
    selected: Some(0),
  })
  let version = scope.input_field(0, label="7guis.crud.version")
  let update : (Msg) -> @tea.Cmd[Msg] = msg => {
    state.val = update_model(msg, state.val)
    version.set(version.peek() + 1)
    @tea.Cmd::none()
  }
  let view : () -> @tea.Html[Msg] raise Failure = () => {
    ignore(version.get())
    view_model(state.val)
  }
  let program = @tea.Program::Program(
    runtime,
    scope,
    update,
    view,
    label="7guis.crud.view",
  )
  { program, _state: state }
}

///|
fn parse_int_or_none(value : String) -> Int? {
  let trimmed = value.trim()
  try @string.parse_int(trimmed) catch {
    _ => None
  } noraise {
    number => Some(number)
  }
}

///|
fn person_label(person : Person) -> String {
  "\{person.surname}, \{person.name}"
}

///|
fn person_matches(person : Person, filter : String) -> Bool {
  let needle = filter.trim().to_lower()
  let surname = person.surname.to_lower()
  let name = person.name.to_lower()
  needle.is_empty() || surname.contains(needle) || name.contains(needle)
}

///|
fn filtered_people(model : Model) -> Array[(Int, Person)] {
  model.people
  .mapi((index, person) => (index, person))
  .filter(pair => person_matches(pair.1, model.filter))
}

///|
fn update_model(msg : Msg, model : Model) -> Model {
  match msg {
    SetFilter(value) => {
      let filtered_model = { ..model, filter: value }
      let people = filtered_people(filtered_model)
      let selected = match model.selected {
        Some(index) =>
          if people.iter().any(pair => pair.0 == index) {
            Some(index)
          } else {
            people.get(0).map(pair => pair.0)
          }
        None => people.get(0).map(pair => pair.0)
      }
      match selected {
        Some(index) =>
          model.people
          .get(index)
          .map_or({ ..filtered_model, selected: None }, person => {
            ..filtered_model,
            selected: Some(index),
            name: person.name,
            surname: person.surname,
          })
        None => { ..filtered_model, selected: None }
      }
    }
    SetName(value) => { ..model, name: value }
    SetSurname(value) => { ..model, surname: value }
    Select(index) =>
      model.people
      .get(index)
      .map_or({ ..model, selected: None }, person => {
        ..model,
        selected: Some(index),
        name: person.name,
        surname: person.surname,
      })
    Create => {
      let person = { name: model.name, surname: model.surname }
      let people = model.people.copy()
      people.push(person)
      let filter = if person_matches(person, model.filter) {
        model.filter
      } else {
        ""
      }
      { ..model, filter, people, selected: Some(people.length() - 1) }
    }
    Update =>
      model.selected.map_or(model, index => {
        let updated_person = { name: model.name, surname: model.surname }
        let people = model.people.mapi((i, person) => {
          if i == index {
            updated_person
          } else {
            person
          }
        })
        let filter = if person_matches(updated_person, model.filter) {
          model.filter
        } else {
          ""
        }
        { ..model, filter, people }
      })
    Delete =>
      model.selected.map_or(model, index => {
        let people = model.people
          .mapi((i, person) => (i, person))
          .filter(pair => pair.0 != index)
          .map(pair => pair.1)
        { ..model, people, selected: None }
      })
  }
}

///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  let people = filtered_people(model)
  @tea.article(attrs=[@tea.class_attr("task-card")], [
    @tea.div(attrs=[@tea.class_attr("task-heading")], [
      @tea.h2([@tea.text("CRUD")]),
      @tea.p([
        @tea.text("Filtered list selection flows through an on_change payload."),
      ]),
    ]),
    @tea.div(attrs=[@tea.class_attr("task-body")], [
      field("Filter prefix", "crud-filter", model.filter, "filter"),
      @tea.node(
        "select",
        attrs=@tea.Attrs::build()
          .attr("size", "5")
          .class("person-list")
          .to_array(),
        events=[@tea.on_change(tag="select")],
        people.map(pair => {
          @tea.node(
            "option",
            attrs=option_attrs("\{pair.0}", model.selected == Some(pair.0)),
            [@tea.text(person_label(pair.1))],
          )
        }),
      ),
      field("Name", "crud-name", model.name, "name"),
      field("Surname", "crud-surname", model.surname, "surname"),
      @tea.div(attrs=[@tea.class_attr("button-row")], [
        @tea.button(
          attrs=button_attrs(),
          events=[@tea.on_click(Create)],
          "Create",
        ),
        @tea.button(
          attrs=button_attrs(),
          events=[@tea.on_click(Update)],
          "Update",
        ),
        @tea.button(
          attrs=button_attrs(),
          events=[@tea.on_click(Delete)],
          "Delete",
        ),
      ]),
    ]),
  ])
}

///|
fn field(
  label : String,
  id : String,
  value : String,
  tag : String,
) -> @tea.Html[Msg] {
  @tea.node("label", attrs=[@tea.class_attr("field"), @tea.attr("for", id)], [
    @tea.span([@tea.text(label)]),
    @tea.input(
      attrs=@tea.Attrs::build().attr("id", id).value(value).to_array(),
      events=[@tea.on_input(tag~)],
    ),
  ])
}

///|
fn option_attrs(value : String, selected : Bool) -> Array[@tea.Attribute] {
  let attrs = @tea.Attrs::build().attr("value", value)
  if selected {
    attrs.selected(true).to_array()
  } else {
    attrs.to_array()
  }
}

///|
fn button_attrs() -> Array[@tea.Attribute] {
  @tea.Attrs::build().attr("type", "button").to_array()
}

///|
fn resolve_value(id : @tea.ValueEventId, payload : @tea.ValuePayload) -> Msg? {
  match id.name {
    "filter" => Some(SetFilter(payload.value))
    "name" => Some(SetName(payload.value))
    "surname" => Some(SetSurname(payload.value))
    "select" => parse_int_or_none(payload.value).map(index => Select(index))
    _ => None
  }
}

///|
/// Mounts the CRUD task into `host` with its own runtime and browser renderer.
pub fn mount(host : @tea.DomElement) -> Unit {
  let runtime = @incr.Runtime()
  let app = App(runtime)
  let renderer = @tea.BrowserRenderer::BrowserRenderer(runtime)
  ignore(renderer.mount(host, app.program, on_value=resolve_value))
}
