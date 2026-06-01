///|
/// Graph-editor-shaped recomputation benchmarks for issue #143.
///
/// The fixture separates durable graph/document state from ephemeral UI state
/// (hover, drag preview, viewport) and records which derived stages recompute
/// for durable edits versus UI-only updates.

///|
struct GraphNode {
  id : Int
  x : Int
  y : Int
  param : Int
}

///|
struct GraphEdge {
  from : Int
  to : Int
}

///|
struct GraphDocument {
  revision : Int
  nodes : Array[GraphNode]
  edges : Array[GraphEdge]
}

///|
struct GraphDrag {
  active : Bool
  node_id : Int
  dx : Int
  dy : Int
  revision : Int
}

///|
struct GraphViewport {
  pan_x : Int
  pan_y : Int
  zoom_milli : Int
  revision : Int
}

///|
struct GraphValidated {
  document : GraphDocument
  node_count : Int
  edge_count : Int
  invalid_edges : Int
  checksum : Int
}

///|
impl Eq for GraphValidated with fn equal(self, other) -> Bool {
  self.node_count == other.node_count &&
  self.edge_count == other.edge_count &&
  self.invalid_edges == other.invalid_edges &&
  self.checksum == other.checksum
}

///|
struct GraphNormalizedNode {
  id : Int
  x : Int
  y : Int
  value : Int
  degree : Int
}

///|
struct GraphNormalized {
  node_count : Int
  edge_count : Int
  nodes : Array[GraphNormalizedNode]
  checksum : Int
}

///|
impl Eq for GraphNormalized with fn equal(self, other) -> Bool {
  self.node_count == other.node_count &&
  self.edge_count == other.edge_count &&
  self.checksum == other.checksum
}

///|
struct GraphLoweredNode {
  id : Int
  x : Int
  y : Int
  render_value : Int
}

///|
impl Eq for GraphLoweredNode with fn equal(self, other) -> Bool {
  self.id == other.id &&
  self.x == other.x &&
  self.y == other.y &&
  self.render_value == other.render_value
}

///|
struct GraphLowered {
  node_count : Int
  nodes : Array[GraphLoweredNode]
  checksum : Int
}

///|
impl Eq for GraphLowered with fn equal(self, other) -> Bool {
  self.node_count == other.node_count && self.checksum == other.checksum
}

///|
struct GraphRender {
  rendered_nodes : Int
  render_checksum : Int
}

///|
impl Eq for GraphRender with fn equal(self, other) -> Bool {
  self.rendered_nodes == other.rendered_nodes &&
  self.render_checksum == other.render_checksum
}

///|
struct GraphInspector {
  node_id : Int
  checksum : Int
}

///|
impl Eq for GraphInspector with fn equal(self, other) -> Bool {
  self.node_id == other.node_id && self.checksum == other.checksum
}

///|
struct GraphRecomputeCounters {
  mut validation : Int
  mut normalization : Int
  mut lowering : Int
  mut lower_node : Int
  mut render : Int
  mut inspector : Int
}

///|
fn GraphRecomputeCounters::GraphRecomputeCounters() -> GraphRecomputeCounters {
  {
    validation: 0,
    normalization: 0,
    lowering: 0,
    lower_node: 0,
    render: 0,
    inspector: 0,
  }
}

///|
struct GraphRecomputeRecord {
  validation : Int
  normalization : Int
  lowering : Int
  lower_node : Int
  render : Int
  inspector : Int
}

///|
fn GraphRecomputeCounters::snapshot(
  self : GraphRecomputeCounters,
) -> GraphRecomputeRecord {
  {
    validation: self.validation,
    normalization: self.normalization,
    lowering: self.lowering,
    lower_node: self.lower_node,
    render: self.render,
    inspector: self.inspector,
  }
}

///|
fn GraphRecomputeRecord::delta(
  self : GraphRecomputeRecord,
  before : GraphRecomputeRecord,
) -> GraphRecomputeRecord {
  {
    validation: self.validation - before.validation,
    normalization: self.normalization - before.normalization,
    lowering: self.lowering - before.lowering,
    lower_node: self.lower_node - before.lower_node,
    render: self.render - before.render,
    inspector: self.inspector - before.inspector,
  }
}

