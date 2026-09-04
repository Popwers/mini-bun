<p align="center">
  <img src="https://bun.sh/logo.svg" alt="Bun Logo" width="150">
  &nbsp;&nbsp;&nbsp;
  <img src="https://www.docker.com/wp-content/uploads/2022/03/vertical-logo-monochromatic.png" alt="Docker Logo" width="150">
</p>

<p align="center">
  <img src="https://alpinelinux.org/alpinelinux-logo.svg" alt="Alpine Linux Logo" height="65">
</p>

# 🍞 Mini Bun Docker Image

> [!NOTE]
> This is an independent minimal packaging of the official [Bun](https://github.com/oven-sh/bun) release binaries. Not affiliated with the Bun team.

## 🚀 Project Overview

[Mini Bun](https://hub.docker.com/r/popwers/mini-bun) packages the official Bun runtime into a **31.1 MB** Docker image, roughly 3× smaller than `oven/bun:alpine`. The official release binary is verified with GPG + SHA256, stripped, and then compressed with UPX (`--best --lzma`), all on top of Alpine 3.24. The megabyte figure is `docker image inspect` Size on amd64, written by `scripts/bump-versions.sh sync-docs`.

## 🏷️ Tags & Architectures

| Tag | Description |
|-----|-------------|
| `latest` | Latest Bun release |
| `vX.Y.Z` | Pinned to a specific Bun version |
| `X.Y` | Minor-line alias — tracks the latest patch for that minor (e.g. `1.3`) |

**Supported architectures**: `linux/amd64` (x64-musl-baseline) and `linux/arm64` (aarch64-musl).

Images are available on both **Docker Hub** (`popwers/mini-bun`) and **GitHub Container Registry** (`ghcr.io/popwers/mini-bun`). All three tags above are published to both registries on every release.

Images are rebuilt and published automatically every Monday when a new Bun release is detected.

## 🏁 Getting Started

```bash
# Pull and check the Bun version
docker run --rm popwers/mini-bun --version

# Interactive shell
docker run -it popwers/mini-bun:latest sh
```

## 📦 Usage in your Dockerfile

```dockerfile
FROM popwers/mini-bun:latest

WORKDIR /home/bun/app

# Copy files with ownership set to the non-root bun user
COPY --chown=bun:bun . .

RUN bun install --frozen-lockfile

CMD ["bun", "index.ts"]
```

To run as the non-root `bun` user (UID/GID 1000):

```dockerfile
FROM popwers/mini-bun:latest

WORKDIR /home/bun/app
COPY --chown=bun:bun . .
RUN bun install --frozen-lockfile

USER bun
CMD ["bun", "index.ts"]
```

Or at runtime: `docker run -u bun popwers/mini-bun:latest bun index.ts`

## ⚙️ Runtime Notes

**Default user**: `root` (matches `oven/bun` behavior). A `bun` user (UID/GID 1000) is available — use `USER bun` in your Dockerfile or `-u bun` at runtime.

**Working directory**: `/home/bun/app` — owned by `bun:bun` and writable by the non-root user.

**Environment variables**:

| Variable | Default | Description |
|----------|---------|-------------|
| `BUN_RUNTIME_TRANSPILER_CACHE_PATH` | `0` (disabled) | Transpiler cache — disabled as it is useless in ephemeral containers |
| `BUN_INSTALL_BIN` | `/usr/local/bin` | Global binary install path so `bun install -g` works out of the box |

**Entrypoint behavior**: The entrypoint prepends `bun` automatically when the first argument is a flag (`--version`, `--help`…), an unknown command, or a non-executable file. Pass a known executable to bypass it.

**Node fallback**: `node script.js` works via a symlink shim (`/usr/local/bun-node-fallback-bin/node → bun`). `node --version` and the Node REPL do **not** work — this is a known upstream wrapper limitation.

**`bunx`** is available (symlink to `bun`).

**TLS / fetch**: Works without installing `ca-certificates` — Bun embeds its own CA store.

## 🛠️ Building Locally

```bash
git clone https://github.com/popwers/mini-bun.git
cd mini-bun

# Build for current platform
docker build -t mini-bun .

# Build with a specific Bun version
docker build --build-arg BUN_VERSION=v1.3.0 -t mini-bun .

# Verify the binary and size
docker run --rm mini-bun --version
docker images mini-bun
```

## 🤖 GitHub Actions Workflow

- **Publish workflow** (`publish.yml`): Runs weekly (Monday midnight). Checks Bun and Alpine pins, updates the Dockerfile when either pin has drifted, smoke-tests amd64 and arm64, writes the measured amd64 image size and the Alpine minor into the README, then pushes the multi-arch image to Docker Hub and GitHub Container Registry.
- **CI workflow** (`ci.yml`): Builds the image, runs the smoke test, and checks that the README Alpine minor and `**N.N MB**` size match the image (native arch only, no QEMU overhead).

## 🙏 Credits

- [Bun](https://bun.sh/) — The JavaScript runtime
- [UPX](https://upx.github.io/) — The Ultimate Packer for eXecutables

## 📚 Additional Resources

- [Bun Documentation](https://bun.sh/docs)
- [Bun GitHub Repository](https://github.com/oven-sh/bun)
- [Docker Hub — popwers/mini-bun](https://hub.docker.com/r/popwers/mini-bun)
