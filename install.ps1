# install.ps1
# Installer script for AI Commit for Lazygit (Windows version)

$ErrorActionPreference = "Stop"

# Use safe Unicode characters via escape sequences
$CheckMark = [char]0x2713
$WarningSign = [char]0x26A0
$RobotEmoji = [char]::ConvertFromUtf32(0x1F916)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Installing AI Commit for Lazygit on Windows" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# --- Define Paths ---
$InstallDir = "$HOME\.ai-commit-lazygit"
$ConfigDir = "$HOME\.config\ai-commit-lazygit"
$ConfigFile = "$ConfigDir\config.json"
$GeneratorScript = "$InstallDir\ai-commit-lazygit.ps1"
$MessageFile = "$ConfigDir\commit_msg.txt"

# 1. Create installation directories
Write-Host "Creating directories..."
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# 2. Copy the generator script
Write-Host "Copying files..."
Copy-Item -Path "ai-commit-lazygit.ps1" -Destination $GeneratorScript -Force

# 3. Create default config if it doesn't exist
if (-not (Test-Path $ConfigFile)) {
    Write-Host "Initializing default config..."
    $defaultConfig = @{
        provider           = "ollama"
        gemini_api_key     = ""
        gemini_model       = "gemini-2.5-flash"
        ollama_model       = "granite4:7b-a1b-h"
        ollama_url         = "http://localhost:11434/api/chat"
        ticket_integration = $false
        ticket_format      = "(#`$ticketId) "
    }
    $defaultConfig | ConvertTo-Json -Depth 10 | Out-File $ConfigFile -Encoding utf8
    Write-Host "$CheckMark Default configuration created at $ConfigFile" -ForegroundColor Green
} else {
    Write-Host "$CheckMark Configuration already exists at $ConfigFile" -ForegroundColor Green
}

# 4. Check for Ollama model
Write-Host "`nChecking Ollama status..."
try {
    # Test connection to Ollama local server
    $response = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -Method Get -TimeoutSec 4
    $models = $response.models.name
    if ($models -contains "granite4:7b-a1b-h" -or $models -contains "granite4:7b-a1b-h:latest") {
        Write-Host "$CheckMark Ollama model 'granite4:7b-a1b-h' is installed." -ForegroundColor Green
    } else {
        Write-Host "$WarningSign Ollama model 'granite4:7b-a1b-h' was not found in local models." -ForegroundColor Yellow
        $pullChoice = Read-Host "Would you like to pull the model 'granite4:7b-a1b-h' now? (y/n) [default: y]"
        if ([string]::IsNullOrWhiteSpace($pullChoice) -or $pullChoice.Trim().ToLower() -eq "y") {
            Write-Host "Pulling model 'granite4:7b-a1b-h'... This may take several minutes."
            ollama pull granite4:7b-a1b-h
            Write-Host "$CheckMark Model pulled successfully." -ForegroundColor Green
        }
    }
} catch {
    Write-Host "$WarningSign Ollama is not running or not installed. Please make sure to download and start Ollama, then run: ollama pull granite4:7b-a1b-h" -ForegroundColor Yellow
}

# 5. Configure Lazygit
Write-Host "`nConfiguring Lazygit integration..."
$lazygitConfigDir = $null
try {
    $lazygitConfigDir = (lazygit --print-config-dir).Trim()
} catch {
    # Fallback paths
    if (Test-Path "$env:LOCALAPPDATA\lazygit") {
        $lazygitConfigDir = "$env:LOCALAPPDATA\lazygit"
    } elseif (Test-Path "$env:APPDATA\lazygit") {
        $lazygitConfigDir = "$env:APPDATA\lazygit"
    }
}

