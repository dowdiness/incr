///|
fn make_reader(
  store : @incr_next.Store,
  region : @incr_next.Region,
  sources : Map[Int, @incr_next.Source[Int]],
  scenario : @model.Scenario,
  computes : Ref[Int],
) -> (Int, Int) -> Result[Int, @incr_next.ReadError] {
  match scenario {
    @model.Scenario::Source =>
      (source_id, _key) => store.read(sources[source_id].view())
    @model.Scenario::UnitQuery => {
      let source = sources[0]
      let query = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          ctx.read(source.view())
        })
        .unwrap()
      let view = query.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::KeyedQuery => {
      let query = region
        .query((ctx, key : (Int, Int)) => {
          computes.val = computes.val + 1
          match ctx.read(sources[key.0].view()) {
            Ok(value) => Ok(value + key.1)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      (source_id, key) => store.read(query.at((source_id, key)))
    }
    @model.Scenario::Chain => {
      let source = sources[0]
      let first = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          ctx.read(source.view())
        })
        .unwrap()
      let second = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.read(first.at(())) {
            Ok(value) => Ok(value + 1)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let view = second.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::Diamond => {
      let source = sources[0]
      let shared = region
        .query((ctx, _branch : Int) => {
          computes.val = computes.val + 1
          ctx.read(source.view())
        })
        .unwrap()
      let left = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.read(shared.at(1)) {
            Ok(value) => Ok(value + 1)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let right = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.read(shared.at(2)) {
            Ok(value) => Ok(value + 2)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let root = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match (ctx.read(left.at(())), ctx.read(right.at(()))) {
            (Ok(a), Ok(b)) => Ok(a + b)
            (Err(error), _) => Err(error)
            (_, Err(error)) => Err(error)
          }
        })
        .unwrap()
      let view = root.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::DynamicBranch => {
      let source = sources[0]
      let query = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match sources.get(1) {
            None => ctx.read(source.view())
            Some(branch) =>
              match ctx.read(branch.view()) {
                Ok(flag) =>
                  if flag == 0 {
                    ctx.read(source.view())
                  } else {
                    Ok(flag)
                  }
                Err(error) => Err(error)
              }
          }
        })
        .unwrap()
      let view = query.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::RootSnapshot => {
      let source = sources[0]
      let query = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.revision() {
            Ok(_) => ctx.read(source.view())
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let view = query.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::DomainFailure | @model.Scenario::StructuralError =>
      (source_id, _key) => store.read(sources[source_id].view())
  }
}

///|
fn publish_or_define(
  store : @incr_next.Store,
  region : @incr_next.Region,
  sources : Map[Int, @incr_next.Source[Int]],
  source_id : Int,
  value : Int,
) -> Unit {
  match sources.get(source_id) {
    Some(source) => ignore(store.transaction(tx => tx.set(source, value)))
    None => sources[source_id] = region.source(value).unwrap()
  }
}

///|
/// Runs the K1.1 kernel through the same logical operation script.
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let sources : Map[Int, @incr_next.Source[Int]] = {
    0: region.source(0).unwrap(),
  }
  let observations : Array[@model.Observation] = []
  let computes = Ref(0)
  let reader : Ref[((Int, Int) -> Result[Int, @incr_next.ReadError])?] = Ref(
    None,
  )
  let read = (source_id : Int, key : Int) => {
    if !sources.contains(source_id) {
      observations.push(@model.Observation::Missing(source_id))
    } else {
      let run = match reader.val {
        Some(run) => run
        None => {
          let run = make_reader(
            store,
            region,
            sources,
            script.scenario_tag(),
            computes,
          )
          reader.val = Some(run)
          run
        }
      }
      match run(source_id, key) {
        Ok(value) => observations.push(@model.Observation::Value(value))
        Err(_) => observations.push(@model.Observation::Missing(source_id))
      }
    }
  }
  for operation in script.operations() {
    match operation {
      @model.Operation::Define(id, value) =>
        publish_or_define(store, region, sources, id, value)
      @model.Operation::Set(id, value) =>
        publish_or_define(store, region, sources, id, value)
      @model.Operation::Read(id) => read(id, 0)
      @model.Operation::ReadKey(id, key) => read(id, key)
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
