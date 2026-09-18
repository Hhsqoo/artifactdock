///|
enum RegistryRoute {
  Root
  Blob(String, String)
  UploadStart(String)
  UploadChunk(String, String)
  Manifest(String, String)
  Tags(String)
  Unknown
}

///|
fn without_query(path : String) -> String {
  match path.find("?") {
    Some(index) => path[:index].to_owned()
    None => path
  }
}

///|
fn query_digest(path : String) -> String? {
  match path.find("?") {
    Some(index) => {
      let query : StringView = path[index + 1:]
      for field in query.split("&") {
        match field.find("=") {
          Some(equal) if field[:equal] == "digest" =>
            return Some(field[equal + 1:].to_owned())
          _ => continue
        }
      }
      None
    }
    None => None
  }
}

///|
fn route_for(path : String) -> RegistryRoute {
  let clean = without_query(path)
  if clean == "/v2/" || clean == "/v2" {
    return Root
  }
  guard clean.length() >= 4 && clean[:4] == "/v2/" else { return Unknown }
  let rest : StringView = clean[4:]
  if rest.rev_find("/blobs/uploads/") is Some(index) {
    let repository = rest[:index].to_owned()
    let upload_id = rest[index + 15:].to_owned()
    if upload_id == "" {
      UploadStart(repository)
    } else {
      UploadChunk(repository, upload_id)
    }
  } else if rest.rev_find("/blobs/") is Some(index) {
    Blob(rest[:index].to_owned(), rest[index + 7:].to_owned())
  } else if rest.rev_find("/manifests/") is Some(index) {
    Manifest(rest[:index].to_owned(), rest[index + 11:].to_owned())
  } else if rest.rev_find("/tags/list") is Some(index) &&
    index + 10 == rest.length() {
    Tags(rest[:index].to_owned())
  } else {
    Unknown
  }
}

///|
async fn send_error(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
) -> Unit {
  let body = "{\"errors\":[{\"code\":\"" +
    reason +
    "\",\"message\":\"" +
    reason +
    "\"}]}"
  conn
  ..send_response(code, reason, extra_headers={
    "Content-Type": "application/json",
  })
  ..write(@utf8.encode(body))
  .end_response()
}

///|
async fn send_empty(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
) -> Unit {
  conn.send_response(code, reason, extra_headers={
    "Docker-Distribution-API-Version": "registry/2.0",
  })
  conn.end_response()
}

///|
async fn send_blob(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  body : Bytes,
  digest : String,
) -> Unit {
  conn
  ..send_response(code, reason, extra_headers={
    "Content-Type": "application/octet-stream",
    "Content-Length": body.length().to_string(),
    "Docker-Content-Digest": digest,
  })
  ..write(body)
  .end_response()
}

///|
async fn send_manifest(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  body : Bytes,
  content_type : String,
) -> Unit {
  let digest = sha256_digest(body)
  conn
  ..send_response(code, reason, extra_headers={
    "Content-Type": content_type,
    "Content-Length": body.length().to_string(),
    "Docker-Content-Digest": digest,
  })
  ..write(body)
  .end_response()
}

///|
/// OCI manifests and indexes are JSON objects. Decode as UTF-8 first so
/// malformed payloads cannot be persisted as apparently valid manifests.
fn valid_manifest_json(body : Bytes) -> Bool {
  let text = @utf8.decode(body) catch { _ => return false }
  let value = @json.parse(text) catch { _ => return false }
  match value {
    Object(object) =>
      match object.get("schemaVersion") {
        Some(Number(version, ..)) => version == 2.0
        _ => false
      }
    _ => false
  }
}

///|
fn manifest_reference_matches(reference : String, digest : String) -> Bool {
  !valid_digest(reference) || reference == digest
}

///|
async fn handle_blob(
  store : RegistryStore,
  repository : String,
  digest : String,
  request_method : @http.RequestMethod,
  conn : @http.ServerConnection,
) -> Unit {
  guard valid_repository(repository) && valid_digest(digest) else {
    send_error(conn, 400, "DIGEST_INVALID")
    return
  }
  let body = match store.get_blob(digest) {
    Some(value) => value
    None => {
      send_error(conn, 404, "BLOB_UNKNOWN")
      return
    }
  }
  match request_method {
    Head => {
      conn.send_response(200, "OK", extra_headers={
        "Content-Length": body.length().to_string(),
        "Docker-Content-Digest": digest,
      })
      conn.end_response()
    }
    Get => send_blob(conn, 200, "OK", body, digest)
    _ => send_error(conn, 405, "UNSUPPORTED")
  }
}

