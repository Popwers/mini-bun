#!/bin/sh
# Smoke-test a built mini-bun image. Usage: smoke-test.sh <image> [expected-version]
# expected-version is the bare version without the leading v (e.g. 1.3.14).
set -eu

IMAGE="${1:?usage: smoke-test.sh <image> [expected-version]}"
EXPECTED="${2:-}"

echo "--- bun --version via entrypoint"
VERSION="$(docker run --rm "$IMAGE" --version)"
echo "reported: $VERSION"
if [ -n "$EXPECTED" ] && [ "$VERSION" != "$EXPECTED" ]; then
  echo "FAIL: image reports $VERSION, expected $EXPECTED" >&2
  exit 1
fi

echo "--- bunx symlink"
docker run --rm "$IMAGE" sh -c 'bunx --version' > /dev/null

echo "--- node fallback runs a script"
docker run --rm "$IMAGE" sh -c 'echo "console.log(\"ok\")" > /tmp/t.js && node /tmp/t.js' | grep -qx ok

echo "--- eval works (exercises the UPX-unpacked runtime)"
docker run --rm "$IMAGE" bun -e 'console.log(1 + 1)' | grep -qx 2

echo "--- TLS fetch (embedded CA store)"
docker run --rm "$IMAGE" bun -e 'fetch("https://bun.sh").then(r => { if (!r.ok) process.exit(1); console.log("fetch", r.status); })'

echo "SMOKE OK"
