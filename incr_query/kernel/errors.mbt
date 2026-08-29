///|
/// Human-facing context with no equality or stable formatting contract.
pub struct Diagnostic {
  priv message_text : String
  priv help_text : String?
} derive(Debug)

///|
/// Returns the actionable failure description.
pub fn Diagnostic::message(self : Diagnostic) -> String {
  self.message_text
}

///|
/// Returns optional recovery guidance.
pub fn Diagnostic::help(self : Diagnostic) -> String? {
  self.help_text
}

///|
fn diagnostic(message : String, help? : String) -> Diagnostic {
  { message_text: message, help_text: help }
}

///|
/// Structural failures reported by Store and QueryContext gets.
pub suberror ReadError {
  CrossStore(Diagnostic)
  ClosedRegion(Diagnostic)
  Cycle(Diagnostic)
  EvaluationLimitExceeded(Diagnostic)
  ExpiredQueryContext(Diagnostic)
  ReentrantRootGet(Diagnostic)
  GetDuringTransaction(Diagnostic)
} derive(Debug)

///|
/// Structural failures while creating or closing a Region.
pub suberror RegionError {
  ClosedRegion(Diagnostic)
  MutationDuringEvaluation(Diagnostic)
  MutationDuringTransaction(Diagnostic)
} derive(Debug)

///|
/// Structural failures while staging or publishing a Transaction.
pub suberror TransactionError {
  CrossStore(Diagnostic)
  ClosedRegion(Diagnostic)
  ExpiredTransaction(Diagnostic)
  TransactionDuringEvaluation(Diagnostic)
  NestedTransaction(Diagnostic)
} derive(Debug)

///|
fn read_store_cross_store() -> ReadError {
  CrossStore(
    diagnostic(
      "Store::get received a View created by a different Store.",
      help="Use the Store that owns the View; Views cannot cross Store boundaries.",
    ),
  )
}

///|
fn read_query_context_cross_store() -> ReadError {
  CrossStore(
    diagnostic(
      "QueryContext::get received a View created by a different Store.",
      help="Define the Derived Value or Query and all of its dependencies in the same Store; Views cannot cross Store boundaries.",
    ),
  )
}

///|
fn read_closed_region() -> ReadError {
  ClosedRegion(
    diagnostic(
      "This View is no longer readable because its owning Region is closed.",
      help="Keep the Region alive while the View is in use, or rebuild the graph in a new Region.",
    ),
  )
}

///|
fn read_cycle(definition_path : String) -> ReadError {
  Cycle(
    diagnostic(
      "Evaluation cannot complete because these definitions depend on each other:\n\{definition_path}",
      help="Break one dependency edge or model the shared external input as a Source.",
    ),
  )
}

///|
fn read_evaluation_limit_exceeded(limit : UInt) -> ReadError {
  EvaluationLimitExceeded(
    diagnostic(
      "Evaluation reached this Store's active Query limit of \{limit}.",
      help="Demand a shallower root, precompute an intermediate root, or create a Store with a larger measured limit.",
    ),
  )
}

///|
fn read_expired_context() -> ReadError {
  ExpiredQueryContext(
    diagnostic(
      "QueryContext was used after its evaluation callback returned.",
      help="Get dependencies synchronously inside the Derived Value or Query callback.",
    ),
  )
}

///|
fn read_reentrant_root_get() -> ReadError {
  ReentrantRootGet(
    diagnostic(
      "Store::get cannot start during another root evaluation.",
      help="Use the active QueryContext::get inside a Derived Value or Query callback.",
    ),
  )
}

///|
fn read_get_during_transaction() -> ReadError {
  GetDuringTransaction(
    diagnostic(
      "Store::get cannot run inside a Transaction.",
      help="Get required values before entering the Transaction.",
    ),
  )
}

///|
fn region_closed() -> RegionError {
  RegionError::ClosedRegion(
    diagnostic(
      "Cannot define new values in a closed Region.",
      help="Create a new Region for new Source, Derived Value, or Query definitions.",
    ),
  )
}

///|
fn region_mutation_during_evaluation() -> RegionError {
  MutationDuringEvaluation(
    diagnostic(
      "A Region cannot be changed during evaluation.",
      help="Create or close Regions outside Derived Value and Query callbacks.",
    ),
  )
}

///|
fn region_mutation_during_transaction() -> RegionError {
  MutationDuringTransaction(
    diagnostic(
      "A Region cannot be changed during a Transaction.",
      help="Create or close Regions before or after the Transaction callback.",
    ),
  )
}

///|
fn transaction_cross_store() -> TransactionError {
  TransactionError::CrossStore(
    diagnostic(
      "Transaction::set received a Source created by another Store.",
      help="A Transaction may set only Sources owned by its Store.",
    ),
  )
}

///|
fn transaction_closed_region() -> TransactionError {
  TransactionError::ClosedRegion(
    diagnostic(
      "Transaction::set received a Source whose Region is closed.",
      help="Set only Sources whose owning Region is still open.",
    ),
  )
}

///|
fn transaction_expired() -> TransactionError {
  ExpiredTransaction(
    diagnostic(
      "Transaction was used after its callback returned.",
      help="Stage writes synchronously inside the Transaction callback.",
    ),
  )
}

///|
fn transaction_during_evaluation() -> TransactionError {
  TransactionDuringEvaluation(
    diagnostic(
      "A Transaction cannot start during evaluation.",
      help="Return a domain decision from evaluation and publish it afterward.",
    ),
  )
}

///|
fn nested_transaction() -> TransactionError {
  NestedTransaction(
    diagnostic(
      "A Transaction cannot start while another Transaction is active.",
      help="Stage all related writes through the active Transaction.",
    ),
  )
}
