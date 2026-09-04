# mini-bun verification map

This directory is the maintained source for verifying the user-facing behavior of the mini-bun image. Read the index before driving the image, then use the matching feature file as the recipe.

## Baseline preconditions

- Build `mini-bun:verify` from the repo root with `docker buildx build --load -t mini-bun:verify .`.
- Set `EXPECTED` to the Dockerfile `ARG BUN_VERSION` value with the leading `v` removed.
- Run `./scripts/verify-doctor.sh mini-bun:verify` and require a matching Bun version, Alpine minor, and README size.
- Never drive `popwers/mini-bun` or another shared tag as if it were this run.

## Driving conventions

- Start every recipe from a fresh `docker run --rm mini-bun:verify` unless the file says otherwise.
- Treat every command as literal. Keep image tags and flags unchanged.
- Run user actions through `docker run` or `./scripts/smoke-test.sh`.
- Do not remove `/tmp/verify-mini-bun/<run-id>/` during cleanup.

## Proof and skip reporting

- Capture the command, stdout, stderr, and exit code.
- Mutation proof includes a second read of the result (version string, file on disk, HTTP status).
- Record the feature ID with every artifact.
- Report an unreachable path with the attempted command and the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with docker` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands, and observable proof.

## Features

- [Run Bun](./run-bun.md) covers `docker run` version, eval, and `bunx`.
- [Node fallback](./node-fallback.md) covers `node script.js` via the bundled symlink.
- [TLS fetch](./tls-fetch.md) covers HTTPS fetch with the embedded CA store.
- [Non-root user](./nonroot-user.md) covers `-u bun` and a writable `/home/bun/app`.
- [Entrypoint](./entrypoint.md) covers flag, unknown command, and executable pass-through.