///|
async fn handle_manifest(
  store : RegistryStore,
  repository : String,
  reference : String,
  request_method : @http.RequestMethod,
  conn : @http.ServerConnection,
  headers : @http.Headers,
  body_reader : &@io.Reader,
) -> Unit {
  guard valid_repository(repository) && valid_manifest_reference(reference) else {
    send_error(conn, 400, "MANIFEST_INVALID")
    return
  }
  if request_method is Put {
    let body = body_reader.read_all().binary()
    guard valid_manifest_json(body) else {
      send_error(conn, 400, "MANIFEST_INVALID")
      return
    }
    let body_digest = sha256_digest(body)
    guard manifest_reference_matches(reference, body_digest) else {
      send_error(conn, 400, "DIGEST_INVALID")
      return
    }
    let content_type = match headers.get("Content-Type") {
      Some(value) =>
        if value.length() > 0 &&
          value.find("\r") is None &&
          value.find("\n") is None {
          value
        } else {
          "application/vnd.oci.image.manifest.v1+json"
        }
      None => "application/vnd.oci.image.manifest.v1+json"
    }
    let digest = store.put_manifest_with_type(
      repository, reference, body, content_type,
    )
    conn.send_response(201, "Created", extra_headers={
      "Location": "/v2/" + repository + "/manifests/" + digest,
      "Docker-Content-Digest": digest,
    })
    conn.end_response()
    return
  }
  let value = match store.get_manifest(repository, reference) {
    Some(value) => value
    None => {
      send_error(conn, 404, "MANIFEST_UNKNOWN")
      return
    }
  }
  match request_method {
    Head => {
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": store.manifest_content_type(
          repository,
          sha256_digest(value),
        ),
        "Content-Length": value.length().to_string(),
        "Docker-Content-Digest": sha256_digest(value),
      })
      conn.end_response()
    }
    Get =>
      send_manifest(
        conn,
        200,
        "OK",
        value,
        store.manifest_content_type(repository, sha256_digest(value)),
      )
    _ => send_error(conn, 405, "UNSUPPORTED")
  }
}

///|
async fn handle_tags(
  store : RegistryStore,
  repository : String,
  request_method : @http.RequestMethod,
  conn : @http.ServerConnection,
) -> Unit {
  guard valid_repository(repository) else {
    send_error(conn, 400, "NAME_INVALID")
    return
  }
  guard request_method is Get else {
    send_error(conn, 405, "UNSUPPORTED")
    return
  }
  let tags = store.list_tags(repository)
  let mut body = "{\"name\":\"" + repository + "\",\"tags\":["
  for i, tag in tags {
    if i > 0 {
      body += ","
    }
    body += "\"" + tag + "\""
  }
  body += "]}"
  conn
  ..send_response(200, "OK", extra_headers={
    "Content-Type": "application/json",
  })
  ..write(@utf8.encode(body))
  .end_response()
}

///|
fn parse_content_range(headers : @http.Headers) -> (Int, Int)? {
  match headers.get("Content-Range") {
    Some(value) =>
      match value.find("-") {
        Some(index) => {
          let start = @string.parse_int(value[:index]) catch { _ => -1 }
          let end = @string.parse_int(value[index + 1:]) catch { _ => -1 }
          if start >= 0 && end >= start {
            Some((start, end))
          } else {
            None
          }
        }
        None => None
      }
    None => None
  }
}

///|
fn content_range_matches(
  headers : @http.Headers,
  current : Int,
  chunk_length : Int,
) -> Bool {
  match headers.get("Content-Range") {
    None => true
    Some(_) =>
      match parse_content_range(headers) {
        Some((start, end)) =>
          start == current && end - start + 1 == chunk_length
        None => false
      }
  }
}

///|
fn upload_range(size : Int) -> String {
  if size == 0 {
    "0-0"
  } else {
    "0-" + (size - 1).to_string()
  }
}

///|
async fn send_upload_created(
  conn : @http.ServerConnection,
  repository : String,
  digest : String,
) -> Unit {
  conn.send_response(201, "Created", extra_headers={
    "Location": "/v2/" + repository + "/blobs/" + digest,
    "Docker-Content-Digest": digest,
  })
  conn.end_response()
}

