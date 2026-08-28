///|
/// Pure semantic node record.
priv struct NodeState {
  descriptor : @application.NodeDescriptor
  bindings : Map[PortReference, BindingTarget]
}

///|
priv struct GraphState {
  graph : Int
  next_node : Int
  nodes : Map[Int, NodeState]
}

///|
priv struct GraphTransition {
  state : GraphState
  added : (NodeReference, Array[PortReference], Array[PortReference])?
  removed : (Array[Int], Array[PortReference])?
}

///|
priv struct PortSchema {
  direction : PortDirection
  value_type : @application.PortValueType
  required : Bool
}

///|
priv struct NodeSchema {
  kind : @application.NodeKind
  ports : Array[PortSchema]
  parameters : Array[@application.PortValueType]
  actions : Int
}

///|
fn descriptor_schema(descriptor : @application.NodeDescriptor) -> NodeSchema {
  let specification = descriptor.specification()
  let ports : Array[PortSchema] = []
  for port in specification.inputs {
    ports.push({
      direction: PortDirection::Input,
      value_type: port.value_type,
      required: port.required,
    })
  }
  for port in specification.outputs {
    ports.push({
      direction: PortDirection::Output,
      value_type: port.value_type,
      required: port.required,
    })
  }
  let parameters : Array[@application.PortValueType] = []
  for parameter in specification.parameters {
    match parameter {
      @application.ParameterValue::Number(_) =>
        parameters.push(@application.PortValueType::Number)
      @application.ParameterValue::Boolean(_) =>
        parameters.push(@application.PortValueType::Boolean)
    }
  }
  {
    kind: descriptor.kind(),
    ports,
    parameters,
    actions: specification.action_count,
  }
}

///|
fn node_input_count(descriptor : @application.NodeDescriptor) -> Int {
  let schema = descriptor_schema(descriptor)
  let mut count = 0
  for port in schema.ports {
    if port.direction is PortDirection::Input {
      count = count + 1
    }
  }
  count
}

///|
fn descriptor_port_schema(
  descriptor : @application.NodeDescriptor,
  ordinal : Int,
) -> PortSchema? {
  let ports = descriptor_schema(descriptor).ports
  if ordinal < 0 || ordinal >= ports.length() {
    None
  } else {
    Some(ports[ordinal])
  }
}

///|
fn descriptor_port_references(
  graph : Int,
  node : Int,
  descriptor : @application.NodeDescriptor,
) -> (Array[PortReference], Array[PortReference]) {
  let inputs : Array[PortReference] = []
  let outputs : Array[PortReference] = []
  for ordinal, port in descriptor_schema(descriptor).ports {
    let reference : PortReference = { graph, node, port: ordinal }
    match port.direction {
      PortDirection::Input => inputs.push(reference)
      PortDirection::Output => outputs.push(reference)
    }
  }
  (inputs, outputs)
}

///|
fn GraphState::apply(
  self : GraphState,
  edit : GraphEdit,
) -> Result[GraphTransition, GraphEditRejection] {
  match edit {
    GraphEdit::AddNode(descriptor~) => {
      let id = self.next_node
      let node = { graph: self.graph, node: id }
      let (inputs, outputs) = descriptor_port_references(
        self.graph,
        id,
        descriptor,
      )
      let nodes = self.nodes.copy()
      nodes[id] = { descriptor, bindings: Map([]) }
      Ok({
        state: { graph: self.graph, next_node: id + 1, nodes },
        added: Some((node, inputs, outputs)),
        removed: None,
      })
    }
    GraphEdit::SetParameter(parameter~, value~) =>
      if parameter.graph != self.graph {
        Err(MissingParameter)
      } else {
        match self.nodes.get(parameter.node) {
          None => Err(MissingParameter)
          Some(current) => {
            let schema = descriptor_schema(current.descriptor)
            if parameter.parameter < 0 ||
              parameter.parameter >= schema.parameters.length() {
              Err(MissingParameter)
            } else {
              match
                current.descriptor.with_parameter(parameter.parameter, value) {
                None => Err(WrongParameterType)
                Some(descriptor) => {
                  let nodes = self.nodes.copy()
                  nodes[parameter.node] = { ..current, descriptor, }
                  Ok({ state: { ..self, nodes, }, added: None, removed: None })
                }
              }
            }
          }
        }
      }
    GraphEdit::BindingChangeSet(changes~) => {
      let targets : Set[PortReference] = Set([])
      for change in changes {
        if targets.contains(change.target) {
          return Err(DuplicateBindingTarget)
        }
        targets.add(change.target)
        if change.target.graph != self.graph {
          return Err(MissingPort)
        }
        match self.nodes.get(change.target.node) {
          None => return Err(MissingPort)
          Some(node) => {
            let target_schema = match
              descriptor_port_schema(node.descriptor, change.target.port) {
              None => return Err(MissingPort)
              Some(schema) => schema
            }
            if !(target_schema.direction is PortDirection::Input) {
              return Err(WrongDirection)
            }
            match change.binding {
              BindingTarget::Unbound => ()
              BindingTarget::Bound(provider) => {
                if provider.graph != self.graph {
                  return Err(MissingPort)
                }
                match self.nodes.get(provider.node) {
                  None => return Err(MissingPort)
                  Some(provider_node) => {
                    let provider_schema = match
                      descriptor_port_schema(
                        provider_node.descriptor,
                        provider.port,
                      ) {
                      None => return Err(MissingPort)
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
      }
      let nodes = self.nodes.copy()
      for change in changes {
        let node = nodes.get(change.target.node).unwrap()
        let bindings = node.bindings.copy()
        bindings[change.target] = change.binding
        nodes[change.target.node] = { ..node, bindings, }
      }
      Ok({ state: { ..self, nodes, }, added: None, removed: None })
    }
    GraphEdit::RemoveNodes(nodes~) => {
      let selected : Set[Int] = Set([])
      for target in nodes {
        if target.graph != self.graph {
          return Err(MissingNode)
        }
        if selected.contains(target.node) {
          return Err(DuplicateNodeTarget)
        }
        selected.add(target.node)
        if self.nodes.get(target.node) is None {
          return Err(MissingNode)
        }
      }
      let removed : Array[Int] = []
      for node_id, _ in self.nodes {
        if selected.contains(node_id) {
          removed.push(node_id)
        }
      }
      removed.sort_by((left, right) => left.compare(right))
      let unbound : Array[PortReference] = []
      for node_id, node in self.nodes {
        if !selected.contains(node_id) {
          for port, schema in descriptor_schema(node.descriptor).ports {
            if schema.direction is PortDirection::Input {
              let target : PortReference = {
                graph: self.graph,
                node: node_id,
                port,
              }
              match node.bindings.get(target) {
                Some(BindingTarget::Bound(provider)) if selected.contains(
                    provider.node,
                  ) => unbound.push(target)
                _ => ()
              }
            }
          }
        }
      }
      unbound.sort_by((left, right) => {
        let node_order = left.node.compare(right.node)
        if node_order == 0 {
          left.port.compare(right.port)
        } else {
          node_order
        }
      })
      let nodes = self.nodes.copy()
      for node_id in removed {
        nodes.remove(node_id)
      }
      for target in unbound {
        let node = nodes.get(target.node).unwrap()
        let bindings = node.bindings.copy()
        bindings[target] = BindingTarget::Unbound
        nodes[target.node] = { ..node, bindings, }
      }
      Ok({
        state: { ..self, nodes, },
        added: None,
        removed: Some((removed, unbound)),
      })
    }
  }
}
