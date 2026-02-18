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

If you're using an Ollama model (e.g. `ollama/llama3`, `ollama/codellama`), you **must disable native tool calling** — Ollama models do not support it and OpenHands will output raw JSON tool calls instead of executing them.

### The Problem

The OpenHands web UI (V1) uses the SDK's `LLM` class which **defaults** `native_tool_calling` to `True`:

```python
# /app/.venv/lib/python3.13/site-packages/openhands/sdk/llm/llm.py
native_tool_calling: bool = Field(default=True, ...)
```

The server's `_configure_llm()` function creates the LLM object with only `model`, `base_url`, and `api_key` — it **never passes** `native_tool_calling`, so every model gets `True` regardless of configuration.

Additionally:
- The web UI's `settings.json` has **no field** for `native_tool_calling`
- The `LLM_NATIVE_TOOL_CALLING` environment variable is **not read** by the server code
- A `config.toml` alone is insufficient because the V1 code path doesn't propagate this setting to the agent-server containers

**Symptoms:** The agent outputs raw JSON like `{"type": "function", "name": "think", ...}` instead of actually executing tools.

### Fix for CLI (Terminal UI)

The CLI stores settings in `~/.openhands/agent_settings.json`. You can set the flag directly:

```bash
openhands \
  --llm-model ollama/llama3 \
  --llm-base-url http://localhost:11434 \
  --llm-native-tool-calling false
```

Or configure it interactively during first run — it will be saved for future sessions.

### Fix for Web UI (`openhands serve`)

Since the web UI has no settings toggle and no config file path that works, the fix **patches the SDK default inside the Docker container** at startup using a wrapper entrypoint.

Run the included fix script:

```bash
./fix-native-tool-calling.sh
```

Then restart the web UI:

```bash
docker stop openhands-app 2>/dev/null
docker rm openhands-app 2>/dev/null
openhands serve --mount-cwd
```

**What the script does (3 steps):**

1. **Creates a wrapper entrypoint** (`~/.openhands/patches/entrypoint-wrapper.sh`) that runs `sed` to change `default=True` to `default=False` in the SDK's `LLM` class before starting the original `/app/entrypoint.sh`
2. **Creates `~/.openhands/config.toml`** with `native_tool_calling = false` under `[llm]` (belt-and-suspenders)
3. **Patches `gui_launcher.py`** to:
   - Mount the wrapper entrypoint into the container
   - Mount `config.toml` into `/app/config.toml`
   - Pass `LLM_NATIVE_TOOL_CALLING=false` as a Docker environment variable
   - Override the container's entrypoint with the wrapper script

> **Important:** The `gui_launcher.py` patch is overwritten when you run `uv tool upgrade openhands`. Re-run `./fix-native-tool-calling.sh` after upgrading.

> **Note:** You must `docker rm openhands-app` before restarting because the container uses `--name openhands-app`. If an old container exists (even stopped), Docker will refuse to start a new one with the same name.

> **Note:** Cloud-hosted models like **Claude** or **GPT** work fine in both the CLI and the UI — no extra flags needed.

## Manual Steps

If you prefer to run the steps manually, see the [setup.sh](setup.sh) script for details.

## References

- [OpenHands GitHub](https://github.com/All-Hands-AI/OpenHands)
- [OpenHands Documentation](https://docs.all-hands.dev/)
