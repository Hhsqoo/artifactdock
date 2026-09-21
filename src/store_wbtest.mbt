///|
async test "filesystem store round trip" {
  let root = @fs.tmpdir(prefix="artifactdock-test-")
  let store = RegistryStore::new(root)
  store.ensure()

  let payload : Bytes = b"hello world"
  let digest = store.put_blob(payload)
  assert_true(store.has_blob(digest))
  assert_true(store.get_blob(digest) is Some(value) && value == payload)
  assert_false(store.has_repository_blob("demo/wasm", digest))
  assert_true(store.get_manifest("demo/wasm", digest) is None)

  let upload_id = store.start_upload("demo/wasm")
  let restarted = RegistryStore::new(root)
  let second_upload_id = restarted.start_upload("demo/wasm")
  assert_true(second_upload_id != upload_id)
  assert_true(store.upload_size("other/repo", upload_id) is None)
  assert_false(store.append_upload("other/repo", upload_id, b"wrong"))
  assert_false(store.delete_upload("other/repo", upload_id))
  let (wrong_status, _) = store.finalize_upload("other/repo", upload_id, digest)
  assert_eq(wrong_status, 404)
  assert_true(store.append_upload("demo/wasm", upload_id, b"hello "))
  assert_true(store.append_upload("demo/wasm", upload_id, b"world"))
  let (status, finalized) = store.finalize_upload(
    "demo/wasm", upload_id, digest,
  )
  assert_eq(status, 201)
  assert_true(finalized is Some(value) && value == digest)
  assert_true(store.has_repository_blob("demo/wasm", digest))
  assert_false(store.has_repository_blob("other/repo", digest))
  assert_true(store.get_repository_blob("other/repo", digest) is None)
  assert_false(store.mount_blob("other/repo", "missing/repo", digest))
  assert_true(store.mount_blob("other/repo", "demo/wasm", digest))
  assert_true(
    store.get_repository_blob("other/repo", digest) is Some(value) &&
    value == payload,
  )
  assert_true(store.delete_repository_blob("demo/wasm", digest))
  assert_false(store.has_repository_blob("demo/wasm", digest))
  assert_true(store.has_repository_blob("other/repo", digest))
  assert_true(store.get_blob(digest) is Some(value) && value == payload)
  assert_false(store.delete_repository_blob("demo/wasm", digest))

  let failed_id = store.start_upload("demo/wasm")
  assert_true(
    store.append_upload("demo/wasm", failed_id, b"not the expected payload"),
  )
  let (failed_status, actual) = store.finalize_upload(
    "demo/wasm",
    failed_id,
    "sha256:" + "0".repeat(64),
  )
  assert_eq(failed_status, 400)
  assert_true(actual is Some(_))
  assert_true(store.delete_upload("demo/wasm", failed_id))

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
  assert_eq(
    store.put_manifest("other/repo", "shared", manifest),
    manifest_digest,
  )
  assert_true(store.delete_manifest("demo/wasm", "a0"))
  assert_true(store.get_manifest("demo/wasm", "a0") is None)
  assert_true(store.get_manifest("demo/wasm", "v1") is Some(_))
  assert_true(store.get_manifest("demo/wasm", "artifact") is Some(_))
  assert_true(store.delete_manifest("demo/wasm", manifest_digest))
  assert_true(store.get_manifest("demo/wasm", manifest_digest) is None)
  assert_true(store.get_manifest("demo/wasm", "v1") is None)
  assert_true(store.list_tags("demo/wasm") is [])
  assert_true(store.get_blob(manifest_digest) is Some(_))
  assert_true(store.get_manifest("other/repo", "shared") is Some(_))
  assert_true(store.list_manifest_digests("other/repo") == [manifest_digest])
  assert_false(store.delete_manifest("demo/wasm", manifest_digest))

  let orphan : Bytes = b"orphan"
  let orphan_digest = store.put_blob(orphan)
  let (dry_scanned, dry_reclaimable, dry_bytes) = store.collect_garbage(true)
  assert_eq(dry_scanned, 3)
  assert_eq(dry_reclaimable, 1)
  assert_eq(dry_bytes, orphan.length().to_int64())
  assert_true(store.get_blob(orphan_digest) is Some(_))
  let (scanned, reclaimable, reclaimed_bytes) = store.collect_garbage(false)
  assert_eq(scanned, 3)
  assert_eq(reclaimable, 1)
  assert_eq(reclaimed_bytes, orphan.length().to_int64())
  assert_true(store.get_blob(orphan_digest) is None)
  assert_true(store.get_blob(digest) is Some(_))
  assert_true(store.get_blob(manifest_digest) is Some(_))

  @fs.rmdir(root, recursive=true)
}