///|
fn GraphRecomputeRecord::summary(self : GraphRecomputeRecord) -> String {
  "validation=\{self.validation}, normalization=\{self.normalization}, lowering=\{self.lowering}, lower_node=\{self.lower_node}, render=\{self.render}, inspector=\{self.inspector}"
}

///|
fn graph_mix(acc : Int, value : Int, index : Int) -> Int {
  (acc * 33 + value.abs() % 4093 * (index % 17 + 1) + 17) % 1000003
}

///|
fn graph_clamp_index(count : Int, requested : Int) -> Int {
  if count <= 0 {
    0
  } else {
    requested.abs() % count
  }
}

///|
fn graph_initial_document(node_count : Int) -> GraphDocument {
  let nodes : Array[GraphNode] = []
  for i in 0..<node_count {
    nodes.push({
      id: i,
      x: i % 40 * 18,
      y: i / 40 * 16,
      param: (i * 7 + 13) % 251,
    })
  }
  let edges : Array[GraphEdge] = []
  if node_count > 1 {
    for i in 0..<(node_count - 1) {
      edges.push({ from: i, to: i + 1 })
    }
  }
  { revision: 0, nodes, edges }
}

///|
fn graph_idle_drag(revision : Int) -> GraphDrag {
  { active: false, node_id: 0, dx: 0, dy: 0, revision }
}

///|
fn graph_drag_preview(frame : Int, node_count : Int) -> GraphDrag {
  {
    active: true,
    node_id: graph_clamp_index(node_count, frame),
    dx: frame % 37,
    dy: -(frame % 29),
    revision: frame,
  }
}

///|
fn graph_initial_viewport() -> GraphViewport {
  { pan_x: 0, pan_y: 0, zoom_milli: 1000, revision: 0 }
}

///|
fn graph_next_viewport(current : GraphViewport, step : Int) -> GraphViewport {
  {
    pan_x: current.pan_x + step % 13,
    pan_y: current.pan_y - step % 11,
    zoom_milli: 900 + step % 300,
    revision: current.revision + 1,
  }
}

///|
fn graph_edit_parameter(doc : GraphDocument, step : Int) -> GraphDocument {
  let nodes = doc.nodes.copy()
  let edges = doc.edges.copy()
  if nodes.length() > 0 {
    let index = graph_clamp_index(nodes.length(), step)
    let node = nodes[index]
    nodes[index] = {
      id: node.id,
      x: node.x,
      y: node.y,
      param: (node.param + step + 1) % 997,
    }
  }
  { revision: doc.revision + 1, nodes, edges }
}

///|
fn graph_add_node(doc : GraphDocument) -> GraphDocument {
  let nodes = doc.nodes.copy()
  let edges = doc.edges.copy()
  let id = nodes.length()
  nodes.push({
    id,
    x: id % 40 * 18,
    y: id / 40 * 16,
    param: (id * 7 + 13) % 251,
  })
  if id > 0 {
    edges.push({ from: id - 1, to: id })
  }
  { revision: doc.revision + 1, nodes, edges }
}

///|
fn graph_delete_last_node(doc : GraphDocument) -> GraphDocument {
  let nodes = doc.nodes.copy()
  let deleted_id = match nodes.pop() {
    Some(node) => node.id
    None => -1
  }
  let edges = doc.edges.filter(edge => {
    edge.from != deleted_id && edge.to != deleted_id
  })
  { revision: doc.revision + 1, nodes, edges }
}

///|
fn graph_connect_edge(doc : GraphDocument, step : Int) -> GraphDocument {
  let nodes = doc.nodes.copy()
  let edges = doc.edges.copy()
  if nodes.length() > 1 {
    let from = graph_clamp_index(nodes.length(), step)
    let to = graph_clamp_index(nodes.length(), step + nodes.length() / 2 + 1)
    if from != to {
      edges.push({ from, to })
    }
  }
  { revision: doc.revision + 1, nodes, edges }
}

///|
fn graph_disconnect_edge(doc : GraphDocument) -> GraphDocument {
  let edges = doc.edges.copy()
  ignore(edges.pop())
  { revision: doc.revision + 1, nodes: doc.nodes.copy(), edges }
}