if ($null -eq $lazygitConfigDir -or -not (Test-Path $lazygitConfigDir)) {
    Write-Warning "Could not locate Lazygit configuration directory. Please configure custom commands manually."
    Write-Host "For manual configuration, add the following to your Lazygit config.yml:"
    Write-Host @"
customCommands:
  - key: "a"
    description: "Generate AI Commit"
    context: "files"
    loadingText: "Generating AI commit message..."
    command: 'powershell -NoProfile -ExecutionPolicy Bypass -File "$GeneratorScript" && git commit -e -F "$MessageFile"'
    output: terminal
"@
} else {
    $lazygitConfigFile = Join-Path $lazygitConfigDir "config.yml"
    Write-Host "Lazygit config file located: $lazygitConfigFile"

    # Load or initialize config.yml
    $lines = @()
    if (Test-Path $lazygitConfigFile) {
        $lines = Get-Content $lazygitConfigFile
        # Backup existing config
        Copy-Item -Path $lazygitConfigFile -Destination "$lazygitConfigFile.bak" -Force
        Write-Host "$CheckMark Backed up existing Lazygit config to $lazygitConfigFile.bak" -ForegroundColor Green
    }

    # Remove existing AI commit custom command blocks
    # Looks for any command containing our generator script name or older generator names
    $cleanLines = [System.Collections.Generic.List[string]]::new()
    $inMatchBlock = $false
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*-\s+key:') {
            # Look ahead to next list item or unindented line
            $j = $i
            $isMatch = $false
            while ($j -lt $lines.Count) {
                if ($j -gt $i -and ($lines[$j] -match '^\s*-\s+key:' -or $lines[$j] -match '^\S')) {
                    break
                }
                if ($lines[$j] -match 'ai-commit-lazygit\.ps1' -or $lines[$j] -match 'Get-GeminiCommit\.ps1' -or $lines[$j] -match 'Get-OllamaCommit\.ps1') {
                    $isMatch = $true
                    break
                }
                $j++
            }
            if ($isMatch) {
                $inMatchBlock = $true
                continue
            } else {
                $inMatchBlock = $false
            }
        } elseif ($line -match '^\S' -and $line -notmatch '^customCommands:') {
            $inMatchBlock = $false
        }
        
        if (-not $inMatchBlock) {
            $cleanLines.Add($line)
        }
    }

    # Prepare command lines
    # Note: Using absolute paths here ensures absolute reliability for the user
    $customCmdBlock = @(
        "  - key: `"a`"",
        "    description: `"Generate AI Commit`"",
        "    context: `"files`"",
        "    loadingText: `"Generating AI commit message...`"",
        "    command: 'powershell -NoProfile -ExecutionPolicy Bypass -Command `"`& `\`"$GeneratorScript`\`"; if (`$`?) { git commit -e -F `\`"$MessageFile`\`" }`"`'",
        "    output: terminal"
    )

    $finalLines = [System.Collections.Generic.List[string]]::new()
    $hasCustomCommandsHeader = $false
    $headerIndex = -1

    for ($i = 0; $i -lt $cleanLines.Count; $i++) {
        $line = $cleanLines[$i]
        $finalLines.Add($line)
        if ($line -match '^customCommands:') {
            $hasCustomCommandsHeader = $true
            $headerIndex = $finalLines.Count
        }
    }

    if ($hasCustomCommandsHeader) {
        # Insert block right after the customCommands: header
        $idx = $headerIndex
        foreach ($cmdLine in $customCmdBlock) {
            $finalLines.Insert($idx++, $cmdLine)
        }
    } else {
        # Append header and block
        $finalLines.Add("customCommands:")
        foreach ($cmdLine in $customCmdBlock) {
            $finalLines.Add($cmdLine)
        }
    }

    # Save configuration
    [System.IO.File]::WriteAllLines($lazygitConfigFile, $finalLines.ToArray(), [System.Text.Encoding]::UTF8)
    Write-Host "$CheckMark Updated Lazygit config.yml successfully with key 'a'." -ForegroundColor Green
}

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "To configure/add Gemini API Key or change settings, edit:"
Write-Host "  $ConfigFile" -ForegroundColor Yellow
Write-Host "To use inside Lazygit, stage your changes, then press 'a'!" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan
