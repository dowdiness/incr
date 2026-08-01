///|
struct RecordingSessionTransport {
  remote : Ref[
    ((@container.SyncMessage) -> Result[Unit, ApplicationRemoteError])?,
  ]
  failure : Ref[((String) -> Unit)?]
  published : Ref[Array[@container.SyncMessage]]
  stopped : Ref[Bool]
  bind_count : Ref[Int]
  delivery_count : Ref[Int]
  stop_count : Ref[Int]
  fail_on_publish : Ref[String?]
}

///|
fn new_recording_session_transport() -> RecordingSessionTransport {
  {
    remote: Ref(None),
    failure: Ref(None),
    published: Ref([]),
    stopped: Ref(false),
    bind_count: Ref(0),
    delivery_count: Ref(0),
    stop_count: Ref(0),
    fail_on_publish: Ref(None),
  }
}

///|
fn RecordingSessionTransport::stop_delivery(
  self : RecordingSessionTransport,
) -> Unit {
  if !self.stopped.val {
    self.remote.val = None
    self.failure.val = None
    self.stopped.val = true
    self.stop_count.val += 1
  }
}

///|
fn RecordingSessionTransport::port(
  self : RecordingSessionTransport,
) -> SessionTransport {
  SessionTransport::SessionTransport(
    (remote, failure) => {
      self.bind_count.val += 1
      self.remote.val = Some(remote)
      self.failure.val = Some(failure)
    },
    message => {
      if !self.stopped.val {
        self.published.val.push(message)
        match self.fail_on_publish.val {
          Some(error) => {
            self.fail_on_publish.val = None
            ignore(self.fail(error))
          }
          None => ()
        }
      }
    },
    () => self.stop_delivery(),
  )
}

///|
fn RecordingSessionTransport::deliver_remote(
  self : RecordingSessionTransport,
  message : @container.SyncMessage,
) -> Result[Unit, ApplicationRemoteError]? {
  match self.remote.val {
    Some(remote) => {
      self.delivery_count.val += 1
      Some(remote(message))
    }
    None => None
  }
}

///|
fn RecordingSessionTransport::fail(
  self : RecordingSessionTransport,
  error : String,
) -> Bool {
  match self.failure.val {
    Some(failure) => {
      failure(error)
      self.stop_delivery()
      true
    }
    None => false
  }
}

///|
test "session transport publishes committed local edits and stops once" {
  let recording = new_recording_session_transport()
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Host("room", ReplicaId("transport-test")),
      Some(recording.port()),
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Ok(app) => app
    Err(_) => fail("collaborative application failed to start")
  }

  inspect(recording.bind_count.val, content="1")
  inspect(recording.delivery_count.val, content="0")
  inspect(recording.published.val.length(), content="0")
  ignore(app.dispatch(BeginInlineEdit("C1")))
  ignore(app.dispatch(UpdateDraft("C1", "7")))
  ignore(app.dispatch(ApplyInlineEdit("C1")))
  inspect(recording.published.val.length(), content="1")
  ignore(app.dispatch(ResetSheet))
  inspect(recording.published.val.length(), content="1")

  let published = recording.published.val[0]
  app.dispose()
  app.dispose()
  inspect(recording.stop_count.val, content="1")
  inspect(recording.deliver_remote(published) is None, content="true")
  inspect(
    app.apply_remote(published) is Err(ApplicationRemoteError::Disposed),
    content="true",
  )
}

///|
test "synchronous publish failure leaves application local only" {
  let recording = new_recording_session_transport()
  recording.fail_on_publish.val = Some("queue limit exceeded")
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Host("room", ReplicaId("transport-failure")),
      Some(recording.port()),
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Ok(app) => app
    Err(_) => fail("collaborative application failed to start")
  }

  ignore(app.dispatch(BeginInlineEdit("C1")))
  ignore(app.dispatch(UpdateDraft("C1", "7")))
  ignore(app.dispatch(ApplyInlineEdit("C1")))
  match app.observe().collaboration {
    ApplicationCollaborationResult::LocalOnly(error) =>
      inspect(error, content="queue limit exceeded")
    _ => fail("synchronous publish failure did not select local-only mode")
  }
  inspect(
    app.observe().snapshot.status,
    content="Collaboration unavailable; edits are now local only: queue limit exceeded",
  )
  inspect(recording.published.val.length(), content="1")
  inspect(recording.stop_count.val, content="1")
  app.dispose()
  inspect(recording.stop_count.val, content="1")
}

