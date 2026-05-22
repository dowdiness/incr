///|
test "memo read primitive: read_result works outside tracked context" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 10)
  let memo = Memo::Memo(rt, () => source.get() * 2)

  match memo.read_result() {
    Ok(value) => inspect(value, content="20")
    Err(_) => abort("expected memo read_result to succeed")
  }
}

///|
test "memo read primitive: get_strict_result records dependency in tracked context" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 10)
  let memo = Memo::Memo(rt, () => source.get() * 2)
  let view = Memo::Memo(rt, () => {
    match memo.get_strict_result() {
      Ok(value) => value + 1
      Err(_) => -1
    }
  })

  inspect(read_memo_for_test(view), content="21")
  source.set(11)
  inspect(read_memo_for_test(view), content="23")
}

///|
test "panic memo read primitive: get_strict_result outside tracked context aborts" {
  let rt = Runtime::Runtime()
  let memo = Memo::Memo(rt, () => 1)

  ignore(memo.get_strict_result())
}

///|
test "memo read primitive: read_result returns cycle error" {
  let rt = Runtime::Runtime()
  let memo = Memo::Memo(rt, () => 1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true
  rt.push_tracking(memo.id())

  let got_cycle = match memo.read_result() {
    Ok(_) => false
    Err(err) => err.cell() == memo.id()
  }
  meta.in_progress = false
  ignore(rt.pop_tracking())
  inspect(got_cycle, content="true")
}

///|
test "hybrid read primitive: read_result works outside tracked context" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 10)
  let hybrid = HybridMemo::HybridMemo(rt, () => source.get() * 2)

  match hybrid.read_result() {
    Ok(value) => inspect(value, content="20")
    Err(_) => abort("expected hybrid read_result to succeed")
  }
}

///|
test "hybrid read primitive: get_strict_result records dependency in tracked context" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 10)
  let hybrid = HybridMemo::HybridMemo(rt, () => source.get() * 2)
  let view = Memo::Memo(rt, () => {
    match hybrid.get_strict_result() {
      Ok(value) => value + 1
      Err(_) => -1
    }
  })

  inspect(read_memo_for_test(view), content="21")
  source.set(11)
  inspect(read_memo_for_test(view), content="23")
}

///|
test "panic hybrid read primitive: get_strict_result outside tracked context aborts" {
  let rt = Runtime::Runtime()
  let hybrid = HybridMemo::HybridMemo(rt, () => 1)

  ignore(hybrid.get_strict_result())
}

///|
test "hybrid read primitive: read_result returns cycle error" {
  let rt = Runtime::Runtime()
  let hybrid = HybridMemo::HybridMemo(rt, () => 1)
  let meta = rt.get_memo_data(hybrid.id())
  meta.in_progress = true

  let got_cycle = match hybrid.read_result() {
    Ok(_) => false
    Err(err) => err.cell() == hybrid.id()
  }
  meta.in_progress = false
  inspect(got_cycle, content="true")
}

///|
test "memo_map read primitive: read_result works outside tracked context" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 10)
  let by_key = MemoMap::MemoMap(rt, (key : Int) => source.get() + key)

  match by_key.read_result(2) {
    Ok(value) => inspect(value, content="12")
    Err(_) => abort("expected memo_map read_result to succeed")
  }
}

///|
test "memo_map read primitive: get_strict_result records dependency in tracked context" {
  let rt = Runtime::Runtime()
  let source = Signal::Signal(rt, 10)
  let by_key = MemoMap::MemoMap(rt, (key : Int) => source.get() + key)
  let view = Memo::Memo(rt, () => {
    match by_key.get_strict_result(1) {
      Ok(value) => value * 2
      Err(_) => -1
    }
  })

  inspect(read_memo_for_test(view), content="22")
  source.set(20)
  inspect(read_memo_for_test(view), content="42")
}

///|
test "panic memo_map read primitive: get_strict_result outside tracked context aborts" {
  let rt = Runtime::Runtime()
  let by_key = MemoMap::MemoMap(rt, (key : Int) => key * 10)

  ignore(by_key.get_strict_result(1))
}

///|
test "memo_map read primitive: read_result returns cycle error" {
  let rt = Runtime::Runtime()
  let by_key = MemoMap::MemoMap(rt, (key : Int) => key * 10)
  let memo = by_key.get_or_create_memo(1)
  let meta = rt.get_memo_data(memo.id())
  meta.in_progress = true

  let got_cycle = match by_key.read_result(1) {
    Ok(_) => false
    Err(err) => err.cell() == memo.id()
  }
  meta.in_progress = false
  inspect(got_cycle, content="true")
}
