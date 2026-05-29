///|
priv struct TextScenario {
  steps : Array[@demo.WorksheetStepResult]
}

///|
impl Show for TextScenario with fn output(self, logger) {
  write_line(logger, "typed spreadsheet demo scenario")
  write_line(
    logger, "trace buckets summarize formula cells after each operation",
  )
  for index, step in self.steps {
    let step_number = index + 1
    let operation = format_op(step.operation)
    write_line(logger, "")
    write_line(logger, "#\{step_number} \{operation}")
    write_line(logger, "outcome: \{format_outcome(step.outcome)}")
    write_line(logger, "trace:")
    write_line(
      logger,
      "  recomputed: \{format_cell_ids(step.trace.recomputed)}",
    )
    write_line(logger, "  changed: \{format_cell_ids(step.trace.changed)}")
    write_line(logger, "  unchanged: \{format_cell_ids(step.trace.unchanged)}")
    write_line(logger, "snapshots:")
    for change in step.cell_snapshots {
      write_snapshot_change(logger, change)
    }
  }
}

///|
fn render_text(steps : Array[@demo.WorksheetStepResult]) -> String {
  TextScenario::{ steps, }.to_string()
}

///|
fn write_snapshot_change(
  logger : &Logger,
  change : @demo.CellSnapshotChange,
) -> Unit {
  let id = cell_id_to_string(change.id)
  write_line(logger, "  \{id}:")
  write_line(logger, "    before: \{format_snapshot(change.before)}")
  write_line(logger, "    after:  \{format_snapshot(change.after)}")
}

///|
fn write_line(logger : &Logger, line : String) -> Unit {
  logger.write_string(line)
  logger.write_char('\n')
}