///|
fn graph_move_nodes(doc : GraphDocument, drag : GraphDrag) -> GraphDocument {
  let nodes = doc.nodes.copy()
  let edges = doc.edges.copy()
  if drag.active && nodes.length() > 0 {
    let index = graph_clamp_index(nodes.length(), drag.node_id)
    let node = nodes[index]
    nodes[index] = {
      id: node.id,
      x: node.x + drag.dx,
      y: node.y + drag.dy,
      param: node.param,
    }
  }
  { revision: doc.revision + 1, nodes, edges }
}

///|
fn graph_validate(doc : GraphDocument) -> GraphValidated {
  let node_count = doc.nodes.length()
  let edge_count = doc.edges.length()
  let mut invalid_edges = 0
  let mut checksum = graph_mix(0, doc.revision, 0)
  for i, node in doc.nodes {
    checksum = graph_mix(checksum, node.param + node.x + node.y, i)
  }
  for i, edge in doc.edges {
    if edge.from < 0 ||
      edge.from >= node_count ||
      edge.to < 0 ||
      edge.to >= node_count {
      invalid_edges += 1
    }
    checksum = graph_mix(
      checksum,
      edge.from * 31 + edge.to * 17,
      node_count + i,
    )
  }
  { document: doc, node_count, edge_count, invalid_edges, checksum }
}

///|
fn graph_normalize(validated : GraphValidated) -> GraphNormalized {
  let degrees : Array[Int] = []
  for _ in 0..<validated.node_count {
    degrees.push(0)
  }
  for edge in validated.document.edges {
    if edge.from >= 0 &&
      edge.from < validated.node_count &&
      edge.to >= 0 &&
      edge.to < validated.node_count {
      degrees[edge.from] = degrees[edge.from] + 1
      degrees[edge.to] = degrees[edge.to] + 1
    }
  }
  let nodes : Array[GraphNormalizedNode] = []
  let mut checksum = graph_mix(0, validated.checksum, 0)
  for i, node in validated.document.nodes {
    let degree = degrees[i]
    let value = (
        node.param * 7 + degree * 11 + validated.invalid_edges * 13 + i
      ) %
      997
    nodes.push({ id: node.id, x: node.x, y: node.y, value, degree })
    checksum = graph_mix(checksum, value + degree, i)
  }
  {
    node_count: validated.node_count,
    edge_count: validated.edge_count,
    nodes,
    checksum,
  }
}

///|
fn graph_lower_node(
  normalized : GraphNormalized,
  index : Int,
) -> GraphLoweredNode {
  if normalized.node_count == 0 {
    { id: -1, x: 0, y: 0, render_value: 0 }
  } else {
    let safe_index = graph_clamp_index(normalized.node_count, index)
    let node = normalized.nodes[safe_index]
    let render_value = (node.value * 5 + node.degree * 23 + safe_index * 19) %
      8191
    { id: node.id, x: node.x, y: node.y, render_value }
  }
}

///|
fn graph_lower(normalized : GraphNormalized) -> GraphLowered {
  let nodes : Array[GraphLoweredNode] = []
  let mut checksum = graph_mix(0, normalized.checksum, 0)
  for i in 0..<normalized.node_count {
    let node = graph_lower_node(normalized, i)
    nodes.push(node)
    checksum = graph_mix(checksum, node.render_value + node.x + node.y, i)
  }
  { node_count: normalized.node_count, nodes, checksum }
}

///|
fn graph_render_node(
  node : GraphLoweredNode,
  drag : GraphDrag,
  viewport : GraphViewport,
  index : Int,
) -> Int {
  let dx = if drag.active && drag.node_id == node.id { drag.dx } else { 0 }
  let dy = if drag.active && drag.node_id == node.id { drag.dy } else { 0 }
  let screen_x = (node.x + dx + viewport.pan_x) * viewport.zoom_milli / 1000
  let screen_y = (node.y + dy + viewport.pan_y) * viewport.zoom_milli / 1000
  graph_mix(node.render_value, screen_x + screen_y, index)
}

