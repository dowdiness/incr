///|
fn normalize_read_error(
  scenario : @model.Scenario,
  source_id : Int,
  error : @incr_query.ReadError,
) -> @model.Observation {
  match (scenario, error) {
    (@model.Scenario::FailureRecovery, @incr_query.ReadError::ClosedRegion(_)) =>
      @model.Observation::Error(@model.ScenarioError::StructuralFailure(1))
    _ => @model.Observation::Missing(source_id)
  }
}

///|
priv struct StructuralSetup {
  other_region : @incr_query.Region
  views : Map[Int, @incr_query.View[Int]]
}

///|
priv struct ReaderSetup {
  read : (Int, Int) -> Int raise @incr_query.ReadError
  query_read : ((Int, Int) -> Int raise @incr_query.ReadError)?
  domain_views : Map[Int, @incr_query.View[Result[Int, Int]]]
  structural : StructuralSetup?
}

///|
fn normalize_query_error(
  query_id : @model.QueryId,
  error : @incr_query.ReadError,
) -> @model.Observation {
  match error {
    @incr_query.ReadError::Cycle(_diagnostic) =>
      @model.Observation::Error(@model.ScenarioError::Cycle)
    _ => @model.Observation::Missing(query_id)
  }
}

///|
fn cycle_reader(
  store : @incr_query.Store,
  region : @incr_query.Region,
  source_views : Map[Int, @incr_query.View[Int]],
  scenario : @model.Scenario,
  computes : Ref[Int],
) -> ((Int, Int) -> Int raise @incr_query.ReadError) raise {
  match scenario {
    @model.Scenario::DirectCycle => {
      let self_view : Ref[@incr_query.View[Int]?] = Ref(None)
      let query = region.query((ctx, _key : Int) => {
        computes.val = computes.val + 1
        ctx.get(self_view.val.unwrap())
      })
      let view = query.view(0)
      self_view.val = Some(view)
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([((0, 0), view)])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    @model.Scenario::MutualCycle => {
      let a_view : Ref[@incr_query.View[Int]?] = Ref(None)
      let b_view : Ref[@incr_query.View[Int]?] = Ref(None)
      let a = region.query((ctx, _key : Int) => {
        computes.val = computes.val + 1
        ctx.get(b_view.val.unwrap())
      })
      let b = region.query((ctx, _key : Int) => {
        computes.val = computes.val + 1
        ctx.get(a_view.val.unwrap())
      })
      let a_at_zero = a.view(0)
      let b_at_zero = b.view(0)
      a_view.val = Some(a_at_zero)
      b_view.val = Some(b_at_zero)
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([
        ((0, 0), a_at_zero),
        ((1, 0), b_at_zero),
      ])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    @model.Scenario::SameQueryKeyCycle => {
      let views_ref : Ref[Map[Int, @incr_query.View[Int]]] = Ref(Map([]))
      let query = region.query((ctx, key : Int) => {
        computes.val = computes.val + 1
        let next_key = if key == 0 { 1 } else { 0 }
        ctx.get(views_ref.val[next_key])
      })
      let at_zero = query.view(0)
      let at_one = query.view(1)
      views_ref.val = Map([(0, at_zero), (1, at_one)])
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([
        ((0, 0), at_zero),
        ((0, 1), at_one),
      ])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    @model.Scenario::FiniteRecursion => {
      let views_ref : Ref[Map[Int, @incr_query.View[Int]]] = Ref(Map([]))
      let query = region.query((ctx, key : Int) => {
        computes.val = computes.val + 1
        if key == 0 {
          0
        } else {
          ctx.get(views_ref.val[key - 1])
        }
      })
      let at_zero = query.view(0)
      let at_one = query.view(1)
      let at_two = query.view(2)
      let at_three = query.view(3)
      views_ref.val = Map([
        (0, at_zero),
        (1, at_one),
        (2, at_two),
        (3, at_three),
      ])
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([
        ((0, 0), at_zero),
        ((0, 1), at_one),
        ((0, 2), at_two),
        ((0, 3), at_three),
      ])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    @model.Scenario::UnequalKeyCrossQuery => {
      let a_views : Ref[Map[Int, @incr_query.View[Int]]] = Ref(Map([]))
      let b_views : Ref[Map[Int, @incr_query.View[Int]]] = Ref(Map([]))
      let a = region.query((ctx, key : Int) => {
        computes.val = computes.val + 1
        if key == 0 {
          ctx.get(b_views.val[0])
        } else {
          key
        }
      })
      let b = region.query((ctx, key : Int) => {
        computes.val = computes.val + 1
        if key == 0 {
          ctx.get(a_views.val[1])
        } else {
          key
        }
      })
      let a_at_zero = a.view(0)
      let a_at_one = a.view(1)
      let b_at_zero = b.view(0)
      let b_at_one = b.view(1)
      a_views.val = Map([(0, a_at_zero), (1, a_at_one)])
      b_views.val = Map([(0, b_at_zero), (1, b_at_one)])
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([
        ((0, 0), a_at_zero),
        ((0, 1), a_at_one),
        ((1, 0), b_at_zero),
        ((1, 1), b_at_one),
      ])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    @model.Scenario::DeadCycleBranch => {
      let self_view : Ref[@incr_query.View[Int]?] = Ref(None)
      let source_view = source_views[0]
      let query = region.query((ctx, _key : Int) => {
        computes.val = computes.val + 1
        let value = ctx.get(source_view)
        if value == 0 {
          value
        } else {
          ctx.get(self_view.val.unwrap())
        }
      })
      let view = query.view(0)
      self_view.val = Some(view)
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([((0, 0), view)])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    @model.Scenario::CycleRecovery => {
      let self_view : Ref[@incr_query.View[Int]?] = Ref(None)
      let source_view = source_views[0]
      let query = region.query((ctx, _key : Int) => {
        computes.val = computes.val + 1
        let value = ctx.get(source_view)
        if value == 1 {
          ctx.get(self_view.val.unwrap())
        } else {
          value
        }
      })
      let view = query.view(0)
      self_view.val = Some(view)
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([((0, 0), view)])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    @model.Scenario::OldTraceCycle => {
      let a_views : Ref[Map[Int, @incr_query.View[Int]]] = Ref(Map([]))
      let b_views : Ref[Map[Int, @incr_query.View[Int]]] = Ref(Map([]))
      let source_view = source_views[0]
      let a = region.query((ctx, _key : Int) => {
        computes.val = computes.val + 1
        let value = ctx.get(source_view)
        if value == 0 {
          0
        } else {
          ctx.get(b_views.val[0])
        }
      })
      let b = region.query((ctx, _key : Int) => {
        computes.val = computes.val + 1
        let value = ctx.get(source_view)
        if value == 0 {
          ctx.get(a_views.val[0])
        } else {
          value
        }
      })
      let a_at_zero = a.view(0)
      let b_at_zero = b.view(0)
      a_views.val = Map([(0, a_at_zero)])
      b_views.val = Map([(0, b_at_zero)])
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([
        ((0, 0), a_at_zero),
        ((1, 0), b_at_zero),
      ])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    @model.Scenario::SequentialDuplicateRead => {
      let child_view : Ref[@incr_query.View[Int]?] = Ref(None)
      let parent = region.query((ctx, _key : Int) => {
        computes.val = computes.val + 1
        let left = ctx.get(child_view.val.unwrap())
        let right = ctx.get(child_view.val.unwrap())
        left + right
      })
      let child = region.query((_ctx, _key : Int) => {
        computes.val = computes.val + 1
        0
      })
      let parent_at_zero = parent.view(0)
      let child_at_zero = child.view(0)
      child_view.val = Some(child_at_zero)
      let views : Map[(Int, Int), @incr_query.View[Int]] = Map([
        ((0, 0), parent_at_zero),
        ((1, 0), child_at_zero),
      ])
      (query_id, key) => store.get(views[(query_id, key)])
    }
    _ => (_query_id, _key) => abort("non-cycle query read")
  }
}

///|
fn make_reader(
  store : @incr_query.Store,
  region : @incr_query.Region,
  source_views : Map[Int, @incr_query.View[Int]],
  operations : Array[@model.Operation],
  scenario : @model.Scenario,
  computes : Ref[Int],
) -> ReaderSetup raise {
  let read : (Int, Int) -> Int raise @incr_query.ReadError = match scenario {
    @model.Scenario::Source =>
      (source_id, _key) => store.get(source_views[source_id])
    @model.Scenario::UnitQuery => {
      let source_view = source_views[0]
      let query = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        ctx.get(source_view)
      })
      let view = query.view(())
      (_source_id, _key) => store.get(view)
    }
    @model.Scenario::KeyedQuery => {
      let query = region.query((ctx, key : (Int, Int)) => {
        computes.val = computes.val + 1
        let value = ctx.get(source_views[key.0])
        value + key.1
      })
      let keyed_views : Map[(Int, Int), @incr_query.View[Int]] = Map([])
      for operation in operations {
        match operation {
          @model.Operation::ReadKey(source_id, key) =>
            keyed_views[(source_id, key)] = query.view((source_id, key))
          _ => ()
        }
      }
      (source_id, key) => store.get(keyed_views[(source_id, key)])
    }
    @model.Scenario::Chain => {
      let source_view = source_views[0]
      let first = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        ctx.get(source_view)
      })
      let first_view = first.view(())
      let second = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        let value = ctx.get(first_view)
        value + 1
      })
      let view = second.view(())
      (_source_id, _key) => store.get(view)
    }
    @model.Scenario::UnrelatedPublication
    | @model.Scenario::SelectedPublication => {
      let source_view = source_views[0]
      let query = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        ctx.get(source_view)
      })
      let view = query.view(())
      (_source_id, _key) => store.get(view)
    }
    @model.Scenario::Diamond => {
      let source_view = source_views[0]
      let shared = region.query((ctx, _key : (Int, Int)) => {
        computes.val = computes.val + 1
        ctx.get(source_view)
      })
      let shared_view = shared.view((0, 0))
      let left = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        let value = ctx.get(shared_view)
        value + 1
      })
      let left_view = left.view(())
      let right = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        let value = ctx.get(shared_view)
        value + 2
      })
      let right_view = right.view(())
      let root = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        let left = ctx.get(left_view)
        let right = ctx.get(right_view)
        left + right
      })
      let view = root.view(())
      (_source_id, _key) => store.get(view)
    }
    @model.Scenario::DynamicBranch => {
      let source_view = source_views[0]
      let branch_view = source_views[1]
      let query = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        let flag = ctx.get(branch_view)
        if flag == 0 {
          ctx.get(source_view)
        } else {
          flag
        }
      })
      let view = query.view(())
      (_source_id, _key) => store.get(view)
    }
    @model.Scenario::FailureRecovery => {
      let source_view = source_views[0]
      let broken_region = store.region()
      let broken_query = broken_region.query((_ctx, _unit : Unit) => 99)
      let broken_view = broken_query.view(())
      // Keep the structural fixture outside the logical source set. The view
      // retains its closed-region behavior for the later stale read.
      ignore(broken_region.close())
      let query = region.query((ctx, _unit : Unit) => {
        computes.val = computes.val + 1
        let value = ctx.get(source_view)
        if value == 1 {
          ctx.get(broken_view)
        } else {
          value
        }
      })
      let view = query.view(())
      (_source_id, _key) => store.get(view)
    }
    @model.Scenario::DomainFailure | @model.Scenario::StructuralError =>
      (source_id, _key) => store.get(source_views[source_id])
    @model.Scenario::DirectCycle
    | @model.Scenario::MutualCycle
    | @model.Scenario::SameQueryKeyCycle
    | @model.Scenario::FiniteRecursion
    | @model.Scenario::UnequalKeyCrossQuery
    | @model.Scenario::DeadCycleBranch
    | @model.Scenario::CycleRecovery
    | @model.Scenario::OldTraceCycle
    | @model.Scenario::SequentialDuplicateRead =>
      (_source_id, _key) => abort("cycle scenario uses query reads")
  }
  let query_read : ((Int, Int) -> Int raise @incr_query.ReadError)? = match
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
  let domain_views : Map[Int, @incr_query.View[Result[Int, Int]]] = Map([])
  if scenario == @model.Scenario::DomainFailure {
    let query = region.query((_ctx, code : Int) => {
      computes.val = computes.val + 1
      let domain_value : Result[Int, Int] = Err(code)
      domain_value
    })
    for operation in operations {
      match operation {
        @model.Operation::DomainFailure(code) =>
          domain_views[code] = query.view(code)
        _ => ()
      }
    }
  }
  let structural = match scenario {
    @model.Scenario::StructuralError => {
      let other = @incr_query.Store::Store()
      let other_region = other.region()
      let foreign = other_region.query((_ctx, code : Int) => code)
      let foreign_views : Map[Int, @incr_query.View[Int]] = Map([])
      for operation in operations {
        match operation {
          @model.Operation::StructuralFailure(code) =>
            foreign_views[code] = foreign.view(code)
          _ => ()
        }
      }
      let local_query = region.query((ctx, code : Int) => {
        computes.val = computes.val + 1
        ctx.get(foreign_views[code])
      })
      let local_views : Map[Int, @incr_query.View[Int]] = Map([])
      for operation in operations {
        match operation {
          @model.Operation::StructuralFailure(code) =>
            local_views[code] = local_query.view(code)
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
  store : @incr_query.Store,
  sources : Map[Int, @incr_query.Source[Int]],
  source_id : Int,
  value : Int,
) -> Unit raise {
  let source = match sources.get(source_id) {
    Some(source) => source
    None => abort("Set target is not an initial source: \{source_id}")
  }
  let _ : Result[Unit, Unit] = store.transaction(tx => {
    tx.set(source, value)
    Ok(())
  })
}

///|
/// Runs the K1.3 kernel through the same two-phase logical script.
pub fn evaluate(script : @model.Script) -> Array[@model.Observation] raise {
  let store = @incr_query.Store::Store()
  let region = store.region()
  let initial_sources = script.initial_sources()
  let sources : Map[Int, @incr_query.Source[Int]] = Map(
    initial_sources.map(init => (init.id, region.source(init.value))),
  )
  let source_views : Map[Int, @incr_query.View[Int]] = Map(
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
      let result : Result[Int, @incr_query.ReadError] = Ok(
        (setup.read)(source_id, key),
      ) catch {
        error => Err(error)
      }
      match result {
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
          Some(query_read) => {
            let result : Result[Int, @incr_query.ReadError] = Ok(
              query_read(query_id, key),
            ) catch {
              error => Err(error)
            }
            match result {
              Ok(value) => observations.push(@model.Observation::Value(value))
              Err(error) =>
                observations.push(normalize_query_error(query_id, error))
            }
          }
          None => observations.push(@model.Observation::Missing(query_id))
        }
      @model.Operation::DomainFailure(code) => {
        let domain_result : Result[Result[Int, Int], @incr_query.ReadError] = Ok(
          store.get(setup.domain_views[code]),
        ) catch {
          error => Err(error)
        }
        match domain_result {
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
        let structural = match setup.structural {
          Some(structural) => structural
          None => abort("StructuralFailure runner was not prepared")
        }
        let structural_result : Result[Int, @incr_query.ReadError] = Ok(
          store.get(structural.views[code]),
        ) catch {
          error => Err(error)
        }
        match structural_result {
          Err(@incr_query.ReadError::CrossStore(_)) =>
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
