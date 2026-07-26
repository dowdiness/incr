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
  {
    schema_version: 1,
    selected_cell: self.selected_cell,
    max_cells: limit,
    truncated,
    region: bounded_region,
    cells: bounded_region.map(cell => self.ai_context_cell(cell)),
    latest_trace: self.latest_ai_context_trace(limit),
    latest_evidence: self.latest_ai_context_evidence(limit),
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
  let json = self.ai_context_json()
  @rabbita_cmd.custom_cmd(
    fn(_) { js_publish_ai_context_json(json) },
    kind=@rabbita_cmd.after_render,
  )
}

///|
fn Model::publish_ai_context(self : Model) -> Unit {
  js_publish_ai_context_json(self.ai_context_json())
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
  let formula = match snapshot.kind {
    Some(Formula) =>
      Some(
        @demo.ai_context_formula(
          committed_text,
          self.sheet.formula_ast(snapshot.id),
        ),
      )
    _ => None
  }
  @demo.ai_context_cell(cell, committed_text, draft_text, snapshot, formula)
}

///|
fn Model::latest_ai_context_trace(
  self : Model,
  max_items : Int,
) -> @demo.AiContextTrace? {
  match self.last_step {
    Some(step) =>
      Some(
        @demo.worksheet_step_ai_context_trace(self.last_edit, step, max_items),
      )
    None => None
  }
}

///|
fn Model::latest_ai_context_evidence(
  self : Model,
  max_items : Int,
) -> @demo.AiContextEvidence? {
  match self.last_step {
    Some(step) =>
      Some(
        @demo.worksheet_step_ai_context_evidence(
          self.last_edit,
          step,
          max_items,
        ),
      )
    None => None
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
