#!/usr/bin/env bash
# Runs scripts/bump-versions.sh check against a local HTTP server standing in for GitHub's release API
# and Alpine's release index. Like GitHub's API once a shared runner address spent its anonymous quota,
# the server answers 403 to a release lookup without the job token.
# Needs bash, curl and python3.
set -u

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/bump-versions.sh"
TOKEN='test-token-must-not-leak'

for tool in curl python3; do
	command -v "$tool" >/dev/null || {
		echo "FAIL: $tool is required" >&2
		exit 1
	}
done

WORK="$(mktemp -d)"
SERVER_PID=''
cleanup() {
	[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
	rm -rf "$WORK"
}
trap cleanup EXIT

cat >"$WORK/server.py" <<'PY'
import http.server, sys

class Handler(http.server.BaseHTTPRequestHandler):
    def answer(self, status, body):
        self.send_response(status)
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.path == "/repos/oven-sh/bun/releases/latest":
            if self.headers.get("Authorization") != "Bearer " + sys.argv[1]:
                self.answer(403, '{"message":"API rate limit exceeded"}')
                return
            self.answer(200, '{"tag_name": "bun-v9.9.9"}')
        elif self.path == "/alpine/latest-releases.yaml":
            self.answer(200, '---\n-\n  title: "Alpine"\n  branch: v3.24\n')
        else:
            self.answer(404, "")

    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print("port", server.server_address[1], flush=True)
server.serve_forever()
PY
python3 -I "$WORK/server.py" "$TOKEN" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
PORT=''
for _ in $(seq 50); do
	PORT="$(sed -n 's/^port \([0-9][0-9]*\)$/\1/p' "$WORK/server.log" | head -n 1)"
	[ -n "$PORT" ] && break
	sleep 0.1
done
if [ -z "$PORT" ]; then
	echo "FAIL: fixture server did not start" >&2
	cat "$WORK/server.log" >&2
	exit 1
fi
BASE="http://127.0.0.1:$PORT"
CURRENT_BUN="$(awk '/^ARG BUN_VERSION=/ { sub(/^ARG BUN_VERSION=/, ""); print; exit }' "$ROOT/Dockerfile")"

FAILED=0
fail() {
	echo "FAIL: $1" >&2
	FAILED=$((FAILED + 1))
}

# run_check <token or empty> — check's output and exit code, with the fixture URLs.
run_check() {
	env -u GITHUB_OUTPUT GITHUB_TOKEN="$1" \
		BUN_LATEST_API="$BASE/repos/oven-sh/bun/releases/latest" \
		ALPINE_LATEST_YAML="$BASE/alpine/latest-releases.yaml" \
		"$SCRIPT" check >"$WORK/out" 2>&1
}

if run_check "$TOKEN"; then
	grep -qx "bun: current=$CURRENT_BUN latest=v9.9.9" "$WORK/out" || fail "token: wrong bun line: $(cat "$WORK/out")"
	grep -qx 'alpine: current=3.24 latest=3.24' "$WORK/out" || fail "token: wrong alpine line: $(cat "$WORK/out")"
else
	fail "token: the release lookup was refused: $(cat "$WORK/out")"
fi
grep -qF "$TOKEN" "$WORK/out" && fail 'token: the token reached the output'

if run_check ''; then
	fail 'no token: an anonymous lookup the API refuses must fail the step'
fi

if [ "$FAILED" -ne 0 ]; then
	echo "$FAILED check(s) failed" >&2
	exit 1
fi
echo 'bump-versions: all checks passed'
