# mini-bun

mini-bun is a Docker image. It packages the official Bun musl release into Alpine Linux, then strips the binary and compresses it with UPX. Images publish to `popwers/mini-bun` and `ghcr.io/popwers/mini-bun`. Default branch is `main`.

## Layout

- `Dockerfile` is the multi-stage build.
- `docker-entrypoint.sh` is the container entrypoint.
- `scripts/smoke-test.sh` runs the image smoke test.
- `scripts/verify-doctor.sh` is the read-only health check.
- `scripts/bump-versions.sh` owns Bun and Alpine pins and the README size.
- `README.MD` uses that uppercase extension on purpose. Pin scripts and `publish.yml` depend on that name.
- `.cursor/skills/verify-mini-bun/` tells you how to drive the image.
- `.github/workflows/ci.yml` builds on push and on PR, then runs the smoke test.
- `.github/workflows/publish.yml` bumps pins weekly and pushes the image.

## Dockerfile

Read the Dockerfile for current pin values. Do not copy those numbers into this file.

- First `ARG BUN_VERSION=` is the Bun pin.
- Both `FROM alpine:X.Y` lines are the Alpine pin. They must match.
- The build stage downloads the official musl zip for the host arch. amd64 uses `x64-musl-baseline`. arm64 uses `aarch64-musl`.
- Downloads verify with GPG key `F3DCC08A8572C0749B3E18888EAB4D40A7B22B59` and SHA256.
- After `chmod +x`, the build runs `strip -s` then `upx --best --lzma --no-backup`. `--ultra-brute` was slower for almost no size win.
- The runtime image creates user `bun` with UID and GID 1000. Workdir is `/home/bun/app`.
- Default process user stays root, matching `oven/bun`. Switch with `USER bun` or `docker run -u bun`.
- `bunx` is a symlink to `/usr/local/bin/bun`.
- `node` is a symlink at `/usr/local/bun-node-fallback-bin/node`. `node script.js` runs Bun. `node --version` and the Node REPL do not work.
- Dockerfile changes must work on `linux/amd64` and `linux/arm64`.

## Environment

| Variable | Default | Role |
| --- | --- | --- |
| `BUN_RUNTIME_TRANSPILER_CACHE_PATH` | `0` | Transpiler cache. Off because ephemeral containers do not reuse it. |
| `BUN_INSTALL_BIN` | `/usr/local/bin` | Path so `bun install -g` writes binaries on `PATH`. |

`PATH` includes `/usr/local/bun-node-fallback-bin`.

## Entrypoint

`docker-entrypoint.sh` prepends `/usr/local/bin/bun` when the first argument is a flag such as `--version`, an unknown command, or a non-executable file. Pass a known executable to skip that.

## Commands

Run a published image:

```sh
docker run --rm popwers/mini-bun --version
docker run -it popwers/mini-bun:latest sh
```

Build locally:

```sh
docker build -t mini-bun .
docker build --build-arg BUN_VERSION=<tag> -t mini-bun .
docker run --rm mini-bun --version
```

`make build` runs `docker build -t mini-bun .`.

Prove a local image:

```sh
EXPECTED="$(grep 'ARG BUN_VERSION=' Dockerfile | cut -d= -f2 | sed 's/^v//')"
docker buildx build --load -t mini-bun:verify .
./scripts/verify-doctor.sh mini-bun:verify
./scripts/smoke-test.sh mini-bun:verify "$EXPECTED"
./scripts/bump-versions.sh check-docs
```

Do not treat `RUN bun --version` in the Dockerfile build log as user proof. Drive `docker run`.

The README `**N.N MB**` pin is GitHub Actions `docker image inspect` Size after the CI buildx load. A local daemon can report a different Size.

Check or apply pins:

```sh
./scripts/bump-versions.sh check
./scripts/bump-versions.sh apply
```

`apply` writes the Dockerfile pins and rewrites Alpine mentions in `README.MD`.

`scripts/bump-versions.sh sync-docs` writes the image size in `README.MD` on GitHub Actions. Do not run `sync-docs` on a laptop.

## Weekly publish

`.github/workflows/publish.yml` runs Monday at midnight UTC, or on manual dispatch.

1. `check` compares Dockerfile pins to latest Bun and latest-stable Alpine.
2. `apply` writes those pins.
3. The amd64 smoke test runs.
4. `sync-docs` writes the measured size into `README.MD`.
5. The job commits `Dockerfile` and `README.MD` only. It does not commit `AGENTS.md`.
6. Registry push runs only when a pin changed or the run is a manual dispatch. Tags go to Docker Hub and GHCR as `latest`, `vX.Y.Z`, and the `X.Y` minor alias.

Pin commit messages use a rocket emoji. See `scripts/bump-versions.sh sync-docs`. CI skips those commits.

`.github/workflows/ci.yml` builds the image, runs `scripts/smoke-test.sh`, and runs `check-docs` against the loaded image.
