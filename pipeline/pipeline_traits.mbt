// === Deprecated Pipeline Traits ===
// These traits were an early sketch of compilation/processing pipeline stages.
// They are too stringly-typed for shared use and have no production consumers.
// Define application-specific Source/Parser/Checker/Transformer traits instead.

///|
/// **Deprecated.** Early sketch for source text input.
///
/// Define an application-local `Source` trait with concrete key, source, and
/// diagnostic types instead.
#deprecated("Define application-specific Source/Parser/Checker/Transformer traits instead", skip_current_package=true)
pub(open) trait Sourceable {
  fn set_source_text(Self, String) -> Unit
  fn source_text(Self) -> String
}

///|
/// **Deprecated.** Early sketch for parse diagnostics.
#deprecated("Define application-specific Source/Parser/Checker/Transformer traits instead", skip_current_package=true)
pub(open) trait Parseable {
  fn parse_errors(Self) -> Array[String]
}

///|
/// **Deprecated.** Early sketch for checking diagnostics.
#deprecated("Define application-specific Source/Parser/Checker/Transformer traits instead", skip_current_package=true)
pub(open) trait Checkable {
  fn check_errors(Self) -> Array[String]
}

///|
/// **Deprecated.** Early sketch for execution output.
#deprecated("Define application-specific Source/Parser/Checker/Transformer traits instead", skip_current_package=true)
pub(open) trait Executable {
  fn run(Self) -> Array[String]
}
