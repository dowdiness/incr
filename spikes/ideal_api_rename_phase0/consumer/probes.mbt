///|
pub(all) struct DownstreamFresh {
  ok : Bool
}

///|
pub fn DownstreamFresh::DownstreamFresh(ok : Bool) -> DownstreamFresh {
  { ok, }
}

///|
pub impl @probe.CurrentFreshness for DownstreamFresh with fn current(self) {
  self.ok
}

///|
pub(all) struct DownstreamLegacy {
  ok : Bool
}

///|
pub fn DownstreamLegacy::DownstreamLegacy(ok : Bool) -> DownstreamLegacy {
  { ok, }
}

///|
pub impl @probe.CompatReadable for DownstreamLegacy with fn readable(self) {
  self.ok
}

///|
pub impl @probe.CompatReadable for DownstreamFresh with fn readable(self) {
  self.current()
}

///|
pub fn probe_public_aliases() -> Int {
  let from_constructor = @probe.ProbeCell::new(1)
  let from_target = @probe.ProbeCell(2)
  let from_type_alias : @probe.RenamedCell[Int] = @probe.RenamedCell::new(3)
  let from_deprecated_alias : @probe.DeprecatedCell[Int] = @probe.ProbeCell(4)
  from_constructor.old_value() +
  from_target.value() +
  from_type_alias.value() +
  from_deprecated_alias.value()
}

///|
pub fn probe_blanket_trait_compatibility() -> Bool {
  let provider_fresh = @probe.FreshOnly(true)
  let provider_legacy = @probe.LegacyOnly(true)
  let downstream_fresh = DownstreamFresh(true)
  let downstream_legacy = DownstreamLegacy(true)
  provider_fresh.readable() &&
  provider_legacy.readable() &&
  downstream_fresh.readable() &&
  downstream_legacy.readable()
}

///|
pub fn probe_same_receiver_overload() -> Int {
  let rt = @probe.ReadRuntime()
  rt.read(@probe.ReadMemo(10)) + rt.read_reactive(@probe.ReadReactive(20))
}
