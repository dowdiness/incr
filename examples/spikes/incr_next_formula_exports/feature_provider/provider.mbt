///|
/// Feature-facing construction failure without exposing the kernel error type.
pub(all) enum FeatureProviderError {
  Unavailable
} derive(Eq, Debug)

///|
priv struct FeatureProviderCore {
  store : @kernel.Store
  region : @kernel.Region
  program : @program.Program
  value : @kernel.Source[Int]
}

///|
/// A feature provider privately owns its Source, View, Store, and Program.
pub struct FeatureProvider {
  priv core : FeatureProviderCore
}

///|
/// Creates one feature provider and its provider-owned typed export source.
pub fn FeatureProvider::create() -> Result[FeatureProvider, FeatureProviderError] {
  let store = @kernel.Store()
  match store.region() {
    Err(_) => Err(Unavailable)
    Ok(region) => match region.source(10) {
      Err(_) => Err(Unavailable)
      Ok(value) => Ok({
        core: {
          store,
          region,
          program: @program.Program(store, region),
          value,
        },
      })
    }
  }
}

///|
/// Returns the Program capability for A without exposing its Region or Store.
pub fn FeatureProvider::program(self : FeatureProvider) -> @program.Program {
  self.core.program
}

///|
/// Returns a typed export; raw kernel Views never cross this feature boundary.
pub fn FeatureProvider::export_value(
  self : FeatureProvider,
) -> Result[@program.ReadExport[Int], @program.ExportError] {
  self.core.program.export(self.core.value.view())
}

///|
/// Gives an importing consumer a Program in a distinct Region of the same Store.
pub fn FeatureProvider::consumer_program(
  self : FeatureProvider,
) -> @program.Program {
  match self.core.store.region() {
    Ok(region) => @program.Program(self.core.store, region)
    Err(_) => abort("consumer Region unavailable")
  }
}

/// Gives local-origin workloads a Program in the provider Region.
pub fn FeatureProvider::local_consumer_program(
  self : FeatureProvider,
) -> @program.Program {
  @program.Program(self.core.store, self.core.region)
}

///|
/// Supplies a local port for workloads that compare Local and Imported origins.
pub fn FeatureProvider::local_port(
  self : FeatureProvider,
  consumer : @program.Program,
) -> Result[@program.ReadPort[Int], @program.PortError] {
  consumer.port(self.core.value.view())
}

///|
/// Commits a value through the provider-owned source.
pub fn FeatureProvider::set(self : FeatureProvider, value : Int) -> Bool {
  self.core.store.transaction(tx => tx.set(self.core.value, value)) is Ok(_)
}

///|
/// Closes the provider Region; imported Formula reads then report outer closure.
pub fn FeatureProvider::close(self : FeatureProvider) -> Bool {
  self.core.region.close() is Ok(_)
}

///|
/// Exposes only source evidence, not a View or Query key.
pub fn FeatureProvider::read_attempts(self : FeatureProvider) -> Int {
  self.core.value.debug().read_count
}
