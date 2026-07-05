///|
/// Lazy formula expression over target facade handles. Materializes to a single
/// `Derived[T]` via `Expr::derived`; operator chains allocate no incremental cells.
pub(all) struct Expr[T] {
  priv rt : Runtime
  priv eval : () -> T raise Failure
  priv debug : ExprDebug
}

///|
priv enum ExprDebug {
  Source(String?)
  Const(String?)
  Op(String, ExprDebug, ExprDebug)
  Map(ExprDebug)
}

///|
/// Creates a constant expression tied to an explicit runtime.
pub fn[T] Expr::constant(rt : Runtime, value : T, label? : String) -> Expr[T] {
  { rt, eval: () => value, debug: ExprDebug::Const(label) }
}

///|
pub fn[A, B] Expr::map(self : Expr[A], f : (A) -> B raise Failure) -> Expr[B] {
  {
    rt: self.rt,
    eval: () => f((self.eval)()),
    debug: ExprDebug::Map(self.debug),
  }
}

///|
pub fn[A, B, C] Expr::map2(
  left : Expr[A],
  right : Expr[B],
  f : (A, B) -> C raise Failure,
) -> Expr[C] {
  Expr::assert_same_runtime(left, right, "map2")
  {
    rt: left.rt,
    eval: () => f((left.eval)(), (right.eval)()),
    debug: ExprDebug::Op("map2", left.debug, right.debug),
  }
}

///|
fn[A, B] Expr::assert_same_runtime(
  left : Expr[A],
  right : Expr[B],
  op : String,
) -> Unit {
  let left_rt = left.rt.id()
  let right_rt = right.rt.id()
  if left_rt != right_rt {
    abort(
      "Cross-runtime expression: operator " +
      op +
      " composed Runtime " +
      right_rt.to_string() +
      " with Runtime " +
      left_rt.to_string(),
    )
  }
}

///|
/// Materializes this expression as one lazy `Derived` cell on its runtime.
pub fn[T : Eq] Expr::derived(self : Expr[T], label? : String) -> Derived[T] {
  Derived(self.rt, () => (self.eval)(), label?)
}

// ── Source lifts ──

///|
pub fn[T] Input::expr(self : Input[T]) -> Expr[T] {
  { rt: self.rt, eval: () => self.get(), debug: ExprDebug::Source(self.label) }
}

///|
pub fn[T] InputField::expr(self : InputField[T]) -> Expr[T] {
  self.input.expr()
}

///|
pub fn[T] Derived::expr(self : Derived[T]) -> Expr[T] {
  {
    rt: self.rt,
    eval: () => self.get_or_abort(),
    debug: ExprDebug::Source(self.label),
  }
}

///|
pub fn[T : Eq] ReachableDerived::expr(self : ReachableDerived[T]) -> Expr[T] {
  {
    rt: self.rt,
    eval: () => self.get_or_abort(),
    debug: ExprDebug::Source(self.label),
  }
}

///|
pub fn[T] EagerDerived::expr(self : EagerDerived[T]) -> Expr[T] {
  { rt: self.rt, eval: () => self.get(), debug: ExprDebug::Source(None) }
}

// ── Operator trait implementations ──

///|
pub impl[T : Add] Add for Expr[T] with fn add(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a + b)
}

///|
pub impl[T : Sub] Sub for Expr[T] with fn sub(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a - b)
}

///|
pub impl[T : Mul] Mul for Expr[T] with fn mul(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a * b)
}

///|
pub impl[T : Div] Div for Expr[T] with fn div(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a / b)
}

///|
pub impl[T : Mod] Mod for Expr[T] with fn mod(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a % b)
}

///|
pub impl[T : Neg] Neg for Expr[T] with fn neg(self) -> Expr[T] {
  Expr::map(self, a => -a)
}
