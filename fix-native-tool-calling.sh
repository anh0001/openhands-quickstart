#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Fix Native Tool Calling for OpenHands Web UI
#
# Problem: The OpenHands web UI (V1) uses the SDK's LLM class which defaults
#          native_tool_calling to True. When using Ollama models that don't
#          support native tool calling, the model outputs raw JSON tool calls
#          instead of executing them. The web UI has no toggle for this setting.
#
# Root cause: In the SDK at
#   /app/.venv/lib/python3.13/site-packages/openhands/sdk/llm/llm.py
#   native_tool_calling: bool = Field(default=True, ...)
#
#   The _configure_llm() function in live_status_app_conversation_service.py
#   creates LLM(model=..., base_url=..., api_key=...) without passing
#   native_tool_calling, so it defaults to True for ALL models.
#
# What this script does:
#   1. Creates a wrapper entrypoint script that patches the SDK default
#      from True to False before starting the app
#   2. Creates ~/.openhands/config.toml with native_tool_calling = false
#   3. Patches the openhands CLI gui_launcher.py to:
#      - Mount the wrapper entrypoint into the container
#      - Mount config.toml into the container
#      - Pass LLM_NATIVE_TOOL_CALLING=false env var
#      - Use the wrapper as the container entrypoint
#
# Usage:
#   ./fix-native-tool-calling.sh
#
# After running, restart the web UI:
#   docker stop openhands-app 2>/dev/null
#   docker rm openhands-app 2>/dev/null
#   openhands serve --mount-cwd
#
# Note: Re-run this script after `uv tool upgrade openhands` since the
#       launcher patch will be overwritten by upgrades.
# =============================================================================

OPENHANDS_DIR="${HOME}/.openhands"
PATCHES_DIR="${OPENHANDS_DIR}/patches"
CONFIG_TOML="${OPENHANDS_DIR}/config.toml"
WRAPPER_SCRIPT="${PATCHES_DIR}/entrypoint-wrapper.sh"
LAUNCHER_PY=$(find "${HOME}/.local/share/uv/tools/openhands" -name "gui_launcher.py" -path "*/openhands_cli/*" 2>/dev/null | head -1)

echo "=== Fix Native Tool Calling for OpenHands Web UI ==="
echo ""

# ---- 1. Create wrapper entrypoint -------------------------------------------
echo "[1/3] Creating wrapper entrypoint script ..."

mkdir -p "${PATCHES_DIR}"

cat > "${WRAPPER_SCRIPT}" << 'WRAPPER_EOF'
#!/usr/bin/env bash
# Wrapper entrypoint for OpenHands that patches native_tool_calling default
# before starting the server.

# Patch the SDK LLM class: change default=True to default=False for native_tool_calling
SDK_LLM="/app/.venv/lib/python3.13/site-packages/openhands/sdk/llm/llm.py"
if [[ -f "$SDK_LLM" ]]; then
    sed -i '/native_tool_calling: bool = Field(/{ n; s/default=True,/default=False,/ }' "$SDK_LLM" 2>/dev/null
    echo "[patch] native_tool_calling default changed to False in SDK LLM"
fi

