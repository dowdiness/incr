///|
fn view_model(model : Model) -> @tea.Html[Msg] {
  @tea.div(attrs=[@tea.class_attr("proof-shell")], [
    view_header(),
    view_formula_bar(model),
    view_sheet(model),
    view_status(model),
    view_trace(model),
  ])
}

///|
fn view_header() -> @tea.Html[Msg] {
  @tea.node("header", attrs=[@tea.class_attr("proof-header")], [
    @tea.div(attrs=[@tea.class_attr("proof-kicker")], [
      @tea.text("side-by-side proof · incr_tea"),
    ]),
    @tea.h2([@tea.text("Typed spreadsheet interactions")]),
    @tea.p(attrs=[@tea.class_attr("proof-copy")], [
      @tea.text(
        "A small representative grid validates pure Html event descriptors, mount-boundary payload resolvers, and post-render inline focus. The Rabbita demo remains the live primary spreadsheet.",
      ),
    ]),
  ])
}

///|
fn view_formula_bar(model : Model) -> @tea.Html[Msg] {
  let draft = draft_for(model, model.selected_cell)
  @tea.node(
    "form",
    attrs=@tea.Attrs::build()
      .class("formula-bar")
      .attr("aria-label", "Formula editor")
      .to_array(),
    events=[@tea.on_submit(ApplySelected)],
    [
      @tea.div(attrs=[@tea.class_attr("formula-cell")], [
        @tea.span(attrs=[@tea.class_attr("muted-label")], [@tea.text("cell")]),
        @tea.span(attrs=[@tea.class_attr("cell-address")], [
          @tea.text(model.selected_cell),
        ]),
      ]),
      @tea.node(
        "label",
        attrs=@tea.Attrs::build()
          .class("sr-only")
          .attr("for", "formula-editor-input")
          .to_array(),
        [@tea.text("Edit \{model.selected_cell}")],
      ),
      @tea.input(
        attrs=@tea.Attrs::build()
          .attr("id", "formula-editor-input")
          .class("formula-input")
          .value(draft)
          .placeholder("10 or =A1")
          .attr("inputmode", "text")
          .attr("aria-label", "Formula text for \{model.selected_cell}")
          .to_array(),
        events=[
          @tea.on_input(tag=input_tag(model.selected_cell)),
          @tea.on_keydown(id=formula_key_id()),
        ],
      ),
      @tea.div(attrs=[@tea.class_attr("formula-actions")], [
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("primary-action")
            .attr("type", "submit")
            .to_array(),
          "Apply",
        ),
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("quiet-button")
            .attr("type", "button")
            .to_array(),
          events=[@tea.on_click(CancelSelected)],
          "Cancel",
        ),
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("quiet-button danger-action")
            .attr("type", "button")
            .to_array(),
          events=[@tea.on_click(DeleteSelected)],
          "Delete",
        ),
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("quiet-button")
            .attr("type", "button")
            .to_array(),
          events=[@tea.on_click(ResetSheet)],
          "Reset proof",
        ),
      ]),
      view_examples(),
    ],
  )
}

///|
fn view_examples() -> @tea.Html[Msg] {
  let examples = ["10", "15", "=A1", "=A1 + 1", "=A1 * 2"]
  @tea.div(attrs=[@tea.class_attr("example-strip")], [
    @tea.span(attrs=[@tea.class_attr("muted-label")], [@tea.text("examples")]),
    @tea.div(
      attrs=[@tea.class_attr("example-chips")],
      examples.map(example => {
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("example-chip")
            .attr("type", "button")
            .to_array(),
          events=[@tea.on_click(UseExample(example))],
          example,
        )
      }),
    ),
  ])
}

///|
fn view_sheet(model : Model) -> @tea.Html[Msg] {
  let children = [@tea.div(attrs=[@tea.class_attr("sheet-corner")], [])]
  for column in column_labels() {
    children.push(view_column_header(column))
  }
  for row in 1..<=grid_row_count() {
    children.push(view_row_header("\{row}"))
    for column_index, column in column_labels() {
      let cell = "\{column}\{row}"
      children.push(view_grid_cell(model, cell, row, column_index + 1))
    }
  }
  @tea.node("section", attrs=[@tea.class_attr("sheet-stage")], [
    @tea.div(
      attrs=@tea.Attrs::build()
        .attr("id", "sheet-grid")
        .class("sheet-grid")
        .role("grid")
        .attr("tabindex", "0")
        .attr("aria-label", "4 by 4 typed spreadsheet proof grid")
        .attr("aria-activedescendant", "cell-" + model.selected_cell)
        .to_array(),
      events=grid_events(model),
      children,
    ),
  ])
}

