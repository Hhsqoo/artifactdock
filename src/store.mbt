///|
struct RegistryStore {
  root : String
  mut next_upload : Int
}

///|
pub fn RegistryStore::new(root : String) -> RegistryStore {
  { root, next_upload: 0, }
}

///|
fn RegistryStore::blobs_dir(self : RegistryStore) -> String {
  self.root + "/blobs"
}

///|
fn RegistryStore::uploads_dir(self : RegistryStore) -> String {
  self.root + "/uploads"
}

///|
fn RegistryStore::repo_dir(self : RegistryStore, repository : String) -> String {
  self.root + "/repos/" + repository
}

///|
fn RegistryStore::blob_path(self : RegistryStore, digest : String) -> String {
  self.blobs_dir() + "/" + digest[7:].to_owned()
}

///|
fn RegistryStore::blob_link_dir(
  self : RegistryStore,
  repository : String,
) -> String {
  self.repo_dir(repository) + "/blobs"
}

///|
fn RegistryStore::blob_link_path(
  self : RegistryStore,
  repository : String,
  digest : String,
) -> String {
  self.blob_link_dir(repository) + "/" + digest[7:].to_owned()
}

///|
fn RegistryStore::upload_path(
  self : RegistryStore,
  upload_id : String,
) -> String {
  self.uploads_dir() + "/" + upload_id
}

///|
fn RegistryStore::upload_owner_path(
  self : RegistryStore,
  upload_id : String,
) -> String {
  self.upload_path(upload_id) + ".repo"
}

///|
fn RegistryStore::tag_path(
  self : RegistryStore,
  repository : String,
  tag : String,
) -> String {
  self.repo_dir(repository) + "/tags/" + tag
}

///|
fn RegistryStore::manifest_tag_dir(
  self : RegistryStore,
  repository : String,
) -> String {
  self.repo_dir(repository) + "/tags"
}

///|
fn RegistryStore::manifest_type_dir(
  self : RegistryStore,
  repository : String,
) -> String {
  self.repo_dir(repository) + "/manifest-types"
}

///|
fn RegistryStore::manifest_type_path(
  self : RegistryStore,
  repository : String,
  digest : String,
) -> String {
  self.manifest_type_dir(repository) + "/" + digest[7:].to_owned()
}

///|
async fn write_bytes(path : String, data : Bytes) -> Unit {
  let file = @fs.open(
    path,
    mode=WriteOnly,
    sync=Data,
    create_mode=CreateOrTruncate,
  )
  defer file.close()
  file.write(data)
  file.sync(only_data=true)
}

///|
async fn read_bytes(path : String) -> Bytes? {
  guard @fs.exists(path) else { return None }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  Some(file.read_all().binary())
}

///|
async fn append_bytes(path : String, data : Bytes) -> Unit {
  let file = @fs.open(
    path,
    mode=WriteOnly,
    append=true,
    sync=Data,
    create_mode=OpenOrCreate,
  )
  defer file.close()
  file.write(data)
  file.sync(only_data=true)
}

///|
async fn atomic_write(path : String, data : Bytes, suffix : String) -> Unit {
  let temp = path + ".tmp-" + suffix
  write_bytes(temp, data)
  @fs.rename(temp, path, replace=true)
}

///|
pub async fn RegistryStore::ensure(self : RegistryStore) -> Unit {
  ensure_dir(self.root)
  ensure_dir(self.blobs_dir())
  ensure_dir(self.uploads_dir())
  ensure_dir(self.root + "/repos")
}

///|
async fn ensure_dir(path : String) -> Unit {
  if !@fs.exists(path) {
    @fs.mkdir(path, recursive=true) catch {
      err => if !@fs.exists(path) { raise err }
    }
  }
}

///|
pub async fn RegistryStore::put_blob(
  self : RegistryStore,
  data : Bytes,
) -> String {
  let digest = sha256_digest(data)
  let path = self.blob_path(digest)
  guard !@fs.exists(path) else { return digest }
  atomic_write(path, data, "blob")
  digest
}

///|
pub async fn RegistryStore::get_blob(
  self : RegistryStore,
  digest : String,
) -> Bytes? {
  guard valid_digest(digest) else { return None }
  read_bytes(self.blob_path(digest))
}

