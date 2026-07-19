///|
/// The oracle deliberately duplicates semantics without engine algorithm
/// helpers. Full recomputation is slower but avoids correlated bugs in routing,
/// consolidation, affected-origin selection, and worker feedback.
priv struct Oracle {
  mut source : @hashmap.HashMap[Edge, Int]
  mut reachable : @hashset.HashSet[Reach]
  mut next_epoch : Int
}

///|
/// Starting at epoch zero mirrors protocol state without importing lifecycle
/// reducer logic that the oracle is meant to check independently.
fn Oracle::Oracle() -> Oracle {
  {
    source: @hashmap.HashMap([]),
    reachable: @hashset.HashSet([]),
    next_epoch: 0,
  }
}

///|
/// Consolidation is duplicated intentionally; sharing this tempting helper
/// would make engine/oracle agreement unable to detect its bugs.
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
/// BFS from every source trades performance for a ground truth that does not
/// depend on affected-origin rebuilding or feedback scheduling.
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
/// Only the output representation is shared conceptually with the engine;
/// canonical form is necessary for comparison, not algorithm reuse.
fn oracle_source(source : @hashmap.HashMap[Edge, Int]) -> Array[WeightedEdge] {
  let result : Array[WeightedEdge] = []
  source.each((edge, weight) => result.push({ edge, weight }))
  result.sort()
  result
}

///|
/// Sorting removes hash order before comparison with scheduled engine output.
fn oracle_reachable(reachable : @hashset.HashSet[Reach]) -> Array[Reach] {
  let result = reachable.to_array()
  result.sort()
  result
}

///|
/// Delta logic is duplicated as part of the oracle contract; sharing the
/// engine helper would conceal publication-delta defects.
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
/// Rejection consumption matches the engine's protocol deliberately: an
/// expected but invalid epoch advances protocol order, whereas an out-of-
/// sequence request does not. Source and closure change only after independent
/// validation and recomputation.
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
