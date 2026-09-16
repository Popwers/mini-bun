# AGENTS.md

mini-bun is a Docker image. It packages the official Bun musl release into Alpine Linux. The build strips the binary and compresses it with UPX. Images publish to `popwers/mini-bun` and `ghcr.io/popwers/mini-bun`. This repo is not a Vite+ app. Do not add `vp`, anti-slop, or shadcn.

## Run the image

```sh
docker run --rm popwers/mini-bun --version
docker run -it popwers/mini-bun:latest sh
```

## Build locally

```sh
docker build -t mini-bun .
docker build --build-arg BUN_VERSION=v1.3.0 -t mini-bun .
docker run --rm mini-bun --version
```

`make build` runs `docker build -t mini-bun .`.

## Prove a local image

```sh
EXPECTED="$(grep 'ARG BUN_VERSION=' Dockerfile | cut -d= -f2 | sed 's/^v//')"
docker buildx build --load -t mini-bun:verify .
./scripts/verify-doctor.sh mini-bun:verify
./scripts/smoke-test.sh mini-bun:verify "$EXPECTED"
./scripts/bump-versions.sh check-docs
```

Do not treat `RUN bun --version` in the Dockerfile build log as user proof. Drive `docker run`.

The README `**N.N MB**` pin is GitHub Actions `docker image inspect` Size after the CI buildx load. A local daemon can report a different Size.

## Pins

Read the Dockerfile for current values. Do not copy those numbers into this file.

- First `ARG BUN_VERSION=` is the Bun pin.
- Both `FROM alpine:X.Y` lines are the Alpine pin.
- `scripts/bump-versions.sh sync-docs` writes the image size in `README.MD` on GitHub Actions. Do not run `sync-docs` on a laptop.

```sh
./scripts/bump-versions.sh check
./scripts/bump-versions.sh apply
```

`apply` writes the Dockerfile pins and rewrites Alpine mentions in `README.MD`. The weekly workflow then smoke-tests amd64, runs `sync-docs`, and commits `Dockerfile` and `README.MD`.

## Constraints

- Dockerfile changes must work on `linux/amd64` (x64-musl-baseline) and `linux/arm64` (aarch64-musl).
- Downloads verify with GPG key `F3DCC08A8572C0749B3E18888EAB4D40A7B22B59` and SHA256.
- UPX flags are `--best --lzma --no-backup` after `strip -s`. `--ultra-brute` was slower for almost no size win.
- There is no `package.json`. There is no Node or Bun project install.
- README uses the uppercase extension `README.MD`. Pin scripts and `publish.yml` depend on that name.
- Default branch is `main`.
- Pin commits use a rocket emoji. See `scripts/bump-versions.sh sync-docs`.

## Layout

- `Dockerfile` is the multi-stage build.
- `docker-entrypoint.sh` prepends `bun` for flags, unknown commands, and non-executable files.
- `scripts/smoke-test.sh` is the image smoke test.
- `scripts/verify-doctor.sh` is the read-only health check.
- `scripts/bump-versions.sh` owns Bun and Alpine pins and the README size.
- `.cursor/skills/verify-mini-bun/` tells you how to drive the image.
- `.github/workflows/ci.yml` builds on push and on PR. It runs the smoke test.
- `.github/workflows/publish.yml` bumps pins weekly and pushes the image.
