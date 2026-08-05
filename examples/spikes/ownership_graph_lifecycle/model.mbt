///|
priv enum NodeId {
  StoreCore
  ViewClosure
  ViewState
  ComputeClosure
  UpstreamState
  MountRecord
  EffectRecord
  StopHandle
  DeferredWrite
  KeyedOwner
  KeyedEntry
  SurvivingGetter
} derive(Eq, Compare, Hash)

///|
priv enum Action {
  MountEffect
  DropView
  DropStore
  DropStop
  InvokeStop
  CloseStore
  QueueWrite
  FlushWrites
  AddKey
  HoldGetter
  RemoveKey
  DropGetter
  AddPassiveBackedge
  RemovePassiveBackedge
  Reset
}

///|
priv struct Edge {
  source : NodeId
  target : NodeId
  label : String
}

///|
priv struct ModelState {
  allocated : @hashset.HashSet[NodeId]
  roots : @hashset.HashSet[NodeId]
  effect_mounted : Bool
  write_queued : Bool
  key_member : Bool
  passive_backedge : Bool
  store_closed : Bool
  last_action : String
  last_reclaimed : Array[NodeId]
}

///|
priv struct Analysis {
  edges : Array[Edge]
  externally_reachable : @hashset.HashSet[NodeId]
  components : Array[Array[NodeId]]
  violations : Array[String]
}

///|
fn node_name(node : NodeId) -> String {
  match node {
    StoreCore => "StoreCore"
    ViewClosure => "View closure"
    ViewState => "ViewState"
    ComputeClosure => "compute closure"
    UpstreamState => "upstream state"
    MountRecord => "mount record"
    EffectRecord => "Effect record"
    StopHandle => "Stop handle"
    DeferredWrite => "deferred write"
    KeyedOwner => "keyed owner"
    KeyedEntry => "keyed entry"
    SurvivingGetter => "surviving getter"
  }
}

///|
fn is_active(node : NodeId) -> Bool {
  match node {
    MountRecord | EffectRecord | DeferredWrite => true
    _ => false
  }
}

///|
fn edge(source : NodeId, target : NodeId, label : String) -> Edge {
  { source, target, label }
}

///|
fn initial_state() -> ModelState {
  {
    allocated: @hashset.HashSet([
      StoreCore,
      ViewClosure,
      ViewState,
      ComputeClosure,
      UpstreamState,
    ]),
    roots: @hashset.HashSet([StoreCore, ViewClosure]),
    effect_mounted: false,
    write_queued: false,
    key_member: false,
    passive_backedge: false,
    store_closed: false,
    last_action: "initial state",
    last_reclaimed: [],
  }
}

///|
fn configured_edges(state : ModelState) -> Array[Edge] {
  let result = [
    edge(ViewClosure, ViewState, "captures"),
    edge(ViewState, ComputeClosure, "owns compute"),
    edge(ViewState, UpstreamState, "cached dependencies"),
    edge(ViewState, StoreCore, "store reference"),
    edge(ComputeClosure, UpstreamState, "lexical capture"),
  ]
  if state.effect_mounted {
    result.push(edge(StoreCore, MountRecord, "mount table"))
    result.push(edge(MountRecord, EffectRecord, "owns active Effect"))
    result.push(edge(EffectRecord, ViewClosure, "runs getter"))
    result.push(edge(StopHandle, StoreCore, "teardown capability"))
  }
  if state.write_queued {
    result.push(edge(StoreCore, DeferredWrite, "deferred queue"))
    result.push(edge(DeferredWrite, StoreCore, "write capability"))
  }
  if state.allocated.contains(KeyedOwner) {
    result.push(edge(ViewState, KeyedOwner, "owns keyed family"))
  }
  if state.key_member {
    result.push(edge(KeyedOwner, KeyedEntry, "membership"))
  }
  if state.allocated.contains(KeyedEntry) {
    result.push(edge(KeyedEntry, UpstreamState, "entry dependency"))
  }
  if state.allocated.contains(SurvivingGetter) {
    result.push(edge(SurvivingGetter, KeyedEntry, "captures entry"))
  }
  if state.passive_backedge {
    result.push(edge(UpstreamState, ViewState, "adversarial back-edge"))
  }
  result.filter(edge => {
    state.allocated.contains(edge.source) &&
    state.allocated.contains(edge.target)
  })
}

