///|
/// Memo-free evaluator for the shared integer operation model.
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] {
  let values : Map[Int, Int] = { 0: 0 }
  let observations : Array[@model.Observation] = []
  for operation in script.operations {
    match operation {
      @model.Operation::Set(id, value) => values[id] = value
      @model.Operation::Read(id) =>
        match values.get(id) {
          Some(value) => observations.push(@model.Observation::Value(value))
          None => observations.push(@model.Observation::Missing(id))
        }
    }
  }
  observations
}
