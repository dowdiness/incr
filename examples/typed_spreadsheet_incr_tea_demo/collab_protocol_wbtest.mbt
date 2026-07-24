///|
/// A tiny sync message fixture for protocol and reducer tests.
fn protocol_sync() -> @container.SyncMessage raise @container.DocumentError {
  let document = @container.Document::new("protocol-host")
  ignore(document.create_node(parent=@container.root_id))
  document.sync().export_all()
}

///|
fn protocol_bootstrap(
  target : PeerId,
  source : PeerId,
) -> CollabMessage raise @container.DocumentError {
  let document = @container.Document::new("protocol-host")
  let node = document.create_node(parent=@container.root_id)
  CollabMessage::Bootstrap(
    target,
    source,
    @core.CollaborativeSheetId::CollaborativeSheetId("room"),
    @typed_spreadsheet.SheetId(1),
    @domain.DocumentGeneration::initial(),
    node,
    document.sync().export_all(),
  )
}

///|
test "startup parsing rejects malformed collab config without fallback" {
  assert_true(parse_startup("/") is Ok(StartupMode::Standalone))
  assert_true(parse_startup("/collab?role=host&room=room&peer=A") is Ok(_))
  assert_true(parse_startup("/collab?role=join&room=room&peer=B") is Ok(_))
  assert_true(parse_startup("/collab?role=host&room=&peer=A") is Err(_))
  assert_true(parse_startup("/collab?role=host&room=room&peer=") is Err(_))
  assert_true(parse_startup("/collab?role=invalid&room=room&peer=A") is Err(_))
  assert_true(parse_startup("/collab?role=join&room=room") is Err(_))
}

///|
test "tagged JSON protocol roundtrips nested sync" {
  let join = CollabMessage::Join(PeerId("joiner"))
  match message_from_json(message_to_json(join)) {
    Ok(CollabMessage::Join(peer)) => assert_eq(peer.0, "joiner")
    _ => fail("join did not roundtrip")
  }
  let ops = CollabMessage::Ops(
    PeerId("joiner"),
    PeerId("host"),
    protocol_sync(),
  )
  match message_from_json(message_to_json(ops)) {
    Ok(CollabMessage::Ops(target, source, _)) => {
      assert_eq(target.0, "joiner")
      assert_eq(source.0, "host")
    }
    _ => fail("ops did not roundtrip")
  }
  let bootstrap = protocol_bootstrap(PeerId("joiner"), PeerId("host"))
  match (bootstrap, message_from_json(message_to_json(bootstrap))) {
    (
      CollabMessage::Bootstrap(
        expected_target,
        expected_source,
        expected_identity,
        _,
        _,
        expected_node,
        expected_sync
      ),
      Ok(CollabMessage::Bootstrap(target, source, identity, _, _, node, sync)),
    ) => {
      assert_eq(target, expected_target)
      assert_eq(source, expected_source)
      assert_eq(identity.value(), expected_identity.value())
      assert_eq(node, expected_node)
      assert_eq(sync.to_canonical_bytes(), expected_sync.to_canonical_bytes())
    }
    _ => fail("bootstrap did not roundtrip")
  }
  assert_true(message_from_json("not json") is Err(_))
  assert_true(message_from_json("[\"other/1\",\"join\",\"x\"]") is Err(_))
}

///|
test "reducer ignores wrong target duplicate bootstrap and pre-attach ops" {
  let host = PeerId("host")
  let joiner = PeerId("joiner")
  let initial = CollabState::join(joiner)
  let wrong = protocol_bootstrap(PeerId("other"), host)
  let (after_wrong, decision_wrong) = reduce_collab(
    initial,
    CollabEvent::Incoming(wrong),
  )
  assert_true(decision_wrong is CollabDecision::NoEffect)
  assert_true(after_wrong.phase is CollabPhase::AwaitingBootstrap)
  let bootstrap = protocol_bootstrap(joiner, host)
  let (attaching, decision_attach) = reduce_collab(
    after_wrong,
    CollabEvent::Incoming(bootstrap),
  )
  assert_true(decision_attach is CollabDecision::Attach(_))
  assert_true(attaching.phase is CollabPhase::Attaching)
  let (_, duplicate) = reduce_collab(
    attaching,
    CollabEvent::Incoming(protocol_bootstrap(joiner, host)),
  )
  assert_true(duplicate is CollabDecision::NoEffect)
  let (_, early_ops) = reduce_collab(
    initial,
    CollabEvent::Incoming(CollabMessage::Ops(joiner, host, protocol_sync())),
  )
  assert_true(early_ops is CollabDecision::NoEffect)
}

