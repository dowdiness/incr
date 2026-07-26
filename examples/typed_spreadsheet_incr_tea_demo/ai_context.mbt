///|
/// Returns a deterministic, bounded AI/tool context for the incr_tea editor.
fn SheetState::ai_context_snapshot(
  self : SheetState,
  region? : Array[String],
  max_cells? : Int = 64,
) -> @demo.AiContextSnapshot {
  let selected_cell = self.selected_cell.peek()
  let source = match region {
    Some(requested) => requested
    None => self.default_ai_context_region()
  }
  let (limit, bounded, truncated) = @demo.bounded_ai_context_region(
    selected_cell, source, max_cells,
  )
  {
    schema_version: 1,
    selected_cell,
    max_cells: limit,
    truncated,
    region: bounded,
    cells: bounded.map(cell => self.ai_context_cell(cell)),
    latest_trace: self.latest_ai_context_trace(limit),
    latest_evidence: self.latest_ai_context_evidence(limit),
  }
}

///|
/// Serializes the current bounded AI/tool context as stable JSON.
fn SheetState::ai_context_json(
  self : SheetState,
  region? : Array[String],
  max_cells? : Int = 64,
) -> String {
  self.ai_context_snapshot(region?, max_cells~).to_json().stringify(indent=2)
}

///|
fn SheetState::default_ai_context_region(self : SheetState) -> Array[String] {
  let selected = self.selected_cell.peek()
  let snapshot = self.adapter.inspect_cell(selected)
  let cells = snapshot.static_references.map(@demo.cell_id_to_string)
  match self.trace.peek() {
    Some(trace) =>
      [..cells, ..trace.recomputed, ..trace.changed, ..trace.unchanged]
    None => cells
  }
}

///|
fn SheetState::ai_context_cell(
  self : SheetState,
  cell : String,
) -> @demo.AiContextCell {
  let snapshot = self.adapter.inspect_cell(cell)
  let committed_text = draft_text_from(self.committed.peek(), cell)
  let draft_text = draft_text_from(self.drafts.peek(), cell)
  let formula = match snapshot.kind {
    Some(Formula) =>
      Some(
        @demo.ai_context_formula(committed_text, self.adapter.formula_ast(cell)),
      )
    _ => None
  }
  @demo.ai_context_cell(cell, committed_text, draft_text, snapshot, formula)
}

///|
fn SheetState::latest_ai_context_trace(
  self : SheetState,
  max_items : Int,
) -> @demo.AiContextTrace? {
  match self.trace.peek() {
    Some(trace) =>
      Some(
        @demo.ai_context_trace(
          self.last_edit.peek(),
          trace.outcome,
          trace.recomputed,
          trace.changed,
          trace.unchanged,
          max_items,
        ),
      )
    None => None
  }
}

///|
fn SheetState::latest_ai_context_evidence(
  self : SheetState,
  max_items : Int,
) -> @demo.AiContextEvidence? {
  match self.evidence.peek() {
    Some(evidence) =>
      Some(
        @demo.ai_context_evidence(
          evidence.edit,
          evidence.outcome,
          evidence.cells,
          max_items,
        ),
      )
    None => None
  }
}

///|
fn publish_ai_context_cmd(state : Ref[SheetState]) -> @tea.Cmd[Msg] {
  @tea.Cmd::after_flush(_ => {
    js_publish_ai_context_json(state.val.ai_context_json())
  })
}

///|
#cfg(target="js")
extern "js" fn js_publish_ai_context_json(json : String) -> Unit =
  #| function(json) {
  #|   var parsed = JSON.parse(json);
  #|   globalThis.__typedSpreadsheetAIContext = parsed;
  #|   globalThis.typedSpreadsheetAIContext = function() { return JSON.parse(json); };
  #|   globalThis.typedSpreadsheetAIContextJson = function() { return json; };
  #| }
