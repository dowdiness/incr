///|
/// DSL-shaped authoring pipeline benchmarks for issue #139.
///
/// These fixtures model control-side editor recomputation, not realtime audio
/// callbacks. Each measured iteration applies one source edit and reads a
/// primed terminal `Watch`.

///|
struct DslSource {
  node_count : Int
  changed_node : Int
  revision : Int
}

///|
fn DslSource::DslSource(node_count~ : Int, revision~ : Int) -> DslSource {
  { node_count, changed_node: 0, revision }
}

///|
impl Eq for DslSource with fn equal(self, other) -> Bool {
  self.node_count == other.node_count &&
  self.changed_node == other.changed_node &&
  self.revision == other.revision
}

///|
struct DslStage {
  count : Int
  values : Array[Int]
  checksum : Int
}

///|
impl Eq for DslStage with fn equal(self, other) -> Bool {
  self.count == other.count && self.checksum == other.checksum
}

///|
struct DslTerminal {
  node_count : Int
  checksum : Int
}

///|
impl Eq for DslTerminal with fn equal(self, other) -> Bool {
  self.node_count == other.node_count && self.checksum == other.checksum
}

///|
fn dsl_mix(acc : Int, value : Int, index : Int) -> Int {
  (acc * 33 + value * (index + 1) + 17) % 1000003
}

///|
fn dsl_build_stage(count : Int, value_at : (Int) -> Int) -> DslStage {
  let values : Array[Int] = []
  let mut checksum = 0
  for i in 0..<count {
    let value = value_at(i)
    values.push(value)
    checksum = dsl_mix(checksum, value, i)
  }
  { count, values, checksum }
}

///|
fn dsl_source_literal(source : DslSource, index : Int) -> Int {
  let edit_delta = if index == source.changed_node {
    source.revision
  } else {
    0
  }
  (index * 17 + 11 + edit_delta) % 4093
}

///|
fn dsl_parse(source : DslSource) -> DslStage {
  dsl_build_stage(source.node_count, i => dsl_source_literal(source, i))
}

///|
fn dsl_project(parsed : DslStage) -> DslStage {
  dsl_build_stage(parsed.count, i => {
    (parsed.values[i] * 3 + i * 5 + parsed.count) % 8191
  })
}

///|
fn dsl_semantic_value(projected : DslStage, index : Int) -> Int {
  let left = if index == 0 { 0 } else { projected.values[index - 1] }
  let right = if index + 1 == projected.count {
    0
  } else {
    projected.values[index + 1]
  }
  (projected.values[index] * 7 + left * 2 + right * 3 + index) % 16381
}

///|
fn dsl_semantic(projected : DslStage) -> DslStage {
  dsl_build_stage(projected.count, i => dsl_semantic_value(projected, i))
}

///|
fn dsl_normalized_value(value : Int, index : Int) -> Int {
  (value % 251 * (index % 13 + 1) + index) % 32749
}

///|
fn dsl_normalize(semantic : DslStage) -> DslStage {
  dsl_build_stage(semantic.count, i => {
    dsl_normalized_value(semantic.values[i], i)
  })
}

///|
fn dsl_lowered_value(value : Int, index : Int) -> Int {
  (value * 5 + index * 19 + 23) % 65521
}

///|
fn dsl_lower(normalized : DslStage) -> DslStage {
  dsl_build_stage(normalized.count, i => {
    dsl_lowered_value(normalized.values[i], i)
  })
}

///|
fn dsl_lower_node_from_projection(projected : DslStage, index : Int) -> Int {
  dsl_lowered_value(
    dsl_normalized_value(dsl_semantic_value(projected, index), index),
    index,
  )
}

///|
fn dsl_terminal_from_stage(lowered : DslStage) -> DslTerminal {
  let mut checksum = 0
  for i in 0..<lowered.count {
    checksum = dsl_mix(checksum, lowered.values[i], i)
  }
  { node_count: lowered.count, checksum }
}