///|
pub async fn RegistryStore::has_blob(
  self : RegistryStore,
  digest : String,
) -> Bool {
  valid_digest(digest) && @fs.exists(self.blob_path(digest))
}

///|
pub async fn RegistryStore::has_repository_blob(
  self : RegistryStore,
  repository : String,
  digest : String,
) -> Bool {
  valid_repository(repository) &&
  self.has_blob(digest) &&
  @fs.exists(self.blob_link_path(repository, digest))
}

///|
pub async fn RegistryStore::get_repository_blob(
  self : RegistryStore,
  repository : String,
  digest : String,
) -> Bytes? {
  guard self.has_repository_blob(repository, digest) else { return None }
  self.get_blob(digest)
}

///|
/// Remove a repository's blob link while retaining shared content for GC.
pub async fn RegistryStore::delete_repository_blob(
  self : RegistryStore,
  repository : String,
  digest : String,
) -> Bool {
  guard valid_repository(repository) && valid_digest(digest) else {
    return false
  }
  let path = self.blob_link_path(repository, digest)
  guard @fs.exists(path) else { return false }
  @fs.remove(path)
  true
}

///|
async fn RegistryStore::link_blob(
  self : RegistryStore,
  repository : String,
  digest : String,
) -> Unit {
  let path = self.blob_link_path(repository, digest)
  ensure_dir(self.blob_link_dir(repository))
  if !@fs.exists(path) {
    write_bytes(path, b"")
  }
}

///|
pub async fn RegistryStore::mount_blob(
  self : RegistryStore,
  repository : String,
  source : String,
  digest : String,
) -> Bool {
  guard valid_repository(repository) && self.has_repository_blob(source, digest) else {
    return false
  }
  self.link_blob(repository, digest)
  true
}

///|
pub async fn RegistryStore::put_manifest(
  self : RegistryStore,
  repository : String,
  reference : String,
  data : Bytes,
) -> String {
  self.put_manifest_with_type(
    repository, reference, data, "application/vnd.oci.image.manifest.v1+json",
  )
}

///|
/// Store a manifest and preserve the media type supplied by its client.
pub async fn RegistryStore::put_manifest_with_type(
  self : RegistryStore,
  repository : String,
  reference : String,
  data : Bytes,
  content_type : String,
) -> String {
  guard valid_repository(repository) && valid_manifest_reference(reference) else {
    return ""
  }
  let digest = self.put_blob(data)
  let tag_dir = self.manifest_tag_dir(repository)
  ensure_dir(tag_dir)
  let type_dir = self.manifest_type_dir(repository)
  ensure_dir(type_dir)
  atomic_write(
    self.manifest_type_path(repository, digest),
    @utf8.encode(content_type),
    "manifest-type",
  )
  guard !valid_digest(reference) else { return digest }
  atomic_write(
    self.tag_path(repository, reference),
    @utf8.encode(digest),
    "tag",
  )
  digest
}

///|
/// Add a tag to a manifest already stored in the repository.
pub async fn RegistryStore::tag_manifest(
  self : RegistryStore,
  repository : String,
  tag : String,
  digest : String,
) -> Bool {
  guard valid_repository(repository) &&
    valid_reference(tag) &&
    valid_digest(digest) &&
    @fs.exists(self.manifest_type_path(repository, digest)) &&
    self.has_blob(digest) else {
    return false
  }
  ensure_dir(self.manifest_tag_dir(repository))
  atomic_write(self.tag_path(repository, tag), @utf8.encode(digest), "tag")
  true
}

///|
/// Return a persisted manifest media type, or the OCI image default.
pub async fn RegistryStore::manifest_content_type(
  self : RegistryStore,
  repository : String,
  digest : String,
) -> String {
  let default_type = "application/vnd.oci.image.manifest.v1+json"
  guard valid_repository(repository) && valid_digest(digest) else {
    return default_type
  }
  let value = read_bytes(self.manifest_type_path(repository, digest)) catch {
    _ => None
  }
  match value {
    Some(bytes) => @utf8.decode(bytes) catch { _ => default_type }
    None => default_type
  }
}