///|
fn graph_render_from_lowered(
  lowered : GraphLowered,
  drag : GraphDrag,
  viewport : GraphViewport,
) -> GraphRender {
  let mut checksum = graph_mix(0, lowered.checksum, 0)
  for i, node in lowered.nodes {
    checksum = graph_mix(
      checksum,
      graph_render_node(node, drag, viewport, i),
      i,
    )
  }
  { rendered_nodes: lowered.node_count, render_checksum: checksum }
}

///|
fn graph_render_from_reader(
  node_count : Int,
  drag : GraphDrag,
  viewport : GraphViewport,
  read_node : (Int) -> GraphLoweredNode,
) -> GraphRender {
  let mut checksum = graph_mix(0, node_count, 0)
  for i in 0..<node_count {
    let node = read_node(i)
    checksum = graph_mix(
      checksum,
      graph_render_node(node, drag, viewport, i),
      i,
    )
  }
  { rendered_nodes: node_count, render_checksum: checksum }
}

///|
fn graph_inspector_from_node(
  requested : Int,
  node : GraphLoweredNode,
) -> GraphInspector {
  {
    node_id: node.id,
    checksum: graph_mix(node.render_value, node.x + node.y + requested, node.id),
  }
}

///|
struct GraphEditorSetup {
  rt : @incr.Runtime
  scope : @incr.Scope
  document : @incr.Input[GraphDocument]
  hover : @incr.Input[Int]
  drag : @incr.Input[GraphDrag]
  viewport : @incr.Input[GraphViewport]
  counters : GraphRecomputeCounters
}

///|
struct GraphEditorPipeline[T] {
  scope : @incr.Scope
  document : @incr.Input[GraphDocument]
  hover : @incr.Input[Int]
  drag : @incr.Input[GraphDrag]
  viewport : @incr.Input[GraphViewport]
  counters : GraphRecomputeCounters
  watch : @incr.Watch[T]
}

///|
fn graph_editor_setup(
  node_count : Int,
  label_prefix : String,
) -> GraphEditorSetup {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let document = scope.input(
    graph_initial_document(node_count),
    label=label_prefix + ".document",
  )
  let hover = scope.input(0, label=label_prefix + ".hover")
  let drag = scope.input(
    graph_idle_drag(0),
    label=label_prefix + ".drag_preview",
  )
  let viewport = scope.input(
    graph_initial_viewport(),
    label=label_prefix + ".viewport",
  )
  {
    rt,
    scope,
    document,
    hover,
    drag,
    viewport,
    counters: GraphRecomputeCounters(),
  }
}

///|
fn graph_editor_normalized(
  setup : GraphEditorSetup,
  label_prefix : String,
) -> @incr.Derived[GraphNormalized] {
  let validated = setup.scope.derived(
    () => {
      setup.counters.validation += 1
      graph_validate(setup.document.get())
    },
    label=label_prefix + ".validation",
  )
  setup.scope.derived(
    () => {
      setup.counters.normalization += 1
      graph_normalize(validated.get_or_abort())
    },
    label=label_prefix + ".normalization",
  )
}

///|
fn graph_editor_lowered_by_node(
  setup : GraphEditorSetup,
  normalized : @incr.Derived[GraphNormalized],
  label_prefix : String,
) -> @incr.DerivedMap[Int, GraphLoweredNode] {
  setup.scope.derived_map(
    (index : Int) => {
      setup.counters.lower_node += 1
      graph_lower_node(normalized.get_or_abort(), index)
    },
    label=label_prefix + ".lowered_by_node",
  )
}

///|
fn[T] graph_finish_pipeline(
  setup : GraphEditorSetup,
  watch : @incr.Watch[T],
) -> GraphEditorPipeline[T] {
  ignore(watch.read_or_abort())
  setup.rt.gc()
  {
    scope: setup.scope,
    document: setup.document,
    hover: setup.hover,
    drag: setup.drag,
    viewport: setup.viewport,
    counters: setup.counters,
    watch,
  }
}