///|
async fn handle_upload(
  store : RegistryStore,
  repository : String,
  upload_id : String?,
  request_method : @http.RequestMethod,
  path : String,
  headers : @http.Headers,
  body_reader : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  guard valid_repository(repository) else {
    send_error(conn, 400, "NAME_INVALID")
    return
  }
  match (request_method, upload_id) {
    (Post, None) => {
      let id = store.start_upload()
      let data = body_reader.read_all().binary()
      if data.length() > 0 {
        ignore(store.append_upload(id, data))
      }
      match query_digest(path) {
        Some(expected) => {
          let (status, digest) = store.finalize_upload(id, expected)
          match (status, digest) {
            (201, Some(value)) => send_upload_created(conn, repository, value)
            (400, _) => send_error(conn, 400, "DIGEST_INVALID")
            _ => send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
          }
        }
        None => {
          conn.send_response(202, "Accepted", extra_headers={
            "Location": "/v2/" + repository + "/blobs/uploads/" + id,
            "Docker-Upload-UUID": id,
            "Range": upload_range(data.length()),
          })
          conn.end_response()
        }
      }
    }
    (Patch, Some(id)) => {
      let current = match store.upload_size(id) {
        Some(value) => value
        None => {
          send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
          return
        }
      }
      let data = body_reader.read_all().binary()
      guard content_range_matches(headers, current, data.length()) else {
        send_error(conn, 416, "RANGE_INVALID")
        return
      }
      guard store.append_upload(id, data) else {
        send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
        return
      }
      conn.send_response(202, "Accepted", extra_headers={
        "Location": "/v2/" + repository + "/blobs/uploads/" + id,
        "Docker-Upload-UUID": id,
        "Range": upload_range(current + data.length()),
      })
      conn.end_response()
    }
    (Get, Some(id)) => {
      let current = match store.upload_size(id) {
        Some(value) => value
        None => {
          send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
          return
        }
      }
      conn.send_response(204, "No Content", extra_headers={
        "Location": "/v2/" + repository + "/blobs/uploads/" + id,
        "Docker-Upload-UUID": id,
        "Range": upload_range(current),
      })
      conn.end_response()
    }
    (Delete, Some(id)) => {
      guard store.delete_upload(id) else {
        send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
        return
      }
      conn.send_response(204, "No Content")
      conn.end_response()
    }
    (Put, Some(id)) => {
      let expected = match query_digest(path) {
        Some(value) => value
        None => {
          send_error(conn, 400, "DIGEST_INVALID")
          return
        }
      }
      let current = match store.upload_size(id) {
        Some(value) => value
        None => {
          send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
          return
        }
      }
      let data = body_reader.read_all().binary()
      guard content_range_matches(headers, current, data.length()) else {
        send_error(conn, 416, "RANGE_INVALID")
        return
      }
      if data.length() > 0 {
        guard store.append_upload(id, data) else {
          send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
          return
        }
      }
      let (status, digest) = store.finalize_upload(id, expected)
      match (status, digest) {
        (201, Some(value)) => send_upload_created(conn, repository, value)
        (400, Some(_)) => send_error(conn, 400, "DIGEST_INVALID")
        (400, None) => send_error(conn, 400, "DIGEST_INVALID")
        _ => send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
      }
    }
    _ => send_error(conn, 404, "BLOB_UPLOAD_UNKNOWN")
  }
}

///|
pub async fn serve(store : RegistryStore, host : String, port : Int) -> Unit {
  store.ensure()
  let server = @http.Server(@socket.Addr::parse(host + ":" + port.to_string()))
  server.run_forever() <| ((request, body, conn) => {
    let route = route_for(request.path)
    match route {
      Root =>
        match request.meth {
          Get | Head => send_empty(conn, 200, "OK")
          _ => send_error(conn, 405, "UNSUPPORTED")
        }
      Blob(repository, digest) =>
        handle_blob(store, repository, digest, request.meth, conn)
      UploadStart(repository) =>
        handle_upload(
          store,
          repository,
          None,
          request.meth,
          request.path,
          request.headers,
          body,
          conn,
        )
      UploadChunk(repository, id) =>
        handle_upload(
          store,
          repository,
          Some(id),
          request.meth,
          request.path,
          request.headers,
          body,
          conn,
        )
      Manifest(repository, reference) =>
        handle_manifest(
          store,
          repository,
          reference,
          request.meth,
          conn,
          request.headers,
          body,
        )
      Tags(repository) => handle_tags(store, repository, request.meth, conn)
      Unknown => send_error(conn, 404, "NAME_UNKNOWN")
    }
  })
}
