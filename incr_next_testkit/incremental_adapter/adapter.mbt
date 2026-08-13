///|
fn read_query(
  store : @incr_next.Store,
  region : @incr_next.Region,
  sources : Map[Int, @incr_next.Source[Int]],
  scenario : @model.Scenario,
  source_id : Int,
  key : Int,
  computes : Ref[Int],
) -> Result[Int, @incr_next.ReadError] {
  let source = match scenario {
    @model.Scenario::Source | @model.Scenario::KeyedQuery => sources[source_id]
    _ => sources[0]
  }
  match scenario {
    @model.Scenario::Source => store.read(source.view())
    @model.Scenario::UnitQuery => {
      let query = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        ctx.read(source.view())
      })
      match query {
        Ok(query) => store.read(query.at(()))
        Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
      }
    }
    @model.Scenario::KeyedQuery => {
      let query = region.query((ctx, key : Int) => {
        computes.val = computes.val + 1
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
      let first = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        ctx.read(source.view())
      })
      match first {
        Err(_) => Err(@incr_next.ReadError::ExpiredQueryContext)
        Ok(first) => {
          let second = region.query((ctx, _unit : Unit) => {
            computes.val = computes.val + 1
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
      let shared = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        ctx.read(source.view())
      })
      let left = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        match ctx.read(shared.unwrap().at(())) {
          Ok(value) => Ok(value + 1)
          Err(error) => Err(error)
        }
      })
      let right = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        match ctx.read(shared.unwrap().at(())) {
          Ok(value) => Ok(value + 2)
          Err(error) => Err(error)
        }
      })
      match (left, right) {
        (Ok(left), Ok(right)) => {
          let root = region.query((ctx, _unit : Unit) => {
            computes.val = computes.val + 1
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
        computes.val = computes.val + 1
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
        computes.val = computes.val + 1
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
  let computes = Ref(0)
  for operation in operations {
    match operation {
      @model.Operation::Define(_, _) => ()
      @model.Operation::Set(id, value) =>
        match sources.get(id) {
          Some(source) => ignore(store.transaction(tx => tx.set(source, value)))
          None => ()
        }
      @model.Operation::Read(id) =>
        match sources.get(id) {
          None => observations.push(@model.Observation::Missing(id))
          Some(_) =>
            match
              read_query(
                store,
                region,
                sources,
                script.scenario_tag(),
                id,
                0,
                computes,
              ) {
              Ok(value) => observations.push(@model.Observation::Value(value))
              Err(_) => observations.push(@model.Observation::Missing(id))
            }
        }
      @model.Operation::ReadKey(id, key) =>
        match sources.get(id) {
          None => observations.push(@model.Observation::Missing(id))
          Some(_) =>
            match
              read_query(
                store,
                region,
                sources,
                script.scenario_tag(),
                id,
                key,
                computes,
              ) {
              Ok(value) => observations.push(@model.Observation::Value(value))
              Err(_) => observations.push(@model.Observation::Missing(id))
            }
        }
      @model.Operation::DomainFailure(code) => {
        let query = region
          .query((_ctx, _unit : Unit) => {
            computes.val = computes.val + 1
            let domain_value : Result[Int, Int] = Err(code)
            Ok(domain_value)
          })
          .unwrap()
        match store.read(query.at(())) {
          Ok(Err(domain_code)) =>
            observations.push(
              @model.Observation::Error(
                @model.ScenarioError::DomainFailure(domain_code),
              ),
            )
          _ => observations.push(@model.Observation::Missing(code))
        }
      }
      @model.Operation::StructuralFailure(code) => {
        let other = @incr_next.Store::Store()
        let other_region = other.region().unwrap()
        let foreign = other_region.source(code).unwrap()
        let query = region
          .query((ctx, _unit : Unit) => {
            computes.val = computes.val + 1
            ctx.read(foreign.view())
          })
          .unwrap()
        match store.read(query.at(())) {
          Err(@incr_next.ReadError::CrossStore(..)) =>
            observations.push(
              @model.Observation::Error(
                @model.ScenarioError::StructuralFailure(code),
              ),
            )
          _ => observations.push(@model.Observation::Missing(code))
        }
        ignore(other_region.close())
      }
    }
  }
  observations.push(@model.Observation::Counter(computes.val))
  ignore(region.close())
  observations
}
