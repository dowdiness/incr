// Cycle detection is handled by the in_progress flag on CellMeta.
// When maybe_changed_after encounters a cell already in_progress,
// it aborts. Future versions may support recovery via a CycleError type.