///|
fn rc_collect(state : ModelState) -> ModelState {
  let edges = configured_edges(state)
  let incoming : @hashmap.HashMap[NodeId, Int] = @hashmap.HashMap([])
  state.allocated.each(node => incoming[node] = 0)
  state.roots.each(node => {
    if state.allocated.contains(node) {
      incoming.update_or_default(node, 1, count => count + 1)
    }
  })
  edges.each(link => {
    incoming.update_or_default(link.target, 1, count => count + 1)
  })
  let pending : @queue.Queue[NodeId] = @queue.Queue([])
  incoming.each((node, count) => if count == 0 { pending.push(node) })
  let reclaimed : @hashset.HashSet[NodeId] = @hashset.HashSet([])
  for ;; {
    let node = match pending.pop() {
      None => break
      Some(node) => node
    }
    if reclaimed.add_and_check(node) {
      edges.each(link => {
        if link.source == node && !reclaimed.contains(link.target) {
          let next = incoming.get_or_default(link.target, 0) - 1
          incoming[link.target] = next
          if next == 0 {
            pending.push(link.target)
          }
        }
      })
    }
  }
  let retained = state.allocated.difference(reclaimed)
  let reclaimed_nodes = reclaimed.to_array()
  reclaimed_nodes.sort()
  { ..state, allocated: retained, last_reclaimed: reclaimed_nodes }
}

///|
fn can_use_store(state : ModelState) -> Bool {
  !state.store_closed && state.roots.contains(StoreCore)
}

///|
fn transition(state : ModelState, action : Action) -> ModelState {
  let allocated = state.allocated.copy()
  let roots = state.roots.copy()
  let mut effect_mounted = state.effect_mounted
  let mut write_queued = state.write_queued
  let mut key_member = state.key_member
  let mut passive_backedge = state.passive_backedge
  let mut store_closed = state.store_closed
  let mut last_action = "ignored"
  match action {
    Reset => return initial_state()
    MountEffect =>
      if can_use_store(state) &&
        state.allocated.contains(ViewClosure) &&
        !effect_mounted {
        allocated.add(MountRecord)
        allocated.add(EffectRecord)
        allocated.add(StopHandle)
        roots.add(StopHandle)
        effect_mounted = true
        last_action = "mounted Effect and returned Stop"
      } else {
        last_action = "mount ignored: Store/View unavailable or Effect active"
      }
    DropView => {
      roots.remove(ViewClosure)
      last_action = "dropped external View root"
    }
    DropStore => {
      roots.remove(StoreCore)
      last_action = "dropped external Store root"
    }
    DropStop => {
      roots.remove(StopHandle)
      last_action = "dropped Stop handle without invoking it"
    }
    InvokeStop =>
      if effect_mounted && roots.contains(StopHandle) {
        roots.remove(StopHandle)
        effect_mounted = false
        last_action = "invoked Stop and removed mount record"
      } else {
        last_action = "Stop ignored: no callable Stop handle"
      }
    CloseStore =>
      if can_use_store(state) {
        roots.remove(StopHandle)
        effect_mounted = false
        write_queued = false
        store_closed = true
        last_action = "closed Store, Effects, mounts, and deferred writes"
      } else {
        last_action = "close ignored: Store capability unavailable"
      }
    QueueWrite =>
      if can_use_store(state) && !write_queued {
        allocated.add(DeferredWrite)
        write_queued = true
        last_action = "queued deferred write capturing Store"
      } else {
        last_action = "queue ignored: Store unavailable or write already queued"
      }
    FlushWrites =>
      if can_use_store(state) && write_queued {
        write_queued = false
        last_action = "flushed deferred-write queue"
      } else {
        last_action = "flush ignored: queue or Store capability unavailable"
      }
    AddKey =>
      if state.allocated.contains(ViewState) {
        allocated.add(KeyedOwner)
        allocated.add(KeyedEntry)
        key_member = true
        last_action = "added keyed owner and membership entry"
      } else {
        last_action = "add key ignored: ViewState reclaimed"
      }
    HoldGetter =>
      if state.allocated.contains(KeyedEntry) {
        allocated.add(SurvivingGetter)
        roots.add(SurvivingGetter)
        last_action = "held surviving getter as an external root"
      } else {
        last_action = "getter ignored: keyed entry unavailable"
      }
    RemoveKey => {
      key_member = false
      last_action = "removed key from membership"
    }
    DropGetter => {
      roots.remove(SurvivingGetter)
      last_action = "dropped surviving getter root"
    }
    AddPassiveBackedge =>
      if state.allocated.contains(ViewState) &&
        state.allocated.contains(UpstreamState) {
        passive_backedge = true
        last_action = "injected adversarial passive back-edge"
      } else {
        last_action = "back-edge ignored: passive nodes reclaimed"
      }
    RemovePassiveBackedge => {
      passive_backedge = false
      last_action = "removed adversarial passive back-edge"
    }
  }
  rc_collect({
    allocated,
    roots,
    effect_mounted,
    write_queued,
    key_member,
    passive_backedge,
    store_closed,
    last_action,
    last_reclaimed: [],
  })
}

