///|
/// Compute a lowercase SHA-256 digest in OCI's `sha256:<hex>` form.
pub fn sha256_digest(data : Bytes) -> String {
  let digest = @sha256.Digest::new()
  for b in data {
    digest.write(b)
  }
  "sha256:" + digest.check_sum()
}

///|
/// Validate an OCI digest reference.
pub fn valid_digest(value : String) -> Bool {
  value =~ re"^sha256:[0-9a-f]{64}$"
}
