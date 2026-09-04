# Node fallback

Node fallback lets a user run `node script.js` inside the image. The `node` name is a symlink to `bun`.

## Sub-features

- `node-script` executes a JavaScript file via `node`.
- `node-repl-gap` documents that `node --version` and the Node REPL do not work.

## How to get to it (user POV)

- Run `docker run --rm popwers/mini-bun node script.js` after the file exists in the container.
- Run `node` from a shell in the container (`docker run --rm -it popwers/mini-bun sh`).

## Driving it with docker

Preconditions:

- Image `mini-bun:verify` exists.
- `./scripts/verify-doctor.sh mini-bun:verify` passed.

- **Script via node.** Run `docker run --rm mini-bun:verify sh -c 'echo "console.log(\"ok\")" > /tmp/t.js && node /tmp/t.js'`. Exit code `0`. Stdout is `ok`.
- **Proof.** Write the command, stdout, and exit code to `/tmp/verify-mini-bun/<run-id>/node-fallback.txt`. The file contains a line `ok`.

## Gotchas

- `node --version` and the Node REPL fail. Do not treat that failure as a regression. The README names this as an upstream wrapper limit.
- The shim lives at `/usr/local/bun-node-fallback-bin/node`. Assert user-visible `node script.js`, not the symlink path, unless the change is the symlink itself.
