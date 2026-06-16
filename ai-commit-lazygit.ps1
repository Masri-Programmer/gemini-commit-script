# ai-commit-lazygit.ps1
# AI-powered Git commit message generator for Lazygit (Windows PowerShell version)

param (
    [string]$OutputFile = "$HOME\.config\ai-commit-lazygit\commit_msg.txt",
    [string]$ProviderOverride = $null,
    [string]$ModelOverride = $null
)

$ErrorActionPreference = "Stop"

# --- Define Paths ---
$ConfigDir = "$HOME\.config\ai-commit-lazygit"
$ConfigFile = "$ConfigDir\config.json"

# Ensure config directory exists
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# --- Default Config Template ---
$DefaultConfig = @{
    provider           = "ollama"
    gemini_api_key     = ""
    gemini_model       = "gemini-2.5-flash"
    ollama_model       = "granite4:7b-a1b-h"
    ollama_url         = "http://localhost:11434/api/chat"
    ticket_integration = $false
    ticket_format      = "(#`$ticketId) "
}

# Load or create config
if (Test-Path $ConfigFile) {
    try {
        $configContent = Get-Content $ConfigFile -Raw -ErrorAction SilentlyContinue
        $config = $configContent | ConvertFrom-Json
        # Merge defaults for any missing keys
        foreach ($key in $DefaultConfig.Keys) {
            if (-not ($config.PSObject.Properties[$key])) {
                $config | Add-Member -MemberType NoteProperty -Name $key -Value $DefaultConfig[$key]
            }
        }
    }
    catch {
        Write-Warning "Failed to parse config.json. Using defaults."
        $config = [PSCustomObject]$DefaultConfig
    }
} else {
    $config = [PSCustomObject]$DefaultConfig
    $config | ConvertTo-Json -Depth 10 | Out-File $ConfigFile -Encoding utf8
}

# Override from command line parameters if provided
$provider = if ($ProviderOverride) { $ProviderOverride } else { $config.provider }
$gemini_model = $config.gemini_model
$ollama_model = if ($ModelOverride) { $ModelOverride } else { $config.ollama_model }
$ollama_url = $config.ollama_url
$gemini_api_key = $config.gemini_api_key

# Check for Gemini key in environment variable if not in config
if ([string]::IsNullOrWhiteSpace($gemini_api_key)) {
    $gemini_api_key = $env:GEMINI_API_KEY
}

# --- Step 1: Check Git Repo & Changes ---
try {
    $branchName = git symbolic-ref --short HEAD 2>$null
} catch {
    Write-Error "Error: Not in a git repository or detached HEAD."
    exit 1
}

$diff = git diff --cached | Out-String
if ([string]::IsNullOrWhiteSpace($diff)) {
    Write-Warning "No staged changes found. Please stage some changes first."
    exit 1
}

# Truncate Diff to avoid model context limit issues (approx 3000 chars of diff)
$MAX_DIFF_LENGTH = 3000
if ($diff.Length -gt $MAX_DIFF_LENGTH) {
    $diff = $diff.Substring(0, $MAX_DIFF_LENGTH) + "`n... [Diff truncated for size]"
}

# --- Step 2: System Prompt ---
$systemPromptText = @"
You are an expert developer and git commit message generator.
Task: Analyze the provided git diff and generate a clean, conventional git commit message.

Strict Rules:
1. Message Structure:
<type>(<scope>): <subject>

- <bullet point detailing change 1>
- <bullet point detailing change 2>

2. Allowed Types: 
   feat (new feature), fix (bug fix), refactor (code change that neither fixes a bug nor adds a feature), perf (performance improvement), style (formatting, missing semi colons, etc), test (adding missing tests), docs (documentation), chore (maintenance), build, ci.

3. Scope: 
   Keep it short and lowercase. Infer it from the changed files (e.g., ui, api, vue, tailwind, inertia, routing, auth).

4. Subject Line: 
   - MUST use the imperative, present tense (e.g., "Ensure...", "Add...", "Fix..." - NEVER "Ensured" or "Adds").
   - Max 50 characters.
   - Do not capitalize the first letter.
   - No trailing period.

5. Body: 
   - Briefly explain WHAT changed and WHY, not just HOW.
   - Keep bullet points concise.

