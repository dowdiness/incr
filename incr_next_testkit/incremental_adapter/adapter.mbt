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
  query_read : ((Int, Int) -> Result[Int, @incr_next.ReadError])?
  domain_views : Map[Int, @incr_next.View[Result[Int, Int]]]
  structural : StructuralSetup?
}

///|
fn normalize_cycle_witness(
  witness : @incr_next.CycleWitness,
) -> @model.CycleWitness {
  let logical_ids : Map[Int, Int] = Map([])
  let path : Array[@model.QueryId] = []
  for raw_id in witness.path() {
    let logical_id = match logical_ids.get(raw_id) {
      Some(id) => id
      None => {
        let id = logical_ids.length()
        logical_ids[raw_id] = id
        id
      }
    }
    path.push(logical_id)
  }
  @model.CycleWitness(path)
}

///|
fn normalize_query_error(
  query_id : @model.QueryId,
  error : @incr_next.ReadError,
) -> @model.Observation {
  match error {
    @incr_next.ReadError::Cycle(witness) =>
      @model.Observation::Error(
        @model.ScenarioError::Cycle(normalize_cycle_witness(witness)),
      )
    _ => @model.Observation::Missing(query_id)
  }
}

///|
fn cycle_reader(
  store : @incr_next.Store,
  region : @incr_next.Region,
  source_views : Map[Int, @incr_next.View[Int]],
  scenario : @model.Scenario,
  computes : Ref[Int],
) -> (Int, Int) -> Result[Int, @incr_next.ReadError] {
  match scenario {
    @model.Scenario::DirectCycle => {
      let self_view : Ref[@incr_next.View[Int]?] = Ref(None)
      let query = region
        .query((ctx, _key : Int) => {
          computes.val = computes.val + 1
          ctx.read(self_view.val.unwrap())
        })
        .unwrap()
      let view = query.at(0)
      self_view.val = Some(view)
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([((0, 0), view)])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    @model.Scenario::MutualCycle => {
      let a_view : Ref[@incr_next.View[Int]?] = Ref(None)
      let b_view : Ref[@incr_next.View[Int]?] = Ref(None)
      let a = region
        .query((ctx, _key : Int) => {
          computes.val = computes.val + 1
          ctx.read(b_view.val.unwrap())
        })
        .unwrap()
      let b = region
        .query((ctx, _key : Int) => {
          computes.val = computes.val + 1
          ctx.read(a_view.val.unwrap())
        })
        .unwrap()
      let a_at_zero = a.at(0)
      let b_at_zero = b.at(0)
      a_view.val = Some(a_at_zero)
      b_view.val = Some(b_at_zero)
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([
        ((0, 0), a_at_zero),
        ((1, 0), b_at_zero),
      ])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    @model.Scenario::SameQueryKeyCycle => {
      let views_ref : Ref[Map[Int, @incr_next.View[Int]]] = Ref(Map([]))
      let query = region
        .query((ctx, key : Int) => {
          computes.val = computes.val + 1
          let next_key = if key == 0 { 1 } else { 0 }
          ctx.read(views_ref.val[next_key])
        })
        .unwrap()
      let at_zero = query.at(0)
      let at_one = query.at(1)
      views_ref.val = Map([(0, at_zero), (1, at_one)])
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([
        ((0, 0), at_zero),
        ((0, 1), at_one),
      ])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    @model.Scenario::FiniteRecursion => {
      let views_ref : Ref[Map[Int, @incr_next.View[Int]]] = Ref(Map([]))
      let query = region
        .query((ctx, key : Int) => {
          computes.val = computes.val + 1
          if key == 0 {
            Ok(0)
          } else {
            ctx.read(views_ref.val[key - 1])
          }
        })
        .unwrap()
      let at_zero = query.at(0)
      let at_one = query.at(1)
      let at_two = query.at(2)
      let at_three = query.at(3)
      views_ref.val = Map([
        (0, at_zero),
        (1, at_one),
        (2, at_two),
        (3, at_three),
      ])
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([
        ((0, 0), at_zero),
        ((0, 1), at_one),
        ((0, 2), at_two),
        ((0, 3), at_three),
      ])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    @model.Scenario::UnequalKeyCrossQuery => {
      let a_views : Ref[Map[Int, @incr_next.View[Int]]] = Ref(Map([]))
      let b_views : Ref[Map[Int, @incr_next.View[Int]]] = Ref(Map([]))
      let a = region
        .query((ctx, key : Int) => {
          computes.val = computes.val + 1
          if key == 0 {
            ctx.read(b_views.val[0])
          } else {
            Ok(key)
          }
        })
        .unwrap()
      let b = region
        .query((ctx, key : Int) => {
          computes.val = computes.val + 1
          if key == 0 {
            ctx.read(a_views.val[1])
          } else {
            Ok(key)
          }
        })
        .unwrap()
      let a_at_zero = a.at(0)
      let a_at_one = a.at(1)
      let b_at_zero = b.at(0)
      let b_at_one = b.at(1)
      a_views.val = Map([(0, a_at_zero), (1, a_at_one)])
      b_views.val = Map([(0, b_at_zero), (1, b_at_one)])
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([
        ((0, 0), a_at_zero),
        ((0, 1), a_at_one),
        ((1, 0), b_at_zero),
        ((1, 1), b_at_one),
      ])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    @model.Scenario::DeadCycleBranch => {
      let self_view : Ref[@incr_next.View[Int]?] = Ref(None)
      let source_view = source_views[0]
      let query = region
        .query((ctx, _key : Int) => {
          computes.val = computes.val + 1
          match ctx.read(source_view) {
            Ok(value) =>
              if value == 0 {
                Ok(value)
              } else {
                ctx.read(self_view.val.unwrap())
              }
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let view = query.at(0)
      self_view.val = Some(view)
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([((0, 0), view)])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    @model.Scenario::CycleRecovery => {
      let self_view : Ref[@incr_next.View[Int]?] = Ref(None)
      let source_view = source_views[0]
      let query = region
        .query((ctx, _key : Int) => {
          computes.val = computes.val + 1
          match ctx.read(source_view) {
            Ok(value) =>
              if value == 1 {
                ctx.read(self_view.val.unwrap())
              } else {
                Ok(value)
              }
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let view = query.at(0)
      self_view.val = Some(view)
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([((0, 0), view)])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    @model.Scenario::OldTraceCycle => {
      let a_views : Ref[Map[Int, @incr_next.View[Int]]] = Ref(Map([]))
      let b_views : Ref[Map[Int, @incr_next.View[Int]]] = Ref(Map([]))
      let source_view = source_views[0]
      let a = region
        .query((ctx, _key : Int) => {
          computes.val = computes.val + 1
          match ctx.read(source_view) {
            Ok(value) =>
              if value == 0 {
                Ok(0)
              } else {
                ctx.read(b_views.val[0])
              }
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let b = region
        .query((ctx, _key : Int) => {
          computes.val = computes.val + 1
          match ctx.read(source_view) {
            Ok(value) =>
              if value == 0 {
                ctx.read(a_views.val[0])
              } else {
                Ok(value)
              }
            Err(error) => Err(error)
          }
        })
        .unwrap()
      let a_at_zero = a.at(0)
      let b_at_zero = b.at(0)
      a_views.val = Map([(0, a_at_zero)])
      b_views.val = Map([(0, b_at_zero)])
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([
        ((0, 0), a_at_zero),
        ((1, 0), b_at_zero),
      ])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    @model.Scenario::SequentialDuplicateRead => {
      let child_view : Ref[@incr_next.View[Int]?] = Ref(None)
      let parent = region
        .query((ctx, _key : Int) => {
          computes.val = computes.val + 1
          match
            (
              ctx.read(child_view.val.unwrap()),
              ctx.read(child_view.val.unwrap()),
            ) {
            (Ok(left), Ok(right)) => Ok(left + right)
            (Err(error), _) => Err(error)
            (_, Err(error)) => Err(error)
          }
        })
        .unwrap()
      let child = region
        .query((_ctx, _key : Int) => {
          computes.val = computes.val + 1
          Ok(0)
        })
        .unwrap()
      let parent_at_zero = parent.at(0)
      let child_at_zero = child.at(0)
      child_view.val = Some(child_at_zero)
      let views : Map[(Int, Int), @incr_next.View[Int]] = Map([
        ((0, 0), parent_at_zero),
        ((1, 0), child_at_zero),
      ])
      (query_id, key) => store.read(views[(query_id, key)])
    }
    _ => (_query_id, _key) => Err(@incr_next.ReadError::ExpiredQueryContext)
  }
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
    @model.Scenario::DirectCycle
    | @model.Scenario::MutualCycle
    | @model.Scenario::SameQueryKeyCycle
    | @model.Scenario::FiniteRecursion
    | @model.Scenario::UnequalKeyCrossQuery
    | @model.Scenario::DeadCycleBranch
    | @model.Scenario::CycleRecovery
    | @model.Scenario::OldTraceCycle
    | @model.Scenario::SequentialDuplicateRead =>
      (_source_id, _key) => Err(@incr_next.ReadError::ExpiredQueryContext)
  }
  let query_read : ((Int, Int) -> Result[Int, @incr_next.ReadError])? = match
    scenario {
    @model.Scenario::DirectCycle
    | @model.Scenario::MutualCycle
    | @model.Scenario::SameQueryKeyCycle
    | @model.Scenario::FiniteRecursion
    | @model.Scenario::UnequalKeyCrossQuery
    | @model.Scenario::DeadCycleBranch
    | @model.Scenario::CycleRecovery
    | @model.Scenario::OldTraceCycle
    | @model.Scenario::SequentialDuplicateRead =>
      Some(cycle_reader(store, region, source_views, scenario, computes))
    _ => None
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
  { read, query_read, domain_views, structural }
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
/// Runs the K1.3 kernel through the same two-phase logical script.
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
      @model.Operation::ReadQuery(query_id, key) =>
        match setup.query_read {
          Some(query_read) =>
            match query_read(query_id, key) {
              Ok(value) => observations.push(@model.Observation::Value(value))
              Err(error) =>
                observations.push(normalize_query_error(query_id, error))
            }
          None => observations.push(@model.Observation::Missing(query_id))
        }
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
