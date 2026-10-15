#!/usr/bin/env bash
# Picks the runner for the CI jobs from the remaining GitHub Actions minutes.
# Inputs are the PICK_* variables set by action.yml. PICK_RUNNER_API_URL points the API calls at another host.
# Always exits 0: any failure picks the build server, so the job is never blocked by this step.

API_URL="${PICK_RUNNER_API_URL:-https://api.github.com}"
API_URL="${API_URL%/}"
TOKEN="${PICK_TOKEN:-}"
OWNER="${PICK_OWNER:-}"
DEFAULT_BUILD_SERVER_RUNNER='["self-hosted","ARM64"]'

target=''
reason=''
used=''
included=''
remaining=''
emitted=''
err_file="$(mktemp)"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Workflow commands treat % as an escape prefix.
annotate() {
	local level=$1 message=$2
	message="${message//%/%25}"
	echo "::${level}::pick-runner: ${message}"
}

choose() {
	target=$1
	reason=$2
}

fallback() {
	choose build-server "$1"
	annotate warning "$1"
}

is_number() { [[ $1 =~ ^[0-9]+([.][0-9]+)?$ ]]; }
is_positive() { is_number "$1" && [[ ! $1 =~ ^0+([.]0+)?$ ]]; }

threshold="${PICK_THRESHOLD:-10}"
if ! is_number "$threshold"; then
	annotate warning "threshold '$threshold' is not a number, using 10"
	threshold=10
fi

github_runner="${PICK_GITHUB_RUNNER:-ubuntu-latest}"
build_server_runner="${PICK_BUILD_SERVER_RUNNER:-$DEFAULT_BUILD_SERVER_RUNNER}"
if ! build_server_runner="$(jq -ce 'select(type == "array" and length > 0 and all(type == "string"))' <<<"$build_server_runner" 2>/dev/null)"; then
	annotate warning "build-server-runner is not a JSON array of labels, using $DEFAULT_BUILD_SERVER_RUNNER"
	build_server_runner="$DEFAULT_BUILD_SERVER_RUNNER"
fi

# GET $API_URL$1. The token goes through stdin so it never appears in the process list.
api() {
	printf 'Authorization: Bearer %s\n' "$TOKEN" | curl \
		--silent --show-error --fail-with-body --location \
		--max-time 15 --retry 1 --retry-all-errors --retry-delay 1 \
		--header @- \
		--header 'Accept: application/vnd.github+json' \
		--header 'X-GitHub-Api-Version: 2022-11-28' \
		"$API_URL$1" 2>"$err_file"
}

# One-line description of the last failed api call.
api_error() {
	local body=$1 detail message
	detail="$(tail -n 1 "$err_file")"
	message="$(jq -r '.message? // empty' <<<"$body" 2>/dev/null | head -n 1)"
	printf '%s%s' "${detail:-request failed}" "${message:+ ($message)}"
}

included_for_plan() {
	case "$(lower "$1")" in
		free) echo 2000 ;;
		pro | team) echo 3000 ;;
		enterprise) echo 50000 ;;
		*) echo 2000 ;;
	esac
}

