///|
fn is_lower_alpha(c : Char) -> Bool {
  c >= 'a' && c <= 'z'
}

///|
fn is_upper_alpha(c : Char) -> Bool {
  c >= 'A' && c <= 'Z'
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_repo_alnum(c : Char) -> Bool {
  is_lower_alpha(c) || is_digit(c)
}

///|
fn char_at(value : StringView, index : Int) -> Char {
  value[index].to_int().unsafe_to_char()
}

///|
fn valid_repository_segment(segment : StringView) -> Bool {
  guard segment.length() > 0 else { return false }
  guard is_repo_alnum(char_at(segment, 0)) else { return false }
  let mut i = 1
  while i < segment.length() {
    let c = char_at(segment, i)
    if is_repo_alnum(c) {
      i += 1
    } else if c == '.' {
      guard i + 1 < segment.length() && is_repo_alnum(char_at(segment, i + 1)) else {
        return false
      }
      i += 1
    } else if c == '_' {
      let next = if i + 1 < segment.length() && char_at(segment, i + 1) == '_' {
        i + 2
      } else {
        i + 1
      }
      guard next < segment.length() && is_repo_alnum(char_at(segment, next)) else {
        return false
      }
      i = next
    } else if c == '-' {
      let mut next = i + 1
      while next < segment.length() && char_at(segment, next) == '-' {
        next += 1
      }
      guard next < segment.length() && is_repo_alnum(char_at(segment, next)) else {
        return false
      }
      i = next
    } else {
      return false
    }
  }
  true
}

///| Repository names are deliberately stricter than the full distribution grammar.

///|
/// This keeps filesystem mapping predictable and rejects traversal attempts.
pub fn valid_repository(value : String) -> Bool {
  guard value.length() > 0 else { return false }
  guard value.find("..") is None else { return false }
  guard value.find("\\") is None else { return false }
  guard value.find("//") is None else { return false }
  let mut start = 0
  for i in 0..<value.length() {
    if char_at(value, i) == '/' {
      guard valid_repository_segment(value[start:i]) else { return false }
      start = i + 1
    }
  }
  valid_repository_segment(value[start:])
}

///|
/// Tags and upload IDs are single safe path components.
pub fn valid_reference(value : String) -> Bool {
  guard value.length() > 0 && value.length() <= 128 else { return false }
  guard value.find("/") is None else { return false }
  guard value.find("\\") is None else { return false }
  let first = char_at(value, 0)
  guard is_lower_alpha(first) ||
    is_upper_alpha(first) ||
    is_digit(first) ||
    first == '_' else {
    return false
  }
  for i in 1..<value.length() {
    let c = char_at(value, i)
    guard is_lower_alpha(c) ||
      is_upper_alpha(c) ||
      is_digit(c) ||
      c == '_' ||
      c == '.' ||
      c == '-' else {
      return false
    }
  }
  true
}

///|
pub fn valid_manifest_reference(value : String) -> Bool {
  valid_digest(value) || valid_reference(value)
}
