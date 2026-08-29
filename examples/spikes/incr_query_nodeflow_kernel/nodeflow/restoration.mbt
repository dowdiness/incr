///|
fn restoration_publication_error(
  error : GraphPublicationError,
) -> GraphRestorationError {
  match error {
    GraphPublicationError::RegionClosed => GraphRestorationError::RegionClosed
    GraphPublicationError::RegionMutationDuringEvaluation =>
      GraphRestorationError::RegionMutationDuringEvaluation
    GraphPublicationError::RegionMutationDuringTransaction =>
      GraphRestorationError::RegionMutationDuringTransaction
    GraphPublicationError::ReadCrossStore =>
      GraphRestorationError::ReadCrossStore
    GraphPublicationError::ReadClosedRegion =>
      GraphRestorationError::ReadClosedRegion
    GraphPublicationError::ReadExpiredContext =>
      GraphRestorationError::ReadExpiredContext
    GraphPublicationError::ReadReentrantRoot =>
      GraphRestorationError::ReadReentrantRoot
    GraphPublicationError::ReadDuringTransaction =>
      GraphRestorationError::ReadDuringTransaction
    GraphPublicationError::ClosedNodeflow =>
      GraphRestorationError::ReadClosedRegion
  }
}

///|
fn close_restoration_nodes(
  nodes : Map[Int, RuntimeNode],
) -> Unit raise GraphRestorationError {
  let entries = nodes.to_array()
  entries.sort_by((a, b) => a.0.compare(b.0))
  for _, entry in entries {
    entry.1.close_runtime() catch {
      GraphCloseError::RegionClosed => raise GraphRestorationError::RegionClosed
      GraphCloseError::RegionMutationDuringEvaluation =>
        raise GraphRestorationError::RegionMutationDuringEvaluation
      GraphCloseError::RegionMutationDuringTransaction =>
        raise GraphRestorationError::RegionMutationDuringTransaction
    }
  }
}

///|
fn validate_document(
  document : GraphDocument,
) -> Result[Unit, GraphRestorationRejection] {
  let wire = document.wire
  if wire.version != 1 {
    return Err(UnsupportedVersion)
  }
  if wire.graph < 0 {
    return Err(InvalidGraphIdentity)
  }
  if wire.next_node < 0 {
    return Err(InvalidFrontier)
  }
  let ids : Set[Int] = Set([])
  for node in wire.nodes {
    if node.id < 0 || node.id >= wire.next_node {
      return Err(NodeBeyondFrontier)
    }
    if ids.contains(node.id) {
      return Err(DuplicateNode)
    }
    ids.add(node.id)
  }
  for node in wire.nodes {
    let inputs = node_input_count(node.descriptor)
    let targets : Set[Int] = Set([])
    for entry in node.bindings {
      let target = entry.0
      let binding = entry.1
      if target < 0 || target >= inputs {
        return Err(InvalidDescriptor)
      }
      let target_schema = descriptor_port_schema(node.descriptor, target).unwrap()
      if targets.contains(target) {
        return Err(DuplicateBindingTarget)
      }
      targets.add(target)
      match binding {
        BindingTarget::Unbound => ()
        BindingTarget::Bound(provider) => {
          if provider.graph != wire.graph {
            return Err(MissingEndpoint)
          }
          let mut provider_node : DocumentNode? = None
          for candidate in wire.nodes {
            if candidate.id == provider.node {
              provider_node = Some(candidate)
            }
          }
          match provider_node {
            None => return Err(MissingEndpoint)
            Some(provider_node) => {
              let provider_schema = match
                descriptor_port_schema(provider_node.descriptor, provider.port) {
                None => return Err(MissingEndpoint)
                Some(schema) => schema
              }
              if !(provider_schema.direction is PortDirection::Output) {
                return Err(WrongDirection)
              }
              if target_schema.value_type != provider_schema.value_type {
                return Err(WrongType)
              }
            }
          }
        }
      }
    }
  }
  Ok(())
}

