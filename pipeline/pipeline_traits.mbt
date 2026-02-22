// === Pipeline Traits ===
// These traits define the stages of a compilation/processing pipeline.
// They are experimental and may change or be removed in future versions.
// No production usage — currently only exercised by test fixtures (CalcPipeline).

///|
/// **Experimental.** A system that has source text input.
///
/// Implement this trait to provide get/set access to source text
/// backed by an incremental Signal.
pub(open) trait Sourceable {
  set_source_text(Self, String) -> Unit
  source_text(Self) -> String
}

///|
/// **Experimental.** A system that can parse and report parse errors.
pub(open) trait Parseable {
  parse_errors(Self) -> Array[String]
}

///|
/// **Experimental.** A system that can check (type-check, lint, etc.) and report errors.
pub(open) trait Checkable {
  check_errors(Self) -> Array[String]
}

///|
/// **Experimental.** A system that can execute/evaluate and produce output.
pub(open) trait Executable {
  run(Self) -> Array[String]
}
