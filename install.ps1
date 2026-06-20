# Qualification Agent — Windows Installer
# Step 1: Download this file
# Step 2: Right-click it and select "Run with PowerShell"

Write-Host ""
Write-Host "=== Qualification Agent Installer ==="
Write-Host ""

# ── Helper: refresh PATH so newly installed tools are found ───────────────────
function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# ── Helper: install via winget ────────────────────────────────────────────────
function Install-WithWinget($packageId, $label) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing $label via winget..."
        winget install --id $packageId --silent --accept-package-agreements --accept-source-agreements
        Refresh-Path
        return $true
    }
    return $false
}

# ── Python ────────────────────────────────────────────────────────────────────
$PYTHON_CMD = $null
foreach ($cmd in @("python", "python3")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        if ((& $cmd --version 2>&1) -match "Python 3") { $PYTHON_CMD = $cmd; break }
    }
}

if (-not $PYTHON_CMD) {
    Write-Host "Python 3 not found — installing automatically..."
    $installed = Install-WithWinget "Python.Python.3.12" "Python 3"

    if (-not $installed) {
        # winget not available — download installer silently
        Write-Host "Downloading Python installer..."
        $pyInstaller = "$env:TEMP\python_installer.exe"
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.4/python-3.12.4-amd64.exe" `
            -OutFile $pyInstaller -UseBasicParsing
        Write-Host "Running Python installer (this may take a minute)..."
        Start-Process -FilePath $pyInstaller `
            -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1" `
            -Wait
        Remove-Item $pyInstaller -Force
        Refresh-Path
    }

    # Re-check
    foreach ($cmd in @("python", "python3")) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            if ((& $cmd --version 2>&1) -match "Python 3") { $PYTHON_CMD = $cmd; break }
        }
    }

    if (-not $PYTHON_CMD) {
        Write-Host ""
        Write-Host "Python installation succeeded but could not be found in PATH."
        Write-Host "Please close this window, reopen PowerShell, and run install.ps1 again."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "Python installed."
}

# ── pip ───────────────────────────────────────────────────────────────────────
$PIP_CMD = $null
foreach ($cmd in @("pip", "pip3")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) { $PIP_CMD = $cmd; break }
}
if (-not $PIP_CMD) {
    # Bootstrap pip via ensurepip
    Write-Host "pip not found — bootstrapping..."
    & $PYTHON_CMD -m ensurepip --upgrade | Out-Null
    Refresh-Path
    foreach ($cmd in @("pip", "pip3")) {
        if (Get-Command $cmd -ErrorAction SilentlyContinue) { $PIP_CMD = $cmd; break }
    }
}
if (-not $PIP_CMD) {
    # Last resort: use python -m pip directly
    $PIP_CMD = "$PYTHON_CMD -m pip"
}

# ── Git ───────────────────────────────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found — installing automatically..."
    $installed = Install-WithWinget "Git.Git" "Git"

    if (-not $installed) {
        Write-Host "Downloading Git installer..."
        $gitInstaller = "$env:TEMP\git_installer.exe"
        Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/Git-2.45.2-64-bit.exe" `
            -OutFile $gitInstaller -UseBasicParsing
        Write-Host "Running Git installer (this may take a minute)..."
        Start-Process -FilePath $gitInstaller `
            -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh" `
            -Wait
        Remove-Item $gitInstaller -Force
        Refresh-Path
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "Git installation succeeded but could not be found in PATH."
        Write-Host "Please close this window, reopen PowerShell, and run install.ps1 again."
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "Git installed."
}

# ── Claude Code ───────────────────────────────────────────────────────────────
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "Claude Code is not installed."
    Write-Host "Please install it from https://claude.ai/code then re-run this installer."
    Start-Process "https://claude.ai/code"
    Read-Host "Press Enter to exit"
    exit 1
}

# ── Clone or update the skill ─────────────────────────────────────────────────
Write-Host ""
$SKILL_DIR = "$env:USERPROFILE\.claude\skills\qualification-agent"

if (Test-Path $SKILL_DIR) {
    Write-Host "Skill already installed — updating..."
    git -C $SKILL_DIR pull -q
} else {
    Write-Host "Downloading qualification-agent..."
    git clone -q https://github.com/Me-Garvit/Parallel-Qualification-Agent $SKILL_DIR
}
Write-Host "Done."
Write-Host ""

# ── Install Python dependency ─────────────────────────────────────────────────
Write-Host "Installing required Python package..."
if ($PIP_CMD -like "* -m pip") {
    $parts = $PIP_CMD -split " "
    & $parts[0] -m pip install "parallel-web>=1.0.1" -q
} else {
    & $PIP_CMD install "parallel-web>=1.0.1" -q
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install package. Please try running this script as Administrator."
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "Done."
Write-Host ""

# ── API key ───────────────────────────────────────────────────────────────────
Write-Host "Enter your Parallel API key."
Write-Host "Get one for free at: https://platform.parallel.ai"
Write-Host ""
$api_key = Read-Host "API key"

if ([string]::IsNullOrWhiteSpace($api_key)) {
    Write-Host ""
    Write-Host "No key entered. You can add it later by editing:"
    Write-Host "  $SKILL_DIR\tools\.env"
} else {
    Write-Host "Verifying key..."
    try {
        $response = Invoke-WebRequest `
            -Uri "https://api.parallel.ai/account/service/v1/balance" `
            -Headers @{ Authorization = "Bearer $api_key" } `
            -UseBasicParsing -ErrorAction Stop

        if ($response.StatusCode -eq 200) {
            Write-Host "Key verified!"
        }
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 401 -or $code -eq 403) {
            Write-Host "Warning: Key looks invalid — double-check at https://platform.parallel.ai"
        } else {
            Write-Host "Could not verify key (network issue). Saving anyway..."
        }
    }
    Set-Content -Path "$SKILL_DIR\tools\.env" -Value "PARALLEL_API_KEY=$api_key"
    Write-Host "API key saved."
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "All done! Here's how to use it:"
Write-Host ""
Write-Host "  1. Open the folder with your companies CSV"
Write-Host "  2. Right-click inside the folder → 'Open in Terminal'"
Write-Host "  3. Type: claude"
Write-Host "  4. Say: parallel qualify companies.csv"
Write-Host ""
Read-Host "Press Enter to exit"
