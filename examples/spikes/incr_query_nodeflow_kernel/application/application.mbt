///|
/// The closed set of executable application node declarations.
pub(all) enum NodeDescriptor {
  Number(value~ : Int)
  Boolean(value~ : Bool)
  Add
  Multiply
  SafeDivide
  Display
  OptionalOffset(value~ : Int)
} derive(Eq, Debug)

///|
/// The semantic kind of a node descriptor.
pub(all) enum NodeKind {
  Number
  Boolean
  Add
  Multiply
  SafeDivide
  Display
  OptionalOffset
} derive(Eq, Debug)

///|
/// A value type carried by an application port.
pub(all) enum PortValueType {
  Number
  Boolean
} derive(Eq, Debug)

///|
/// A typed authored parameter value.
pub(all) enum ParameterValue {
  Number(Int)
  Boolean(Bool)
} derive(Eq, Debug)

///|
/// A typed failure produced by a number formula.
pub(all) enum FormulaFailure {
  DivisionByZero
} derive(Eq, Debug)

///|
/// The current result of a number formula.
pub(all) enum NumberFormulaOutcome {
  Success(Int)
  Failure(FormulaFailure)
} derive(Eq, Debug)

///|
/// Consumer data carried by a current output.
pub(all) enum OutputData {
  Number(NumberFormulaOutcome)
  Boolean(Bool)
} derive(Eq, Debug)

///|
/// The command emitted by the Display action.
pub(all) enum Command {
  RecordNumber(Int)
} derive(Eq, Debug)

///|
/// The closed application decision made by an action.
pub(all) enum ApplicationDecision {
  Success(Command)
  ApplicationRefusal(FormulaFailure)
} derive(Eq, Debug)

///|
/// Metadata for one ordered input or output port.
pub(all) struct PortSpecification {
  value_type : PortValueType
  required : Bool
} derive(Eq, Debug)

///|
/// Immutable metadata needed to lower a descriptor into a graph.
pub(all) struct NodeSpecification {
  inputs : ReadOnlyArray[PortSpecification]
  outputs : ReadOnlyArray[PortSpecification]
  parameters : ReadOnlyArray[ParameterValue]
  action_count : Int
} derive(Eq, Debug)

///|
/// Returns the descriptor's stable kind.
pub fn NodeDescriptor::kind(self : NodeDescriptor) -> NodeKind {
  match self {
    Number(_) => NodeKind::Number
    Boolean(_) => NodeKind::Boolean
    Add => NodeKind::Add
    Multiply => NodeKind::Multiply
    SafeDivide => NodeKind::SafeDivide
    Display => NodeKind::Display
    OptionalOffset(_) => NodeKind::OptionalOffset
  }
}

///|
/// Returns ordered port, parameter, and action metadata for lowering.
pub fn NodeDescriptor::specification(
  self : NodeDescriptor,
) -> NodeSpecification {
  let number = { value_type: PortValueType::Number, required: true }
  let optional = { value_type: PortValueType::Number, required: false }
  let output_number = { value_type: PortValueType::Number, required: false }
  match self {
    Number(value~) =>
      {
        inputs: ReadOnlyArray::from_array([]),
        outputs: ReadOnlyArray::from_array([output_number]),
        parameters: ReadOnlyArray::from_array([ParameterValue::Number(value)]),
        action_count: 0,
      }
    Boolean(value~) =>
      {
        inputs: ReadOnlyArray::from_array([]),
        outputs: ReadOnlyArray::from_array([
          { value_type: PortValueType::Boolean, required: false },
        ]),
        parameters: ReadOnlyArray::from_array([ParameterValue::Boolean(value)]),
        action_count: 0,
      }
    Add | Multiply | SafeDivide =>
      {
        inputs: ReadOnlyArray::from_array([number, number]),
        outputs: ReadOnlyArray::from_array([output_number]),
        parameters: ReadOnlyArray::from_array([]),
        action_count: 0,
      }
    Display =>
      {
        inputs: ReadOnlyArray::from_array([number]),
        outputs: ReadOnlyArray::from_array([output_number]),
        parameters: ReadOnlyArray::from_array([]),
        action_count: 1,
      }
    OptionalOffset(value~) =>
      {
        inputs: ReadOnlyArray::from_array([number, optional]),
        outputs: ReadOnlyArray::from_array([output_number]),
        parameters: ReadOnlyArray::from_array([ParameterValue::Number(value)]),
        action_count: 0,
      }
  }
}

///|
/// Returns the declared parameter values in declaration order.
pub fn NodeDescriptor::parameter_values(
  self : NodeDescriptor,
) -> ReadOnlyArray[ParameterValue] {
  self.specification().parameters
}

///|
/// Returns a descriptor with one authored parameter replaced, when valid.
pub fn NodeDescriptor::with_parameter(
  self : NodeDescriptor,
  ordinal : Int,
  value : ParameterValue,
) -> NodeDescriptor? {
  if ordinal != 0 {
    return None
  }
  match (self, value) {
    (Number(_), ParameterValue::Number(value)) => Some(Number(value~))
    (Boolean(_), ParameterValue::Boolean(value)) => Some(Boolean(value~))
    (OptionalOffset(_), ParameterValue::Number(value)) =>
      Some(OptionalOffset(value~))
    _ => None
  }
}

