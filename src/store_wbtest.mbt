///|
async test "filesystem store round trip" {
  let root = @fs.tmpdir(prefix="artifactdock-test-")
  let store = RegistryStore::new(root)
  store.ensure()

  let payload : Bytes = b"hello world"
  let digest = store.put_blob(payload)
  assert_true(store.has_blob(digest))
  assert_true(store.get_blob(digest) is Some(value) && value == payload)
  assert_true(store.get_manifest("demo/wasm", digest) is None)

  let upload_id = store.start_upload()
  let restarted = RegistryStore::new(root)
  let second_upload_id = restarted.start_upload()
  assert_true(second_upload_id != upload_id)
  assert_true(store.append_upload(upload_id, b"hello "))
  assert_true(store.append_upload(upload_id, b"world"))
  let (status, finalized) = store.finalize_upload(upload_id, digest)
  assert_eq(status, 201)
  assert_true(finalized is Some(value) && value == digest)

  let failed_id = store.start_upload()
  assert_true(store.append_upload(failed_id, b"not the expected payload"))
  let (failed_status, actual) = store.finalize_upload(
    failed_id,
    "sha256:" + "0".repeat(64),
  )
  assert_eq(failed_status, 400)
  assert_true(actual is Some(_))
  assert_true(store.delete_upload(failed_id))

  let manifest : Bytes = b"{\"schemaVersion\":2}"
  assert_eq(store.put_manifest("../escape", "v1", manifest), "")
  assert_true(store.get_manifest("../escape", "v1") is None)
  assert_true(store.list_tags("../escape") is [])
  let manifest_digest = store.put_manifest("demo/wasm", "v1", manifest)
  ignore(store.put_manifest("demo/wasm", "a0", manifest))
  assert_true(
    store.get_manifest("demo/wasm", "v1") is Some(value) && value == manifest,
  )
  assert_true(
    store.get_manifest("demo/wasm", manifest_digest) is Some(value) &&
    value == manifest,
  )
  assert_true(store.list_tags("demo/wasm") is ["a0", "v1"])
  ignore(
    store.put_manifest_with_type(
      "demo/wasm", "artifact", manifest, "application/vnd.oci.artifact.manifest.v1+json",
    ),
  )
  assert_eq(
    store.manifest_content_type("demo/wasm", manifest_digest),
    "application/vnd.oci.artifact.manifest.v1+json",
  )

  @fs.rmdir(root, recursive=true)
}
