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
