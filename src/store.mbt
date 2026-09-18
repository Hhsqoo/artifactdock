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
fn RegistryStore::upload_path(
  self : RegistryStore,
  upload_id : String,
) -> String {
  self.uploads_dir() + "/" + upload_id
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
  @fs.mkdir(self.root, recursive=true)
  @fs.mkdir(self.blobs_dir(), recursive=true)
  @fs.mkdir(self.uploads_dir(), recursive=true)
  @fs.mkdir(self.root + "/repos", recursive=true)
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
  @fs.mkdir(tag_dir, recursive=true)
  let type_dir = self.manifest_type_dir(repository)
  @fs.mkdir(type_dir, recursive=true)
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
pub async fn RegistryStore::list_tags(
  self : RegistryStore,
  repository : String,
) -> Array[String] {
  guard valid_repository(repository) else { return [] }
  let path = self.manifest_tag_dir(repository)
  guard @fs.exists(path) else { return [] }
  @fs.readdir(path, include_hidden=false)
}

///|
pub async fn RegistryStore::start_upload(self : RegistryStore) -> String {
  @fs.mkdir(self.uploads_dir(), recursive=true)
  let mut sequence = self.next_upload + 1
  let mut upload_id = "u" + sequence.to_string()
  while @fs.exists(self.upload_path(upload_id)) {
    sequence += 1
    upload_id = "u" + sequence.to_string()
  }
  self.next_upload = sequence
  write_bytes(self.upload_path(upload_id), b"")
  upload_id
}

///|
pub async fn RegistryStore::append_upload(
  self : RegistryStore,
  upload_id : String,
  data : Bytes,
) -> Bool {
  guard valid_reference(upload_id) else { return false }
  let path = self.upload_path(upload_id)
  guard @fs.exists(path) else { return false }
  append_bytes(path, data)
  true
}

///|
/// Return the current byte length of an upload session.
pub async fn RegistryStore::upload_size(
  self : RegistryStore,
  upload_id : String,
) -> Int? {
  guard valid_reference(upload_id) else { return None }
  let path = self.upload_path(upload_id)
  guard @fs.exists(path) else { return None }
  Some(@fs.file_size(path).to_int())
}

///|
/// Remove an in-progress upload session.
pub async fn RegistryStore::delete_upload(
  self : RegistryStore,
  upload_id : String,
) -> Bool {
  guard valid_reference(upload_id) else { return false }
  let path = self.upload_path(upload_id)
  guard @fs.exists(path) else { return false }
  @fs.remove(path)
  true
}

///|
pub async fn RegistryStore::finalize_upload(
  self : RegistryStore,
  upload_id : String,
  expected_digest : String,
) -> (Int, String?) {
  guard valid_reference(upload_id) && valid_digest(expected_digest) else {
    return (400, None)
  }
  let path = self.upload_path(upload_id)
  let data = match read_bytes(path) {
    Some(value) => value
    None => return (404, None)
  }
  let actual = sha256_digest(data)
  guard actual == expected_digest else { return (400, Some(actual)) }
  let digest = self.put_blob(data)
  @fs.remove(path)
  (201, Some(digest))
}
