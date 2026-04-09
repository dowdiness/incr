///|
test "scope: new creates empty scope" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  inspect(scope.is_disposed(), content="false")
}

///|
test "scope: dispose marks scope as disposed" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "scope: dispose is idempotent" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  scope.dispose()
  // Second dispose should not abort
  scope.dispose()
  inspect(scope.is_disposed(), content="true")
}

///|
test "scope: child creates nested scope" {
  let rt = Runtime::new()
  let parent = Scope::new(rt)
  let child = parent.child()
  inspect(child.is_disposed(), content="false")
  inspect(parent.is_disposed(), content="false")
}

///|
test "scope: disposing parent disposes children" {
  let rt = Runtime::new()
  let parent = Scope::new(rt)
  let child1 = parent.child()
  let child2 = parent.child()
  parent.dispose()
  inspect(child1.is_disposed(), content="true")
  inspect(child2.is_disposed(), content="true")
  inspect(parent.is_disposed(), content="true")
}

///|
test "scope: nested children disposed bottom-up" {
  let rt = Runtime::new()
  let root = Scope::new(rt)
  let mid = root.child()
  let leaf = mid.child()
  root.dispose()
  inspect(leaf.is_disposed(), content="true")
  inspect(mid.is_disposed(), content="true")
  inspect(root.is_disposed(), content="true")
}

///|
test "panic scope: child of disposed scope aborts" {
  let rt = Runtime::new()
  let scope = Scope::new(rt)
  scope.dispose()
  let _ = scope.child()
}
