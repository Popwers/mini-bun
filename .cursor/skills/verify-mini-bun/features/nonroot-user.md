# Non-root user

Non-root user lets a user run the container as `bun` (UID/GID 1000) and write files in `/home/bun/app`.

## Sub-features

- `user-bun` starts the container with `-u bun`.
- `workdir-write` creates and deletes a file in `/home/bun/app`.

## How to get to it (user POV)

- Run `docker run --rm -u bun popwers/mini-bun:latest bun index.ts`.
- Set `USER bun` in a derived Dockerfile.

## Driving it with docker

Preconditions:

- Image `mini-bun:verify` exists.
- `./scripts/verify-doctor.sh mini-bun:verify` passed.

- **Writable workdir.** Run `docker run --rm -u bun mini-bun:verify sh -c 'touch /home/bun/app/.w && rm /home/bun/app/.w'`. Exit code `0`.
- **Identity.** Run `docker run --rm -u bun mini-bun:verify sh -c 'id -u; id -g; pwd'`. Exit code `0`. Stdout has `1000`, `1000`, and `/home/bun/app`.
- **Proof.** Write both commands, stdout, and exit codes to `/tmp/verify-mini-bun/<run-id>/nonroot-user.txt`. The file contains `1000` and `/home/bun/app`.

## Gotchas

- The default user is `root`. A passing run without `-u bun` does not prove this feature.
- `/home/bun/app` must be owned by `bun:bun`. A permission denied on `touch` is a fail, not a skip.
