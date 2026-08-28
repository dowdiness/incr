///|
/// The owned, execution-independent representation of a Semantic Graph.
pub struct GraphDocument {
  priv wire : DocumentWire
}

///|
priv struct DocumentWire {
  version : Int
  graph : Int
  next_node : Int
  nodes : Array[DocumentNode]
}

///|
priv struct DocumentNode {
  id : Int
  descriptor : @application.NodeDescriptor
  bindings : Array[(Int, BindingTarget)]
}

///|
/// Errors raised by JSON parsing or strict wire-shape decoding.
pub enum GraphDocumentDecodeError {
  MalformedJson
  WrongShape
} derive(Eq, Debug)

///|
/// Expected semantic rejection while restoring a document.
pub enum GraphRestorationRejection {
  UnsupportedVersion
  InvalidGraphIdentity
  InvalidFrontier
  DuplicateNode
  NodeBeyondFrontier
  InvalidDescriptor
  DuplicateBindingTarget
  MissingEndpoint
  WrongDirection
  WrongType
} derive(Eq, Debug)

///|
/// Structural failure while constructing or publishing a restored graph.
pub suberror GraphRestorationError {
  RegionClosed
  RegionMutationDuringEvaluation
  RegionMutationDuringTransaction
  ReadCrossStore
  ReadClosedRegion
  ReadExpiredContext
  ReadReentrantRoot
  ReadDuringTransaction
} derive(Debug)

///|
/// The atomic result of restoring a document.
pub struct GraphRestoration {
  priv graph : Nodeflow
  priv snapshot : SurfaceSnapshot
}

///|
/// Returns the fresh graph created by restoration.
pub fn GraphRestoration::nodeflow(self : GraphRestoration) -> Nodeflow {
  self.graph
}

///|
/// Returns the one snapshot assembled after publication.
pub fn GraphRestoration::snapshot(self : GraphRestoration) -> SurfaceSnapshot {
  self.snapshot
}

///|
fn json_int(value : Json) -> Int? {
  match value {
    Json::Number(value, ..) if value == value.to_int().to_double() =>
      Some(value.to_int())
    _ => None
  }
}

///|
fn field(object : Map[String, Json], name : String) -> Json? {
  object.get_from_string(name.view())
}

