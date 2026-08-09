///|
priv enum BuilderState {
  Open
  Built
}

///|
priv struct BuilderCore {
  program : ProgramId
  formula_id : FormulaId
  region : @kernel.Region
  auth : Map[PortId, Unit]
  manifest : Array[PortId]
  state : Ref[BuilderState]
}

///|
/// Builds exactly one Formula and combines declaration with authorization.
pub struct FormulaBuilder {
  priv core : BuilderCore
}

///|
/// Declares and authorizes one Port; duplicate declarations preserve first order.
pub fn[T] FormulaBuilder::declare_port(
  self : FormulaBuilder,
  port : ReadPort[T],
) -> Result[DeclaredRead[T], BuilderError] {
  match self.core.state.val {
    Built => Err(BuilderExpired)
    Open =>
      if port.core.program != self.core.program {
        Err(ForeignPort(port_id=port.core.port_id))
      } else {
        if !self.core.auth.contains(port.core.port_id) {
          self.core.auth[port.core.port_id] = ()
          self.core.manifest.push(port.core.port_id)
        }
        Ok({ port, formula_id: self.core.formula_id })
      }
  }
}

///|
/// Creates the kernel Query only after the builder has been validated and expires it.
pub fn[V] FormulaBuilder::build(
  self : FormulaBuilder,
  compute : (ProgramEvalCtx) -> Result[V, ProgramError],
) -> Result[Formula[V], BuilderError] {
  match self.core.state.val {
    Built => Err(BuilderExpired)
    Open => {
      // Build is consuming even when kernel definition registration is rejected.
      self.core.state.val = Built
      let observations : Ref[Array[ObservedInvocation]] = Ref([])
      let auth = self.core.auth.copy()
      let formula_id = self.core.formula_id
      let manifest = Manifest::{ ports: self.core.manifest.copy() }
      let query_result = self.core.region.query_always_changed(
        (raw_ctx, _ : Unit) => {
          observations.val = []
          let ctx = ProgramEvalCtx::{
            raw: raw_ctx,
            program: self.core.program,
            formula_id,
            auth,
            observations,
            structural: Ref(None),
          }
          let value = compute(ctx)
          match ctx.structural.val {
            Some(error) => Err(error)
            None => Ok(value)
          }
        },
      )
      match query_result {
        Err(error) => Err(Region(error~))
        Ok(query) => {
          Ok({
            core: {
              formula_id,
              manifest,
              observations,
              view: query.at(()),
            },
          })
        }
      }
    }
  }
}
