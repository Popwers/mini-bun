<p align="center">
  <img src="https://bun.sh/logo.svg" alt="Bun Logo" width="200" height="200">
</p>

# 🍞 Mini Bun Docker Image

[!IMPORTANT]
This project is a fork of the official [Bun repository](https://github.com/oven-sh/bun).

## 🚀 Project Overview

Mini Bun Docker Image aims to create a compact and efficient Docker image for Bun by leveraging UPX (Ultimate Packer for eXecutables) to compress the Bun binary. The result is a significantly smaller container image without compromising functionality.

## 📁 Project Structure

- `Dockerfile`: Defines the multi-stage build process, including UPX compression
- `docker-entrypoint.sh`: Entry point script for the Docker container
- `.github/workflows/`:
  - `publish.yml`: Workflow for building and publishing the Docker image

## 🏁 Getting Started

To use this optimized Bun Docker image:

1. Pull the image from Docker Hub:
   ```bash
   docker pull popwers/mini-bun:latest
   ```

2. Run a container:
   ```bash
   docker run -it popwers/mini-bun:latest
   ```

## 🛠️ Building the Image Locally

If you want to build the image locally:

1. Clone the repository:
   ```bash
   git clone https://github.com/popwers/mini-bun.git
   cd mini-bun
   ```

2. Build the Docker image:
   ```bash
   docker build -t mini-bun .
   ```

## 🤖 GitHub Actions Workflow

This project uses GitHub Actions for automation:

- **Publish Workflow**: Builds the Docker image for multiple architectures (amd64, arm64) and pushes it to Docker Hub
- **Version Check Workflow**: Automatically checks for new Bun releases and triggers a rebuild if a new version is available

## 🙏 Credits

- [Bun](https://bun.sh/) - The JavaScript runtime
- [UPX](https://upx.github.io/) - The Ultimate Packer for eXecutables

## 📚 Additional Resources

- [Bun Documentation](https://bun.sh/docs)
- [Bun GitHub Repository](https://github.com/oven-sh/bun)
