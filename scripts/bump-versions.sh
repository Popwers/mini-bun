#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

DOCKERFILE="$ROOT/Dockerfile"
README="$ROOT/README.MD"
CLAUDE="$ROOT/CLAUDE.md"

BUN_LATEST_API="https://api.github.com/repos/oven-sh/bun/releases/latest"
ALPINE_LATEST_YAML="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/latest-releases.yaml"
PINS="bun alpine"
IMAGE=

usage() {
	echo "usage: $0 check|apply|check-docs [image]|sync-docs <image>" >&2
	exit 1
}

pin_current() {
	case "$1" in
		bun)
			awk '/^ARG BUN_VERSION=/ { sub(/^ARG BUN_VERSION=/, ""); print; exit }' "$DOCKERFILE"
			;;
		alpine)
			pins=$(sed -n 's/^FROM alpine:\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' "$DOCKERFILE")
			first=
			n=0
			for p in $pins; do
				n=$((n + 1))
				if [ -z "$first" ]; then
					first=$p
				elif [ "$p" != "$first" ]; then
					echo "error: FROM alpine pins disagree ($first vs $p)" >&2
					exit 1
				fi
			done
			if [ "$n" -ne 2 ]; then
				echo "error: expected two FROM alpine:X.Y lines, found $n" >&2
				exit 1
			fi
			printf '%s\n' "$first"
			;;
		size)
			sed -n \
				-e 's/.*\*\*~\([0-9][0-9]*\.[0-9][0-9]*\) MB\*\*.*/\1/p' \
				-e 's/.*\*\*\([0-9][0-9]*\.[0-9][0-9]*\) MB\*\*.*/\1/p' \
				"$README" | sed -n '1p'
			;;
		*)
			echo "error: unknown pin: $1" >&2
			exit 1
			;;
	esac
}

pin_latest() {
	case "$1" in
		bun)
			json=$(curl -fsSL "$BUN_LATEST_API")
			tag=$(printf '%s\n' "$json" | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p')
			tag=${tag#bun-}
			if [ -z "$tag" ]; then
				echo "error: could not parse Bun latest tag" >&2
				exit 1
			fi
			printf '%s\n' "$tag"
			;;
		alpine)
			yaml=$(curl -fsSL "$ALPINE_LATEST_YAML")
			# First branch: is latest-stable; never use edge.
			branch=$(printf '%s\n' "$yaml" | sed -n 's/^[[:space:]]*branch:[[:space:]]*//p' | sed -n '1p' | tr -d '"')
			if [ -z "$branch" ]; then
				echo "error: could not parse Alpine latest-stable branch" >&2
				exit 1
			fi
			case "$branch" in
				edge|vedge)
					echo "error: refuse Alpine edge ($branch)" >&2
					exit 1
					;;
			esac
			ver=${branch#v}
			if [ -z "$ver" ] || [ "$ver" = "edge" ]; then
				echo "error: refuse Alpine edge ($branch)" >&2
				exit 1
			fi
			printf '%s\n' "$ver"
			;;
		size)
			if [ -z "$IMAGE" ]; then
				echo "error: size pin needs an image" >&2
				exit 1
			fi
			bytes=$(docker image inspect -f '{{.Size}}' "$IMAGE")
			awk -v b="$bytes" 'BEGIN { printf "%.1f\n", b/1000/1000 }'
			;;
		*)
			echo "error: unknown pin: $1" >&2
			exit 1
			;;
	esac
}

pin_guard() {
	id=$1
	latest=${2:-}
	case "$id" in
		bun)
			base="https://github.com/oven-sh/bun/releases/download/bun-${latest}"
			# GitHub asset URLs 302; curl -f treats that as present.
			for artifact in bun-linux-x64-musl-baseline.zip bun-linux-aarch64-musl.zip; do
				url="$base/$artifact"
				if ! curl -fsI "$url" >/dev/null; then
					echo "error: missing $url — refusing bun bump" >&2
					exit 1
				fi
			done
			;;
		alpine)
			url="https://dl-cdn.alpinelinux.org/alpine/v${latest}/releases/x86_64/latest-releases.yaml"
			if ! curl -fsI "$url" >/dev/null; then
				echo "error: missing $url — refusing alpine bump" >&2
				exit 1
			fi
			;;
		size)
			if [ -z "$IMAGE" ]; then
				echo "error: size pin needs an image" >&2
				exit 1
			fi
			if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
				echo "error: image not found: $IMAGE" >&2
				exit 1
			fi
			;;
		*)
			echo "error: unknown pin: $1" >&2
			exit 1
			;;
	esac
}

pin_write() {
	id=$1
	latest=$2
	tmp=$(mktemp)
	target=$DOCKERFILE
	case "$id" in
		bun)
			awk -v ver="$latest" '
				!done && /^ARG BUN_VERSION=/ { print "ARG BUN_VERSION=" ver; done=1; next }
				{ print }
			' "$DOCKERFILE" > "$tmp"
			;;
		alpine)
			sed "s/^FROM alpine:[0-9][0-9]*\.[0-9][0-9]*/FROM alpine:${latest}/" "$DOCKERFILE" > "$tmp"
			;;
		size)
			target=$README
			sed -e "s/\*\*~[0-9][0-9]*\.[0-9][0-9]* MB\*\*/**${latest} MB**/" \
				-e "s/\*\*[0-9][0-9]*\.[0-9][0-9]* MB\*\*/**${latest} MB**/" \
				"$README" > "$tmp"
			;;
		*)
			rm -f "$tmp"
			echo "error: unknown pin: $1" >&2
			exit 1
			;;
	esac
	mv "$tmp" "$target"
}