///|
test "reducer closes before any later effect" {
  let state = CollabState::join(PeerId("joiner"))
  let (closed, decision) = reduce_collab(state, CollabEvent::CloseRequested)
  assert_true(closed.phase is CollabPhase::Closed)
  assert_true(decision is CollabDecision::Stop)
  let (_, repeated_close) = reduce_collab(closed, CollabEvent::CloseRequested)
  assert_true(repeated_close is CollabDecision::NoEffect)
  let (_, later) = reduce_collab(closed, CollabEvent::RemoteApplySucceeded)
  assert_true(later is CollabDecision::NoEffect)
}

///|
test "host lifecycle refreshes bootstrap and failures close" {
  let host = PeerId("host")
  let joiner = PeerId("joiner")
  let bootstrap = match protocol_bootstrap(joiner, host) {
    CollabMessage::Bootstrap(_, _, identity, sheet_id, generation, node, sync) =>
      BootstrapData::{ identity, sheet_id, generation, node, sync }
    _ => fail("bootstrap fixture has the wrong variant")
  }
  let (hosting, mount) = reduce_collab(
    CollabState::starting_host(host),
    CollabEvent::HostStartSucceeded(bootstrap),
  )
  assert_true(hosting.phase is CollabPhase::Hosting)
  assert_true(mount is CollabDecision::Mount)
  let latest = protocol_sync()
  let (refreshed, refreshed_decision) = reduce_collab(
    hosting,
    CollabEvent::LocalCommitted(latest),
  )
  assert_true(refreshed_decision is CollabDecision::NoEffect)
  let (attached, send) = reduce_collab(
    refreshed,
    CollabEvent::Incoming(CollabMessage::Join(joiner)),
  )
  assert_true(attached.phase is CollabPhase::Attached)
  match send {
    CollabDecision::Send(CollabMessage::Bootstrap(_, _, _, _, _, _, sync)) =>
      assert_eq(sync.to_canonical_bytes(), latest.to_canonical_bytes())
    _ => fail("host did not send the refreshed bootstrap")
  }
  let (failed, failure) = reduce_collab(
    CollabState::starting_host(host),
    CollabEvent::HostStartFailed("bootstrap failed"),
  )
  assert_true(failed.phase is CollabPhase::Failed)
  assert_true(failure is CollabDecision::Fail(_))
  let (closed, stop) = reduce_collab(failed, CollabEvent::CloseRequested)
  assert_true(closed.phase is CollabPhase::Closed)
  assert_true(stop is CollabDecision::Stop)
}

///|
test "remote apply failure transitions attached state to failed" {
  let host = PeerId("host")
  let joiner = PeerId("joiner")
  let attaching = CollabState::{
    phase: CollabPhase::Attaching,
    local_peer: joiner,
    remote_peer: Some(host),
    bootstrap: None,
  }
  let (attached, _) = reduce_collab(attaching, CollabEvent::AttachSucceeded)
  let (failed, decision) = reduce_collab(
    attached,
    CollabEvent::RemoteApplyFailed("sync failed"),
  )
  assert_true(failed.phase is CollabPhase::Failed)
  assert_true(decision is CollabDecision::Fail(_))
  let (local_only, publish) = reduce_collab(
    failed,
    CollabEvent::LocalCommitted(protocol_sync()),
  )
  assert_true(local_only.phase is CollabPhase::Failed)
  assert_true(publish is CollabDecision::NoEffect)
}
