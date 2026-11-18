///|
/// Failure channel of pull verification and recompute.
///
/// `Cycle` is an expected, recoverable outcome that read boundaries convert
/// to `ReadError::Cycle`. `Defect` is a user compute closure's `Failure`;
/// read boundaries treat it as a defect and abort. Keeping the two cases in
/// one closed type makes every catch exhaustive.
pub(all) suberror PullError {
  Cycle(@incr_types.CycleError)
  Defect(Failure)
}