6. Output Constraints:
   - Output ONLY the raw commit message text.
   - ABSOLUTELY NO markdown code fences (```).
   - NO conversational filler, greetings, or explanations.
"@

# --- Step 3: Run Generation ---
$commitMsg = $null
$success = $false

# Helper to run Ollama API
filter Get-OllamaCommitMessage {
    $messages = @(
        @{ role = "system"; content = $systemPromptText },
        @{ role = "user"; content = "Here is the diff to analyze:`n$diff" }
    )
    $body = @{
        model    = $ollama_model
        messages = $messages
        stream   = $false
        options  = @{
            temperature = 0.1
            num_ctx     = 2048
        }
    } | ConvertTo-Json -Depth 10

    $RobotEmoji = [char]::ConvertFromUtf32(0x1F916)
    Write-Host "$RobotEmoji Calling Ollama ($ollama_model)..."
    try {
        $response = Invoke-RestMethod -Uri $ollama_url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30
        if ($response.message -and $response.message.content) {
            return $response.message.content
        }
    } catch {
        Write-Warning "Ollama failed: $($_.Exception.Message)"
    }
    return $null
}

# Helper to run Gemini API
filter Get-GeminiCommitMessage {
    if ([string]::IsNullOrWhiteSpace($gemini_api_key)) {
        Write-Warning "Gemini API key is not configured."
        return $null
    }

    $geminiUrl = "https://generativelanguage.googleapis.com/v1beta/models/${gemini_model}:generateContent?key=${gemini_api_key}"
    $body = @{
        systemInstruction = @{
            parts = @( @{ text = $systemPromptText } )
        }
        contents          = @(
            @{
                role  = "user"
                parts = @( @{ text = "Here is the diff to analyze:`n$diff" } )
            }
        )
        generationConfig  = @{
            temperature     = 0.1
            maxOutputTokens = 1000
        }
    } | ConvertTo-Json -Depth 10

    $RobotEmoji = [char]::ConvertFromUtf32(0x1F916)
    Write-Host "$RobotEmoji Calling Gemini ($gemini_model)..."
    try {
        $response = Invoke-RestMethod -Uri $geminiUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 20
        if ($response.candidates -and $response.candidates.Count -gt 0 -and $response.candidates[0].content.parts.Count -gt 0) {
            return $response.candidates[0].content.parts[0].text
        }
    } catch {
        Write-Warning "Gemini failed: $($_.Exception.Message)"
    }
    return $null
}

# Select and Execute Provider
if ($provider -eq "ollama") {
    $commitMsg = Get-OllamaCommitMessage
    if ($commitMsg) { $success = $true }
}
elseif ($provider -eq "gemini") {
    $commitMsg = Get-GeminiCommitMessage
    if ($commitMsg) { $success = $true }
}
elseif ($provider -eq "both") {
    # Try Gemini first, then Ollama fallback
    $commitMsg = Get-GeminiCommitMessage
    if ($commitMsg) {
        $success = $true
    } else {
        $CircleArrows = [char]::ConvertFromUtf32(0x1F504)
        Write-Host "$CircleArrows Falling back to Ollama..."
        $commitMsg = Get-OllamaCommitMessage
        if ($commitMsg) { $success = $true }
    }
}
else {
    Write-Error "Error: Unknown provider '$provider' in configuration."
    exit 1
}

if (-not $success -or [string]::IsNullOrWhiteSpace($commitMsg)) {
    Write-Error "Error: Failed to generate commit message from all attempted providers."
    exit 1
}

# --- Step 4: Cleanup & Formatting ---
$commitMsg = $commitMsg.Trim()
# Remove markdown code block markers
$commitMsg = $commitMsg -replace '^```.*$', '' -replace '```$', '' 
# Remove accidental diff inclusions
$commitMsg = $commitMsg -replace '(?m)^diff --git.*[\s\S]*$', ''
$commitMsg = $commitMsg.Trim()

# Apply ticket ID prefix if configured and found
if ($config.ticket_integration -and $branchName) {
    if ($branchName -match '\d+') {
        $ticketId = $Matches[0]
        # Resolve ticket format
        $prefix = $config.ticket_format.Replace("`$ticketId", $ticketId)
        $commitMsg = "$prefix$commitMsg"
    }
}

# --- Step 5: Save & Output ---
# Ensure Output File parent directory exists
$outputFileDir = [System.IO.Path]::GetDirectoryName($OutputFile)
if (-not (Test-Path $outputFileDir)) {
    New-Item -ItemType Directory -Path $outputFileDir -Force | Out-Null
}

# Write UTF-8 file cleanly without BOM using .NET to avoid PowerShell Core/Desktop differences
[System.IO.File]::WriteAllLines($OutputFile, @($commitMsg), [System.Text.Encoding]::UTF8)

Write-Host "`n--------------------------" -ForegroundColor Green
Write-Host $commitMsg
Write-Host "--------------------------`n" -ForegroundColor Green
Write-Host "Generated commit message saved to: $OutputFile"
