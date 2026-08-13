///|
test "fresh and incremental adapters compare normalized outcomes" {
  assert_true(@differential.canonical_matches())
}
