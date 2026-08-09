///|
priv struct ReadPortCore[T] {
  program : ProgramId
  port_id : PortId
  view : @kernel.View[T]
}

///|
/// A typed capability for reading one opaque kernel View.
pub struct ReadPort[T] {
  priv core : ReadPortCore[T]
}

///|
/// A Formula-local typed declaration of a ReadPort.
pub struct DeclaredRead[T] {
  priv port : ReadPort[T]
  priv formula_id : FormulaId
}
