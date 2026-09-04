#!/bin/sh
# Read-only health check for a mini-bun image. Usage: verify-doctor.sh <image>
set -eu

IMAGE="${1:?usage: verify-doctor.sh <image>}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! docker info >/dev/null 2>&1; then
	echo "FAIL: docker info" >&2
	exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
	echo "FAIL: image missing: $IMAGE" >&2
	exit 1
fi

BUN_PIN="$(grep 'ARG BUN_VERSION=' Dockerfile | cut -d= -f2)"
EXPECTED="${BUN_PIN#v}"
ALPINE_PIN="$(sed -n 's/^FROM alpine:\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' Dockerfile | head -n 1)"

VERSION="$(docker run --rm "$IMAGE" --version)"
if [ "$VERSION" != "$EXPECTED" ]; then
	echo "FAIL: bun version $VERSION, expected $EXPECTED" >&2
	exit 1
fi

OS_RELEASE="$(docker run --rm "$IMAGE" cat /etc/os-release)"
echo "$OS_RELEASE" | grep -q "^VERSION_ID=${ALPINE_PIN}" || {
	echo "FAIL: alpine VERSION_ID is not ${ALPINE_PIN}.x" >&2
	echo "$OS_RELEASE" >&2
	exit 1
}

BYTES="$(docker image inspect -f '{{.Size}}' "$IMAGE")"
MEASURED="$(awk "BEGIN { printf \"%.1f\", $BYTES / 1000 / 1000 }")"
CLAIMED="$(sed -n 's/.*\*\*~\?\([0-9][0-9]*\.[0-9]\) MB\*\*.*/\1/p' README.MD | head -n1)"
if [ -z "$CLAIMED" ]; then
	echo "FAIL: README.MD has no **N.N MB** size claim" >&2
	exit 1
fi
if [ "$CLAIMED" != "$MEASURED" ]; then
	echo "FAIL: README size $CLAIMED MB, image is $MEASURED MB ($BYTES bytes)" >&2
	exit 1
fi

echo "doctor ok"
echo "image=$IMAGE"
echo "bun=$VERSION"
echo "alpine=$ALPINE_PIN"
echo "size=${MEASURED} MB"
echo "bytes=$BYTES"
