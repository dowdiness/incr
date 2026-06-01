///|
/// Bench entry points for the graph-editor recomputation fixture.

///|
fn[T] bench_graph_parameter_edit(
  b : @bench.T,
  node_count : Int,
  make_pipeline : (Int) -> GraphEditorPipeline[T],
) -> Unit {
  let pipeline = make_pipeline(node_count)
  let mut step = 0
  b.bench(fn() {
    step += 1
    pipeline.edit_parameter(step)
    b.keep(pipeline.read())
  })
  pipeline.dispose()
}

///|
fn bench_graph_viewport_pan_zoom(
  b : @bench.T,
  node_count : Int,
  make_pipeline : (Int) -> GraphEditorPipeline[GraphRender],
) -> Unit {
  let pipeline = make_pipeline(node_count)
  let mut step = 0
  b.bench(fn() {
    step += 1
    pipeline.pan_zoom(step)
    b.keep(pipeline.read())
  })
  pipeline.dispose()
}

///|
fn bench_graph_hover_inspector(b : @bench.T, node_count : Int) -> Unit {
  let pipeline = graph_editor_sparse_inspector_pipeline(node_count)
  let mut step = 0
  b.bench(fn() {
    step += 1
    pipeline.set_hover(step)
    b.keep(pipeline.read())
  })
  pipeline.dispose()
}

///|
fn bench_graph_live_drag(
  b : @bench.T,
  node_count : Int,
  make_pipeline : (Int) -> GraphEditorPipeline[GraphRender],
) -> Unit {
  let pipeline = make_pipeline(node_count)
  let mut frame = 0
  b.bench(fn() {
    for _ in 0..<60 {
      frame += 1
      pipeline.drag_preview(frame)
      b.keep(pipeline.read())
    }
  })
  pipeline.dispose()
}

///|
fn bench_graph_move_commit(
  b : @bench.T,
  node_count : Int,
  make_pipeline : (Int) -> GraphEditorPipeline[GraphRender],
) -> Unit {
  let pipeline = make_pipeline(node_count)
  let mut frame = 0
  b.bench(fn() {
    frame += 1
    pipeline.drag_preview(frame)
    pipeline.commit_move_nodes()
    b.keep(pipeline.read())
  })
  pipeline.dispose()
}

///|
test "graph editor: coarse parameter edit full render 100 nodes" (b : @bench.T) {
  bench_graph_parameter_edit(b, 100, graph_editor_coarse_full_pipeline)
}

///|
test "graph editor: coarse parameter edit full render 1000 nodes" (b : @bench.T) {
  bench_graph_parameter_edit(b, 1000, graph_editor_coarse_full_pipeline)
}

///|
test "graph editor: per-node DerivedMap parameter edit full render 100 nodes" (
  b : @bench.T,
) {
  bench_graph_parameter_edit(b, 100, graph_editor_per_node_full_pipeline)
}

///|
test "graph editor: per-node DerivedMap parameter edit full render 1000 nodes" (
  b : @bench.T,
) {
  bench_graph_parameter_edit(b, 1000, graph_editor_per_node_full_pipeline)
}

///|
test "graph editor: ReachableDerived sparse inspector parameter edit 100 nodes" (
  b : @bench.T,
) {
  bench_graph_parameter_edit(b, 100, graph_editor_sparse_inspector_pipeline)
}

///|
test "graph editor: ReachableDerived sparse inspector parameter edit 1000 nodes" (
  b : @bench.T,
) {
  bench_graph_parameter_edit(b, 1000, graph_editor_sparse_inspector_pipeline)
}

///|
test "graph editor: coarse viewport pan/zoom full render 1000 nodes" (
  b : @bench.T,
) {
  bench_graph_viewport_pan_zoom(b, 1000, graph_editor_coarse_full_pipeline)
}

///|
test "graph editor: per-node DerivedMap viewport pan/zoom full render 1000 nodes" (
  b : @bench.T,
) {
  bench_graph_viewport_pan_zoom(b, 1000, graph_editor_per_node_full_pipeline)
}

///|
test "graph editor: ReachableDerived sparse inspector hover change 1000 nodes" (
  b : @bench.T,
) {
  bench_graph_hover_inspector(b, 1000)
}

///|
test "graph editor: coarse live drag preview 60 frames full render 1000 nodes" (
  b : @bench.T,
) {
  bench_graph_live_drag(b, 1000, graph_editor_coarse_full_pipeline)
}

///|
test "graph editor: per-node DerivedMap live drag preview 60 frames full render 1000 nodes" (
  b : @bench.T,
) {
  bench_graph_live_drag(b, 1000, graph_editor_per_node_full_pipeline)
}

///|
test "graph editor: coarse MoveNodes commit full render 1000 nodes" (
  b : @bench.T,
) {
  bench_graph_move_commit(b, 1000, graph_editor_coarse_full_pipeline)
}
