#!/bin/bash
set -e

echo ""
echo "=== Qualification Agent Setup ==="
echo ""

# Find Python command
if command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD="python"
else
  echo "Error: Python is not installed. Please install Python 3 and try again."
  exit 1
fi

# Find Pip command
if command -v pip3 >/dev/null 2>&1; then
  PIP_CMD="pip3"
elif command -v pip >/dev/null 2>&1; then
  PIP_CMD="pip"
else
  echo "Error: pip is not installed. Please install pip and try again."
  exit 1
fi

# Install Python dependency
echo "Installing required Python package..."
if ! $PIP_CMD install "parallel-web>=1.0.1" -q; then
  echo "Global installation failed (possibly due to PEP 668 / managed environment)."
  echo "Attempting to install with --break-system-packages..."
  if ! $PIP_CMD install "parallel-web>=1.0.1" --break-system-packages -q; then
    echo "Failed to install package. Please create a virtual environment and try again:"
    echo "  python3 -m venv venv"
    echo "  source venv/bin/activate"
    echo "  pip install parallel-web"
    exit 1
  fi
fi
echo "Done."
echo ""

# Ask for API key
echo "Enter your Parallel API key (get one at https://platform.parallel.ai):"
read -r api_key

if [ -z "$api_key" ]; then
  echo "No API key entered. You can add it later by editing tools/.env"
else
  echo "Verifying API key..."
  VERIFY_RESULT=$($PYTHON_CMD -c '
import urllib.request
import urllib.error
import sys

api_key = sys.argv[1]
req = urllib.request.Request(
    "https://api.parallel.ai/account/service/v1/balance",
    headers={"Authorization": f"Bearer {api_key}"}
)
try:
    with urllib.request.urlopen(req) as response:
        if response.status == 200:
            print("VALID")
            sys.exit(0)
except urllib.error.HTTPError as e:
    if e.code in (401, 403):
        print("INVALID")
        sys.exit(1)
    else:
        print(f"HTTP_ERROR_{e.code}")
        sys.exit(2)
except Exception as e:
    print("CONNECTION_ERROR")
    sys.exit(3)
' "$api_key" 2>&1 || true)

  if [ "$VERIFY_RESULT" = "VALID" ]; then
    echo "API key verified successfully!"
    echo "PARALLEL_API_KEY=$api_key" > tools/.env
    echo "API key saved to tools/.env"
  elif [ "$VERIFY_RESULT" = "INVALID" ]; then
    echo "Error: The API key entered is invalid."
    echo "Please double-check your key at https://platform.parallel.ai."
    echo "Do you still want to save it? (y/n)"
    read -r save_anyway
    if [ "$save_anyway" = "y" ] || [ "$save_anyway" = "Y" ]; then
      echo "PARALLEL_API_KEY=$api_key" > tools/.env
      echo "API key saved to tools/.env"
    else
      echo "API key was not saved."
    fi
  else
    echo "Warning: Could not verify API key ($VERIFY_RESULT)."
    echo "Saving key anyway..."
    echo "PARALLEL_API_KEY=$api_key" > tools/.env
    echo "API key saved to tools/.env"
  fi
fi

echo ""
echo "Setup complete! Open Claude Code and say: qualify these companies"
echo ""

