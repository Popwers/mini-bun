#!/usr/bin/env bash
# Runs .github/actions/pick-runner/pick-runner.sh against a local HTTP server that serves billing API fixtures.
# Each case gets its own URL prefix under one local python3 server, so a missing fixture is a real HTTP 404.
# Needs bash, curl, jq and python3.
set -u

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/.github/actions/pick-runner/pick-runner.sh"
TOKEN='test-token-must-not-leak'

for tool in curl jq python3; do
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

FIXTURES="$WORK/fixtures"
mkdir -p "$FIXTURES"

# fixture <case> <api path> <body>
fixture() {
	mkdir -p "$(dirname "$FIXTURES/$1$2")"
	printf '%s' "$3" >"$FIXTURES/$1$2"
}

usage_json() {
	local owner_key=$1 owner=$2
	shift 2
	jq -cn --arg key "$owner_key" --arg owner "$owner" --argjson items "$*" \
		'{timePeriod: {year: 2026, month: 10}, ($key): $owner, product: "Actions", usageItems: $items}'
}

ORG_USAGE="/organizations/acme/settings/billing/usage/summary"
USER_USAGE="/users/jdoe/settings/billing/usage/summary"

fixture org-ok "$ORG_USAGE" "$(usage_json organization acme '[
	{"product":"Actions","sku":"actions_linux","grossQuantity":200.0,"discountQuantity":200.0,"netQuantity":0.0,"unitType":"minutes"},
	{"product":"Actions","sku":"actions_linux_arm","grossQuantity":25.0,"unitType":"Minutes"},
	{"product":"Actions","sku":"actions_storage","grossQuantity":9999.0,"unitType":"gigabyte-hours"}]')"
fixture org-ok /orgs/acme '{"login":"acme","plan":{"name":"team"}}'

fixture org-low "$ORG_USAGE" "$(usage_json organization acme '[
	{"sku":"actions_linux","grossQuantity":2900.0,"unitType":"minutes"},
	{"sku":"actions_macos","grossQuantity":50.0,"unitType":"MINUTES"}]')"
fixture org-low /orgs/acme '{"login":"acme","plan":{"name":"Team"}}'

fixture org-over "$ORG_USAGE" "$(usage_json organization acme '[{"sku":"actions_linux","grossQuantity":2500,"unitType":"minutes"}]')"
fixture org-over /orgs/acme '{"login":"acme","plan":{"name":"free"}}'

fixture org-no-plan "$ORG_USAGE" "$(usage_json organization acme '[{"sku":"actions_linux","grossQuantity":1900,"unitType":"minutes"}]')"
fixture org-no-plan /orgs/acme '{"login":"acme"}'

fixture org-empty "$ORG_USAGE" "$(usage_json organization acme '[]')"

fixture org-bad-json "$ORG_USAGE" '{"usageItems": [ not json'
fixture org-bad-shape "$ORG_USAGE" '{"message":"ok but no usageItems"}'
fixture org-bad-quantity "$ORG_USAGE" "$(usage_json organization acme '[{"sku":"actions_linux","grossQuantity":"lots","unitType":"minutes"}]')"

fixture user-ok "$USER_USAGE" "$(usage_json user jdoe '[{"sku":"actions_linux","grossQuantity":2225.0,"unitType":"minutes"}]')"
fixture user-ok /user '{"login":"jdoe","plan":{"name":"pro"}}'

# /users/jdoe is also the parent of the usage path: http.server redirects it to /users/jdoe/ and serves index.html.
fixture user-lookup /users/jdoe/index.html '{"login":"jdoe","type":"User"}'
fixture user-lookup "$USER_USAGE" "$(usage_json user jdoe '[{"sku":"actions_linux","grossQuantity":100,"unitType":"minutes"}]')"
fixture user-lookup /user '{"login":"jdoe","plan":{"name":"free"}}'

