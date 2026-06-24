///|
suberror CallbackTestError {
  CallbackDepthStop
}

///|
test "run_callback restores callback_depth when callback raises" {
  let rt = Runtime::Runtime()
  let result = try
    @kernel.run_callback(rt.core, fn() raise {
      raise CallbackTestError::CallbackDepthStop
    })
  catch {
    e => Err(e)
  } noraise {
    _ => Ok(())
  }
  inspect(result is Err(_), content="true")
  inspect(rt.core.callback_depth, content="0")
}
