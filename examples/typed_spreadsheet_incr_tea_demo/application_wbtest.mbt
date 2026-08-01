///|
test "unmounted application dispatches and observes semantic state" {
  let app = match
    TypedSheetApplication::start(@incr.Runtime(), SheetStartMode::Standalone) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  let before = app.observe()
  assert_true(before.lifecycle is Unmounted)
  inspect(before.snapshot.ai_context.selected_cell, content="B1")

  let outcome = match app.dispatch(SelectCell("C1")) {
    Ok(outcome) => outcome
    Err(_) => fail("unmounted dispatch was rejected")
  }
  inspect(outcome.authority_changed, content="false")
  let after = app.observe()
  assert_true(after.lifecycle is Unmounted)
  inspect(after.snapshot.ai_context.selected_cell, content="C1")
  inspect(after.snapshot.status, content="Selected C1.")
  app.dispose()
}

///|
test "committed edit reports an authority change" {
  let app = match
    TypedSheetApplication::start(@incr.Runtime(), SheetStartMode::Standalone) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(UpdateDraft("A1", "12")))
  let outcome = match app.dispatch(ApplySelected) {
    Ok(outcome) => outcome
    Err(_) => fail("unmounted committed edit was rejected")
  }

  inspect(outcome.authority_changed, content="true")
  app.dispose()
}

///|
test "unmounted dispose preserves the final semantic observation" {
  let app = match
    TypedSheetApplication::start(@incr.Runtime(), SheetStartMode::Standalone) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  ignore(app.dispatch(SelectCell("C1")))
  let before = app.observe()
  app.dispose()

  let after = app.observe()
  assert_true(after.lifecycle is Disposed)
  inspect(after.snapshot.ai_context.selected_cell, content="C1")
  inspect(after.snapshot.status, content="Selected C1.")
  inspect(
    after.snapshot.ai_context.to_json().stringify() ==
    before.snapshot.ai_context.to_json().stringify(),
    content="true",
  )
}

///|
test "disposed application rejects dispatch through a typed result" {
  let app = match
    TypedSheetApplication::start(@incr.Runtime(), SheetStartMode::Standalone) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  app.dispose()

  match app.dispatch(SelectCell("C1")) {
    Err(Disposed) => ()
    Err(_) => fail("disposed dispatch returned the wrong lifecycle error")
    Ok(_) => fail("disposed dispatch was accepted")
  }
}

///|
test "application dispose is idempotent" {
  let app = match
    TypedSheetApplication::start(@incr.Runtime(), SheetStartMode::Standalone) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  ignore(app.dispatch(SelectCell("C1")))
  app.dispose()
  let first = app.observe()
  app.dispose()
  let second = app.observe()

  assert_true(second.lifecycle is Disposed)
  inspect(
    second.snapshot.ai_context.to_json().stringify() ==
    first.snapshot.ai_context.to_json().stringify(),
    content="true",
  )
}

