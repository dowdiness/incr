///|
test "formula evaluation preserves declared input order" {
  let failure = NumberFormulaOutcome::Failure(FormulaFailure::DivisionByZero)
  assert_eq(evaluate_add(failure, NumberFormulaOutcome::Success(2)), failure)
  assert_eq(
    evaluate_safe_divide(
      NumberFormulaOutcome::Success(8),
      NumberFormulaOutcome::Success(0),
    ),
    failure,
  )
  assert_eq(
    evaluate_optional_offset(NumberFormulaOutcome::Success(5), None, 3),
    NumberFormulaOutcome::Success(8),
  )
}

///|
test "descriptor metadata parameter updates and codec are application-owned" {
  let descriptor = NodeDescriptor::OptionalOffset(value=3)
  let specification = descriptor.specification()
  assert_eq(specification.inputs.length(), 2)
  assert_eq(specification.inputs[0].required, true)
  assert_eq(specification.inputs[1].required, false)
  assert_eq(
    descriptor.with_parameter(0, ParameterValue::Number(9)),
    Some(NodeDescriptor::OptionalOffset(value=9)),
  )
  assert_eq(descriptor.with_parameter(0, ParameterValue::Boolean(true)), None)
  let encoded = encode_descriptor_json(descriptor)
  assert_eq(decode_descriptor_json(encoded), Ok(descriptor))
}

///|
test "Display decision captures a prepared value" {
  assert_eq(
    display_decision(NumberFormulaOutcome::Success(11)),
    ApplicationDecision::Success(Command::RecordNumber(11)),
  )
}