///|
fn graph_editor_coarse_full_pipeline(
  node_count : Int,
) -> GraphEditorPipeline[GraphRender] {
  let setup = graph_editor_setup(node_count, "graph.coarse")
  let normalized = graph_editor_normalized(setup, "graph.coarse")
  let lowered = setup.scope.derived(
    () => {
      setup.counters.lowering += 1
      graph_lower(normalized.get_or_abort())
    },
    label="graph.coarse.lowering",
  )
  let render = setup.scope.derived(
    () => {
      setup.counters.render += 1
      graph_render_from_lowered(
        lowered.get_or_abort(),
        setup.drag.get(),
        setup.viewport.get(),
      )
    },
    label="graph.coarse.render",
  )
  let watch = setup.scope.add_watch(render.watch())
  graph_finish_pipeline(setup, watch)
}

///|
fn graph_editor_per_node_full_pipeline(
  node_count : Int,
) -> GraphEditorPipeline[GraphRender] {
  let setup = graph_editor_setup(node_count, "graph.per_node")
  let normalized = graph_editor_normalized(setup, "graph.per_node")
  let lowered_by_node = graph_editor_lowered_by_node(
    setup, normalized, "graph.per_node",
  )
  let render = setup.scope.derived(
    () => {
      setup.counters.render += 1
      let current = normalized.get_or_abort()
      graph_render_from_reader(
        current.node_count,
        setup.drag.get(),
        setup.viewport.get(),
        i => lowered_by_node.get_or_abort(i),
      )
    },
    label="graph.per_node.render",
  )
  let watch = setup.scope.add_watch(render.watch())
  graph_finish_pipeline(setup, watch)
}

///|
fn graph_editor_sparse_inspector_pipeline(
  node_count : Int,
) -> GraphEditorPipeline[GraphInspector] {
  let setup = graph_editor_setup(node_count, "graph.inspector")
  let normalized = graph_editor_normalized(setup, "graph.inspector")
  let lowered_by_node = graph_editor_lowered_by_node(
    setup, normalized, "graph.inspector",
  )
  let panel_scope = setup.scope.child()
  let inspector = panel_scope.reachable_derived(
    () => {
      setup.counters.inspector += 1
      let current = normalized.get_or_abort()
      let requested = setup.hover.get()
      let index = graph_clamp_index(current.node_count, requested)
      graph_inspector_from_node(requested, lowered_by_node.get_or_abort(index))
    },
    label="graph.inspector.panel",
  )
  let watch = panel_scope.add_watch(inspector.watch())
  graph_finish_pipeline(setup, watch)
}

///|
fn[T] GraphEditorPipeline::read(self : GraphEditorPipeline[T]) -> T {
  self.watch.read_or_abort()
}

///|
fn[T] GraphEditorPipeline::counts(
  self : GraphEditorPipeline[T],
) -> GraphRecomputeRecord {
  self.counters.snapshot()
}

///|
fn[T] GraphEditorPipeline::dispose(self : GraphEditorPipeline[T]) -> Unit {
  self.scope.dispose()
}

///|
fn[T] GraphEditorPipeline::edit_parameter(
  self : GraphEditorPipeline[T],
  step : Int,
) -> Unit {
  self.document.force_set(graph_edit_parameter(self.document.peek(), step))
}

///|
fn[T] GraphEditorPipeline::add_node(self : GraphEditorPipeline[T]) -> Unit {
  self.document.force_set(graph_add_node(self.document.peek()))
}

///|
fn[T] GraphEditorPipeline::delete_node(self : GraphEditorPipeline[T]) -> Unit {
  self.document.force_set(graph_delete_last_node(self.document.peek()))
}

///|
fn[T] GraphEditorPipeline::connect_edge(
  self : GraphEditorPipeline[T],
  step : Int,
) -> Unit {
  self.document.force_set(graph_connect_edge(self.document.peek(), step))
}

///|
fn[T] GraphEditorPipeline::disconnect_edge(
  self : GraphEditorPipeline[T],
) -> Unit {
  self.document.force_set(graph_disconnect_edge(self.document.peek()))
}

///|
fn[T] GraphEditorPipeline::pan_zoom(
  self : GraphEditorPipeline[T],
  step : Int,
) -> Unit {
  self.viewport.force_set(graph_next_viewport(self.viewport.peek(), step))
}

