///|
pub(all) struct ProbeCell[T] {
  value : T
}

///|
#alias(new, deprecated="Use ProbeCell(value)")
pub fn[T] ProbeCell::ProbeCell(value : T) -> ProbeCell[T] {
  { value, }
}

///|
#alias(old_value, deprecated="Use ProbeCell::value")
pub fn[T] ProbeCell::value(self : ProbeCell[T]) -> T {
  self.value
}

///|
pub type RenamedCell[T] = ProbeCell[T]

///|
#deprecated("Use RenamedCell")
pub type DeprecatedCell[T] = ProbeCell[T]

///|
pub(open) trait CurrentFreshness {
  fn current(Self) -> Bool
}

///|
pub(open) trait CompatReadable {
  fn readable(Self) -> Bool
}

///|
pub(all) struct FreshOnly {
  ok : Bool
}

///|
pub fn FreshOnly::FreshOnly(ok : Bool) -> FreshOnly {
  { ok, }
}

///|
pub impl CurrentFreshness for FreshOnly with fn current(self) {
  self.ok
}

///|
pub impl CompatReadable for FreshOnly with fn readable(self) {
  self.current()
}

///|
pub(all) struct LegacyOnly {
  ok : Bool
}

///|
pub fn LegacyOnly::LegacyOnly(ok : Bool) -> LegacyOnly {
  { ok, }
}

///|
pub impl CompatReadable for LegacyOnly with fn readable(self) {
  self.ok
}

///|
pub(all) struct ReadRuntime {
  marker : Unit
}

///|
pub fn ReadRuntime::ReadRuntime() -> ReadRuntime {
  { marker: () }
}

///|
pub(all) struct ReadMemo[T] {
  value : T
}

///|
pub fn[T] ReadMemo::ReadMemo(value : T) -> ReadMemo[T] {
  { value, }
}

///|
pub(all) struct ReadReactive[T] {
  value : T
}

///|
pub fn[T] ReadReactive::ReadReactive(value : T) -> ReadReactive[T] {
  { value, }
}

///|
pub fn[T] ReadRuntime::read(self : ReadRuntime, memo : ReadMemo[T]) -> T {
  ignore(self)
  memo.value
}

///|
pub fn[T] ReadRuntime::read_reactive(
  self : ReadRuntime,
  reactive : ReadReactive[T],
) -> T {
  ignore(self)
  reactive.value
}