# When --entrypoint is overridden, Docker does NOT forward the image's default CMD.
# We must provide it explicitly.
if [[ $# -eq 0 ]]; then
    exec /app/entrypoint.sh uvicorn openhands.server.listen:app --host 0.0.0.0 --port 3000
else
    exec /app/entrypoint.sh "$@"
fi
WRAPPER_EOF

chmod +x "${WRAPPER_SCRIPT}"
echo "      [✓] Wrapper entrypoint created: ${WRAPPER_SCRIPT}"
echo ""

# ---- 2. Create/update config.toml -------------------------------------------
echo "[2/3] Setting up ${CONFIG_TOML} ..."

if [[ -f "${CONFIG_TOML}" ]]; then
    if grep -q "native_tool_calling" "${CONFIG_TOML}" 2>/dev/null; then
        sed -i 's/native_tool_calling\s*=.*/native_tool_calling = false/' "${CONFIG_TOML}"
        echo "      Updated existing native_tool_calling to false"
    else
        if grep -q '^\[llm\]' "${CONFIG_TOML}" 2>/dev/null; then
            sed -i '/^\[llm\]/a native_tool_calling = false' "${CONFIG_TOML}"
            echo "      Added native_tool_calling = false to existing [llm] section"
        else
            cat >> "${CONFIG_TOML}" << 'EOF'

[llm]
native_tool_calling = false
EOF
            echo "      Added [llm] section with native_tool_calling = false"
        fi
    fi
else
    cat > "${CONFIG_TOML}" << 'EOF'
[llm]
native_tool_calling = false
EOF
    echo "      Created ${CONFIG_TOML}"
fi

echo "      [✓] config.toml ready"
echo ""

# ---- 3. Patch gui_launcher.py -----------------------------------------------
echo "[3/3] Patching openhands CLI gui_launcher.py ..."

if [[ -z "${LAUNCHER_PY}" ]]; then
    echo "      [!] Could not find gui_launcher.py. Is openhands installed via uv?"
    echo "          Install with: uv tool install openhands"
    exit 1
fi

echo "      Found: ${LAUNCHER_PY}"

# Patch A: Add LLM_NATIVE_TOOL_CALLING=false env var
if grep -q "LLM_NATIVE_TOOL_CALLING" "${LAUNCHER_PY}" 2>/dev/null; then
    echo "      LLM_NATIVE_TOOL_CALLING env var already patched"
else
    sed -i '/"LOG_ALL_EVENTS=true",/a\        "-e",\n        "LLM_NATIVE_TOOL_CALLING=false",' "${LAUNCHER_PY}"
    echo "      Added LLM_NATIVE_TOOL_CALLING=false env var"
fi

# Patch B: Mount config.toml into /app/config.toml
if grep -q "config.toml:/app/config.toml" "${LAUNCHER_PY}" 2>/dev/null; then
    echo "      config.toml mount already patched"
else
    sed -i '/f"{config_dir}:\/.openhands",/a\        "-v",\n        f"{config_dir / '\''config.toml'\''}:/app/config.toml",' "${LAUNCHER_PY}"
    echo "      Added config.toml volume mount"
fi

# Patch C: Mount wrapper entrypoint and use it as container entrypoint
if grep -q "entrypoint-wrapper.sh" "${LAUNCHER_PY}" 2>/dev/null; then
    echo "      Wrapper entrypoint already patched"
else
    # Mount the wrapper script into the container
    sed -i '/f"{config_dir}:\/.openhands",/a\        "-v",\n        f"{config_dir / '\''patches'\'' / '\''entrypoint-wrapper.sh'\''}:/entrypoint-wrapper.sh",' "${LAUNCHER_PY}"
    # Add --entrypoint flag before the --name flag
    sed -i '/\"--name\",/i\        "--entrypoint",\n        "/entrypoint-wrapper.sh",' "${LAUNCHER_PY}"
    echo "      Added wrapper entrypoint mount and --entrypoint flag"
fi

echo "      [✓] gui_launcher.py patched"
echo ""

# ---- Verify ------------------------------------------------------------------
echo "=== Verification ==="
echo ""
echo "config.toml contents:"
cat "${CONFIG_TOML}"
echo ""

echo "Wrapper entrypoint:"
cat "${WRAPPER_SCRIPT}"
echo ""

echo "gui_launcher.py patches:"
grep -n "NATIVE_TOOL_CALLING\|config.toml\|entrypoint-wrapper\|--entrypoint" "${LAUNCHER_PY}" 2>/dev/null | while read -r line; do
    echo "  ${line}"
done
echo ""

# ---- Done --------------------------------------------------------------------
echo "=== Done ==="
echo ""
echo "Restart the web UI to apply changes:"
echo ""
echo "    docker stop openhands-app 2>/dev/null"
echo "    docker rm openhands-app 2>/dev/null"
echo "    openhands serve --mount-cwd"
echo ""
