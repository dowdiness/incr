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
fn ExprDebug::to_string(self : ExprDebug) -> String {
  match self {
    Source(l) => "Source(" + (match l { Some(s) => "\"" + s + "\""; None => "None" }) + ")"
    Const(l) => "Const(" + (match l { Some(s) => "\"" + s + "\""; None => "None" }) + ")"
    Op(name, left, right) => "Op(" + name + ", " + left.to_string() + ", " + right.to_string() + ")"
    Map(inner) => "Map(" + inner.to_string() + ")"
  }
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
#alias(e)
pub fn[T] Input::expr(self : Input[T]) -> Expr[T] {
  { rt: self.rt, eval: () => self.get(), debug: ExprDebug::Source(self.label) }
}

///|
#alias(e)
pub fn[T] InputField::expr(self : InputField[T]) -> Expr[T] {
  self.input.expr()
}

///|
#alias(e)
pub fn[T] Derived::expr(self : Derived[T]) -> Expr[T] {
  {
    rt: self.rt,
    eval: () => self.get_or_abort(),
    debug: ExprDebug::Source(self.label),
  }
}

///|
#alias(e)
pub fn[T : Eq] ReachableDerived::expr(self : ReachableDerived[T]) -> Expr[T] {
  {
    rt: self.rt,
    eval: () => self.get_or_abort(),
    debug: ExprDebug::Source(self.label),
  }
}

///|
#alias(e)
pub fn[T] EagerDerived::expr(self : EagerDerived[T]) -> Expr[T] {
  { rt: self.rt, eval: () => self.get(), debug: ExprDebug::Source(None) }
}

// ── Operator trait implementations ──

///|
/// Adds two expressions when materialized. The operator chain stays lazy until
/// `Expr::derived`; no incremental cell is allocated for `+` itself. Aborts if
/// the operands belong to different runtimes.
pub impl[T : Add] Add for Expr[T] with fn add(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a + b)
}

///|
/// Subtracts the right expression from the left when materialized. Stays lazy
/// until `Expr::derived`; no incremental cell is allocated for `-` itself.
/// Aborts if the operands belong to different runtimes.
pub impl[T : Sub] Sub for Expr[T] with fn sub(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a - b)
}

///|
/// Multiplies two expressions when materialized. Stays lazy until
/// `Expr::derived`; no incremental cell is allocated for `*` itself. Aborts if
/// the operands belong to different runtimes.
pub impl[T : Mul] Mul for Expr[T] with fn mul(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a * b)
}

///|
/// Divides the left expression by the right when materialized. Stays lazy until
/// `Expr::derived`; no incremental cell is allocated for `/` itself. Aborts if
/// the operands belong to different runtimes.
pub impl[T : Div] Div for Expr[T] with fn div(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a / b)
}

///|
/// Remainder of dividing the left expression by the right when materialized.
/// Stays lazy until `Expr::derived`; no incremental cell is allocated for `%`
/// itself. Aborts if the operands belong to different runtimes.
pub impl[T : Mod] Mod for Expr[T] with fn mod(self, other) -> Expr[T] {
  Expr::map2(self, other, (a, b) => a % b)
}

///|
/// Negates the expression when materialized. Composes lazily via `Expr::map`;
/// no incremental cell is allocated for unary `-` until `Expr::derived`.
pub impl[T : Neg] Neg for Expr[T] with fn neg(self) -> Expr[T] {
  Expr::map(self, a => -a)
}