///|
fn read_port(value : Json) -> (Int, Int)? {
  match value {
    Json::Array(xs) if xs.length() == 2 => {
      let node = json_int(xs[0])
      let port = json_int(xs[1])
      if node is Some(_) && port is Some(_) {
        Some((node.unwrap(), port.unwrap()))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn descriptor_json(descriptor : @application.NodeDescriptor) -> Json {
  @json.parse(@application.encode_descriptor_json(descriptor)) catch {
    _ => abort("application descriptor encoding produced invalid JSON")
  }
}

///|
fn binding_json(binding : (Int, BindingTarget)) -> Json {
  let (port, target) = binding
  let provider : Json = match target {
    BindingTarget::Unbound => @json.to_json(())
    BindingTarget::Bound(reference) =>
      Json::array([
        Json::number(reference.node.to_double()),
        Json::number(reference.port.to_double()),
      ])
  }
  Json::object({
    "target": Json::number(port.to_double()),
    "provider": provider,
  })
}

///|
/// Captures semantic data in deterministic node and binding order.
pub fn Nodeflow::document(self : Nodeflow) -> GraphDocument {
  let nodes : Array[DocumentNode] = []
  for id, node in self.state.nodes {
    let bindings = node.bindings.to_array()
    bindings.sort_by((a, b) => {
      let left = a.0.port
      let right = b.0.port
      left.compare(right)
    })
    let compact : Array[(Int, BindingTarget)] = []
    for entry in bindings {
      let reference = entry.0
      let target = entry.1
      compact.push((reference.port, target))
    }
    nodes.push({ id, descriptor: node.descriptor, bindings: compact })
  }
  nodes.sort_by((a, b) => a.id.compare(b.id))
  {
    wire: {
      version: 1,
      graph: self.state.graph,
      next_node: self.state.next_node,
      nodes,
    },
  }
}

///|
/// Encodes this document using the version-1 deterministic wire schema.
pub fn GraphDocument::encode_json(self : GraphDocument) -> String {
  let node_json : Array[Json] = []
  for node in self.wire.nodes {
    let bindings : Array[Json] = []
    for binding in node.bindings {
      bindings.push(binding_json(binding))
    }
    node_json.push(
      Json::object({
        "id": Json::number(node.id.to_double()),
        "descriptor": descriptor_json(node.descriptor),
        "bindings": Json::array(bindings),
      }),
    )
  }
  Json::object({
    "version": Json::number(self.wire.version.to_double()),
    "graph": Json::number(self.wire.graph.to_double()),
    "frontier": Json::number(self.wire.next_node.to_double()),
    "nodes": Json::array(node_json),
  }).stringify()
}

///|
fn parse_descriptor(value : Json) -> @application.NodeDescriptor? {
  match @application.decode_descriptor_json(value.stringify()) {
    Ok(descriptor) => Some(descriptor)
    Err(_) => None
  }
}

///|
/// Strictly parses a version-1 document without allocating execution state.
pub fn GraphDocument::decode_json(
  text : StringView,
) -> Result[GraphDocument, GraphDocumentDecodeError] noraise {
  let root = @json.parse(text) catch {
    @json.ParseError::InvalidChar(_, _)
    | @json.ParseError::InvalidEof
    | @json.ParseError::InvalidNumber(_, _)
    | @json.ParseError::InvalidIdentEscape(_)
    | @json.ParseError::DepthLimitExceeded => return Err(MalformedJson)
  }
  match root {
    Json::Object(object) => {
      let version = match field(object, "version") {
        Some(v) => json_int(v)
        _ => None
      }
      let graph = match field(object, "graph") {
        Some(v) => json_int(v)
        _ => None
      }
      let frontier = match field(object, "frontier") {
        Some(v) => json_int(v)
        _ => None
      }
      let nodes = match field(object, "nodes") {
        Some(Json::Array(v)) => Some(v)
        _ => None
      }
      if version is None || graph is None || frontier is None || nodes is None {
        return Err(WrongShape)
      }
      let parsed : Array[DocumentNode] = []
      for item in nodes.unwrap() {
        match item {
          Json::Object(node) => {
            let id = match field(node, "id") {
              Some(v) => json_int(v)
              _ => None
            }
            let descriptor = match field(node, "descriptor") {
              Some(v) => parse_descriptor(v)
              _ => None
            }
            let bindings = match field(node, "bindings") {
              Some(Json::Array(v)) => Some(v)
              _ => None
            }
            if id is None || descriptor is None || bindings is None {
              return Err(WrongShape)
            }
            let decoded : Array[(Int, BindingTarget)] = []
            for item in bindings.unwrap() {
              match item {
                Json::Object(binding) => {
                  let target = match field(binding, "target") {
                    Some(v) => json_int(v)
                    _ => None
                  }
                  let provider = match field(binding, "provider") {
                    Some(Json::Null) => Some(BindingTarget::Unbound)
                    Some(value) =>
                      match read_port(value) {
                        Some((node, port)) =>
                          Some(
                            BindingTarget::Bound({
                              graph: graph.unwrap(),
                              node,
                              port,
                            }),
                          )
                        _ => None
                      }
                    _ => None
                  }
                  if target is None || provider is None {
                    return Err(WrongShape)
                  }
                  decoded.push((target.unwrap(), provider.unwrap()))
                }
                _ => return Err(WrongShape)
              }
            }
            parsed.push({
              id: id.unwrap(),
              descriptor: descriptor.unwrap(),
              bindings: decoded,
            })
          }
          _ => return Err(WrongShape)
        }
      }
      Ok({
        wire: {
          version: version.unwrap(),
          graph: graph.unwrap(),
          next_node: frontier.unwrap(),
          nodes: parsed,
        },
      })
    }
    _ => Err(WrongShape)
  }
}
