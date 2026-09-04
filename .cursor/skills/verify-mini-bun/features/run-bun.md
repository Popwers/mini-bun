# Run Bun

Run Bun lets a user print the runtime version, evaluate an expression, and invoke `bunx` from a container started with the image.

## Sub-features

- `bun-version` prints the pinned Bun version through the entrypoint.
- `bun-eval` evaluates a one-liner with the unpacked UPX binary.
- `bunx-version` runs the `bunx` symlink.

## How to get to it (user POV)

- Run `docker run --rm popwers/mini-bun --version`.
- Run `docker run --rm popwers/mini-bun bun -e 'console.log(1 + 1)'`.
- Run `docker run --rm popwers/mini-bun bunx --version`.

## Driving it with docker

Preconditions:

- Image `mini-bun:verify` exists.
- `EXPECTED` is the Dockerfile `ARG BUN_VERSION` value without the leading `v`.
- `./scripts/verify-doctor.sh mini-bun:verify` passed.

- **Version via entrypoint.** Run `docker run --rm mini-bun:verify --version`. Exit code `0`. Stdout is exactly `$EXPECTED`.
- **Eval.** Run `docker run --rm mini-bun:verify bun -e 'console.log(1 + 1)'`. Exit code `0`. Stdout is `2`.
- **bunx.** Run `docker run --rm mini-bun:verify bunx --version`. Exit code `0`. Stdout is `$EXPECTED`.
- **Smoke bundle.** Run `./scripts/smoke-test.sh mini-bun:verify "$EXPECTED"`. Exit code `0`. Stdout contains `SMOKE OK`.
- **Proof.** Write the version command, stdout, and exit code to `/tmp/verify-mini-bun/<run-id>/run-bun.txt`. The file contains `$EXPECTED` and `SMOKE OK`.

## Gotchas

- `docker build` prints `bun --version` during `RUN`. That is not user proof. Capture `docker run`.
- `--version` without `bun` is the entrypoint path. `bun --version` is the explicit binary path. Drive both only when the change touches the entrypoint. Otherwise the entrypoint form is enough here.
- Do not compare against a version copied from memory. Read `ARG BUN_VERSION` from the Dockerfile.