///|
fn reachable_from(
  start : NodeId,
  nodes : @hashset.HashSet[NodeId],
  edges : ArrayView[Edge],
) -> @hashset.HashSet[NodeId] {
  let visited : @hashset.HashSet[NodeId] = @hashset.HashSet([])
  let pending : @queue.Queue[NodeId] = @queue.Queue([])
  if nodes.contains(start) {
    visited.add(start)
    pending.push(start)
  }
  for ;; {
    let node = match pending.pop() {
      None => break
      Some(node) => node
    }
    for link in edges {
      if link.source == node && visited.add_and_check(link.target) {
        pending.push(link.target)
      }
    }
  }
  visited
}

///|
fn externally_reachable(
  state : ModelState,
  edges : ArrayView[Edge],
) -> @hashset.HashSet[NodeId] {
  let result : @hashset.HashSet[NodeId] = @hashset.HashSet([])
  state.roots.each(root => {
    reachable_from(root, state.allocated, edges).each(node => result.add(node))
  })
  result
}

///|
fn strong_components(
  nodes : @hashset.HashSet[NodeId],
  edges : ArrayView[Edge],
) -> Array[Array[NodeId]] {
  let ordered = nodes.to_array()
  ordered.sort()
  let assigned : @hashset.HashSet[NodeId] = @hashset.HashSet([])
  let result : Array[Array[NodeId]] = []
  for node in ordered {
    if !assigned.contains(node) {
      let forward = reachable_from(node, nodes, edges)
      let component = ordered.filter(other => {
        forward.contains(other) &&
        reachable_from(other, nodes, edges).contains(node)
      })
      component.each(node_in_component => assigned.add(node_in_component))
      result.push(component)
    }
  }
  result
}

///|
fn is_nontrivial(
  component : ArrayView[NodeId],
  edges : ArrayView[Edge],
) -> Bool {
  component.length() > 1 ||
  component.any(node => {
    edges.any(link => link.source == node && link.target == node)
  })
}

///|
fn component_has_breaker(
  component : ArrayView[NodeId],
  state : ModelState,
) -> Bool {
  let needs_effect_breaker = component.contains(EffectRecord)
  let needs_queue_breaker = component.contains(DeferredWrite)
  let store_callable = can_use_store(state)
  let effect_breaker = !needs_effect_breaker ||
    state.roots.contains(StopHandle) ||
    store_callable
  let queue_breaker = !needs_queue_breaker || store_callable
  effect_breaker && queue_breaker
}

///|
fn node_list(nodes : Array[NodeId]) -> String {
  if nodes.is_empty() {
    "(none)"
  } else {
    nodes.iter().map(node_name).join(", ")
  }
}

///|
fn analyze(state : ModelState) -> Analysis {
  let edges = configured_edges(state)
  let reachable = externally_reachable(state, edges)
  let components = strong_components(state.allocated, edges)
  let violations : Array[String] = []
  for component in components {
    if is_nontrivial(component, edges) {
      if !component.any(is_active) {
        violations.push("PASSIVE-ONLY SCC: \{node_list(component)}")
      } else if !component_has_breaker(component, state) {
        violations.push(
          "ACTIVE SCC WITHOUT CALLABLE BREAKER: \{node_list(component)}",
        )
      }
    }
  }
  { edges, externally_reachable: reachable, components, violations }
}

///|
fn bool_word(value : Bool) -> String {
  if value {
    "yes"
  } else {
    "no"
  }
}

///|
fn sorted_nodes(nodes : @hashset.HashSet[NodeId]) -> Array[NodeId] {
  let result = nodes.to_array()
  result.sort()
  result
}

///|
fn append_line(buffer : StringBuilder, text : String) -> Unit {
  buffer.write_string(text)
  buffer.write_char('\n')
}

