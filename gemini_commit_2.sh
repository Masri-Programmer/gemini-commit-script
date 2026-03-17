#!/bin/bash

LOG_FILE="/tmp/lazygit_gemini_debug.log"
echo "--- Starting execution at $(date) ---" >> "$LOG_FILE"

# 1. CHECK API KEY
if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY is not set." | tee -a "$LOG_FILE"
    echo "Please export it in your shell profile (e.g., ~/.bashrc):"
    echo "export GEMINI_API_KEY='your_api_key'"
    exit 1
fi

# 2. GET GIT INFO
BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$BRANCH_NAME" ]; then
    echo "Error: Not in a git repository or detached HEAD." | tee -a "$LOG_FILE"
    exit 1
fi

TICKET_ID=$(echo "$BRANCH_NAME" | grep -oE '[0-9]+' | head -n 1)
DIFF=$(git diff --cached --diff-algorithm=minimal)

if [ -z "$DIFF" ]; then
    echo "Error: No staged changes found." | tee -a "$LOG_FILE"
    exit 1
fi

# 3. CONSTRUCT PROMPT
PROMPT="You are an expert developer. Write a commit message for the following git diff.
The commit message MUST follow the Conventional Commits format: <type>: <description>.
The type must be one of: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.
Keep the description concise (under 72 characters if possible).
Do NOT include the ticket number in your output, I will add it myself.
Do NOT output anything else, just the commit message line.

Diff:
$DIFF"

# Export PROMPT so Python can read it safely from the environment
export PROMPT

# 4. PREPARE PAYLOAD (Using Python to avoid jq dependency)
# We use Python to create safe JSON, handling all quote escaping automatically.
PAYLOAD=$(python -c "import json, os; print(json.dumps({'contents': [{'parts': [{'text': os.environ['PROMPT']}]}]}))")

# GEMINI 3 CONFIGURATION
# Using 'gemini-3-flash-preview' for speed.
# If you prefer the heavier model, use: 'gemini-3-pro-preview'
MODEL="gemini-3-flash-preview"

echo "Calling Gemini API ($MODEL)..." >> "$LOG_FILE"

# 5. CALL API
RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent?key=$GEMINI_API_KEY")

# 6. PARSE RESPONSE (Using Python to avoid jq dependency)
# We pipe the response into Python to extract the specific field safely.
COMMIT_MSG=$(echo "$RESPONSE" | python -c "import sys, json; print(json.load(sys.stdin)['candidates'][0]['content']['parts'][0]['text'])")

# Remove trailing newlines/whitespace
COMMIT_MSG=$(echo "$COMMIT_MSG" | tr -d '\n' | sed 's/^[ \t]*//;s/[ \t]*$//')

# Check for errors
if [ -z "$COMMIT_MSG" ]; then
    echo "Error: Failed to generate commit message." | tee -a "$LOG_FILE"
    echo "Raw Response: $RESPONSE" >> "$LOG_FILE"
    exit 1
fi

# 7. OUTPUT FORMAT
if [ -n "$TICKET_ID" ]; then
    echo "(#$TICKET_ID) $COMMIT_MSG"
else
    echo "$COMMIT_MSG"
fi
