///|
fn read_query(
  store : @incr_next.Store,
  region : @incr_next.Region,
  sources : Map[Int, @incr_next.Source[Int]],
  scenario : @model.Scenario,
  source_id : Int,
  key : Int,
) -> Result[Int, @incr_next.ReadError] {
  let source = match scenario {
    @model.Scenario::Source | @model.Scenario::KeyedQuery => sources[source_id]
    _ => sources[0]
  }
  match scenario {
    @model.Scenario::Source => store.read(source.view())
    @model.Scenario::UnitQuery => {
      let query = region.query((ctx, _unit : Unit) => ctx.read(source.view()))
      match query {
        Ok(query) => store.read(query.at(()))
        Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
      }
    }
    @model.Scenario::KeyedQuery => {
      let query = region.query((ctx, key : Int) => {
        match ctx.read(source.view()) {
          Ok(value) => Ok(value + key)
          Err(error) => Err(error)
        }
      })
      match query {
        Ok(query) => store.read(query.at(key))
        Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
      }
    }
    @model.Scenario::Chain => {
      let first = region.query((ctx, _unit : Unit) => ctx.read(source.view()))
      match first {
        Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
        Ok(first) => {
          let second = region.query((ctx, _unit : Unit) => {
            match ctx.read(first.at(())) {
              Ok(value) => Ok(value + 1)
              Err(error) => Err(error)
            }
          })
          match second {
            Ok(second) => store.read(second.at(()))
            Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
          }
        }
      }
    }
    @model.Scenario::Diamond => {
      let shared = region.query((ctx, _unit : Unit) => ctx.read(source.view()))
      let left = region.query((ctx, _unit : Unit) => {
        match ctx.read(shared.unwrap().at(())) {
          Ok(value) => Ok(value + 1)
          Err(error) => Err(error)
        }
      })
      let right = region.query((ctx, _unit : Unit) => {
        match ctx.read(shared.unwrap().at(())) {
          Ok(value) => Ok(value + 2)
          Err(error) => Err(error)
        }
      })
      match (left, right) {
        (Ok(left), Ok(right)) => {
          let root = region.query((ctx, _unit : Unit) => {
            match (ctx.read(left.at(())), ctx.read(right.at(()))) {
              (Ok(a), Ok(b)) => Ok(a + b)
              (Err(error), _) => Err(error)
              (_, Err(error)) => Err(error)
            }
          })
          match root {
            Ok(root) => store.read(root.at(()))
            Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
          }
        }
        _ => Err(@incr_next.ReadError::ExpiredQueryContext)
      }
    }
    @model.Scenario::DynamicBranch => {
      let branch = sources[1]
      let query = region.query((ctx, _unit : Unit) => {
        match ctx.read(branch.view()) {
          Ok(flag) => if flag == 0 { ctx.read(source.view()) } else { Ok(flag) }
          Err(error) => Err(error)
        }
      })
      match query {
        Ok(query) => store.read(query.at(()))
        Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
      }
    }
    @model.Scenario::RootSnapshot => {
      let query = region.query((ctx, _unit : Unit) => {
        match ctx.revision() {
          Ok(_) => ctx.read(source.view())
          Err(error) => Err(error)
        }
      })
      match query {
        Ok(query) => store.read(query.at(()))
        Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
      }
    }
    @model.Scenario::DomainFailure | @model.Scenario::StructuralError =>
      store.read(source.view())
  }
}

///|
/// Runs the K1.1 kernel through the same logical operation script.
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let operations = script.operations()
  let initial : Map[Int, Int] = Map([])
  let known : Map[Int, Bool] = { 0: true }
  for operation in operations {
    match operation {
      @model.Operation::Define(id, value) => {
        initial[id] = value
        known[id] = true
      }
      @model.Operation::ReadKey(id, _) => known[id] = true
      @model.Operation::Set(id, _) => known[id] = true
      _ => ()
    }
  }
  if script.scenario_tag() is @model.Scenario::DynamicBranch {
    known[1] = true
  }
  let sources : Map[Int, @incr_next.Source[Int]] = Map([])
  for id, _ in known {
    let value = match initial.get(id) {
      Some(value) => value
      None => 0
    }
    sources[id] = region.source(value).unwrap()
  }
  let observations : Array[@model.Observation] = []
  let reads = Ref(0)
  for operation in operations {
    match operation {
      @model.Operation::Define(_, _) => ()
      @model.Operation::Set(id, value) =>
        match sources.get(id) {
          Some(source) => ignore(store.transaction(tx => tx.set(source, value)))
          None => ()
        }
      @model.Operation::Read(id) => {
        reads.val = reads.val + 1
        match sources.get(id) {
          None => observations.push(@model.Observation::Missing(id))
          Some(_) =>
            match
              read_query(store, region, sources, script.scenario_tag(), id, 0) {
              Ok(value) => observations.push(@model.Observation::Value(value))
              Err(_) => observations.push(@model.Observation::Missing(id))
            }
        }
      }
      @model.Operation::ReadKey(id, key) => {
        reads.val = reads.val + 1
        match sources.get(id) {
          None => observations.push(@model.Observation::Missing(id))
          Some(_) =>
            match
              read_query(store, region, sources, script.scenario_tag(), id, key) {
              Ok(value) => observations.push(@model.Observation::Value(value))
              Err(_) => observations.push(@model.Observation::Missing(id))
            }
        }
      }
      @model.Operation::DomainFailure(code) =>
        observations.push(
          @model.Observation::Error(@model.ScenarioError::DomainFailure(code)),
        )
      @model.Operation::StructuralFailure(code) =>
        observations.push(
          @model.Observation::Error(
            @model.ScenarioError::StructuralFailure(code),
          ),
        )
    }
  }
  observations.push(@model.Observation::Counter(reads.val))
  ignore(region.close())
  observations
}
