# CLAUDE.md - AI Assistant Guide for mini-bun

## Project Overview

**mini-bun** is a minimal Docker image for [Bun](https://bun.sh/) (JavaScript runtime) that uses UPX compression to create a smaller container image. The image is based on Alpine Linux and published to Docker Hub at `popwers/mini-bun`.

## Repository Structure

```
mini-bun/
├── Dockerfile              # Multi-stage build with UPX compression
├── docker-entrypoint.sh    # Container entry point script
├── README.MD               # Project documentation
├── CLAUDE.md               # This file - AI assistant guide
├── scripts/
│   ├── bump-versions.sh    # Check and apply Bun and Alpine pins; sync README size
│   ├── smoke-test.sh       # Image smoke test
│   └── verify-doctor.sh    # Read-only image health check
├── .cursor/
│   └── skills/
│       └── verify-mini-bun/
└── .github/
    └── workflows/
        ├── ci.yml          # PR and push build + smoke test
        └── publish.yml     # Weekly pin bump and Docker Hub deploy
```

## Key Files

### Dockerfile
- **Purpose**: Multi-stage build that downloads Bun, verifies with GPG, and compresses with UPX
- **Base image**: `alpine:3.24` (source of truth is the Dockerfile `FROM alpine` lines)
- **Current Bun version**: Defined by `ARG BUN_VERSION` at the top of the Dockerfile (auto-bumped weekly by CI — never trust a version number written in prose; read the Dockerfile)
- **Architecture support**: x86_64 (x64-musl-baseline) and aarch64 (aarch64-musl)
- **Key features**:
  - GPG signature verification for downloads
  - UPX compression for smaller binary size
  - Creates `bun` user (UID/GID 1000)
  - Node.js fallback symlink at `/usr/local/bun-node-fallback-bin/node`
  - Runtime transpiler cache disabled by default

### docker-entrypoint.sh
- **Purpose**: Entry point that prepends `/usr/local/bin/bun` if first argument is a flag, unknown command, or non-executable file
- Simple shell script with `set -e` for error handling

### .github/workflows/publish.yml
- **Trigger**: Weekly cron (Mondays at midnight) or manual dispatch
- **Two jobs**:
  1. `check_and_update_bun_version`: Compares current vs latest Bun and Alpine pins and exports them
  2. `docker`: Applies both pins, smoke-tests amd64, then commits Dockerfile, README, and CLAUDE in one commit (Bun, Alpine, measured size). Registry push runs only when a pin changed or the run is a manual dispatch.

## Development Workflows

### Building Locally
```bash
docker build -t mini-bun .
```

### Building with Specific Bun Version
```bash
docker build --build-arg BUN_VERSION=v1.3.0 -t mini-bun .
```

### Running the Container
```bash
docker run -it popwers/mini-bun:latest
```

### Testing a Local Build
```bash
docker run -it mini-bun bun --version
```

## Version Management

Bun and Alpine pins live in the Dockerfile. Run `scripts/bump-versions.sh apply` (or wait for the weekly workflow) to update them:
- Bun: first `ARG BUN_VERSION=...` (read the Dockerfile for the current value)
- Alpine: both `FROM alpine:X.Y` lines
- README Alpine minor and `**N.N MB**` size: `scripts/bump-versions.sh sync-docs <image>` after a real amd64 build. Do not type the size by hand.
- The weekly job commits Dockerfile + README + CLAUDE together. Message lists Bun, Alpine, and the measured size.

## Conventions

### Commit Messages
- Pin commits use a rocket emoji and list Bun, Alpine, and image size. See `scripts/bump-versions.sh sync-docs`.

### Docker Tags
- `popwers/mini-bun:latest` - Latest stable build
- `popwers/mini-bun:vX.X.X` - Specific version tags

### File Naming
- README uses uppercase extension: `README.MD`

## Important Notes for AI Assistants

1. **Version Updates**: Run `scripts/bump-versions.sh apply` (updates `ARG BUN_VERSION` and both `FROM alpine` lines). Do not hand-edit version numbers in docs.
2. **Multi-arch Support**: Any Dockerfile changes must work for both amd64 and arm64
3. **GPG Keys**: The GPG key `F3DCC08A8572C0749B3E18888EAB4D40A7B22B59` is Bun's official signing key
4. **Alpine Version**: Source of truth is the Dockerfile `FROM alpine` lines. Check compatibility before bumping the pin.
5. **No package.json**: This is a Docker-only project, no Node/Bun package management. Vite+, shadcn, and UI verify do not apply. This repo is a Docker runtime image, not a Vite+ or UI app. Do not install them.
6. **UPX Compression**: Uses `--best --lzma --no-backup` (binary stripped via `strip -s` before packing). `--ultra-brute` was benchmarked and rejected: ~10× slower for <1% gain. `--all-methods` was the previous setting; `--best --lzma` is both faster and slightly smaller in practice.
7. **Security**: Downloads are verified via GPG signature and SHA256 checksum

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BUN_RUNTIME_TRANSPILER_CACHE_PATH` | `0` (disabled) | Transpiler cache path |
| `BUN_INSTALL_BIN` | `/usr/local/bin` | Global package install location |

## Common Tasks

### Check or apply image pins
```bash
./scripts/bump-versions.sh check
./scripts/bump-versions.sh apply
./scripts/bump-versions.sh check-docs
./scripts/bump-versions.sh check-docs mini-bun:ci-test
./scripts/bump-versions.sh sync-docs mini-bun:smoke-amd64
```

### Smoke test
```bash
EXPECTED=$(grep 'ARG BUN_VERSION=' Dockerfile | cut -d'=' -f2 | sed 's/^v//')
./scripts/smoke-test.sh mini-bun:ci-test "$EXPECTED"
```

### Verify Image Size
```bash
docker image inspect -f '{{.Size}}' mini-bun:verify
./scripts/verify-doctor.sh mini-bun:verify
```

### Check Latest Bun Release
```bash
curl -s https://api.github.com/repos/oven-sh/bun/releases/latest | jq -r .tag_name
```
