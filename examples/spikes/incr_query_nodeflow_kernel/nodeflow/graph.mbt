///|
/// Pure semantic node record.
priv struct NodeState {
  descriptor : NodeDescriptor
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
fn node_input_count(descriptor : NodeDescriptor) -> Int {
  match descriptor {
    Number(_) | Boolean(_) => 0
    Add | Multiply | SafeDivide => 2
    Display => 1
  }
}

///|
fn port_kind(descriptor : NodeDescriptor, ordinal : Int) -> (Bool, Bool) {
  match descriptor {
    Number(_) | Boolean(_) => (false, ordinal == 0)
    Add | Multiply | SafeDivide => (ordinal < 2, ordinal == 2)
    Display => (ordinal == 0, ordinal == 1)
  }
}

///|
fn descriptor_type(descriptor : NodeDescriptor) -> Bool {
  match descriptor {
    Boolean(_) => true
    _ => false
  }
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
      let input_count = node_input_count(descriptor)
      let output_count = 1
      let inputs : Array[PortReference] = []
      for i = 0; i < input_count; i = i + 1 {
        inputs.push({ graph: self.graph, node: id, port: i })
      }
      let outputs : Array[PortReference] = []
      for i = 0; i < output_count; i = i + 1 {
        outputs.push({ graph: self.graph, node: id, port: input_count + i })
      }
      let nodes = self.nodes.copy()
      nodes[id] = { descriptor, bindings: Map([]) }
      Ok({
        state: { graph: self.graph, next_node: id + 1, nodes },
        added: Some((node, inputs, outputs)),
        removed: None,
      })
    }
    GraphEdit::SetNumberParameter(node~, value~) =>
      if node.graph != self.graph {
        Err(MissingNode)
      } else {
        match self.nodes.get(node.node) {
          None => Err(MissingNode)
          Some(current) =>
            match current.descriptor {
              NodeDescriptor::Number(_) => {
                let nodes = self.nodes.copy()
                nodes[node.node] = {
                  ..current,
                  descriptor: NodeDescriptor::Number(value~),
                }
                Ok({ state: { ..self, nodes, }, added: None, removed: None })
              }
              _ => Err(InvalidEdit)
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
            let (is_input, _) = port_kind(node.descriptor, change.target.port)
            if !is_input {
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
                    let (_, is_output) = port_kind(
                      provider_node.descriptor,
                      provider.port,
                    )
                    if !is_output {
                      return Err(WrongDirection)
                    }
                    if descriptor_type(node.descriptor) !=
                      descriptor_type(provider_node.descriptor) {
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
          let input_count = node_input_count(node.descriptor)
          for port in 0..<input_count {
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