///|
fn dsl_terminal_from_reader(
  node_count : Int,
  read_node : (Int) -> Int,
) -> DslTerminal {
  let mut checksum = 0
  for i in 0..<node_count {
    checksum = dsl_mix(checksum, read_node(i), i)
  }
  { node_count, checksum }
}

///|
struct DslAuthoringPipeline {
  node_count : Int
  scope : @incr.Scope
  source : @incr.Input[DslSource]
  watch : @incr.Watch[DslTerminal]
}

///|
fn dsl_pipeline_setup(
  node_count : Int,
  source_label : String,
) -> (@incr.Runtime, @incr.Scope, @incr.Input[DslSource]) {
  let rt = @incr.Runtime()
  let scope = @incr.Scope::new(rt)
  let source = scope.input(
    DslSource(node_count~, revision=0),
    label=source_label,
  )
  (rt, scope, source)
}

///|
fn dsl_parse_projection(
  scope : @incr.Scope,
  source : @incr.Input[DslSource],
  label_prefix : String,
) -> @incr.Derived[DslStage] {
  let parsed = scope.derived(
    () => dsl_parse(source.get()),
    label=label_prefix + ".parse",
  )
  scope.derived(
    () => dsl_project(parsed.get_or_abort()),
    label=label_prefix + ".projection",
  )
}

///|
fn dsl_finish_pipeline(
  node_count : Int,
  rt : @incr.Runtime,
  scope : @incr.Scope,
  source : @incr.Input[DslSource],
  watch : @incr.Watch[DslTerminal],
) -> DslAuthoringPipeline {
  ignore(watch.read_or_abort())
  rt.gc()
  { node_count, scope, source, watch }
}

///|
fn DslAuthoringPipeline::edit(
  self : DslAuthoringPipeline,
  revision : Int,
) -> Unit {
  self.source.set(DslSource(node_count=self.node_count, revision~))
}

///|
fn DslAuthoringPipeline::read(self : DslAuthoringPipeline) -> DslTerminal {
  self.watch.read_or_abort()
}

///|
fn DslAuthoringPipeline::dispose(self : DslAuthoringPipeline) -> Unit {
  self.scope.dispose()
}

///|
fn dsl_coarse_pipeline(node_count : Int) -> DslAuthoringPipeline {
  let (rt, scope, source) = dsl_pipeline_setup(node_count, "dsl.coarse.source")
  let projected = dsl_parse_projection(scope, source, "dsl.coarse")
  let semantic = scope.derived(
    () => dsl_semantic(projected.get_or_abort()),
    label="dsl.coarse.semantic",
  )
  let normalized = scope.derived(
    () => dsl_normalize(semantic.get_or_abort()),
    label="dsl.coarse.normalized",
  )
  let lowered = scope.derived(
    () => dsl_lower(normalized.get_or_abort()),
    label="dsl.coarse.lowered",
  )
  let terminal = scope.derived(
    () => dsl_terminal_from_stage(lowered.get_or_abort()),
    label="dsl.coarse.terminal",
  )
  let watch = scope.add_watch(terminal.watch())
  dsl_finish_pipeline(node_count, rt, scope, source, watch)
}

///|
fn dsl_lowered_by_node(
  scope : @incr.Scope,
  projected : @incr.Derived[DslStage],
  label : String,
) -> @incr.DerivedMap[Int, Int] {
  scope.derived_map(
    (index : Int) => {
      dsl_lower_node_from_projection(projected.get_or_abort(), index)
    },
    label~,
  )
}

///|
fn dsl_per_node_full_pipeline(node_count : Int) -> DslAuthoringPipeline {
  let (rt, scope, source) = dsl_pipeline_setup(
    node_count, "dsl.per_node.source",
  )
  let projected = dsl_parse_projection(scope, source, "dsl.per_node")
  let lowered_by_node = dsl_lowered_by_node(
    scope, projected, "dsl.per_node.lowered_by_node",
  )
  let terminal = scope.derived(
    () => {
      dsl_terminal_from_reader(node_count, i => lowered_by_node.get_or_abort(i))
    },
    label="dsl.per_node.terminal",
  )
  let watch = scope.add_watch(terminal.watch())
  dsl_finish_pipeline(node_count, rt, scope, source, watch)
}