pick() {
	case "$(lower "${PICK_FORCE:-}")" in
		github)
			choose github "forced to github"
			return
			;;
		build-server)
			choose build-server "forced to build-server"
			return
			;;
	esac

	if [ "${PICK_REPO_PRIVATE:-}" = false ]; then
		choose github "public repository, GitHub-hosted minutes are free"
		return
	fi

	if [ -z "$TOKEN" ]; then
		fallback "no CI_BILLING_TOKEN, quota unknown"
		return
	fi

	if [ -z "$OWNER" ]; then
		fallback "repository owner unknown"
		return
	fi

	local owner_type="${PICK_OWNER_TYPE:-}" body
	if [ -z "$owner_type" ]; then
		if ! body="$(api "/users/$OWNER")" || ! owner_type="$(jq -er '.type | strings' <<<"$body" 2>/dev/null)"; then
			fallback "owner type lookup failed: $(api_error "$body")"
			return
		fi
	fi

	local usage_path plan_path
	case "$owner_type" in
		Organization)
			usage_path="/organizations/$OWNER/settings/billing/usage/summary?product=actions"
			plan_path="/orgs/$OWNER"
			;;
		User)
			usage_path="/users/$OWNER/settings/billing/usage/summary?product=actions"
			plan_path="/user"
			;;
		*)
			fallback "unsupported owner type '$owner_type'"
			return
			;;
	esac

	if ! body="$(api "$usage_path")"; then
		fallback "billing usage request failed: $(api_error "$body")"
		return
	fi
	if ! used="$(jq -er '
		if (.usageItems | type) != "array" then error("usageItems is not an array") else . end
		| [.usageItems[] | select((.unitType // "" | ascii_downcase) == "minutes") | .grossQuantity // 0]
		| add // 0
		| if type == "number" then . else error("grossQuantity is not a number") end
	' <<<"$body" 2>/dev/null)"; then
		used=''
		fallback "billing usage response is not the expected JSON"
		return
	fi

	local plan_note=''
	if is_positive "${PICK_INCLUDED_MINUTES:-}"; then
		included="$PICK_INCLUDED_MINUTES"
		plan_note="included-minutes input"
	else
		if [ -n "${PICK_INCLUDED_MINUTES:-}" ]; then
			annotate warning "included-minutes '$PICK_INCLUDED_MINUTES' is not a positive number, using the plan"
		fi
		local plan=''
		if body="$(api "$plan_path")"; then
			plan="$(jq -r '.plan.name? // empty' <<<"$body" 2>/dev/null)"
		fi
		included="$(included_for_plan "$plan")"
		if [ -n "$plan" ]; then
			plan_note="plan $plan"
		else
			plan_note="plan unknown, default"
			annotate notice "plan name unavailable, assuming $included included minutes. Set included-minutes to override."
		fi
	fi

	local verdict
	if ! verdict="$(jq -nr --argjson used "$used" --argjson included "$included" --argjson threshold "$threshold" '
		((($included - $used) * 100 / $included) | if . < 0 then 0 else . end) as $remaining
		| "\(($remaining * 10 | floor) / 10) \(if $remaining < $threshold then "below" else "ok" end)"
	' 2>/dev/null)"; then
		fallback "could not compute the remaining quota"
		return
	fi
	remaining="${verdict% *}"
	used="$(jq -n --argjson used "$used" '($used * 10 | floor) / 10')"

	if [ "${verdict#* }" = below ]; then
		choose build-server "${remaining}% of ${included} minutes left (${plan_note}), below ${threshold}%"
		annotate notice "$reason"
	else
		choose github "${remaining}% of ${included} minutes left (${plan_note})"
	fi
}

emit() {
	emitted=1
	local runner
	if [ "$target" = github ]; then
		runner="$(jq -cn --arg label "$github_runner" '$label')"
	else
		runner="$build_server_runner"
	fi
	reason="$(printf '%s' "$reason" | tr '\r\n' '  ')"

	local out="${GITHUB_OUTPUT:-/dev/stdout}"
	{
		echo "runner=$runner"
		echo "target=$target"
		echo "remaining-percent=$remaining"
		echo "reason=$reason"
	} >>"$out"

	echo "pick-runner: target=$target runner=$runner reason=$reason"

	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		local usage='n/a'
		[ -n "$used" ] && [ -n "$included" ] && usage="$used / $included"
		{
			echo '### Runner selection'
			echo
			echo '| Target | Reason | Used / included minutes | Remaining | Threshold |'
			echo '| --- | --- | --- | --- | --- |'
			echo "| \`$target\` | ${reason//|/\\|} | $usage | ${remaining:+$remaining%}${remaining:-n/a} | $threshold% |"
		} >>"$GITHUB_STEP_SUMMARY"
	fi
}

on_exit() {
	if [ -z "$emitted" ]; then
		fallback "pick-runner stopped unexpectedly"
		emit
	fi
	rm -f "$err_file"
	exit 0
}
trap on_exit EXIT

pick
emit
