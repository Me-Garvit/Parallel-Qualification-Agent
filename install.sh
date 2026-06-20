#!/bin/bash
# Qualification Agent — macOS/Linux Installer
# Run: curl -fsSL https://raw.githubusercontent.com/garvit-exe/qualification-agent/main/install.sh | bash

set -e

echo ""
echo "=== Qualification Agent Installer ==="
echo ""

# ── Check Python ──────────────────────────────────────────────────────────────
PYTHON_CMD=""
for cmd in python3 python; do
    if command -v "$cmd" >/dev/null 2>&1; then
        if "$cmd" --version 2>&1 | grep -q "Python 3"; then
            PYTHON_CMD="$cmd"; break
        fi
    fi
done
if [ -z "$PYTHON_CMD" ]; then
    echo "Python 3 is not installed."
    echo "Install it from https://python.org and re-run this installer."
    exit 1
fi

# ── Check pip ─────────────────────────────────────────────────────────────────
PIP_CMD=""
for cmd in pip3 pip; do
    if command -v "$cmd" >/dev/null 2>&1; then
        PIP_CMD="$cmd"; break
    fi
done
if [ -z "$PIP_CMD" ]; then
    echo "pip is not installed. Please reinstall Python from https://python.org"
    exit 1
fi

# ── Check Git ─────────────────────────────────────────────────────────────────
if ! command -v git >/dev/null 2>&1; then
    echo "Git is not installed."
    echo "Install it from https://git-scm.com and re-run this installer."
    exit 1
fi

# ── Check Claude Code ─────────────────────────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
    echo "Claude Code is not installed."
    echo "Install it from https://claude.ai/code and re-run this installer."
    exit 1
fi

# ── Clone or update the skill ─────────────────────────────────────────────────
SKILL_DIR="$HOME/.claude/skills/qualification-agent"

if [ -d "$SKILL_DIR" ]; then
    echo "Skill already installed — updating..."
    git -C "$SKILL_DIR" pull -q
else
    echo "Downloading qualification-agent..."
    git clone -q https://github.com/garvit-exe/qualification-agent "$SKILL_DIR"
fi
echo "Done."
echo ""

# ── Install Python dependency ─────────────────────────────────────────────────
echo "Installing required Python package..."
if ! $PIP_CMD install "parallel-web>=1.0.1" -q; then
    echo "Global install failed — trying with --break-system-packages..."
    if ! $PIP_CMD install "parallel-web>=1.0.1" --break-system-packages -q; then
        echo "Failed to install package. Please try:"
        echo "  python3 -m venv venv && source venv/bin/activate && pip install parallel-web"
        exit 1
    fi
fi
echo "Done."
echo ""

# ── API key ───────────────────────────────────────────────────────────────────
echo "Enter your Parallel API key."
echo "Get one for free at: https://platform.parallel.ai"
echo ""
read -rp "API key: " api_key

if [ -z "$api_key" ]; then
    echo ""
    echo "No key entered. You can add it later by editing:"
    echo "  $SKILL_DIR/tools/.env"
else
    echo "Verifying key..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $api_key" \
        "https://api.parallel.ai/account/service/v1/balance")

    if [ "$HTTP_CODE" = "200" ]; then
        echo "Key verified!"
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        echo "Warning: Key looks invalid. Saving anyway — double-check at https://platform.parallel.ai"
    else
        echo "Could not verify key (no internet?). Saving anyway..."
    fi
    echo "PARALLEL_API_KEY=$api_key" > "$SKILL_DIR/tools/.env"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "All done! Here's how to use it:"
echo ""
echo "  1. Open Terminal in the folder with your companies CSV"
echo "  2. Type: claude"
echo "  3. Say: parallel qualify companies.csv"
echo ""
