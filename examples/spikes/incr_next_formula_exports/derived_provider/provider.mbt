///|
pub(all) enum DerivedProviderError {
  UpstreamExport(error~ : @program.ExportError)
  Import(error~ : @program.ImportError)
  Declaration(error~ : @program.BuilderError)
  Build(error~ : @program.BuilderError)
  FormulaExport(error~ : @program.ExportError)
} derive(Eq, Debug)

///|
priv struct DerivedProviderCore {
  upstream : @feature_provider.FeatureProvider
  source_export_id : @program.ExportId
  program : @program.Program
  formula : @program.Formula[Int]
  formula_export : @program.ReadExport[Result[Int, @program.ProgramError]]
  unauthorized_export : @program.ReadExport[Result[Int, @program.ProgramError]]
}

///|
/// B owns a Formula whose result is itself a typed provider export.
pub struct DerivedProvider {
  priv core : DerivedProviderCore
}

///|
/// Imports A's source export, doubles it, and exports the Formula result.
pub fn DerivedProvider::create(
  upstream : @feature_provider.FeatureProvider,
) -> Result[DerivedProvider, DerivedProviderError] {
  let source_export = match upstream.export_value() {
    Ok(exported) => exported
    Err(error) => return Err(UpstreamExport(error~))
  }
  let program = upstream.consumer_program()
  let imported = match program.import_export(source_export) {
    Ok(port) => port
    Err(error) => return Err(Import(error~))
  }
  let builder = program.builder()
  let declared = match builder.declare_port(imported) {
    Ok(read) => read
    Err(error) => return Err(Declaration(error~))
  }
  let formula = match builder.build(ctx => {
    match ctx.read(declared) {
      Ok(value) => Ok(value * 2)
      Err(error) => Err(error)
    }
  }) {
    Ok(formula) => formula
    Err(error) => return Err(Build(error~))
  }
  let formula_export = match program.export_formula(formula) {
    Ok(exported) => exported
    Err(error) => return Err(FormulaExport(error~))
  }
  // This Formula intentionally invokes an unauthorized declaration without a
  // View call, so its ProgramError remains an application value for C.
  let bad_builder = program.builder()
  let bad_formula = match bad_builder.build(ctx => ctx.read(declared)) {
    Ok(formula) => formula
    Err(error) => return Err(Build(error~))
  }
  let unauthorized_export = match program.export_formula(bad_formula) {
    Ok(exported) => exported
    Err(error) => return Err(FormulaExport(error~))
  }
  Ok({
    core: {
      upstream,
      source_export_id: source_export.export_id(),
      program,
      formula,
      formula_export,
      unauthorized_export,
    },
  })
}

///|
pub fn DerivedProvider::source_export_id(
  self : DerivedProvider,
) -> @program.ExportId {
  self.core.source_export_id
}

///|
pub fn DerivedProvider::program(
  self : DerivedProvider,
) -> @program.Program {
  self.core.program
}

///|
pub fn DerivedProvider::formula(
  self : DerivedProvider,
) -> @program.Formula[Int] {
  self.core.formula
}

///|
pub fn DerivedProvider::export_formula(
  self : DerivedProvider,
) -> @program.ReadExport[Result[Int, @program.ProgramError]] {
  self.core.formula_export
}

///|
/// Returns the Formula whose provider application fails before any View call.
pub fn DerivedProvider::unauthorized_export(
  self : DerivedProvider,
) -> @program.ReadExport[Result[Int, @program.ProgramError]] {
  self.core.unauthorized_export
}

///|
/// Creates C's Program in a fresh Region of A's Store.
pub fn DerivedProvider::consumer_program(
  self : DerivedProvider,
) -> @program.Program {
  self.core.upstream.consumer_program()
}

///|
/// Closes B's Region; C's imported Formula edge then reports ClosedRegion.
pub fn DerivedProvider::close(self : DerivedProvider) -> Bool {
  self.core.program.close()
}