///|
pub async fn RegistryStore::get_manifest(
  self : RegistryStore,
  repository : String,
  reference : String,
) -> Bytes? {
  guard valid_repository(repository) && valid_manifest_reference(reference) else {
    return None
  }
  let digest : String? = if valid_digest(reference) {
    Some(reference)
  } else {
    let tag : Bytes? = read_bytes(self.tag_path(repository, reference)) catch {
      _ => None
    }
    match tag {
      Some(value) => Some(@utf8.decode(value)) catch { _ => None }
      None => None
    }
  }
  match digest {
    Some(digest) => {
      guard @fs.exists(self.manifest_type_path(repository, digest)) else {
        return None
      }
      self.get_blob(digest)
    }
    None => None
  }
}

///|
/// Delete a tag, or remove a manifest and every tag that points to it.
/// The content-addressed blob remains available for other repositories and GC.
pub async fn RegistryStore::delete_manifest(
  self : RegistryStore,
  repository : String,
  reference : String,
) -> Bool {
  guard valid_repository(repository) && valid_manifest_reference(reference) else {
    return false
  }
  if !valid_digest(reference) {
    let path = self.tag_path(repository, reference)
    guard @fs.exists(path) else { return false }
    @fs.remove(path)
    return true
  }
  let type_path = self.manifest_type_path(repository, reference)
  guard @fs.exists(type_path) else { return false }
  let tag_dir = self.manifest_tag_dir(repository)
  if @fs.exists(tag_dir) {
    for tag in @fs.readdir(tag_dir, include_hidden=false, sort=false) {
      let target = read_bytes(self.tag_path(repository, tag)) catch {
        _ => None
      }
      match target {
        Some(value) => {
          let digest = @utf8.decode(value) catch { _ => "" }
          if digest == reference {
            @fs.remove(self.tag_path(repository, tag))
          }
        }
        None => ()
      }
    }
  }
  @fs.remove(type_path)
  true
}

///|
/// Remove global content that has no repository blob or manifest reference.
/// Returns the number of content files scanned, reclaimable files, and bytes.
pub async fn RegistryStore::collect_garbage(
  self : RegistryStore,
  dry_run : Bool,
) -> (Int, Int, Int64) {
  let referenced : Map[String, Bool] = Map([])
  let repos = self.root + "/repos"
  if @fs.exists(repos) {
    @fs.walk(
      repos,
      fn(path, entries) {
        if path.has_suffix("/blobs") || path.has_suffix("/manifest-types") {
          for name in entries {
            if valid_digest("sha256:" + name) {
              referenced[name] = true
            }
          }
        }
      },
      max_concurrency=1,
    )
  }
  let blobs = self.blobs_dir()
  guard @fs.exists(blobs) else { return (0, 0, 0L) }
  let mut scanned = 0
  let mut reclaimable = 0
  let mut bytes = 0L
  for name in @fs.readdir(blobs, include_hidden=false, sort=true) {
    guard valid_digest("sha256:" + name) else { continue }
    let path = blobs + "/" + name
    guard @fs.kind(path, follow_symlink=false) is Regular else { continue }
    scanned += 1
    if !referenced.contains(name) {
      bytes += @fs.file_size(path)
      reclaimable += 1
      if !dry_run {
        @fs.remove(path)
      }
    }
  }
  (scanned, reclaimable, bytes)
}

///|
pub async fn RegistryStore::list_tags(
  self : RegistryStore,
  repository : String,
) -> Array[String] {
  guard valid_repository(repository) else { return [] }
  let path = self.manifest_tag_dir(repository)
  guard @fs.exists(path) else { return [] }
  let tags = @fs.readdir(path, include_hidden=false, sort=false)
  sort_ascii(tags)
  tags
}

