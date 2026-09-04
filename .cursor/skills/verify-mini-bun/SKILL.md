---
name: verify-mini-bun
description: Drive the mini-bun Docker image the way a user does. Use when a Dockerfile, entrypoint, Alpine pin, Bun pin, smoke test, or image-size claim changes, or when you need proof the image runs.
---

# Verify mini-bun

Primary surface is the Docker image. Users run `docker run` and `FROM popwers/mini-bun`. There is no web UI, no Vite+ app, and no shadcn surface. Do not install Vite or shadcn to verify this repo.

Harness is `docker run` plus `scripts/smoke-test.sh`. Evidence is command transcripts, exit codes, `bun --version`, `/etc/os-release`, and `docker image inspect` size.

## Launch

Build a disposable tag from the repo root. Ready means the build exits 0.

```sh
docker build -t mini-bun:verify .
```

There is no long-lived server. Each drive starts a new `docker run --rm`.

Teardown is `Cleanup` below. Do not `docker rmi` by a shared name such as `mini-bun:latest`.

## Doctor

Run this first when anything looks off. It is read-only.

```sh
./scripts/verify-doctor.sh mini-bun:verify
```

Doctor must report all of these or stop:

- `docker` answers `docker info`
- image `mini-bun:verify` exists
- `docker run --rm mini-bun:verify --version` equals `ARG BUN_VERSION` in the Dockerfile with the leading `v` stripped
- `docker run --rm mini-bun:verify cat /etc/os-release` has `VERSION_ID` equal to the Dockerfile `FROM alpine:X.Y` minor
- `docker image inspect -f '{{.Size}}'` formatted as one-decimal MB (`bytes / 1000 / 1000`) equals the `**N.N MB**` claim in `README.MD`

## Drive

Tag is `mini-bun:verify`. Expected Bun version is the Dockerfile pin without `v`.

```sh
EXPECTED="$(grep 'ARG BUN_VERSION=' Dockerfile | cut -d= -f2 | sed 's/^v//')"
./scripts/smoke-test.sh mini-bun:verify "$EXPECTED"
```

Then drive the feature file you are proving. Commands in the map are literal. Do not substitute a unit test or a Dockerfile `RUN bun --version` for `docker run`.

## Evidence

Write proof under `/tmp/verify-mini-bun/<run-id>/`. Keep that directory after cleanup.

Minimum per feature:

- the exact command
- stdout, stderr, and exit code
- a second observation of the resulting state (version string, `SMOKE OK`, size bytes, Alpine `VERSION_ID`)

Standards:

- Exercise the user path (`docker run` / `docker build`). Do not treat `docker build` log lines that print `bun --version` during `RUN` as user proof.
- Capture the action and the resulting state.
- Size proof is `docker image inspect -f '{{.Size}}'`, not a remembered number.
- No mocks. TLS fetch hits `https://bun.sh`.

## Cleanup

Remove only what this run created:

```sh
docker rmi mini-bun:verify
```

If Launch used another unique tag, remove that tag. Do not `docker rmi mini-bun` or `popwers/mini-bun`. Do not delete `/tmp/verify-mini-bun/<run-id>/`.

## Helpers

```sh
./scripts/verify-doctor.sh mini-bun:verify
./scripts/smoke-test.sh mini-bun:verify "$EXPECTED"
./scripts/bump-versions.sh check-docs mini-bun:verify
```

`verify-doctor.sh` is the Doctor check. `smoke-test.sh` is the default Drive. `bump-versions.sh check-docs` fails on a README size or Alpine pin that does not match the image.

## Vite+ / UI

N/A. This repo is a Docker runtime image. Skip browser, `vp`, shadcn, and `control-ui`.

## Feature map

Read `features/README.md`, then the file for the change. A proof that only runs smoke and ignores other map entries is incomplete when the change touches those entries.