///|
fn grid_events(model : Model) -> Array[@tea.EventBinding[Msg]] {
  match model.editing_cell {
    Some(_) => []
    None => [@tea.on_keydown(id=grid_key_id())]
  }
}

///|
fn view_column_header(label : String) -> @tea.Html[Msg] {
  @tea.div(
    attrs=@tea.Attrs::build()
      .class("sheet-column-header")
      .role("columnheader")
      .to_array(),
    [@tea.text(label)],
  )
}

///|
fn view_row_header(label : String) -> @tea.Html[Msg] {
  @tea.div(
    attrs=@tea.Attrs::build()
      .class("sheet-row-header")
      .role("rowheader")
      .to_array(),
    [@tea.text(label)],
  )
}

///|
fn view_grid_cell(
  model : Model,
  cell : String,
  row_index : Int,
  column_index : Int,
) -> @tea.Html[Msg] {
  let snapshot = model.sheet.inspect_cell(cell_id(model, cell))
  let selected = model.selected_cell == cell
  let editing = model.editing_cell == Some(cell)
  let dirty = draft_is_dirty(model, cell)
  let class_name = grid_cell_class(snapshot, selected, dirty, editing)
  @tea.div(
    attrs=@tea.Attrs::build()
      .attr("id", "cell-" + cell)
      .class(class_name)
      .role("gridcell")
      .attr("data-cell", cell)
      .attr("aria-selected", if selected { "true" } else { "false" })
      .attr("aria-rowindex", "\{row_index}")
      .attr("aria-colindex", "\{column_index}")
      .attr("aria-label", grid_cell_label(cell, snapshot))
      .to_array(),
    events=if editing {
      []
    } else {
      [
        @tea.on_click(SelectCell(cell)),
        @tea.on_dblclick(
          BeginInlineEdit(cell),
          prevent_default=true,
          stop_propagation=true,
        ),
      ]
    },
    [view_cell_content(model, cell, snapshot, editing)],
  )
}

///|
fn view_cell_content(
  model : Model,
  cell : String,
  snapshot : @typed_spreadsheet.CellSnapshot,
  editing : Bool,
) -> @tea.Html[Msg] {
  if editing {
    @tea.input(
      attrs=@tea.Attrs::build()
        .attr("id", inline_editor_id(cell))
        .class("cell-inline-input")
        .value(draft_for(model, cell))
        .attr("inputmode", "text")
        .attr("aria-label", "Edit \{cell} directly")
        .to_array(),
      events=[
        @tea.on_input(tag=input_tag(cell)),
        @tea.on_keydown(id=inline_key_id(cell)),
        @tea.on_blur(ApplyInlineEdit(cell)),
      ],
    )
  } else {
    @tea.span(attrs=[@tea.class_attr("cell-value")], [
      @tea.text(cell_result_text(snapshot.result)),
    ])
  }
}

///|
fn grid_cell_class(
  snapshot : @typed_spreadsheet.CellSnapshot,
  selected : Bool,
  dirty : Bool,
  editing : Bool,
) -> String {
  let parts = [
    "sheet-cell",
    "sheet-cell--" + cell_result_class(snapshot.result),
  ]
  if selected {
    parts.push("is-selected")
  }
  if dirty {
    parts.push("is-dirty")
  }
  if editing {
    parts.push("is-editing")
  }
  parts.join(" ")
}

///|
fn grid_cell_label(
  cell : String,
  snapshot : @typed_spreadsheet.CellSnapshot,
) -> String {
  let value = cell_result_text(snapshot.result)
  let kind = snapshot_kind_text(snapshot)
  if value.is_empty() {
    "Select cell \{cell}: \{kind}, blank"
  } else {
    "Select cell \{cell}: \{kind}, \{value}"
  }
}

///|
fn view_status(model : Model) -> @tea.Html[Msg] {
  @tea.div(attrs=[@tea.class_attr("status-panel")], [
    @tea.div(attrs=[@tea.class_attr("status-line")], [@tea.text(model.status)]),
    match model.error {
      Some(error) =>
        @tea.div(attrs=[@tea.class_attr("error-line")], [@tea.text(error)])
      None =>
        @tea.div(attrs=[@tea.class_attr("hint-line")], [
          @tea.text(
            "Double-click a cell for inline edit. Enter applies; Escape cancels.",
          ),
        ])
    },
  ])
}