///|
fn render_frame(state : ModelState) -> String {
  let analysis = analyze(state)
  let retained = sorted_nodes(state.allocated)
  let roots = sorted_nodes(state.roots)
  let detached_retained = state.allocated.difference(
    analysis.externally_reachable,
  )
  let nontrivial = analysis.components.filter(component => {
    is_nontrivial(component, analysis.edges)
  })
  let buffer = StringBuilder()
  buffer.write_string("\u001b[2J\u001b[H")
  append_line(buffer, "\u001b[1mOwnership graph lifecycle prototype\u001b[0m")
  append_line(
    buffer, "\u001b[2mCounterexample finder for incr #451; not an RC proof.\u001b[0m",
  )
  append_line(buffer, "")
  append_line(buffer, "\u001b[1mLast transition\u001b[0m  \{state.last_action}")
  append_line(buffer, "")
  append_line(buffer, "\u001b[1mState\u001b[0m")
  append_line(buffer, "  effect mounted:  \{bool_word(state.effect_mounted)}")
  append_line(buffer, "  deferred write:  \{bool_word(state.write_queued)}")
  append_line(buffer, "  keyed membership: \{bool_word(state.key_member)}")
  append_line(
    buffer,
    "  passive back-edge: \{bool_word(state.passive_backedge)}",
  )
  append_line(buffer, "  Store closed:     \{bool_word(state.store_closed)}")
  append_line(buffer, "  external roots:   \{node_list(roots)}")
  append_line(buffer, "  RC-retained:      \{node_list(retained)}")
  append_line(
    buffer,
    "  unreachable retained: \{node_list(sorted_nodes(detached_retained))}",
  )
  append_line(
    buffer,
    "  reclaimed last step:  \{node_list(state.last_reclaimed)}",
  )
  append_line(buffer, "")
  append_line(buffer, "\u001b[1mStrong edges\u001b[0m")
  if analysis.edges.is_empty() {
    append_line(buffer, "  (none)")
  } else {
    for link in analysis.edges {
      append_line(
        buffer,
        "  \{node_name(link.source)} -> \{node_name(link.target)}  [\{link.label}]",
      )
    }
  }
  append_line(buffer, "")
  append_line(buffer, "\u001b[1mNontrivial SCCs\u001b[0m")
  if nontrivial.is_empty() {
    append_line(buffer, "  (none)")
  } else {
    nontrivial.each(component => {
      append_line(buffer, "  \{node_list(component)}")
    })
  }
  append_line(buffer, "")
  if analysis.violations.is_empty() {
    append_line(buffer, "\u001b[32mModeled invariant: valid\u001b[0m")
  } else {
    append_line(buffer, "\u001b[31mModeled invariant: COUNTEREXAMPLE\u001b[0m")
    analysis.violations.each(message => append_line(buffer, "  \{message}"))
  }
  append_line(buffer, "")
  append_line(buffer, "\u001b[1mCommands\u001b[0m")
  append_line(
    buffer, "  m mount Effect    d drop View root    r drop Store root",
  )
  append_line(buffer, "  x drop Stop       s invoke Stop       c close Store")
  append_line(
    buffer, "  w queue write     f flush writes      k add keyed entry",
  )
  append_line(buffer, "  g hold getter     u remove key        h drop getter")
  append_line(
    buffer, "  b add back-edge   n remove back-edge  z reset    q quit",
  )
  append_line(buffer, "")
  append_line(buffer, "Enter one command and press Return:")
  buffer.to_string()
}

///|
fn apply_command(state : ModelState, command : StringView) -> ModelState {
  let action = match command {
    "m" => Some(MountEffect)
    "d" => Some(DropView)
    "r" => Some(DropStore)
    "x" => Some(DropStop)
    "s" => Some(InvokeStop)
    "c" => Some(CloseStore)
    "w" => Some(QueueWrite)
    "f" => Some(FlushWrites)
    "k" => Some(AddKey)
    "g" => Some(HoldGetter)
    "u" => Some(RemoveKey)
    "h" => Some(DropGetter)
    "b" => Some(AddPassiveBackedge)
    "n" => Some(RemovePassiveBackedge)
    "z" => Some(Reset)
    _ => None
  }
  match action {
    Some(action) => transition(state, action)
    None =>
      {
        ..state,
        last_action: "unknown command: \{command.to_owned()}",
        last_reclaimed: [],
      }
  }
}
