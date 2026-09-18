///|
test "OCI routes" {
  assert_true(route_for("/v2/") is Root)
  assert_true(
    route_for("/v2/demo/wasm/blobs/sha256:abc")
    is Blob("demo/wasm", "sha256:abc"),
  )
  assert_true(
    route_for("/v2/demo/wasm/blobs/uploads/") is UploadStart("demo/wasm"),
  )
  assert_true(
    route_for("/v2/demo/wasm/blobs/uploads/u1?digest=sha256:abc")
    is UploadChunk("demo/wasm", "u1"),
  )
  assert_true(
    route_for("/v2/demo/wasm/manifests/v1") is Manifest("demo/wasm", "v1"),
  )
  assert_true(
    route_for("/v2/team/blobs/image/manifests/v1")
    is Manifest("team/blobs/image", "v1"),
  )
  assert_true(route_for("/v2/demo/wasm/tags/list") is Tags("demo/wasm"))
  assert_true(route_for("/health") is Unknown)
  assert_true(query_digest("/upload?digest=sha256:abc") is Some("sha256:abc"))
  assert_true(
    query_digest("/upload?trace=1&digest=sha256:abc&mode=close")
    is Some("sha256:abc"),
  )
}

///|
test "upload ranges" {
  let headers : @http.Headers = { "Content-Range": "0-4" }
  assert_true(content_range_matches(headers, 0, 5))
  assert_false(content_range_matches(headers, 1, 5))
  assert_false(content_range_matches(headers, 0, 4))
  assert_true(content_range_matches({}, 5, 2))
}

///|
test "blob byte ranges" {
  assert_true(select_blob_range({}, 10) is Full)
  assert_true(select_blob_range({ "Range": "bytes=2-5" }, 10) is Partial(2, 5))
  assert_true(select_blob_range({ "Range": "bytes=7-" }, 10) is Partial(7, 9))
  assert_true(select_blob_range({ "Range": "bytes=-3" }, 10) is Partial(7, 9))
  assert_true(select_blob_range({ "Range": "bytes=8-99" }, 10) is Partial(8, 9))
  assert_true(select_blob_range({ "Range": "bytes=10-" }, 10) is Unsatisfiable)
  assert_true(select_blob_range({ "Range": "bytes=-0" }, 10) is Unsatisfiable)
  assert_true(select_blob_range({ "Range": "items=1-2" }, 10) is Full)
  assert_true(select_blob_range({ "Range": "bytes=1-2,4-5" }, 10) is Full)
  assert_true(select_blob_range({ "Range": "bytes=oops" }, 10) is Full)
}

///|
test "manifest JSON validation" {
  assert_true(valid_manifest_json(@utf8.encode("{\"schemaVersion\":2}")))
  assert_true(
    valid_manifest_json(
      @utf8.encode("  {\"schemaVersion\":2,\"manifests\":[]}  "),
    ),
  )
  assert_false(valid_manifest_json(@utf8.encode("{\"schemaVersion\":")))
  assert_false(valid_manifest_json(@utf8.encode("{}")))
  assert_false(valid_manifest_json(@utf8.encode("{\"schemaVersion\":3}")))
  assert_false(valid_manifest_json(@utf8.encode("[]")))
  assert_false(valid_manifest_json([0xFF]))
}

///|
test "manifest digest references" {
  let body : Bytes = b"{\"schemaVersion\":2}"
  let digest = sha256_digest(body)
  assert_true(manifest_reference_matches("v1", digest))
  assert_true(manifest_reference_matches(digest, digest))
  assert_false(manifest_reference_matches("sha256:" + "0".repeat(64), digest))
}
