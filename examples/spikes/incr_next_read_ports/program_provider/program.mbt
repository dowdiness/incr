///|
let next_program : Ref[Int] = Ref(1)

///|
priv struct ProgramCore {
  region : @kernel.Region
  program_id : ProgramId
  next_port : Ref[Int]
  next_formula : Ref[Int]
}

///|
/// A Program scopes typed read capabilities and Formula definitions to one Region.
pub struct Program {
  priv core : ProgramCore
}

///|
/// Wraps an existing kernel Region without changing or forking the kernel.
pub fn Program::Program(region : @kernel.Region) -> Program {
  let program_id = ProgramId::{ sequence: next_program.val }
  next_program.val = next_program.val + 1
  {
    core: {
      region,
      program_id,
      next_port: Ref(1),
      next_formula: Ref(1),
    },
  }
}

///|
/// Creates a typed Port from an opaque kernel View owned by this Region.
pub fn[T] Program::port(
  self : Program,
  view : @kernel.View[T],
) -> Result[ReadPort[T], BuilderError] {
  if view.generation().region_id() != self.core.region.id() {
    Err(PortRegionMismatch)
  } else {
    let port_id = PortId::{
      program: self.core.program_id,
      sequence: self.core.next_port.val,
    }
    self.core.next_port.val = self.core.next_port.val + 1
    Ok({ core: { program: self.core.program_id, port_id, view } })
  }
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
