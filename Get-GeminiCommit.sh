#!/bin/bash

# ==========================================
# 1. PREPARATION (Shared Logic)
# ==========================================

# --- Common Config ---
MAX_DIFF_LENGTH=3000

# Get Staged Changes
diff=$(git diff --cached)

if [ -z "$diff" ]; then
    echo "No staged changes found."
    exit 0
fi

# Truncate Diff (Shared)
if [ ${#diff} -gt $MAX_DIFF_LENGTH ]; then
    diff="${diff:0:$MAX_DIFF_LENGTH}\n... [Diff truncated]"
fi

# Define the System Prompt (Shared)
systemPromptText="You are an expert developer and git commit message generator.
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
   - MUST use the imperative, present tense (e.g., \"Ensure...\", \"Add...\", \"Fix...\" - NEVER \"Ensured\" or \"Adds\").
   - Max 50 characters.
   - Do not capitalize the first letter.
   - No trailing period.

5. Body: 
   - Briefly explain WHAT changed and WHY, not just HOW.
   - Keep bullet points concise.

6. Output Constraints:
   - Output ONLY the raw commit message text.
   - ABSOLUTELY NO markdown code fences (\`\`\`).
   - NO conversational filler, greetings, or explanations."

# ==========================================
# 2. ATTEMPT OLLAMA (First Try)
# ==========================================
ollamaSuccess=false
commitMsg=""

OLLAMA_URL="http://localhost:11434/api/chat"
ollamaModelsToTry=("qwen3-coder:480b-cloud") 

for OLLAMA_MODEL in "${ollamaModelsToTry[@]}"; do
    echo "🤖 Attempting Ollama ($OLLAMA_MODEL)..." >&2

    ollamaBody=$(jq -n \
        --arg system "$systemPromptText" \
        --arg user "Here is the diff to analyze:\n$diff" \
        --arg model "$OLLAMA_MODEL" \
        '{
            model: $model,
            messages: [
                { role: "system", content: $system },
                { role: "user", content: $user }
            ],
            stream: false,
            options: { temperature: 0.1, num_ctx: 2048 }
        }')

    response=$(curl -s -X POST "$OLLAMA_URL" \
        -H "Content-Type: application/json" \
        -d "$ollamaBody")

    commitMsg=$(echo "$response" | jq -r '.message.content // empty')

    if [ -n "$commitMsg" ] && [ "$commitMsg" != "null" ]; then
        ollamaSuccess=true
        break
    fi
    echo "⚠️ Ollama ($OLLAMA_MODEL) Failed." >&2
done

# ==========================================
# 3. FALLBACK TO GEMINI (If Ollama Failed)
# ==========================================
if [ "$ollamaSuccess" = false ]; then
    geminiSuccess=false

    # --- Gemini Configuration ---
    if [ -z "$GEMINI_API_KEY" ]; then
        # Fallback to hardcoded key if env var is missing
        GEMINI_API_KEY="AIzaSyA7Et4mVYMSXq9O-3NIiUpeZKBX4IyWw5k" 
    fi

    # Model choice (using gemini-2.5-flash as requested)
    GEMINI_MODEL="gemini-2.5-flash" 
    GEMINI_URL="https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}"

    echo "🤖 Attempting Gemini ($GEMINI_MODEL)..." >&2

    # Construct Gemini JSON Body using jq
    geminiBody=$(jq -n \
        --arg system "$systemPromptText" \
        --arg user "Here is the diff to analyze:\n$diff" \
        '{
            systemInstruction: { parts: [{ text: $system }] },
            contents: [{ role: "user", parts: [{ text: $user }] }],
            generationConfig: { temperature: 0.1, maxOutputTokens: 1000 }
        }')

    # Call Gemini API
    response=$(curl -s -X POST "$GEMINI_URL" \
        -H "Content-Type: application/json" \
        -d "$geminiBody")

    # Extract Message
    commitMsg=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty')

    if [ -n "$commitMsg" ] && [ "$commitMsg" != "null" ]; then
        geminiSuccess=true
    else
        echo "❌ Gemini Failed or returned empty response." >&2
        exit 1
    fi
fi

# ==========================================
# 4. FINAL CLEANUP & OUTPUT
# ==========================================

# Clean the message
commitMsg=$(echo "$commitMsg" | sed -E 's/^```.*$//g' | sed -E 's/```$//g')
commitMsg=$(echo "$commitMsg" | sed -n '/^diff --git/!p')
commitMsg=$(echo "$commitMsg" | xargs)

# Output only the message to stdout
echo "$commitMsg"
