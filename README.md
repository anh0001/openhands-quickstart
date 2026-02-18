# OpenHands Quickstart

Quick setup guide for [OpenHands](https://github.com/All-Hands-AI/OpenHands) — an autonomous AI software engineer.

## Prerequisites

- Linux (tested on Ubuntu)
- Docker installed and running
- `curl` available

## Quick Setup

```bash
./setup.sh
```

This script will:

1. **Install `uv`** — a fast Python package manager used to install OpenHands
2. **Install OpenHands** via `uv tool install`
3. **Fix container-to-host disk write permissions** using POSIX ACLs so the OpenHands sandbox container can write to your local workspace

## What the ACL Fix Does

OpenHands runs code inside a Docker container. By default, the container user may not have permission to write files back to your mounted workspace directory. The setup script uses `setfacl` to grant the container's default user (UID 1000) read/write/execute access to the workspace, solving "Permission denied" errors.

## Running OpenHands

After setup, start OpenHands:

```bash
openhands
```

Or specify a workspace directory:

```bash
WORKSPACE_DIR=/path/to/your/project openhands
```

## Manual Steps

If you prefer to run the steps manually, see the [setup.sh](setup.sh) script for details.

## References

- [OpenHands GitHub](https://github.com/All-Hands-AI/OpenHands)
- [OpenHands Documentation](https://docs.all-hands.dev/)