///|
/// Restores a fresh execution domain from semantic document data.
pub fn Nodeflow::restore(
  document : GraphDocument,
  demand : ObservationDemand,
) -> Result[GraphRestoration, GraphRestorationRejection] raise GraphRestorationError {
  match validate_document(document) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let wire = document.wire
  let store = @incr_query.Store::Store(
    max_active_queries=NODEFLOW_MAX_ACTIVE_QUERIES,
  )
  let nodes : Map[Int, RuntimeNode] = Map([])
  let outputs : Map[PortReference, RuntimeOutput] = Map([])
  let ordered = wire.nodes.copy()
  ordered.sort_by((a, b) => a.id.compare(b.id))
  for node in ordered {
    let reference : NodeReference = { graph: wire.graph, node: node.id }
    let runtime = make_runtime_node(store, reference, node.descriptor) catch {
      error => {
        close_restoration_nodes(nodes)
        raise restoration_publication_error(error)
      }
    }
    let output = runtime_output(runtime)
    nodes[node.id] = runtime
    let (_, output_references) = descriptor_port_references(
      wire.graph,
      node.id,
      node.descriptor,
    )
    for output_reference in output_references {
      outputs[output_reference] = output
    }
  }
  let runtime = {
    store,
    nodes,
    outputs,
    lifecycle: Ref(RuntimeLifecycle::Open),
  }
  let restored = {
    state: { graph: wire.graph, next_node: wire.next_node, nodes: Map([]) },
    runtime,
  }
  let result : Result[Unit, Unit] = store.transaction(tx => {
    for node in ordered {
      let bindings = node.bindings.copy()
      bindings.sort_by((a, b) => a.0.compare(b.0))
      for entry in bindings {
        let target = entry.0
        let binding = entry.1
        let runtime_node = nodes.get(node.id).unwrap()
        let (_, value) = runtime_node
          .runtime_binding(target, binding, outputs)
          .unwrap()
        match runtime_node {
          RuntimeNode::Add(_, left, right, _, _)
          | RuntimeNode::Multiply(_, left, right, _, _)
          | RuntimeNode::SafeDivide(_, left, right, _, _) =>
            tx.set(if target == 0 { left } else { right }, value)
          RuntimeNode::Display(_, input, _, _, _) => tx.set(input, value)
          RuntimeNode::OptionalOffset(_, _, required, optional, _, _) =>
            tx.set(if target == 0 { required } else { optional }, value)
          _ => ()
        }
      }
    }
    Ok(())
  }) catch {
    error => {
      close_restoration_nodes(nodes)
      raise match error {
        @incr_query.TransactionError::CrossStore(_) =>
          GraphRestorationError::ReadCrossStore
        @incr_query.TransactionError::ClosedRegion(_) =>
          GraphRestorationError::RegionClosed
        @incr_query.TransactionError::ExpiredTransaction(_) =>
          GraphRestorationError::ReadExpiredContext
        @incr_query.TransactionError::TransactionDuringEvaluation(_) =>
          GraphRestorationError::RegionMutationDuringEvaluation
        @incr_query.TransactionError::NestedTransaction(_) =>
          GraphRestorationError::RegionMutationDuringTransaction
      }
    }
  }
  ignore(result)
  let semantic_nodes : Map[Int, NodeState] = Map([])
  for node in ordered {
    let bindings : Map[PortReference, BindingTarget] = Map([])
    for entry in node.bindings {
      let target = entry.0
      let binding = entry.1
      bindings[{ graph: wire.graph, node: node.id, port: target }] = binding
    }
    semantic_nodes[node.id] = { descriptor: node.descriptor, bindings }
  }
  restored.state = {
    graph: wire.graph,
    next_node: wire.next_node,
    nodes: semantic_nodes,
  }
  let snapshot = match restored.snapshot_core(demand) {
    Ok(value) => value
    Err(error) => {
      close_restoration_nodes(nodes)
      raise restoration_publication_error(map_publication_read_failure(error))
    }
  }
  reserve_graph_id(wire.graph)
  Ok(GraphRestoration::{ graph: restored, snapshot })
}
