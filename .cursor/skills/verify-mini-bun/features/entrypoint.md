# Entrypoint

Entrypoint prepends `/usr/local/bin/bun` when the first argument is a flag, an unknown command, or a non-executable file. A known executable runs as-is.

## Sub-features

- `entry-flag` treats `--version` as a bun flag.
- `entry-unknown` treats an unknown command as a bun argument.
- `entry-exec` runs a real executable such as `sh` without prepending bun.

## How to get to it (user POV)

- Run `docker run --rm popwers/mini-bun --version`.
- Run `docker run --rm popwers/mini-bun index.ts` when the file is not executable.
- Run `docker run --rm -it popwers/mini-bun sh`.

## Driving it with docker

Preconditions:

- Image `mini-bun:verify` exists.
- `EXPECTED` is the Dockerfile `ARG BUN_VERSION` value without the leading `v`.
- `./scripts/verify-doctor.sh mini-bun:verify` passed.

- **Flag.** Run `docker run --rm mini-bun:verify --version`. Exit code `0`. Stdout is `$EXPECTED`.
- **Unknown command.** Run `docker run --rm mini-bun:verify not-a-real-cmd`. The process starts bun (not `executable not found` from the shell alone). Exit is bun's, not a missing-binary path from `command -v`.
- **Known executable.** Run `docker run --rm mini-bun:verify sh -c 'echo pass'`. Exit code `0`. Stdout is `pass`.
- **Proof.** Write the three commands, stdout, and exit codes to `/tmp/verify-mini-bun/<run-id>/entrypoint.txt`. The file contains `$EXPECTED` and `pass`.

## Gotchas

- `sh` is a known executable and must not be prepended with bun.
- A missing file that is still a valid bun entry (`.ts` / `.js`) goes through bun. Drive that path only when the change touches file detection.
- Do not exec the entrypoint script on the host. Drive it inside the image.
