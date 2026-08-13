///|
/// Runs the K1.1 kernel through the same logical operation script.
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let source = region.source(0).unwrap()
  let observations : Array[@model.Observation] = []
  for operation in script.operations {
    match operation {
      @model.Operation::Set(_id, value) =>
        ignore(store.transaction(tx => tx.set(source, value)))
      @model.Operation::Read(id) =>
        match store.read(source.view()) {
          Ok(value) => observations.push(@model.Observation::Value(value))
          Err(_) => observations.push(@model.Observation::Missing(id))
        }
    }
  }
  ignore(region.close())
  observations
}