///|
/// Evaluates addition, preserving left-to-right failure precedence.
pub fn evaluate_add(
  left : NumberFormulaOutcome,
  right : NumberFormulaOutcome,
) -> NumberFormulaOutcome {
  match (left, right) {
    (Failure(error), _) => Failure(error)
    (_, Failure(error)) => Failure(error)
    (Success(a), Success(b)) => Success(a + b)
  }
}

///|
/// Evaluates multiplication, preserving left-to-right failure precedence.
pub fn evaluate_multiply(
  left : NumberFormulaOutcome,
  right : NumberFormulaOutcome,
) -> NumberFormulaOutcome {
  match (left, right) {
    (Failure(error), _) => Failure(error)
    (_, Failure(error)) => Failure(error)
    (Success(a), Success(b)) => Success(a * b)
  }
}

///|
/// Evaluates safe division, preserving declared-order failures.
pub fn evaluate_safe_divide(
  left : NumberFormulaOutcome,
  right : NumberFormulaOutcome,
) -> NumberFormulaOutcome {
  match (left, right) {
    (Failure(error), _) => Failure(error)
    (_, Failure(error)) => Failure(error)
    (Success(_), Success(0)) => Failure(FormulaFailure::DivisionByZero)
    (Success(a), Success(b)) => Success(a / b)
  }
}

///|
/// Evaluates OptionalOffset; an absent optional input contributes zero.
pub fn evaluate_optional_offset(
  required : NumberFormulaOutcome,
  optional : NumberFormulaOutcome?,
  offset : Int,
) -> NumberFormulaOutcome {
  match required {
    Failure(error) => Failure(error)
    Success(value) =>
      match optional {
        Some(Failure(error)) => Failure(error)
        Some(Success(extra)) => Success(value + extra + offset)
        None => Success(value + offset)
      }
  }
}

///|
/// Produces the Display action decision for a prepared number outcome.
pub fn display_decision(outcome : NumberFormulaOutcome) -> ApplicationDecision {
  match outcome {
    Success(value) => ApplicationDecision::Success(Command::RecordNumber(value))
    Failure(error) => ApplicationDecision::ApplicationRefusal(error)
  }
}

///|
/// Encodes a descriptor using the stable descriptor wire shape.
pub fn encode_descriptor_json(descriptor : NodeDescriptor) -> String {
  let value : Json = match descriptor {
    Number(value~) =>
      Json::object({
        "kind": Json::string("number"),
        "value": Json::number(value.to_double()),
      })
    Boolean(value~) =>
      Json::object({
        "kind": Json::string("boolean"),
        "value": @json.to_json(value),
      })
    Add => Json::object({ "kind": Json::string("add") })
    Multiply => Json::object({ "kind": Json::string("multiply") })
    SafeDivide => Json::object({ "kind": Json::string("safe_divide") })
    Display => Json::object({ "kind": Json::string("display") })
    OptionalOffset(value~) =>
      Json::object({
        "kind": Json::string("optional_offset"),
        "value": Json::number(value.to_double()),
      })
  }
  value.stringify()
}

///|
/// Errors returned by descriptor JSON decoding.
pub(all) enum DescriptorDecodeError {
  MalformedJson
  WrongShape
} derive(Eq, Debug)

///|
fn json_int(value : Json) -> Int? {
  match value {
    Json::Number(value, ..) if value == value.to_int().to_double() =>
      Some(value.to_int())
    _ => None
  }
}

///|
fn json_field(object : Map[String, Json], name : String) -> Json? {
  object.get_from_string(name.view())
}

///|
/// Decodes the stable descriptor JSON shape.
pub fn decode_descriptor_json(
  text : StringView,
) -> Result[NodeDescriptor, DescriptorDecodeError] noraise {
  let root = @json.parse(text) catch {
    _ => return Err(DescriptorDecodeError::MalformedJson)
  }
  match root {
    Json::Object(object) =>
      match json_field(object, "kind") {
        Some(Json::String(kind)) =>
          match kind {
            "number" =>
              match json_field(object, "value") {
                Some(value) =>
                  match json_int(value) {
                    Some(v) => Ok(NodeDescriptor::Number(value=v))
                    None => Err(WrongShape)
                  }
                _ => Err(WrongShape)
              }
            "boolean" =>
              match json_field(object, "value") {
                Some(Json::True) => Ok(NodeDescriptor::Boolean(value=true))
                Some(Json::False) => Ok(NodeDescriptor::Boolean(value=false))
                _ => Err(WrongShape)
              }
            "add" => Ok(NodeDescriptor::Add)
            "multiply" => Ok(NodeDescriptor::Multiply)
            "safe_divide" => Ok(NodeDescriptor::SafeDivide)
            "display" => Ok(NodeDescriptor::Display)
            "optional_offset" =>
              match json_field(object, "value") {
                Some(value) =>
                  match json_int(value) {
                    Some(v) => Ok(NodeDescriptor::OptionalOffset(value=v))
                    None => Err(WrongShape)
                  }
                _ => Err(WrongShape)
              }
            _ => Err(WrongShape)
          }
        _ => Err(WrongShape)
      }
    _ => Err(WrongShape)
  }
}