///|
fn view_trace(model : Model) -> @tea.Html[Msg] {
  match model.trace_data {
    None =>
      @tea.node(
        "aside",
        attrs=[@tea.class_attr("trace-panel trace-panel--empty")],
        [
          @tea.h3([@tea.text("Trace")]),
          @tea.p([@tea.text("No user edit has been applied in this proof yet.")]),
        ],
      )
    Some(td) =>
      @tea.node("aside", attrs=[@tea.class_attr("trace-panel")], [
        @tea.h3([@tea.text("Latest edit")]),
        @tea.p(attrs=[@tea.class_attr("trace-edit")], [
          @tea.text(model.last_edit),
        ]),
        view_trace_bucket("recomputed", td.recomputed_str),
        view_trace_bucket("changed", td.changed_str),
        view_trace_bucket("unchanged", td.unchanged_str),
        @tea.p(attrs=[@tea.class_attr("snapshot-count")], [
          @tea.text("Evidence snapshots: \{td.snapshot_count}"),
        ]),
      ])
  }
}

///|
fn view_trace_bucket(label : String, value : String) -> @tea.Html[Msg] {
  @tea.div(attrs=[@tea.class_attr("trace-bucket")], [
    @tea.span(attrs=[@tea.class_attr("muted-label")], [@tea.text(label)]),
    @tea.span(attrs=[@tea.class_attr("trace-values")], [@tea.text(value)]),
  ])
}

///|
fn state_formula_bar(state : SheetState) -> @tea.Html[Msg] {
  let cell = state.selected_cell.get()
  let current_drafts = state.drafts.get()
  let draft = draft_text_from(current_drafts, cell)
  @tea.node(
    "form",
    attrs=@tea.Attrs::build()
      .class("formula-bar")
      .attr("aria-label", "Formula editor")
      .to_array(),
    events=[@tea.on_submit(ApplySelected)],
    [
      @tea.div(attrs=[@tea.class_attr("formula-cell")], [
        @tea.span(attrs=[@tea.class_attr("muted-label")], [@tea.text("cell")]),
        @tea.span(attrs=[@tea.class_attr("cell-address")], [@tea.text(cell)]),
      ]),
      @tea.node(
        "label",
        attrs=@tea.Attrs::build()
          .class("sr-only")
          .attr("for", "formula-editor-input")
          .to_array(),
        [@tea.text("Edit \{cell}")],
      ),
      @tea.input(
        attrs=@tea.Attrs::build()
          .attr("id", "formula-editor-input")
          .class("formula-input")
          .value(draft)
          .placeholder("10 or =A1")
          .attr("inputmode", "text")
          .attr("aria-label", "Formula text for \{cell}")
          .to_array(),
        events=[
          @tea.on_input(tag=input_tag(cell)),
          @tea.on_keydown(id=formula_key_id()),
        ],
      ),
      @tea.div(attrs=[@tea.class_attr("formula-actions")], [
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("primary-action")
            .attr("type", "submit")
            .to_array(),
          "Apply",
        ),
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("quiet-button")
            .attr("type", "button")
            .to_array(),
          events=[@tea.on_click(CancelSelected)],
          "Cancel",
        ),
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("quiet-button danger-action")
            .attr("type", "button")
            .to_array(),
          events=[@tea.on_click(DeleteSelected)],
          "Delete",
        ),
        @tea.button(
          attrs=@tea.Attrs::build()
            .class("quiet-button")
            .attr("type", "button")
            .to_array(),
          events=[@tea.on_click(ResetSheet)],
          "Reset proof",
        ),
      ]),
      view_examples(),
    ],
  )
}