///|
test "disposed observations do not alias retained arrays" {
  let app = match
    TypedSheetApplication::start(@incr.Runtime(), SheetStartMode::Standalone) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  ignore(app.dispatch(SelectCell("A1")))
  ignore(app.dispatch(UpdateDraft("A1", "12")))
  ignore(app.dispatch(ApplySelected))
  app.dispose()
  let exposed = app.observe()
  let cell_count = exposed.snapshot.ai_context.cells.length()
  let evidence_count = match exposed.snapshot.ai_context.latest_evidence {
    Some(evidence) => evidence.cells.length()
    None => fail("expected committed-edit evidence")
  }
  exposed.snapshot.ai_context.region.push("MUTATED")
  match exposed.snapshot.ai_context.cells {
    [first, ..] => exposed.snapshot.ai_context.cells.push(first)
    [] => fail("expected bounded AI context cells")
  }
  for cell in exposed.snapshot.ai_context.cells {
    cell.installed_dependencies.push("MUTATED")
    cell.static_references.push("MUTATED")
    cell.last_dynamic_dependencies.push("MUTATED")
  }
  match exposed.snapshot.ai_context.latest_trace {
    Some(trace) => {
      trace.recomputed.push("MUTATED")
      trace.changed.push("MUTATED")
      trace.unchanged.push("MUTATED")
    }
    None => fail("expected committed-edit trace")
  }
  match exposed.snapshot.ai_context.latest_evidence {
    Some(evidence) =>
      match evidence.cells {
        [first, ..] => evidence.cells.push(first)
        [] => fail("expected committed-edit evidence cells")
      }
    None => fail("expected committed-edit evidence")
  }

  let later = app.observe()
  inspect(later.snapshot.ai_context.region.contains("MUTATED"), content="false")
  inspect(later.snapshot.ai_context.cells.length(), content="\{cell_count}")
  inspect(
    later.snapshot.ai_context.cells.any(cell => {
      cell.installed_dependencies.contains("MUTATED") ||
      cell.static_references.contains("MUTATED") ||
      cell.last_dynamic_dependencies.contains("MUTATED")
    }),
    content="false",
  )
  match later.snapshot.ai_context.latest_trace {
    Some(trace) => {
      inspect(trace.recomputed.contains("MUTATED"), content="false")
      inspect(trace.changed.contains("MUTATED"), content="false")
      inspect(trace.unchanged.contains("MUTATED"), content="false")
    }
    None => fail("expected retained committed-edit trace")
  }
  match later.snapshot.ai_context.latest_evidence {
    Some(evidence) =>
      inspect(evidence.cells.length(), content="\{evidence_count}")
    None => fail("expected retained committed-edit evidence")
  }
}

///|
#cfg(target="js")
test "missing host resolution fails before application mutation" {
  install_test_dom()
  let app = match
    TypedSheetApplication::start(@incr.Runtime(), SheetStartMode::Standalone) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }

  match resolve_typed_sheet_hosts("missing") {
    Err(MissingRegion(id)) => inspect(id, content="missing-grid")
    Ok(_) => fail("incomplete host cohort was accepted")
  }
  let observation = app.observe()
  assert_true(observation.lifecycle is Unmounted)
  inspect(observation.region_stats.length(), content="0")
  app.dispose()
  restore_test_dom()
}

///|
#cfg(target="js")
test "application mounts one complete five-region host cohort" {
  install_test_dom()
  create_locality_hosts()
  let app = match
    TypedSheetApplication::start(@incr.Runtime(), SheetStartMode::Standalone) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  match app.flush_presentation() {
    Err(NotMounted) => ()
    _ => fail("unmounted presentation flush was not rejected")
  }
  let hosts = TypedSheetHosts::{
    grid: @tea.dom_get_element_by_id("locality-grid"),
    formula: @tea.dom_get_element_by_id("locality-formula"),
    status: @tea.dom_get_element_by_id("locality-status"),
    trace: @tea.dom_get_element_by_id("locality-trace"),
    evidence: @tea.dom_get_element_by_id("locality-evidence"),
  }
  match app.mount(hosts) {
    Ok(_) => ()
    Err(_) => fail("complete host cohort was rejected")
  }
  let mounted = match app.flush_presentation() {
    Ok(observation) => observation
    Err(_) => fail("mounted presentation flush was rejected")
  }
  assert_true(mounted.lifecycle is Mounted)
  inspect(mounted.region_stats.length(), content="5")
  inspect(
    mounted.region_stats.map(row => row.label).join(","),
    content="formula-bar,grid,status,trace,evidence",
  )
  inspect(
    mounted.region_stats.all(row => {
      row.patch_attempts == 1 && row.skipped_patches == 1
    }),
    content="true",
  )
  match app.mount(hosts) {
    Err(AlreadyMounted) => ()
    _ => fail("second mount was not rejected")
  }
  app.dispose()
  match app.flush_presentation() {
    Err(Disposed) => ()
    _ => fail("disposed presentation flush was not rejected")
  }
  restore_test_dom()
}

///|
test "authority startup failure is returned as an application error" {
  match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Host("room", ReplicaId("")),
    ) {
    Err(AuthorityStartFailed(detail)) =>
      inspect(detail, content="Authority replica ID is empty.")
    Ok(app) => {
      app.dispose()
      fail("invalid authority unexpectedly started")
    }
  }
}
