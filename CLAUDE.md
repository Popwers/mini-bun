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
└── .github/
    └── workflows/
        └── publish.yml     # CI/CD workflow for Docker Hub deployment
```

## Key Files

### Dockerfile
- **Purpose**: Multi-stage build that downloads Bun, verifies with GPG, and compresses with UPX
- **Base image**: `alpine:3.22`
- **Current Bun version**: Defined by `ARG BUN_VERSION` (currently v1.3.4)
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
  1. `check_and_update_bun_version`: Compares current vs latest Bun release, updates Dockerfile and commits if new version found
  2. `docker`: Builds multi-arch image (amd64, arm64) and pushes to Docker Hub

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

The Bun version is managed via the `BUN_VERSION` build argument in the Dockerfile:
- Located at line 3: `ARG BUN_VERSION=v1.3.4`
- Automatically updated by GitHub Actions when new Bun releases are detected
- Commit message format: `🚀 Update Bun version to vX.X.X`

## Conventions

### Commit Messages
- Version updates use rocket emoji: `🚀 Update Bun version to vX.X.X`

### Docker Tags
- `popwers/mini-bun:latest` - Latest stable build
- `popwers/mini-bun:vX.X.X` - Specific version tags

### File Naming
- README uses uppercase extension: `README.MD`

## Important Notes for AI Assistants

1. **Version Updates**: When updating Bun version, only modify the `ARG BUN_VERSION=` line in Dockerfile
2. **Multi-arch Support**: Any Dockerfile changes must work for both amd64 and arm64
3. **GPG Keys**: The GPG key `F3DCC08A8572C0749B3E18888EAB4D40A7B22B59` is Bun's official signing key
4. **Alpine Version**: Currently using Alpine 3.22 - check compatibility before upgrading
5. **No package.json**: This is a Docker-only project, no Node/Bun package management
6. **UPX Compression**: Uses `--all-methods` flag for maximum compression
7. **Security**: Downloads are verified via GPG signature and SHA256 checksum

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BUN_RUNTIME_TRANSPILER_CACHE_PATH` | `0` (disabled) | Transpiler cache path |
| `BUN_INSTALL_BIN` | `/usr/local/bin` | Global package install location |

## Common Tasks

### Check Current Bun Version
```bash
grep 'ARG BUN_VERSION=' Dockerfile | cut -d'=' -f2
```

### Verify Image Size
```bash
docker images mini-bun
```

### Check Latest Bun Release
```bash
curl -s https://api.github.com/repos/oven-sh/bun/releases/latest | jq -r .tag_name
```
