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
