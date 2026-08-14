///|
fn normalize_read_error(
  scenario : @model.Scenario,
  source_id : Int,
  error : @incr_next.ReadError,
) -> @model.Observation {
  match (scenario, error) {
    (@model.Scenario::FailureRecovery, @incr_next.ReadError::ClosedRegion(..)) =>
      @model.Observation::Error(@model.ScenarioError::StructuralFailure(1))
    _ => @model.Observation::Missing(source_id)
  }
}

///|
priv struct StructuralSetup {
  other_region : @incr_next.Region
  views : Map[Int, @incr_next.View[Int]]
}

///|
priv struct ReaderSetup {
  read : (Int, Int) -> Result[Int, @incr_next.ReadError]
  domain_views : Map[Int, @incr_next.View[Result[Int, Int]]]
  structural : StructuralSetup?
}

///|
fn make_reader(
  store : @incr_next.Store,
  region : @incr_next.Region,
  source_views : Map[Int, @incr_next.View[Int]],
  operations : Array[@model.Operation],
  scenario : @model.Scenario,
  computes : Ref[Int],
) -> ReaderSetup {
  let read : (Int, Int) -> Result[Int, @incr_next.ReadError] = match scenario {
    @model.Scenario::Source =>
      (source_id, _key) => store.read(source_views[source_id])
    @model.Scenario::UnitQuery => {
      let source_view = source_views[0]
      let query = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          ctx.read(source_view)
        })
        .unwrap()
      let view = query.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::KeyedQuery => {
      let query = region
        .query((ctx, key : (Int, Int)) => {
          computes.val = computes.val + 1
          match ctx.read(source_views[key.0]) {
            Ok(value) => Ok(value + key.1)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let keyed_views : Map[(Int, Int), @incr_next.View[Int]] = Map([])
      for operation in operations {
        match operation {
          @model.Operation::ReadKey(source_id, key) =>
            keyed_views[(source_id, key)] = query.at((source_id, key))
          _ => ()
        }
      }
      (source_id, key) => store.read(keyed_views[(source_id, key)])
    }
    @model.Scenario::Chain => {
      let source_view = source_views[0]
      let first = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          ctx.read(source_view)
        })
        .unwrap()
      let first_view = first.at(())
      let second = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.read(first_view) {
            Ok(value) => Ok(value + 1)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let view = second.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::UnrelatedPublication
    | @model.Scenario::SelectedPublication => {
      let source_view = source_views[0]
      let query = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          ctx.read(source_view)
        })
        .unwrap()
      let view = query.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::Diamond => {
      let source_view = source_views[0]
      let shared = region
        .query((ctx, _key : (Int, Int)) => {
          computes.val = computes.val + 1
          ctx.read(source_view)
        })
        .unwrap()
      let shared_view = shared.at((0, 0))
      let left = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.read(shared_view) {
            Ok(value) => Ok(value + 1)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let left_view = left.at(())
      let right = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.read(shared_view) {
            Ok(value) => Ok(value + 2)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let right_view = right.at(())
      let root = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match (ctx.read(left_view), ctx.read(right_view)) {
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
      let source_view = source_views[0]
      let branch_view = source_views[1]
      let query = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.read(branch_view) {
            Ok(flag) => if flag == 0 { ctx.read(source_view) } else { Ok(flag) }
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let view = query.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::FailureRecovery => {
      let source_view = source_views[0]
      let broken_region = store.region().unwrap()
      let broken_query = broken_region
        .query((_ctx, _unit : Unit) => Ok(99))
        .unwrap()
      let broken_view = broken_query.at(())
      // Keep the structural fixture outside the logical source set. The view
      // retains its closed-region behavior for the later stale read.
      ignore(broken_region.close())
      let query = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.read(source_view) {
            Ok(value) if value == 1 => ctx.read(broken_view)
            Ok(value) => Ok(value)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let view = query.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::RootSnapshot => {
      let source_view = source_views[0]
      let query = region
        .query((ctx, _unit : Unit) => {
          computes.val = computes.val + 1
          match ctx.revision() {
            Ok(_) => ctx.read(source_view)
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let view = query.at(())
      (_source_id, _key) => store.read(view)
    }
    @model.Scenario::DomainFailure | @model.Scenario::StructuralError =>
      (source_id, _key) => store.read(source_views[source_id])
  }
  let domain_views : Map[Int, @incr_next.View[Result[Int, Int]]] = Map([])
  if scenario == @model.Scenario::DomainFailure {
    let query = region
      .query((_ctx, code : Int) => {
        computes.val = computes.val + 1
        let domain_value : Result[Int, Int] = Err(code)
        Ok(domain_value)
      })
      .unwrap()
    for operation in operations {
      match operation {
        @model.Operation::DomainFailure(code) =>
          domain_views[code] = query.at(code)
        _ => ()
      }
    }
  }
  let structural = match scenario {
    @model.Scenario::StructuralError => {
      let other = @incr_next.Store::Store()
      let other_region = other.region().unwrap()
      let foreign = other_region.query((_ctx, code : Int) => Ok(code)).unwrap()
      let foreign_views : Map[Int, @incr_next.View[Int]] = Map([])
      for operation in operations {
        match operation {
          @model.Operation::StructuralFailure(code) =>
            foreign_views[code] = foreign.at(code)
          _ => ()
        }
      }
      let local_query = region
        .query((ctx, code : Int) => {
          computes.val = computes.val + 1
          ctx.read(foreign_views[code])
        })
        .unwrap()
      let local_views : Map[Int, @incr_next.View[Int]] = Map([])
      for operation in operations {
        match operation {
          @model.Operation::StructuralFailure(code) =>
            local_views[code] = local_query.at(code)
          _ => ()
        }
      }
      Some(StructuralSetup::{ other_region, views: local_views })
    }
    _ => None
  }
  { read, domain_views, structural }
}

///|
fn publish_existing(
  store : @incr_next.Store,
  sources : Map[Int, @incr_next.Source[Int]],
  source_id : Int,
  value : Int,
) -> Unit {
  let source = match sources.get(source_id) {
    Some(source) => source
    None => abort("Set target is not an initial source: \{source_id}")
  }
  match store.transaction(tx => tx.set(source, value)) {
    Ok(_) => ()
    Err(_) => abort("valid testkit Set failed unexpectedly")
  }
}

///|
/// Runs the K1.2 kernel through the same two-phase logical script.
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] {
  let store = @incr_next.Store::Store()
  let region = store.region().unwrap()
  let initial_sources = script.initial_sources()
  let sources : Map[Int, @incr_next.Source[Int]] = Map(
    initial_sources.map(init => (init.id, region.source(init.value).unwrap())),
  )
  let source_views : Map[Int, @incr_next.View[Int]] = Map(
    initial_sources.map(init => (init.id, sources[init.id].view())),
  )
  let operations = script.operations()
  let observations : Array[@model.Observation] = []
  let computes = Ref(0)
  let setup = make_reader(
    store,
    region,
    source_views,
    operations,
    script.scenario_tag(),
    computes,
  )
  let read = (source_id : Int, key : Int) => {
    if !sources.contains(source_id) {
      observations.push(@model.Observation::Missing(source_id))
    } else {
      match (setup.read)(source_id, key) {
        Ok(value) => observations.push(@model.Observation::Value(value))
        Err(error) =>
          observations.push(
            normalize_read_error(script.scenario_tag(), source_id, error),
          )
      }
    }
  }
  for operation in operations {
    match operation {
      @model.Operation::Set(id, value) =>
        publish_existing(store, sources, id, value)
      @model.Operation::Read(id) => read(id, 0)
      @model.Operation::ReadKey(id, key) => read(id, key)
      @model.Operation::DomainFailure(code) =>
        match store.read(setup.domain_views[code]) {
          Ok(Err(domain_code)) =>
            observations.push(
              @model.Observation::Error(
                @model.ScenarioError::DomainFailure(domain_code),
              ),
            )
          _ => observations.push(@model.Observation::Missing(code))
        }
      @model.Operation::StructuralFailure(code) => {
        let structural = match setup.structural {
          Some(structural) => structural
          None => abort("StructuralFailure runner was not prepared")
        }
        match store.read(structural.views[code]) {
          Err(@incr_next.ReadError::CrossStore(..)) =>
            observations.push(
              @model.Observation::Error(
                @model.ScenarioError::StructuralFailure(code),
              ),
            )
          _ => observations.push(@model.Observation::Missing(code))
        }
      }
    }
  }
  match setup.structural {
    Some(structural) => ignore(structural.other_region.close())
    None => ()
  }
  observations.push(@model.Observation::Counter(computes.val))
  ignore(region.close())
  observations
}
