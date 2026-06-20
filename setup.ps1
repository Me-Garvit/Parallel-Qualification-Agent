# Qualification Agent Setup — Windows (PowerShell)
# Run with: powershell -ExecutionPolicy Bypass -File setup.ps1

Write-Host ""
Write-Host "=== Qualification Agent Setup ==="
Write-Host ""

# Find Python
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    $PYTHON_CMD = "python3"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $PYTHON_CMD = "python"
} else {
    Write-Host "Error: Python is not installed. Please install it from https://python.org and try again."
    exit 1
}

# Find pip
if (Get-Command pip3 -ErrorAction SilentlyContinue) {
    $PIP_CMD = "pip3"
} elseif (Get-Command pip -ErrorAction SilentlyContinue) {
    $PIP_CMD = "pip"
} else {
    Write-Host "Error: pip is not installed. Please install pip and try again."
    exit 1
}

# Install Python dependency
Write-Host "Installing required Python package..."
$pipResult = & $PIP_CMD install "parallel-web>=1.0.1" -q 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installation failed. Please try running in a virtual environment:"
    Write-Host "  python -m venv venv"
    Write-Host "  .\venv\Scripts\Activate.ps1"
    Write-Host "  pip install parallel-web"
    exit 1
}
Write-Host "Done."
Write-Host ""

# Ask for API key
$api_key = Read-Host "Enter your Parallel API key (get one at https://platform.parallel.ai)"

if ([string]::IsNullOrWhiteSpace($api_key)) {
    Write-Host "No API key entered. You can add it later by creating tools\.env with:"
    Write-Host "  PARALLEL_API_KEY=your-key-here"
} else {
    Write-Host "Verifying API key..."
    try {
        $response = Invoke-WebRequest `
            -Uri "https://api.parallel.ai/account/service/v1/balance" `
            -Headers @{ Authorization = "Bearer $api_key" } `
            -UseBasicParsing `
            -ErrorAction Stop

        if ($response.StatusCode -eq 200) {
            Write-Host "API key verified successfully!"
            Set-Content -Path "tools\.env" -Value "PARALLEL_API_KEY=$api_key"
            Write-Host "API key saved to tools\.env"
        }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401 -or $statusCode -eq 403) {
            Write-Host "Error: The API key entered is invalid."
            Write-Host "Please double-check your key at https://platform.parallel.ai."
            $save_anyway = Read-Host "Do you still want to save it? (y/n)"
            if ($save_anyway -eq "y" -or $save_anyway -eq "Y") {
                Set-Content -Path "tools\.env" -Value "PARALLEL_API_KEY=$api_key"
                Write-Host "API key saved to tools\.env"
            } else {
                Write-Host "API key was not saved."
            }
        } else {
            Write-Host "Warning: Could not verify API key (network error). Saving anyway..."
            Set-Content -Path "tools\.env" -Value "PARALLEL_API_KEY=$api_key"
            Write-Host "API key saved to tools\.env"
        }
    }
}

Write-Host ""
Write-Host "Setup complete! Open Claude Code and say: parallel qualify companies.csv"
Write-Host ""
