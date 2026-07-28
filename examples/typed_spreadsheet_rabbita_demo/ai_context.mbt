///|
/// Serializable AI/tool context for the editable typed spreadsheet demo.

///|
/// Returns a deterministic, bounded AI/tool context for this editor model.
pub fn Model::ai_context_snapshot(
  self : Model,
  region? : Array[String],
  max_cells? : Int = 64,
) -> @demo.AiContextSnapshot {
  let source = match region {
    Some(requested) => requested
    None => default_ai_context_region(self)
  }
  let (limit, bounded_region, truncated) = @demo.bounded_ai_context_region(
    self.selected_cell,
    source,
    max_cells,
  )
  let (latest_trace, latest_evidence) = self.latest_ai_context_history(limit)
  {
    schema_version: 3,
    selected_cell: self.selected_cell,
    max_cells: limit,
    truncated,
    region: bounded_region,
    cells: bounded_region.map(cell => self.ai_context_cell(cell)),
    latest_trace,
    latest_evidence,
  }
}

///|
/// Serializes `Model::ai_context_snapshot` as stable indented JSON.
pub fn Model::ai_context_json(
  self : Model,
  region? : Array[String],
  max_cells? : Int = 64,
) -> String {
  self.ai_context_snapshot(region?, max_cells~).to_json().stringify(indent=2)
}

///|
fn Model::publish_ai_context_cmd(self : Model) -> @rabbita.Cmd {
  let json = self.cached_ai_context_json()
  @rabbita_cmd.custom_cmd(
    fn(_) { js_publish_ai_context_json(json) },
    kind=@rabbita_cmd.after_render,
  )
}

///|
fn Model::publish_ai_context(self : Model) -> Unit {
  js_publish_ai_context_json(self.cached_ai_context_json())
}

///|
fn Model::cached_ai_context_json(self : Model) -> String {
  match self.explanation_frame {
    Some(frame) => frame.context.to_json().stringify(indent=2)
    None => self.ai_context_json()
  }
}

///|
fn default_ai_context_region(model : Model) -> Array[String] {
  let observed = model.grid_snapshot_cache.keys().to_array()
  observed.sort()
  observed
}

///|
fn Model::ai_context_cell(self : Model, cell : String) -> @demo.AiContextCell {
  let id = cell_id(self, cell)
  let snapshot = self.sheet.inspect_cell(id)
  let committed_text = committed_for(self, cell)
  let draft_text = draft_for(self, cell)
  let formula_ast = match snapshot.kind {
    Some(Formula) => Some(self.sheet.formula_ast(snapshot.id))
    _ => None
  }
  @demo.ai_context_cell(cell, committed_text, draft_text, snapshot, formula_ast)
}

///|
fn Model::latest_ai_context_history(
  self : Model,
  max_items : Int,
) -> (@demo.AiContextTrace?, @demo.AiContextEvidence?) {
  match self.last_step {
    Some(step) => {
      let (trace, evidence) = @demo.worksheet_step_ai_context_history(
        self.last_edit,
        step,
        max_items,
      )
      (Some(trace), Some(evidence))
    }
    None => (None, None)
  }
}

///|
fn Model::refresh_explanation(self : Model) -> Model {
  let snapshot = self.ai_context_snapshot()
  let current = match @demo.explain_cell(snapshot, self.selected_cell) {
    Ok(answer) => answer
    Err(_) => abort("selected cell missing from its explanation context")
  }
  {
    ..self,
    explanation_frame: Some({
      context: snapshot,
      current,
      last_change: @demo.explain_last_change(snapshot, self.selected_cell),
    }),
  }
}

///|
extern "js" fn js_publish_ai_context_json(json : String) -> Unit =
  #| function(json) {
  #|   var parsed = JSON.parse(json);
  #|   globalThis.__typedSpreadsheetAIContext = parsed;
  #|   globalThis.typedSpreadsheetAIContext = function() { return JSON.parse(json); };
  #|   globalThis.typedSpreadsheetAIContextJson = function() { return json; };
  #| }
