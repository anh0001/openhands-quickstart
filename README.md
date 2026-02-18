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

## Using Ollama (Local Models)

If you're using an Ollama model (e.g. `ollama/llama3`, `ollama/codellama`), you **must disable native tool calling** — Ollama models do not support it properly and OpenHands will fail silently or produce errors.

**This only works via the CLI** (running `openhands` in the terminal). Set the flag with:

```bash
openhands \
  --llm-model ollama/llama3 \
  --llm-base-url http://localhost:11434 \
  --llm-native-tool-calling false
```

> **Note:** The OpenHands web UI currently has **no option** to set `native_tool_calling` to `false`. If you need to use Ollama models, use the CLI instead.
>
> Cloud-hosted models like **Claude** or **GPT** work fine in both the CLI and the UI — no extra flags needed.

## Manual Steps

If you prefer to run the steps manually, see the [setup.sh](setup.sh) script for details.

## References

- [OpenHands GitHub](https://github.com/All-Hands-AI/OpenHands)
- [OpenHands Documentation](https://docs.all-hands.dev/)
