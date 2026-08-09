///|
let next_program : Ref[Int] = Ref(1)

///|
priv struct ProgramCore {
  region : @kernel.Region
  region_id : @kernel.RegionId
  store : @kernel.Store
  program_id : ProgramId
  next_port : Ref[Int]
  next_export : Ref[Int]
  next_formula : Ref[Int]
}

///|
/// A Program owns one ProgramId and scopes capabilities to one Region identity.
pub struct Program {
  priv core : ProgramCore
}

///|
/// Wraps one existing kernel Region without changing the kernel.
pub fn Program::Program(
  store : @kernel.Store,
  region : @kernel.Region,
) -> Program {
  if store.id() != region.id().store_id() {
    abort("program Store/Region mismatch")
  }
  let program_id = ProgramId::{ sequence: next_program.val }
  next_program.val = next_program.val + 1
  {
    core: {
      region,
      region_id: region.id(),
      store,
      program_id,
      next_port: Ref(1),
      next_export: Ref(1),
      next_formula: Ref(1),
    },
  }
}

///|
/// Creates a local Port only for a View in this Program's Region.
pub fn[T] Program::port(
  self : Program,
  view : @kernel.View[T],
) -> Result[ReadPort[T], PortError] {
  if view.generation().region_id() != self.core.region_id {
    Err(PortRegionMismatch)
  } else {
    let port_id = PortId::{
      program: self.core.program_id,
      sequence: self.core.next_port.val,
    }
    self.core.next_port.val = self.core.next_port.val + 1
    Ok({
      core: {
        program: self.core.program_id,
        port_id,
        origin: Local,
        view,
      },
    })
  }
}

///|
/// Publishes a typed export only for a View in this provider's Region.
pub fn[T] Program::export(
  self : Program,
  view : @kernel.View[T],
) -> Result[ReadExport[T], ExportError] {
  if view.generation().region_id() != self.core.region_id {
    Err(ForeignView)
  } else {
    let export_id = ExportId::{
      provider: self.core.program_id,
      sequence: self.core.next_export.val,
    }
    self.core.next_export.val = self.core.next_export.val + 1
    Ok({
      core: {
        provider: self.core.program_id,
        export_id,
        store: self.core.store.id(),
        view,
      },
    })
  }
}

///|
/// Imports an export after Store validation and then allocates a local PortId.
pub fn[T] Program::import_export(
  self : Program,
  exported : ReadExport[T],
) -> Result[ReadPort[T], ImportError] {
  if exported.core.store != self.core.store.id() {
    Err(DifferentStore)
  } else {
    let port_id = PortId::{
      program: self.core.program_id,
      sequence: self.core.next_port.val,
    }
    self.core.next_port.val = self.core.next_port.val + 1
    Ok({
      core: {
        program: self.core.program_id,
        port_id,
        origin: Imported(
          provider_program=exported.core.provider,
          export_id=exported.core.export_id,
        ),
        view: exported.core.view,
      },
    })
  }
}

///|
/// Re-export is explicit and forbidden; an imported capability cannot be promoted.
pub fn[T] Program::export_port(
  _self : Program,
  _port : ReadPort[T],
) -> Result[ReadExport[T], ExportError] {
  Err(ReexportForbidden)
}

///|
/// Starts a Formula-local, single-use declaration builder.
pub fn Program::builder(self : Program) -> FormulaBuilder {
  let formula_id = FormulaId::{
    program: self.core.program_id,
    sequence: self.core.next_formula.val,
  }
  self.core.next_formula.val = self.core.next_formula.val + 1
  {
    core: {
      program: self.core.program_id,
      formula_id,
      region: self.core.region,
      auth: Map([]),
      manifest: [],
      state: Ref(Open),
    },
  }
}

///|
/// Reads a Formula without requiring a kernel import in a consumer package.
pub fn[V] Program::read(
  self : Program,
  formula : Formula[V],
) -> Result[Result[V, ProgramError], FormulaReadError] {
  if formula.core.formula_id.program != self.core.program_id {
    return Err(ForeignFormula)
  }
  match self.core.store.read(formula.core.view) {
    Ok(value) => Ok(value)
    Err(error) => match error {
      @kernel.ReadError::CrossStore(..) => Err(CrossStore)
      @kernel.ReadError::ClosedRegion(_) => Err(ClosedRegion)
      @kernel.ReadError::Cycle(_) => Err(Cycle)
      _ => Err(Other)
    }
  }
}
