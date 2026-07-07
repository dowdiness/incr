///|
suberror CallbackTestError {
  CallbackDepthStop
}

///|
test "run_callback restores callback_depth when callback raises" {
  let core = RuntimeCore()
  let mut callback_failed = false
  try
    run_callback(core, fn() raise { raise CallbackTestError::CallbackDepthStop })
  catch {
    _ => callback_failed = true
  } noraise {
    _ => ()
  }
  inspect(callback_failed, content="true")
  inspect(core.callback_depth, content="0")
}