# http.server's static handler, plus a 401 when the request lacks the headers GitHub's API expects.
cat >"$WORK/server.py" <<'PY'
import functools, http.server, sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if (self.headers.get("Authorization") != "Bearer " + sys.argv[2]
                or self.headers.get("Accept") != "application/vnd.github+json"
                or self.headers.get("X-GitHub-Api-Version") != "2022-11-28"):
            self.send_error(401, "Bad credentials")
            return
        super().do_GET()

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=sys.argv[1]))
print("port", server.server_address[1], flush=True)
server.serve_forever()
PY
python3 -I "$WORK/server.py" "$FIXTURES" "$TOKEN" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
PORT=''
for _ in $(seq 50); do
	PORT="$(sed -n 's/^port \([0-9][0-9]*\)$/\1/p' "$WORK/server.log" | head -n 1)"
	[ -n "$PORT" ] && break
	PORT=''
	sleep 0.1
done
if [ -z "$PORT" ]; then
	echo "FAIL: fixture server did not start" >&2
	cat "$WORK/server.log" >&2
	exit 1
fi
BASE="http://127.0.0.1:$PORT"

PASSED=0
FAILED=0

# run <case> [VAR=value...]: runs the script with private-repo defaults and the case's API prefix.
run() {
	local case=$1
	shift
	CASE_DIR="$WORK/run-$case"
	mkdir -p "$CASE_DIR"
	: >"$CASE_DIR/output"
	: >"$CASE_DIR/summary"
	env -i PATH="$PATH" HOME="$HOME" \
		GITHUB_OUTPUT="$CASE_DIR/output" \
		GITHUB_STEP_SUMMARY="$CASE_DIR/summary" \
		PICK_RUNNER_API_URL="$BASE/$case" \
		PICK_TOKEN="$TOKEN" \
		PICK_REPO_PRIVATE=true \
		PICK_OWNER=acme \
		PICK_OWNER_TYPE=Organization \
		"$@" \
		bash "$SCRIPT" >"$CASE_DIR/log" 2>&1
	STATUS=$?
}

output() { sed -n "s/^$1=//p" "$CASE_DIR/output"; }

check() {
	local label=$1 expected=$2 actual=$3
	if [ "$expected" = "$actual" ]; then
		PASSED=$((PASSED + 1))
		echo "ok - $CURRENT: $label"
	else
		FAILED=$((FAILED + 1))
		echo "not ok - $CURRENT: $label: expected '$expected', got '$actual'"
		sed 's/^/    log: /' "$CASE_DIR/log"
	fi
}

check_contains() {
	local label=$1 needle=$2 file=$3
	if grep -qF -- "$needle" "$file"; then
		check "$label" yes yes
	else
		check "$label" "contains '$needle'" "$(tr '\n' ' ' <"$file")"
	fi
}

# expect <target> <remaining-percent> <reason substring>: shared assertions for every case.
expect() {
	check 'exit status' 0 "$STATUS"
	check 'target' "$1" "$(output target)"
	if [ "$1" = github ]; then
		check 'runner' '"ubuntu-latest"' "$(output runner)"
	else
		check 'runner' '["self-hosted","ARM64"]' "$(output runner)"
	fi
	check 'remaining-percent' "$2" "$(output remaining-percent)"
	check_contains 'reason' "$3" "$CASE_DIR/output"
	check_contains 'summary table' "| \`$1\` |" "$CASE_DIR/summary"
	check 'output lines' 4 "$(wc -l <"$CASE_DIR/output" | tr -d ' ')"
	check 'token hidden' 0 "$(cat "$CASE_DIR/log" "$CASE_DIR/output" "$CASE_DIR/summary" | grep -cF "$TOKEN")"
}

expect_warning() { check_contains 'warning annotation' "::warning::pick-runner: $1" "$CASE_DIR/log"; }
expect_no_warning() { check 'no warning' 0 "$(grep -c '::warning::' "$CASE_DIR/log")"; }

CURRENT='force github'
run none PICK_FORCE=GitHub PICK_TOKEN=
expect github '' 'forced to github'
expect_no_warning