///|
/// Return repositories that have persisted blobs, tags, or manifests.
pub async fn RegistryStore::list_repositories(
  self : RegistryStore,
) -> Array[String] {
  let root = self.root + "/repos"
  guard @fs.exists(root) else { return [] }
  let repositories : Array[String] = []
  @fs.walk(
    root,
    async fn(path, _entries) {
      guard path != root else { return }
      let repository = path[root.length() + 1:].to_owned()
      if valid_repository(repository) &&
        (
          @fs.exists(path + "/blobs") ||
          @fs.exists(path + "/tags") ||
          @fs.exists(path + "/manifest-types")
        ) {
        repositories.push(repository)
      }
    },
    max_concurrency=1,
  )
  sort_ascii(repositories)
  repositories
}

///|
/// Return every manifest digest currently addressable in a repository.
pub async fn RegistryStore::list_manifest_digests(
  self : RegistryStore,
  repository : String,
) -> Array[String] {
  guard valid_repository(repository) else { return [] }
  let path = self.manifest_type_dir(repository)
  guard @fs.exists(path) else { return [] }
  let digests : Array[String] = []
  for name in @fs.readdir(path, include_hidden=false, sort=true) {
    let digest = "sha256:" + name
    if valid_digest(digest) && self.has_blob(digest) {
      digests.push(digest)
    }
  }
  digests
}

///|
pub async fn RegistryStore::start_upload(
  self : RegistryStore,
  repository : String,
) -> String {
  guard valid_repository(repository) else { return "" }
  ensure_dir(self.uploads_dir())
  let mut sequence = self.next_upload + 1
  let mut upload_id = "u" + sequence.to_string()
  while @fs.exists(self.upload_path(upload_id)) ||
        @fs.exists(self.upload_owner_path(upload_id)) {
    sequence += 1
    upload_id = "u" + sequence.to_string()
  }
  self.next_upload = sequence
  write_bytes(self.upload_owner_path(upload_id), @utf8.encode(repository))
  write_bytes(self.upload_path(upload_id), b"")
  upload_id
}

///|
async fn RegistryStore::owns_upload(
  self : RegistryStore,
  repository : String,
  upload_id : String,
) -> Bool {
  guard valid_repository(repository) && valid_reference(upload_id) else {
    return false
  }
  let owner = read_bytes(self.upload_owner_path(upload_id)) catch { _ => None }
  match owner {
    Some(bytes) => {
      let decoded = @utf8.decode(bytes) catch { _ => "" }
      decoded == repository
    }
    None => false
  }
}

///|
pub async fn RegistryStore::append_upload(
  self : RegistryStore,
  repository : String,
  upload_id : String,
  data : Bytes,
) -> Bool {
  guard self.owns_upload(repository, upload_id) else { return false }
  let path = self.upload_path(upload_id)
  guard @fs.exists(path) else { return false }
  append_bytes(path, data)
  true
}

///|
/// Return the current byte length of an upload session.
pub async fn RegistryStore::upload_size(
  self : RegistryStore,
  repository : String,
  upload_id : String,
) -> Int? {
  guard self.owns_upload(repository, upload_id) else { return None }
  let path = self.upload_path(upload_id)
  guard @fs.exists(path) else { return None }
  Some(@fs.file_size(path).to_int())
}

///|
/// Remove an in-progress upload session.
pub async fn RegistryStore::delete_upload(
  self : RegistryStore,
  repository : String,
  upload_id : String,
) -> Bool {
  guard self.owns_upload(repository, upload_id) else { return false }
  let path = self.upload_path(upload_id)
  guard @fs.exists(path) else { return false }
  @fs.remove(path)
  @fs.remove(self.upload_owner_path(upload_id))
  true
}

///|
pub async fn RegistryStore::finalize_upload(
  self : RegistryStore,
  repository : String,
  upload_id : String,
  expected_digest : String,
) -> (Int, String?) {
  guard valid_digest(expected_digest) else { return (400, None) }
  guard self.owns_upload(repository, upload_id) else { return (404, None) }
  let path = self.upload_path(upload_id)
  let data = match read_bytes(path) {
    Some(value) => value
    None => return (404, None)
  }
  let actual = sha256_digest(data)
  guard actual == expected_digest else { return (400, Some(actual)) }
  let digest = self.put_blob(data)
  self.link_blob(repository, digest)
  @fs.remove(path)
  @fs.remove(self.upload_owner_path(upload_id))
  (201, Some(digest))
}
