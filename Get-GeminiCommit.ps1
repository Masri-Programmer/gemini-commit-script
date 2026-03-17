# ==========================================
# 1. PREPARATION (Shared Logic)
# ==========================================

# --- Common Config ---
$MAX_DIFF_LENGTH = 3000

# Get Staged Changes
$diff = git diff --cached | Out-String

if ([string]::IsNullOrWhiteSpace($diff)) {
    Write-Output "No staged changes found."
    exit 0
}

# Truncate Diff (Shared)
if ($diff.Length -gt $MAX_DIFF_LENGTH) {
    $diff = $diff.Substring(0, $MAX_DIFF_LENGTH) + "`n... [Diff truncated]"
}

# Define the System Prompt (Shared)
# Define the System Prompt (Shared)
$systemPromptText = @"
You are an expert developer and git commit message generator.
Task: Analyze the provided git diff and generate a clean, conventional git commit message.

Strict Rules:
1. Message Structure:
<type>(<scope>): <subject>
<BLANK LINE>
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

# ==========================================
# 2. ATTEMPT GEMINI
# ==========================================
$geminiSuccess = $false

try {
    # --- Gemini Configuration ---
    $GEMINI_API_KEY = $env:GEMINI_API_KEY
    if ([string]::IsNullOrWhiteSpace($GEMINI_API_KEY)) {
        # Fallback to hardcoded key if env var is missing
        $GEMINI_API_KEY = "AIzaSyA7Et4mVYMSXq9O-3NIiUpeZKBX4IyWw5k" 
    }
    
    # Use the correct current model name
    $GEMINI_MODEL = "gemini-2.5-flash-lite" 
    $GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}"

    Write-Output "🤖 Attempting Gemini ($GEMINI_MODEL)..."

    # Construct Gemini JSON Body
    $geminiBody = @{
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

    # Call Gemini API
    $response = Invoke-RestMethod -Uri $GEMINI_URL -Method Post -Body $geminiBody -ContentType "application/json" -ErrorAction Stop
    
    # Extract Message
    if ($response.candidates -and $response.candidates.Count -gt 0) {
        $commitMsg = $response.candidates[0].content.parts[0].text
        $geminiSuccess = $true
    }
    else {
        throw "Gemini API returned empty candidates."
    }
}
catch {
    Write-Output "⚠️ Gemini Failed: $($_.Exception.Message)"
    Write-Output "🔄 Switching to Ollama Fallback..."
    $geminiSuccess = $false
}

# ==========================================
# 3. FALLBACK TO OLLAMA (If Gemini Failed)
# ==========================================
if (-not $geminiSuccess) {
    # --- Ollama Configuration ---
    $OLLAMA_URL = "http://localhost:11434/api/chat"
    $ollamaModelsToTry = @("qwen3-coder:480b-cloud", "qwen3.5:2b")
    $ollamaSuccess = $false

    foreach ($OLLAMA_MODEL in $ollamaModelsToTry) {
        try {
            Write-Output "🤖 Attempting Ollama ($OLLAMA_MODEL)..."

            # Construct Ollama JSON Body
            $ollamaMessages = @(
                @{ role = "system"; content = $systemPromptText },
                @{ role = "user"; content = "Here is the diff to analyze:`n$diff" }
            )

            $ollamaBody = @{
                model    = $OLLAMA_MODEL
                messages = $ollamaMessages
                stream   = $false
                options  = @{
                    temperature = 0.1
                    num_ctx     = 2048
                }
            } | ConvertTo-Json -Depth 10

            # Call Ollama API
            $response = Invoke-RestMethod -Uri $OLLAMA_URL -Method Post -Body $ollamaBody -ContentType "application/json" -ErrorAction Stop
            
            # Extract Message
            $commitMsg = $response.message.content
            $ollamaSuccess = $true
            break # Exit loop if successful
        }
        catch {
            Write-Output "⚠️ Ollama ($OLLAMA_MODEL) Failed: $($_.Exception.Message)"
            if ($OLLAMA_MODEL -ne $ollamaModelsToTry[-1]) {
                Write-Output "🔄 Switching to next Ollama model..."
            }
        }
    }

    if (-not $ollamaSuccess) {
        Write-Output "❌ All Ollama models failed."
        exit 1
    }
}

# ==========================================
# 4. FINAL CLEANUP & OUTPUT
# ==========================================

# Clean the message (works for both sources)
$commitMsg = $commitMsg.Trim()
$commitMsg = $commitMsg -replace '^```.*$', '' -replace '```$', ''  # Remove code blocks
$commitMsg = $commitMsg -replace '(?m)^diff --git.*[\s\S]*$', ''    # Remove accidental diff dumps
$commitMsg = $commitMsg.Trim()

Write-Output "--------------------------"
Write-Output $commitMsg
Write-Output "--------------------------"