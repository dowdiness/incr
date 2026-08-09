///|
/// The public origin of a consumer-owned port.
pub(all) enum PortOrigin {
  Local
  Imported(provider_program~ : ProgramId, export_id~ : ExportId)
} derive(Eq, Debug)

///|
/// A provider-owned typed capability. Its kernel View is private to this package.
pub struct ReadExport[T] {
  priv core : ReadExportCore[T]
}

///|
priv struct ReadExportCore[T] {
  provider : ProgramId
  export_id : ExportId
  store : @kernel.StoreId
  view : @kernel.View[T]
}

///|
/// A consumer-owned typed port. Imported ports retain no public kernel handle.
pub struct ReadPort[T] {
  priv core : ReadPortCore[T]
}

///|
priv struct ReadPortCore[T] {
  program : ProgramId
  port_id : PortId
  origin : PortOrigin
  view : @kernel.View[T]
}

///|
/// One Formula-local declaration of a port.
pub struct DeclaredRead[T] {
  priv port : ReadPort[T]
  priv formula_id : FormulaId
}

///|
pub fn[T] ReadExport::provider_program(self : ReadExport[T]) -> ProgramId {
  self.core.provider
}

///|
pub fn[T] ReadExport::export_id(self : ReadExport[T]) -> ExportId {
  self.core.export_id
}

///|
pub fn[T] ReadPort::port_id(self : ReadPort[T]) -> PortId {
  self.core.port_id
}

///|
pub fn[T] ReadPort::origin(self : ReadPort[T]) -> PortOrigin {
  self.core.origin
}
