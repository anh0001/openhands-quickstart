#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# OpenHands Quickstart Setup
# Installs OpenHands via uv and fixes ACL permissions so the sandbox container
# can write to the local workspace directory.
# =============================================================================

WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"

echo "=== OpenHands Quickstart Setup ==="
echo ""

# ---- 1. Install uv (if not already installed) --------------------------------
if command -v uv &>/dev/null; then
    echo "[✓] uv is already installed: $(uv --version)"
else
    echo "[*] Installing uv ..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Source the env so uv is available in this session
    if [[ -f "$HOME/.local/bin/env" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.local/bin/env"
    fi
    export PATH="$HOME/.local/bin:$PATH"

    echo "[✓] uv installed: $(uv --version)"
fi

echo ""

# ---- 2. Install OpenHands via uv ---------------------------------------------
if uv tool list 2>/dev/null | grep -q "openhands"; then
    echo "[✓] openhands is already installed via uv"
    echo "    To upgrade: uv tool upgrade openhands"
else
    echo "[*] Installing openhands via uv ..."
    uv tool install openhands
    echo "[✓] openhands installed"
fi

echo ""

# ---- 3. Fix ACL permissions for container write access ------------------------
# OpenHands sandbox containers typically run as UID 1000. If your workspace
# directory is not writable by that UID, the container will fail with
# "Permission denied". We use POSIX ACLs to grant access without changing
# ownership or broadening world permissions.

CONTAINER_UID="${CONTAINER_UID:-1000}"

echo "[*] Setting up ACL permissions for workspace: ${WORKSPACE_DIR}"
echo "    Container UID: ${CONTAINER_UID}"

# Install acl utilities if missing
if ! command -v setfacl &>/dev/null; then
    echo "[*] Installing ACL utilities ..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq acl
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y acl
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm acl
    else
        echo "[!] Could not install acl package. Please install it manually."
        exit 1
    fi
fi

# Set ACL: grant the container UID rwx on existing files and as the default for
# new files/directories created under the workspace.
setfacl -R -m u:"${CONTAINER_UID}":rwx "${WORKSPACE_DIR}"
setfacl -R -d -m u:"${CONTAINER_UID}":rwx "${WORKSPACE_DIR}"

echo "[✓] ACL permissions applied"
echo ""

# ---- Done ---------------------------------------------------------------------
echo "=== Setup complete ==="
echo ""
echo "Start OpenHands with:"
echo ""
echo "    openhands"
echo ""
echo "Or with a custom workspace:"
echo ""
echo "    WORKSPACE_DIR=/path/to/project openhands"
echo ""
