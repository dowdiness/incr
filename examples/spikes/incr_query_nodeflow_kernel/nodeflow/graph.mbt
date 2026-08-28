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
      let input_count = match descriptor {
        Number(_) | Boolean(_) => 0
        Add | Multiply | SafeDivide => 2
        Display => 1
      }
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
                Ok({ state: { ..self, nodes, }, added: None })
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
      Ok({ state: { ..self, nodes, }, added: None })
    }
  }
}