///|
fn[T] GraphEditorPipeline::drag_preview(
  self : GraphEditorPipeline[T],
  frame : Int,
) -> Unit {
  self.drag.force_set(
    graph_drag_preview(frame, self.document.peek().nodes.length()),
  )
}

///|
fn[T] GraphEditorPipeline::commit_move_nodes(
  self : GraphEditorPipeline[T],
) -> Unit {
  let drag = self.drag.peek()
  self.document.force_set(graph_move_nodes(self.document.peek(), drag))
  self.drag.force_set(graph_idle_drag(drag.revision + 1))
}

///|
fn[T] GraphEditorPipeline::set_hover(
  self : GraphEditorPipeline[T],
  node_id : Int,
) -> Unit {
  self.hover.set(node_id)
}

///|
fn[T] graph_delta_after(
  pipeline : GraphEditorPipeline[T],
  action : () -> Unit,
) -> GraphRecomputeRecord {
  let before = pipeline.counts()
  action()
  ignore(pipeline.read())
  pipeline.counts().delta(before)
}

///|
test "graph editor: MoveNodes commit uses drag anchor only" {
  let doc = graph_initial_document(12)
  let drag = { active: true, node_id: 5, dx: 3, dy: -2, revision: 1 }
  let moved = graph_move_nodes(doc, drag)
  let revision_delta = moved.revision - doc.revision
  let deltas = [
    for i in 4..<=6 => {
      let before = doc.nodes[i]
      let after = moved.nodes[i]
      "\{after.x - before.x},\{after.y - before.y}"
    }
  ].join(";")
  inspect(
    "revision=\{revision_delta}; deltas=\{deltas}",
    content="revision=1; deltas=0,0;3,-2;0,0",
  )
}

///|
test "graph editor: recompute records for durable and ephemeral edits" {
  let pipeline = graph_editor_coarse_full_pipeline(50)
  inspect(
    graph_delta_after(pipeline, () => pipeline.edit_parameter(1)).summary(),
    content="validation=1, normalization=1, lowering=1, lower_node=0, render=1, inspector=0",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.add_node()).summary(),
    content="validation=1, normalization=1, lowering=1, lower_node=0, render=1, inspector=0",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.delete_node()).summary(),
    content="validation=1, normalization=1, lowering=1, lower_node=0, render=1, inspector=0",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.connect_edge(3)).summary(),
    content="validation=1, normalization=1, lowering=1, lower_node=0, render=1, inspector=0",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.disconnect_edge()).summary(),
    content="validation=1, normalization=1, lowering=1, lower_node=0, render=1, inspector=0",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.pan_zoom(7)).summary(),
    content="validation=0, normalization=0, lowering=0, lower_node=0, render=1, inspector=0",
  )
  let before_drag = pipeline.counts()
  for frame in 1..<=5 {
    pipeline.drag_preview(frame)
    ignore(pipeline.read())
  }
  inspect(
    pipeline.counts().delta(before_drag).summary(),
    content="validation=0, normalization=0, lowering=0, lower_node=0, render=5, inspector=0",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.commit_move_nodes()).summary(),
    content="validation=1, normalization=1, lowering=1, lower_node=0, render=1, inspector=0",
  )
  pipeline.dispose()
}

///|
test "graph editor: sparse inspector ignores viewport and drag preview" {
  let pipeline = graph_editor_sparse_inspector_pipeline(50)
  inspect(
    graph_delta_after(pipeline, () => pipeline.set_hover(7)).summary(),
    content="validation=0, normalization=0, lowering=0, lower_node=1, render=0, inspector=1",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.pan_zoom(11)).summary(),
    content="validation=0, normalization=0, lowering=0, lower_node=0, render=0, inspector=0",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.drag_preview(12)).summary(),
    content="validation=0, normalization=0, lowering=0, lower_node=0, render=0, inspector=0",
  )
  inspect(
    graph_delta_after(pipeline, () => pipeline.edit_parameter(13)).summary(),
    content="validation=1, normalization=1, lowering=0, lower_node=1, render=0, inspector=1",
  )
  pipeline.dispose()
}