///|
test "session transport applies remote sync without republishing" {
  let host_transport = new_recording_session_transport()
  let host = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Host("room", ReplicaId("transport-host")),
      Some(host_transport.port()),
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Ok(app) => app
    Err(_) => fail("host application failed to start")
  }
  inspect(host_transport.bind_count.val, content="1")
  inspect(host_transport.delivery_count.val, content="0")
  let bootstrap = match host.observe().collaboration {
    ApplicationCollaborationResult::BootstrapReady(bootstrap) => bootstrap
    _ => fail("host bootstrap was not exposed through observation")
  }
  let join_document = @container.Document::new("transport-join")
  ignore(join_document.sync().apply(bootstrap.sync))
  let join_transport = new_recording_session_transport()
  let join = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Join(bootstrap, join_document),
      Some(join_transport.port()),
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Ok(app) => app
    Err(_) => fail("join application failed to start")
  }

  ignore(host.dispatch(BeginInlineEdit("C1")))
  ignore(host.dispatch(UpdateDraft("C1", "7")))
  ignore(host.dispatch(ApplyInlineEdit("C1")))
  guard host_transport.published.val is [sync] else {
    fail("host edit did not publish exactly once")
  }
  inspect(join_transport.deliver_remote(sync) is Some(Ok(_)), content="true")
  inspect(join_transport.published.val.length(), content="0")
  inspect(join.observe().snapshot.status, content="Remote update applied.")
  inspect(join_transport.deliver_remote(sync) is Some(Ok(_)), content="true")
  inspect(join_transport.published.val.length(), content="0")
  inspect(
    join.observe().snapshot.status,
    content="Remote update had no semantic changes.",
  )

  inspect(join_transport.fail("transport failed"), content="true")
  match join.observe().collaboration {
    ApplicationCollaborationResult::LocalOnly(error) =>
      inspect(error, content="transport failed")
    _ => fail("transport failure did not record local-only collaboration")
  }
  ignore(join.dispatch(BeginInlineEdit("C1")))
  ignore(join.dispatch(UpdateDraft("C1", "8")))
  ignore(join.dispatch(ApplyInlineEdit("C1")))
  inspect(join_transport.published.val.length(), content="0")

  join.dispose()
  host.dispose()
  inspect(join_transport.stop_count.val, content="1")
  inspect(host_transport.stop_count.val, content="1")
}

///|
test "unmounted application dispatches and observes semantic state" {
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
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
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
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
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
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
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
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
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
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
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
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
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
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
test "AI context publishes initially and after mounted flush" {
  install_test_dom()
  create_locality_hosts()
  let published : Ref[Array[@demo.AiContextSnapshot]] = Ref([])
  let publisher = AiContextPublisher::AiContextPublisher(snapshot => {
    published.val.push(snapshot)
  })
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      publisher,
    ) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  let hosts = match resolve_typed_sheet_hosts("locality") {
    Ok(hosts) => hosts
    Err(_) => fail("complete host cohort was rejected")
  }
  ignore(app.mount(hosts))
  guard published.val is [initial] else {
    fail("initial mount did not publish exactly once")
  }
  inspect(initial.selected_cell, content="B1")

  ignore(app.dispatch(SelectCell("C1")))
  inspect(published.val.length(), content="1")
  ignore(app.flush_presentation())
  guard published.val is [_, after_flush] else {
    fail("mounted dispatch did not publish exactly once after flush")
  }
  inspect(after_flush.selected_cell, content="C1")
  app.dispose()
  restore_test_dom()
}

///|
#cfg(target="js")
test "unmounted dispatch publishes through queued flush then initial mount" {
  install_test_dom()
  create_locality_hosts()
  let published : Ref[Array[@demo.AiContextSnapshot]] = Ref([])
  let publisher = AiContextPublisher::AiContextPublisher(snapshot => {
    published.val.push(snapshot)
  })
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      publisher,
    ) {
    Ok(app) => app
    Err(_) => fail("standalone application failed to start")
  }
  ignore(app.dispatch(SelectCell("C1")))
  inspect(published.val.length(), content="0")
  inspect(app.observe().snapshot.ai_context.selected_cell, content="C1")
  let hosts = match resolve_typed_sheet_hosts("locality") {
    Ok(hosts) => hosts
    Err(_) => fail("complete host cohort was rejected")
  }
  ignore(app.mount(hosts))

  inspect(published.val.length(), content="2")
  inspect(
    published.val.all(snapshot => snapshot.selected_cell == "C1"),
    content="true",
  )
  app.dispose()
  restore_test_dom()
}

///|
#cfg(target="js")
test "application mounts one complete five-region host cohort" {
  install_test_dom()
  create_locality_hosts()
  let app = match
    TypedSheetApplication::start(
      @incr.Runtime(),
      SheetStartMode::Standalone,
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
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
      None,
      AiContextPublisher::AiContextPublisher(_ => ()),
    ) {
    Err(AuthorityStartFailed(detail)) =>
      inspect(detail, content="Authority replica ID is empty.")
    Ok(app) => {
      app.dispose()
      fail("invalid authority unexpectedly started")
    }
  }
}