///|
fn dsl_sparse_inspector_pipeline(node_count : Int) -> DslAuthoringPipeline {
  let (rt, scope, source) = dsl_pipeline_setup(
    node_count, "dsl.inspector.source",
  )
  let projected = dsl_parse_projection(scope, source, "dsl.inspector")
  let lowered_by_node = dsl_lowered_by_node(
    scope, projected, "dsl.inspector.lowered_by_node",
  )
  let selected = scope.input(0, label="dsl.inspector.selected")
  let panel_scope = scope.child()
  let inspector = panel_scope.reachable_derived(
    () => {
      let index = selected.get()
      let lowered = lowered_by_node.get_or_abort(index)
      { node_count: 1, checksum: dsl_mix(0, lowered, index) }
    },
    label="dsl.inspector.panel",
  )
  let watch = panel_scope.add_watch(inspector.watch())
  dsl_finish_pipeline(node_count, rt, scope, source, watch)
}

///|
fn bench_dsl_pipeline(
  b : @bench.T,
  node_count : Int,
  make_pipeline : (Int) -> DslAuthoringPipeline,
) -> Unit {
  let pipeline = make_pipeline(node_count)
  let mut revision = 0
  b.bench(fn() {
    revision += 1
    pipeline.edit(revision)
    b.keep(pipeline.read())
  })
  pipeline.dispose()
}

///|
fn bench_dsl_coarse(b : @bench.T, node_count : Int) -> Unit {
  bench_dsl_pipeline(b, node_count, dsl_coarse_pipeline)
}

///|
fn bench_dsl_per_node_full(b : @bench.T, node_count : Int) -> Unit {
  bench_dsl_pipeline(b, node_count, dsl_per_node_full_pipeline)
}

///|
fn bench_dsl_sparse_inspector(b : @bench.T, node_count : Int) -> Unit {
  bench_dsl_pipeline(b, node_count, dsl_sparse_inspector_pipeline)
}

///|
test "dsl authoring: coarse staged pipeline 20 nodes" (b : @bench.T) {
  bench_dsl_coarse(b, 20)
}

///|
test "dsl authoring: coarse staged pipeline 100 nodes" (b : @bench.T) {
  bench_dsl_coarse(b, 100)
}

///|
test "dsl authoring: coarse staged pipeline 500 nodes" (b : @bench.T) {
  bench_dsl_coarse(b, 500)
}

///|
test "dsl authoring: coarse staged pipeline 1000 nodes" (b : @bench.T) {
  bench_dsl_coarse(b, 1000)
}

///|
test "dsl authoring: per-node DerivedMap full terminal 20 nodes" (b : @bench.T) {
  bench_dsl_per_node_full(b, 20)
}

///|
test "dsl authoring: per-node DerivedMap full terminal 100 nodes" (b : @bench.T) {
  bench_dsl_per_node_full(b, 100)
}

///|
test "dsl authoring: per-node DerivedMap full terminal 500 nodes" (b : @bench.T) {
  bench_dsl_per_node_full(b, 500)
}

///|
test "dsl authoring: per-node DerivedMap full terminal 1000 nodes" (
  b : @bench.T,
) {
  bench_dsl_per_node_full(b, 1000)
}

///|
test "dsl authoring: ReachableDerived sparse inspector 20 nodes" (b : @bench.T) {
  bench_dsl_sparse_inspector(b, 20)
}

///|
test "dsl authoring: ReachableDerived sparse inspector 100 nodes" (b : @bench.T) {
  bench_dsl_sparse_inspector(b, 100)
}

///|
test "dsl authoring: ReachableDerived sparse inspector 500 nodes" (b : @bench.T) {
  bench_dsl_sparse_inspector(b, 500)
}

///|
test "dsl authoring: ReachableDerived sparse inspector 1000 nodes" (
  b : @bench.T,
) {
  bench_dsl_sparse_inspector(b, 1000)
}
