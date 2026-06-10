///|
suberror CallbackTestError {
  CallbackDepthStop
}

///|
test "run_callback restores callback_depth when callback raises" {
  let rt = Runtime::Runtime()
  let mut callback_failed = false
  try
    @kernel.run_callback(rt.core, fn() raise {
      raise CallbackTestError::CallbackDepthStop
    })
  catch {
    _ => callback_failed = true
  } noraise {
    _ => ()
  }
  inspect(callback_failed, content="true")
  inspect(rt.core.callback_depth, content="0")
}
