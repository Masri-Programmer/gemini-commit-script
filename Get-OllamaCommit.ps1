# --- CONFIGURATION ---
$OLLAMA_MODEL = "qwen2.5-coder:3b" 
# CHANGED: Switched to the Chat endpoint
$OLLAMA_URL = "http://localhost:11434/api/chat"
$MAX_DIFF_LENGTH = 2000

# 1. Get Staged Changes
$diff = git diff --cached | Out-String

if ([string]::IsNullOrWhiteSpace($diff)) {
    Write-Output "No staged changes found."
    exit 0
}

# 1.5 Truncate Diff
if ($diff.Length -gt $MAX_DIFF_LENGTH) {
    $diff = $diff.Substring(0, $MAX_DIFF_LENGTH) + "`n... [Diff truncated]"
}

# 2. Construct the Messages (Chat Format)
$systemPrompt = @"
You are a git commit message generator.
Task: Generate a concise, standardized git commit message.

Rules:
1. Format: <type>: <subject>
2. Followed by a blank line.
3. Followed by bullet points (-) explaining changes.
4. DO NOT output markdown blocks or conversational filler.
"@

# CHANGED: We now use an array of messages instead of a single string prompt
$messages = @(
    @{
        role    = "system"
        content = $systemPrompt
    },
    @{
        role    = "user"
        content = "Here is the diff to analyze:`n$diff"
    }
)

$body = @{
    model    = $OLLAMA_MODEL
    messages = $messages
    stream   = $false
    options  = @{
        temperature = 0.1
        num_ctx     = 2048
    }
} | ConvertTo-Json -Depth 10

# 3. Call Ollama API
try {
    Write-Output "🤖 Generiere Commit-Message mit $OLLAMA_MODEL (Chat Mode)..."
    
    $response = Invoke-RestMethod -Uri $OLLAMA_URL -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
    
    # 4. Extract Message
    # CHANGED: The response is now inside 'message.content'
    $commitMsg = $response.message.content.Trim()
    
    # 5. Clean Message
    # Remove Markdown code blocks
    $commitMsg = $commitMsg -replace '^```.*$', '' -replace '```$', '' 
    
    # Safety Regex: Only remove diff if it starts on a new line
    $commitMsg = $commitMsg -replace '(?m)^diff --git.*[\s\S]*$', ''

    $commitMsg = $commitMsg.Trim()

    # 6. Output
    Write-Output "--------------------------"
    Write-Output $commitMsg
    Write-Output "--------------------------"
}
catch {
    Write-Output "Error: $($_.Exception.Message)"
}