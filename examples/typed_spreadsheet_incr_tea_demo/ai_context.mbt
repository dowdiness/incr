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
  let (latest_trace, latest_evidence) = self.latest_ai_context_history(limit)
  {
    schema_version: 3,
    selected_cell,
    max_cells: limit,
    truncated,
    region: bounded,
    cells: bounded.map(cell => self.ai_context_cell(cell)),
    latest_trace,
    latest_evidence,
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
  let formula_ast = match snapshot.kind {
    Some(Formula) => Some(self.adapter.formula_ast(cell))
    _ => None
  }
  @demo.ai_context_cell(cell, committed_text, draft_text, snapshot, formula_ast)
}

///|
fn SheetState::latest_ai_context_history(
  self : SheetState,
  max_items : Int,
) -> (@demo.AiContextTrace?, @demo.AiContextEvidence?) {
  match (self.trace.peek(), self.evidence.peek()) {
    (Some(trace), Some(evidence)) => {
      let edit = self.last_edit.peek()
      if trace.outcome != evidence.outcome || edit != evidence.edit {
        abort("AI context trace and evidence history diverged")
      }
      let (bounded_trace, bounded_evidence) = @demo.ai_context_history(
        edit,
        trace.outcome,
        trace.recomputed,
        trace.changed,
        trace.unchanged,
        evidence.cells,
        max_items,
      )
      (Some(bounded_trace), Some(bounded_evidence))
    }
    (None, None) => (None, None)
    _ => abort("AI context trace and evidence presence diverged")
  }
}

///|
fn publish_ai_context_now(
  state : Ref[SheetState],
  publisher : AiContextPublisher,
) -> Unit {
  (publisher.publish)(state.val.ai_context_snapshot())
}

///|
fn publish_ai_context_cmd(
  state : Ref[SheetState],
  publisher : AiContextPublisher,
) -> @tea.Cmd[Msg] {
  @tea.Cmd::after_flush(_ => publish_ai_context_now(state, publisher))
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
