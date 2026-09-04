# TLS fetch

TLS fetch lets a user call `fetch` over HTTPS without installing `ca-certificates` in a derived image. Bun embeds its own CA store.

## Sub-features

- `fetch-https` completes an HTTPS GET.
- `fetch-status` reports a successful HTTP status.

## How to get to it (user POV)

- Run `docker run --rm popwers/mini-bun bun -e 'fetch("https://example.com")...'`.
- Call `fetch` from application code in a `FROM popwers/mini-bun` image that did not `apk add ca-certificates`.

## Driving it with docker

Preconditions:

- Image `mini-bun:verify` exists.
- The environment can reach `https://bun.sh`.
- `./scripts/verify-doctor.sh mini-bun:verify` passed.

- **HTTPS fetch.** Run `docker run --rm mini-bun:verify bun -e 'fetch("https://bun.sh").then(r => { if (!r.ok) process.exit(1); console.log("fetch", r.status); })'`. Exit code `0`. Stdout matches `fetch 200` or another `fetch` line with a 2xx status.
- **Proof.** Write the command, stdout, and exit code to `/tmp/verify-mini-bun/<run-id>/tls-fetch.txt`. The file contains `fetch` and a 2xx status.

## Gotchas

- A build-time `RUN bun --version` does not exercise TLS. Drive `fetch`.
- Offline or filtered CI makes this feature unreachable. Record the curl/fetch error and stop. Do not mark it verified.
- Do not add `ca-certificates` to the image to make this pass.