sync_alpine_docs() {
	minor=$(pin_current alpine)
	for f in "$README" "$CLAUDE"; do
		tmp=$(mktemp)
		sed -e "s/Alpine 3\.[0-9][0-9]*/Alpine ${minor}/g" \
			-e "s/alpine:3\.[0-9][0-9]*/alpine:${minor}/g" \
			"$f" > "$tmp"
		mv "$tmp" "$f"
	done
}

write_output() {
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
	fi
}

collect_pins() {
	bun_current=
	bun_latest=
	bun_changed=false
	alpine_current=
	alpine_latest=
	alpine_changed=false

	for id in $PINS; do
		cur=$(pin_current "$id")
		lat=$(pin_latest "$id")
		if [ -z "$cur" ] || [ -z "$lat" ]; then
			echo "error: empty $id pin (current='$cur' latest='$lat')" >&2
			exit 1
		fi
		changed=false
		if [ "$cur" != "$lat" ]; then
			changed=true
		fi
		case "$id" in
			bun)
				bun_current=$cur
				bun_latest=$lat
				bun_changed=$changed
				;;
			alpine)
				alpine_current=$cur
				alpine_latest=$lat
				alpine_changed=$changed
				;;
		esac
		printf '%s: current=%s latest=%s\n' "$id" "$cur" "$lat"
	done

	case "${bun_changed}:${alpine_changed}" in
		true:false) commit_message="🚀 Update Bun version to ${bun_latest}" ;;
		false:true) commit_message="🚀 Update Alpine to ${alpine_latest}" ;;
		true:true) commit_message="🚀 Update Bun version to ${bun_latest} and Alpine to ${alpine_latest}" ;;
		*) commit_message= ;;
	esac
	case "${bun_changed}:${alpine_changed}" in
		false:false) new_version=false ;;
		*) new_version=true ;;
	esac
}

cmd_check() {
	collect_pins
	write_output new_version "$new_version"
	write_output latest_version "$bun_latest"
	write_output alpine_latest "$alpine_latest"
	write_output bun_changed "$bun_changed"
	write_output alpine_changed "$alpine_changed"
	write_output commit_message "$commit_message"
}

cmd_apply() {
	collect_pins
	for id in $PINS; do
		case "$id" in
			bun)
				changed=$bun_changed
				lat=$bun_latest
				;;
			alpine)
				changed=$alpine_changed
				lat=$alpine_latest
				;;
		esac
		if [ "$changed" = true ]; then
			pin_guard "$id" "$lat"
			pin_write "$id" "$lat"
			echo "wrote $id=$lat"
		fi
	done
	sync_alpine_docs
}

cmd_check_docs() {
	IMAGE=${1:-}
	status=0
	minor=$(pin_current alpine)
	leftover=$(grep -nE 'Alpine 3\.[0-9]+|alpine:3\.[0-9]+' "$README" "$CLAUDE" | grep -vF "Alpine ${minor}" | grep -vF "alpine:${minor}" || true)
	if [ -n "$leftover" ]; then
		printf '%s\n' "$leftover" >&2
		echo "error: Alpine minor in README.MD or CLAUDE.md does not match Dockerfile ($minor)" >&2
		status=1
	fi
	if [ -n "$IMAGE" ]; then
		pin_guard size
		measured=$(pin_latest size)
		claimed=$(pin_current size)
		if [ -z "$claimed" ]; then
			echo "error: README.MD has no **N.N MB** size token" >&2
			status=1
		elif [ "$claimed" != "$measured" ]; then
			echo "error: README size **${claimed} MB** != measured ${measured} MB ($IMAGE)" >&2
			status=1
		fi
		if grep -qE '\*\*~[0-9][0-9]*\.[0-9][0-9]* MB\*\*' "$README"; then
			echo "error: README size still uses a tilde; canonical form is **${measured} MB**" >&2
			status=1
		fi
	fi
	exit "$status"
}

cmd_sync_docs() {
	IMAGE=$1
	pin_guard size
	mb=$(pin_latest size)
	pin_write size "$mb"
	sync_alpine_docs
	bun=$(pin_current bun)
	alpine=$(pin_current alpine)
	msg="🚀 Update Bun ${bun}, Alpine ${alpine}, image size ${mb} MB"
	write_output commit_message "$msg"
	echo "size: ${mb} MB ($IMAGE)"
	echo "$msg"
}

case "${1:-}" in
	check) cmd_check ;;
	apply) cmd_apply ;;
	check-docs) cmd_check_docs "${2:-}" ;;
	sync-docs)
		[ -n "${2:-}" ] || usage
		cmd_sync_docs "$2"
		;;
	*) usage ;;
esac
