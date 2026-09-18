///|
test "digest validation" {
  assert_true(valid_digest("sha256:" + "a".repeat(64)))
  assert_false(valid_digest("sha256:ABC"))
  assert_false(valid_digest("md5:" + "a".repeat(32)))
}

///|
test "path validation" {
  assert_true(valid_repository("library/demo"))
  assert_true(valid_repository("team/tools/image"))
  assert_true(valid_repository("team__tools/image--debug"))
  assert_false(valid_repository("../escape"))
  assert_false(valid_repository("team//image"))
  assert_false(valid_repository("team-/image"))
  assert_true(valid_reference("v1.2.3"))
  assert_true(valid_reference("v..1"))
  assert_false(valid_reference("../../tmp"))
}