///|
fn state_grid(state : SheetState) -> @tea.Html[Msg] {
  let cells = state.cells.get()
  let selected_cell = state.selected_cell.get()
  let editing_cell = state.editing_cell.get()
  let current_drafts = state.drafts.get()
  let current_committed = state.committed.get()
  let children = [@tea.div(attrs=[@tea.class_attr("sheet-corner")], [])]
  for column in column_labels() {
    children.push(view_column_header(column))
  }
  for row in 1..<=grid_row_count() {
    children.push(view_row_header("\{row}"))
    for column_index, column in column_labels() {
      let cell = "\{column}\{row}"
      let snapshot = state.sheet.inspect_cell(
        cell_id_from_sheet(state.sheet, cell),
      )
      let selected = selected_cell == cell
      let editing = editing_cell == Some(cell)
      let dirty = draft_text_from(current_drafts, cell) !=
        draft_text_from(current_committed, cell)
      let class_name = grid_cell_class(snapshot, selected, dirty, editing)
      children.push(
        @tea.div(
          attrs=@tea.Attrs::build()
            .attr("id", "cell-" + cell)
            .class(class_name)
            .role("gridcell")
            .attr("data-cell", cell)
            .attr("aria-selected", if selected { "true" } else { "false" })
            .attr("aria-rowindex", "\{row}")
            .attr("aria-colindex", "\{column_index + 1}")
            .attr("aria-label", grid_cell_label(cell, snapshot))
            .to_array(),
          events=if editing_cell is Some(_) {
            []
          } else {
            [
              @tea.on_click(SelectCell(cell)),
              @tea.on_dblclick(
                BeginInlineEdit(cell),
                prevent_default=true,
                stop_propagation=true,
              ),
            ]
          },
          [
            if editing {
              @tea.input(
                attrs=@tea.Attrs::build()
                  .attr("id", inline_editor_id(cell))
                  .class("cell-inline-input")
                  .value(draft_text_from(current_drafts, cell))
                  .attr("inputmode", "text")
                  .attr("aria-label", "Edit \{cell} directly")
                  .to_array(),
                events=[
                  @tea.on_input(tag=input_tag(cell)),
                  @tea.on_keydown(id=inline_key_id(cell)),
                  @tea.on_blur(ApplyInlineEdit(cell)),
                ],
              )
            } else {
              @tea.span(attrs=[@tea.class_attr("cell-value")], [
                @tea.text(cell_result_text(snapshot.result)),
              ])
            },
          ],
        ),
      )
    }
  }
  @tea.node("section", attrs=[@tea.class_attr("sheet-stage")], [
    @tea.div(
      attrs=@tea.Attrs::build()
        .attr("id", "sheet-grid")
        .class("sheet-grid")
        .role("grid")
        .attr("tabindex", "0")
        .attr("aria-label", "4 by 4 typed spreadsheet proof grid")
        .attr("aria-activedescendant", "cell-" + selected_cell)
        .to_array(),
      events=if editing_cell is Some(_) {
        []
      } else {
        [@tea.on_keydown(id=grid_key_id())]
      },
      children,
    ),
  ])
}

///|
fn state_status(state : SheetState) -> @tea.Html[Msg] {
  let status_text = state.status.get()
  let error_val = state.error.get()
  @tea.div(attrs=[@tea.class_attr("status-panel")], [
    @tea.div(attrs=[@tea.class_attr("status-line")], [@tea.text(status_text)]),
    match error_val {
      Some(error) =>
        @tea.div(attrs=[@tea.class_attr("error-line")], [@tea.text(error)])
      None =>
        @tea.div(attrs=[@tea.class_attr("hint-line")], [
          @tea.text(
            "Double-click a cell for inline edit. Enter applies; Escape cancels.",
          ),
        ])
    },
  ])
}

///|
fn state_trace(state : SheetState) -> @tea.Html[Msg] {
  match state.trace.get() {
    None =>
      @tea.node(
        "aside",
        attrs=[@tea.class_attr("trace-panel trace-panel--empty")],
        [
          @tea.h3([@tea.text("Trace")]),
          @tea.p([@tea.text("No user edit has been applied in this proof yet.")]),
        ],
      )
    Some(td) =>
      @tea.node("aside", attrs=[@tea.class_attr("trace-panel")], [
        @tea.h3([@tea.text("Latest edit")]),
        @tea.p(attrs=[@tea.class_attr("trace-edit")], [
          @tea.text(state.last_edit.get()),
        ]),
        view_trace_bucket("recomputed", td.recomputed_str),
        view_trace_bucket("changed", td.changed_str),
        view_trace_bucket("unchanged", td.unchanged_str),
        @tea.p(attrs=[@tea.class_attr("snapshot-count")], [
          @tea.text("Evidence snapshots: \{td.snapshot_count}"),
        ]),
      ])
  }
}
