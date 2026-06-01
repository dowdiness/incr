///|
fn current_model_pull_memo_idx(rt : Runtime, cell_id : CellId) -> Int {
  match rt.core.cell_index[cell_id.id] {
    PullMemo(idx) => idx
    _ => abort("expected PullMemo")
  }
}

///|
test "dynamic dependency replacement: trace follows current branch" {
  let rt = Runtime()
  let choose_left = Signal(rt, true)
  let left = Signal(rt, 10)
  let right = Signal(rt, 20)
  let mut runs = 0
  let selected = Memo(rt, () => {
    runs += 1
    if choose_left.get() {
      left.get()
    } else {
      right.get()
    }
  })

  inspect(read_memo_for_test(selected), content="10")
  inspect(runs, content="1")
  inspect(selected.dependencies().contains(left.id()), content="true")
  inspect(selected.dependencies().contains(right.id()), content="false")

  right.set(21)
  inspect(read_memo_for_test(selected), content="10")
  inspect(runs, content="1")

  choose_left.set(false)
  inspect(read_memo_for_test(selected), content="21")
  inspect(runs, content="2")
  inspect(selected.dependencies().contains(left.id()), content="false")
  inspect(selected.dependencies().contains(right.id()), content="true")

  left.set(11)
  inspect(read_memo_for_test(selected), content="21")
  inspect(runs, content="2")
}

///|
test "green path skips recompute: unrelated revision only verifies" {
  let rt = Runtime()
  let source = Signal(rt, 1)
  let unrelated = Signal(rt, 0)
  let mut runs = 0
  let derived = Memo(rt, () => {
    runs += 1
    source.get() + 1
  })

  inspect(read_memo_for_test(derived), content="2")
  inspect(runs, content="1")

  unrelated.set(1)
  inspect(derived.is_up_to_date(), content="false")
  inspect(read_memo_for_test(derived), content="2")
  inspect(runs, content="1")
  inspect(derived.is_up_to_date(), content="true")
}

///|
test "backdating early cutoff: stable middle prevents downstream recompute" {
  let rt = Runtime()
  let input = Signal(rt, 4)
  let mut parity_runs = 0
  let mut label_runs = 0
  let is_even = Memo(rt, () => {
    parity_runs += 1
    input.get() % 2 == 0
  })
  let label = Memo(rt, () => {
    label_runs += 1
    if is_even.get() {
      "even"
    } else {
      "odd"
    }
  })

  inspect(read_memo_for_test(label), content="even")
  inspect(parity_runs, content="1")
  inspect(label_runs, content="1")

  input.set(6)
  inspect(read_memo_for_test(label), content="even")
  inspect(parity_runs, content="2")
  inspect(label_runs, content="1")

  input.set(7)
  inspect(read_memo_for_test(label), content="odd")
  inspect(parity_runs, content="3")
  inspect(label_runs, content="2")
}

///|
test "failed read does not record dependency: self cycle is not traced" {
  let rt = Runtime()
  let source = Signal(rt, 100)
  let memo_ref : Ref[Memo[Int]?] = { val: None }
  let mut runs = 0
  let memo = Memo(rt, () => {
    runs += 1
    match memo_ref.val {
      Some(self) =>
        match self.get_result() {
          Ok(value) => ignore(value)
          Err(_) => ()
        }
      None => ()
    }
    source.get()
  })
  memo_ref.val = Some(memo)

  inspect(read_memo_for_test(memo), content="100")
  inspect(runs, content="1")
  inspect(memo.dependencies().contains(memo.id()), content="false")

  source.set(200)
  inspect(read_memo_for_test(memo), content="200")
  inspect(runs, content="2")
  inspect(memo.dependencies().contains(memo.id()), content="false")
}

///|
test "cycle cleanup preserves previous trace: in_progress cleared on verify error" {
  let rt = Runtime()
  let tick = Signal(rt, 0)
  let a = Memo(rt, () => 1)
  let b = Memo(rt, () => 2)

  inspect(read_memo_for_test(a), content="1")
  inspect(read_memo_for_test(b), content="2")

  let a_idx = current_model_pull_memo_idx(rt, a.id())
  let b_idx = current_model_pull_memo_idx(rt, b.id())
  rt.pull.memos[a_idx].dependencies = [b.id()]
  rt.pull.memos[b_idx].dependencies = [a.id()]

  tick.set(1)
  match rt.pull_verify(a.id()) {
    Ok(_) => abort("expected cycle during trace verification")
    Err(_) => ()
  }

  inspect(rt.pull.memos[a_idx].in_progress, content="false")
  inspect(rt.pull.memos[b_idx].in_progress, content="false")
  inspect(rt.pull.memos[a_idx].dependencies.length(), content="1")
  inspect(rt.pull.memos[a_idx].dependencies[0] == b.id(), content="true")
  inspect(rt.pull.memos[b_idx].dependencies.length(), content="1")
  inspect(rt.pull.memos[b_idx].dependencies[0] == a.id(), content="true")
}