CURRENT='force build-server'
run none PICK_FORCE=BUILD-SERVER PICK_REPO_PRIVATE=false
expect build-server '' 'forced to build-server'
expect_no_warning

CURRENT='unknown force value means auto'
run none PICK_FORCE=sometimes PICK_REPO_PRIVATE=false
expect github '' 'public repository'

CURRENT='public repository'
run none PICK_REPO_PRIVATE=false
expect github '' 'public repository'
expect_no_warning

CURRENT='no token'
run none PICK_TOKEN=
expect build-server '' 'no CI_BILLING_TOKEN'
expect_warning 'no CI_BILLING_TOKEN'

CURRENT='org quota ok'
run org-ok
expect github 92.5 'plan team'
check_contains 'used / included' '| 225 / 3000 |' "$CASE_DIR/summary"
expect_no_warning

CURRENT='org quota below threshold'
run org-low
expect build-server 1.6 'below 10%'
check_contains 'notice annotation' '::notice::pick-runner:' "$CASE_DIR/log"
expect_no_warning

CURRENT='org quota over included'
run org-over
expect build-server 0 'below 10%'

CURRENT='custom threshold'
run org-ok PICK_THRESHOLD=95
expect build-server 92.5 'below 95%'

CURRENT='included-minutes override skips the plan'
run org-no-plan PICK_INCLUDED_MINUTES=10000
expect github 81 'included-minutes input'

CURRENT='plan unknown defaults to 2000'
run org-no-plan
expect build-server 5 'plan unknown'

CURRENT='no usage this month'
run org-empty PICK_INCLUDED_MINUTES=3000
expect github 100 '100% of 3000'

CURRENT='http error'
run org-missing
expect build-server '' 'billing usage request failed'
expect_warning 'billing usage request failed'
check_contains 'http status in warning' '404' "$CASE_DIR/log"

CURRENT='invalid json'
run org-bad-json
expect build-server '' 'not the expected JSON'
expect_warning 'billing usage response is not the expected JSON'

CURRENT='json without usageItems'
run org-bad-shape
expect build-server '' 'not the expected JSON'

CURRENT='non-numeric grossQuantity'
run org-bad-quantity
expect build-server '' 'not the expected JSON'

CURRENT='user endpoints'
run user-ok PICK_OWNER=jdoe PICK_OWNER_TYPE=User
expect github 25.8 'plan pro'

CURRENT='user endpoints are not org endpoints'
run org-ok PICK_OWNER=acme PICK_OWNER_TYPE=User
expect build-server '' 'billing usage request failed'

CURRENT='org endpoints are not user endpoints'
run user-ok PICK_OWNER=jdoe PICK_OWNER_TYPE=Organization
expect build-server '' 'billing usage request failed'

CURRENT='owner type looked up when missing'
run user-lookup PICK_OWNER=jdoe PICK_OWNER_TYPE=
expect github 95 'plan free'

CURRENT='custom runners'
run none PICK_FORCE=github PICK_GITHUB_RUNNER=ubuntu-24.04-arm
check 'github runner' '"ubuntu-24.04-arm"' "$(output runner)"
run none PICK_FORCE=build-server PICK_BUILD_SERVER_RUNNER='["self-hosted","Linux","X64"]'
check 'build-server runner' '["self-hosted","Linux","X64"]' "$(output runner)"

CURRENT='invalid build-server-runner'
run none PICK_FORCE=build-server PICK_BUILD_SERVER_RUNNER='self-hosted'
expect build-server '' 'forced to build-server'
expect_warning 'build-server-runner is not a JSON array'

CURRENT='invalid threshold'
run org-ok PICK_THRESHOLD=ten
expect github 92.5 'plan team'
expect_warning "threshold 'ten' is not a number"

CURRENT='wrong token'
run org-ok PICK_TOKEN=revoked
expect build-server '' 'billing usage request failed'
check_contains 'http status in warning' '401' "$CASE_DIR/log"

CURRENT='api unreachable'
run none PICK_RUNNER_API_URL=http://127.0.0.1:1
expect build-server '' 'billing usage request failed'

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
