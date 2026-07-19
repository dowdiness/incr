///|
priv struct Oracle {
  mut source : @hashmap.HashMap[Edge, Int]
  mut reachable : @hashset.HashSet[Reach]
  mut next_epoch : Int
}

///|
fn Oracle::Oracle() -> Oracle {
  {
    source: @hashmap.HashMap([]),
    reachable: @hashset.HashSet([]),
    next_epoch: 0,
  }
}

///|
fn oracle_consolidate(updates : ArrayView[SourceUpdate]) -> Array[SourceUpdate] {
  let sums : @hashmap.HashMap[Edge, Int] = @hashmap.HashMap([])
  for update in updates {
    sums.update_or_default(update.edge, update.diff, old => old + update.diff)
  }
  let result : Array[SourceUpdate] = []
  sums.each((edge, diff) => if diff != 0 { result.push({ edge, diff }) })
  result.sort()
  result
}

///|
fn oracle_recompute(
  source : @hashmap.HashMap[Edge, Int],
) -> @hashset.HashSet[Reach] {
  let adjacency : @hashmap.HashMap[Int, @hashset.HashSet[Int]] = @hashmap.HashMap([],
  )
  source.each((edge, weight) => {
    if weight > 0 {
      adjacency.get_or_init(edge.from, () => @hashset.HashSet([])).add(edge.to)
    }
  })
  let origins = adjacency.keys().to_array()
  origins.sort()
  let result : @hashset.HashSet[Reach] = @hashset.HashSet([])
  for origin in origins {
    let visited : @hashset.HashSet[Int] = @hashset.HashSet([])
    let pending : @queue.Queue[Int] = @queue.Queue([])
    match adjacency.get(origin) {
      None => ()
      Some(targets) => {
        let initial = targets.to_array()
        initial.sort()
        initial.each(target => {
          if visited.add_and_check(target) {
            pending.push(target)
          }
        })
      }
    }
    for ;; {
      let target = match pending.pop() {
        None => break
        Some(target) => target
      }
      result.add(Reach::{ origin, target })
      match adjacency.get(target) {
        None => ()
        Some(next_targets) => {
          let next = next_targets.to_array()
          next.sort()
          next.each(next_target => {
            if visited.add_and_check(next_target) {
              pending.push(next_target)
            }
          })
        }
      }
    }
  }
  result
}

///|
fn oracle_source(source : @hashmap.HashMap[Edge, Int]) -> Array[WeightedEdge] {
  let result : Array[WeightedEdge] = []
  source.each((edge, weight) => result.push({ edge, weight }))
  result.sort()
  result
}

///|
fn oracle_reachable(reachable : @hashset.HashSet[Reach]) -> Array[Reach] {
  let result = reachable.to_array()
  result.sort()
  result
}

///|
fn oracle_delta(
  previous : @hashset.HashSet[Reach],
  next : @hashset.HashSet[Reach],
) -> Array[ReachUpdate] {
  let result : Array[ReachUpdate] = []
  previous.each(reach => {
    if !next.contains(reach) {
      result.push({ reach, diff: -1 })
    }
  })
  next.each(reach => {
    if !previous.contains(reach) {
      result.push({ reach, diff: 1 })
    }
  })
  result.sort()
  result
}

///|
fn Oracle::apply(
  self : Oracle,
  epoch_value : Int,
  updates : ArrayView[SourceUpdate],
) -> Result[Publication, ProtocolError] {
  if epoch_value != self.next_epoch {
    return Err(EpochNotExpected(self.next_epoch, epoch_value))
  }
  let consolidated = oracle_consolidate(updates)
  let next_source = self.source.copy()
  for update in consolidated {
    let next_weight = next_source.get(update.edge).unwrap_or(0) + update.diff
    if next_weight < 0 {
      self.next_epoch = epoch_value + 1
      return Err(InvalidSourceMultiplicity(update.edge, next_weight))
    }
    if next_weight == 0 {
      next_source.remove(update.edge)
    } else {
      next_source[update.edge] = next_weight
    }
  }
  let previous = self.reachable
  let next_reachable = oracle_recompute(next_source)
  let publication : Publication = {
    epoch: Epoch(epoch_value),
    source: oracle_source(next_source),
    reachable: oracle_reachable(next_reachable),
    delta: oracle_delta(previous, next_reachable),
  }
  self.source = next_source
  self.reachable = next_reachable
  self.next_epoch = epoch_value + 1
  Ok(copy_publication(publication))
}
