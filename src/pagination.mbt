///|
/// Compare strings by UTF-16 code unit order, matching ASCII order for all
/// repository names and tags accepted by ArtifactDock.
fn compare_code_units(left : String, right : String) -> Int {
  let shared = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<shared {
    if left[index] != right[index] {
      return if left[index] < right[index] { -1 } else { 1 }
    }
  }
  left.length() - right.length()
}

///|
fn sort_ascii(values : Array[String]) -> Unit {
  values.sort_by(compare_code_units)
}

///|
/// Paginate an already ASCII-sorted list after an optional exclusive cursor.
fn list_page(
  values : Array[String],
  limit : Int?,
  last : String?,
) -> (Array[String], String?) {
  let page : Array[String] = []
  if limit is Some(0) {
    return (page, None)
  }
  for value in values {
    if last is Some(cursor) && compare_code_units(value, cursor) <= 0 {
      continue
    }
    if limit is Some(n) && page.length() >= n {
      return (page, Some(page[page.length() - 1]))
    }
    page.push(value)
  }
  (page, None)
}
