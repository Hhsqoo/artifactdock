#!/usr/bin/env bash
set -euo pipefail

base='http://127.0.0.1:5051'
root="${RUNNER_TEMP:-/tmp}/artifactdock-range-${RANDOM}"
moon run src -- --root "$root" --host 127.0.0.1 --port 5051 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

ready=0
for _ in {1..50}; do
  if curl -fsS "$base/v2/" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.2
done
test "$ready" -eq 1

digest="sha256:$(printf 'hello range' | sha256sum | cut -d ' ' -f 1)"
upload_status=$(printf 'hello range' | curl -sS -o /dev/null -w '%{http_code}' \
  -X POST "$base/v2/demo/range/blobs/uploads/?digest=$digest" \
  --data-binary @-)
test "$upload_status" = 201

foreign_status=$(curl -sS -o /dev/null -w '%{http_code}' \
  "$base/v2/other/repo/blobs/$digest")
test "$foreign_status" = 404
mount_status=$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
  "$base/v2/other/repo/blobs/uploads/?mount=${digest/://%3A}&from=demo%2Frange")
test "$mount_status" = 201
test "$(curl -sS "$base/v2/other/repo/blobs/$digest")" = 'hello range'

upload_start=$(curl -sS -o /dev/null -D "$root.headers" \
  -w '%{http_code}' -X POST "$base/v2/demo/range/blobs/uploads/")
test "$upload_start" = 202
upload_id=$(grep -i '^docker-upload-uuid:' "$root.headers" | cut -d: -f2 | tr -d '\r ')
wrong_patch=$(curl -sS -o /dev/null -w '%{http_code}' -X PATCH \
  --data-binary 'wrong' "$base/v2/other/repo/blobs/uploads/$upload_id")
test "$wrong_patch" = 404
delete_status=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
  "$base/v2/demo/range/blobs/uploads/$upload_id")
test "$delete_status" = 204

partial_status=$(curl -sS -o "$root.body" -D "$root.headers" \
  -w '%{http_code}' -H 'Range: bytes=6-10' \
  "$base/v2/demo/range/blobs/$digest")
test "$partial_status" = 206
test "$(cat "$root.body")" = range
grep -iq '^content-range: bytes 6-10/11' "$root.headers"
grep -iq '^accept-ranges: bytes' "$root.headers"

invalid_status=$(curl -sS -o /dev/null -D "$root.headers" \
  -w '%{http_code}' -H 'Range: bytes=11-' \
  "$base/v2/demo/range/blobs/$digest")
test "$invalid_status" = 416
grep -iq '^content-range: bytes \*/11' "$root.headers"

for tag in c a b; do
  status=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
    -H 'Content-Type: application/vnd.oci.image.manifest.v1+json' \
    --data-binary '{"schemaVersion":2}' \
    "$base/v2/demo/range/manifests/$tag")
  test "$status" = 201
done

first_page=$(curl -sS -D "$root.headers" \
  "$base/v2/demo/range/tags/list?n=2")
test "$first_page" = '{"name":"demo/range","tags":["a","b"]}'
grep -Fq '</v2/demo/range/tags/list?n=2&last=b>; rel="next"' "$root.headers"

second_page=$(curl -sS "$base/v2/demo/range/tags/list?n=2&last=b")
test "$second_page" = '{"name":"demo/range","tags":["c"]}'
