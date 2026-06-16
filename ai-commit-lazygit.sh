#!/bin/bash
# ai-commit-lazygit.sh
# AI-powered Git commit message generator for Lazygit (Linux/macOS version)

set -e

# Disable MSYS2 path conversion to prevent corruption of JSON payloads containing file paths
export MSYS_NO_PATHCONV=1

# --- Default Paths ---
CONFIG_DIR="$HOME/.config/ai-commit-lazygit"
CONFIG_FILE="$CONFIG_DIR/config.json"
DEFAULT_OUTPUT_FILE="$CONFIG_DIR/commit_msg.txt"

OUTPUT_FILE="$DEFAULT_OUTPUT_FILE"
PROVIDER_OVERRIDE=""
MODEL_OVERRIDE=""

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -o|--output) OUTPUT_FILE="$2"; shift ;;
        -p|--provider) PROVIDER_OVERRIDE="$2"; shift ;;
        -m|--model) MODEL_OVERRIDE="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Write default config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    cat <<EOF > "$CONFIG_FILE"
{
  "provider": "ollama",
  "gemini_api_key": "",
  "gemini_model": "gemini-2.5-flash",
  "ollama_model": "granite4:7b-a1b-h",
  "ollama_url": "http://localhost:11434/api/chat",
  "ticket_integration": false,
  "ticket_format": "(#\$ticketId) "
}
EOF
fi

# Helper to translate UNIX paths to Windows format when using native Python on Windows (MSYS/Git Bash)
get_win_path() {
    local path=$1
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$path"
    else
        echo "$path"
    fi
}

# Helper to read config value
get_config_value() {
    local key=$1
    local win_config_file=$(get_win_path "$CONFIG_FILE")
    if command -v jq >/dev/null 2>&1; then
        jq -r ".$key // empty" "$CONFIG_FILE"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import json; print(json.load(open('$win_config_file', encoding='utf-8-sig')).get('$key', ''))" 2>/dev/null
    elif command -v python >/dev/null 2>&1; then
        python -c "import json; print(json.load(open('$win_config_file', encoding='utf-8-sig')).get('$key', ''))" 2>/dev/null
    else
        grep -oP '"'"$key"'"\s*:\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null || echo ""
    fi
}

# Read config values
provider=$(get_config_value "provider")
gemini_model=$(get_config_value "gemini_model")
ollama_model=$(get_config_value "ollama_model")
ollama_url=$(get_config_value "ollama_url")
gemini_api_key=$(get_config_value "gemini_api_key")
ticket_integration=$(get_config_value "ticket_integration")
ticket_format=$(get_config_value "ticket_format")

# Apply overrides
[ -n "$PROVIDER_OVERRIDE" ] && provider="$PROVIDER_OVERRIDE"
[ -n "$MODEL_OVERRIDE" ] && ollama_model="$MODEL_OVERRIDE"

# Defaults if config was corrupt or empty
[ -z "$provider" ] && provider="ollama"
[ -z "$gemini_model" ] && gemini_model="gemini-2.5-flash"
[ -z "$ollama_model" ] && ollama_model="granite4:7b-a1b-h"
[ -z "$ollama_url" ] && ollama_url="http://localhost:11434/api/chat"
[ -z "$ticket_integration" ] && ticket_integration="false"
[ -z "$ticket_format" ] && ticket_format='(#$ticketId) '

# Read Gemini key from env if not set in config
if [ -z "$gemini_api_key" ]; then
    gemini_api_key="$GEMINI_API_KEY"
fi

# --- Step 1: Check Git Repo & Changes ---
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not in a git repository." >&2
    exit 1
fi

BRANCH_NAME=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

diff=$(git diff --cached)
if [ -z "$diff" ]; then
    echo "Warning: No staged changes found. Please stage some changes first." >&2
    exit 1
fi

# Truncate Diff (approx 3000 chars of diff)
MAX_DIFF_LENGTH=3000
if [ ${#diff} -gt $MAX_DIFF_LENGTH ]; then
    diff="${diff:0:$MAX_DIFF_LENGTH}"$'\n... [Diff truncated for size]'
fi

# --- Step 2: System Prompt ---
systemPromptText="You are an expert developer and git commit message generator.
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

# --- Helper functions to build JSON payload ---
build_json_payload() {
    local mode=$1
    if command -v jq >/dev/null 2>&1; then
        if [ "$mode" = "ollama" ]; then
            jq -n \
               --arg sys "$systemPromptText" \
               --arg usr "Here is the diff to analyze:\n$diff" \
               --arg mdl "$ollama_model" \
               '{model: $mdl, messages: [{role: "system", content: $sys}, {role: "user", content: $usr}], stream: false, options: {temperature: 0.1, num_ctx: 2048}}'
        else
            jq -n \
               --arg sys "$systemPromptText" \
               --arg usr "Here is the diff to analyze:\n$diff" \
               '{systemInstruction: {parts: [{text: $sys}]}, contents: [{role: "user", parts: [{text: $usr}]}], generationConfig: {temperature: 0.1, maxOutputTokens: 1000}}'
        fi
    elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        local py_cmd="python3"
        command -v python3 >/dev/null 2>&1 || py_cmd="python"
        export TEMP_SYS="$systemPromptText"
        export TEMP_USR="Here is the diff to analyze:\n$diff"
        export TEMP_MDL="$ollama_model"
        if [ "$mode" = "ollama" ]; then
            $py_cmd -c 'import json, os; print(json.dumps({"model": os.environ["TEMP_MDL"], "messages": [{"role": "system", "content": os.environ["TEMP_SYS"]}, {"role": "user", "content": os.environ["TEMP_USR"]}], "stream": False, "options": {"temperature": 0.1, "num_ctx": 2048}}))'
        else
            $py_cmd -c 'import json, os; print(json.dumps({"systemInstruction": {"parts": [{"text": os.environ["TEMP_SYS"]}]}, "contents": [{"role": "user", "parts": [{"text": os.environ["TEMP_USR"]}]}], "generationConfig": {"temperature": 0.1, "maxOutputTokens": 1000}}))'
        fi
        unset TEMP_SYS TEMP_USR TEMP_MDL
    else
        # fallback simple string escaping
        local escaped_sys=$(echo "$systemPromptText" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
        local escaped_usr=$(echo "Here is the diff to analyze:\n$diff" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
        if [ "$mode" = "ollama" ]; then
            echo "{\"model\": \"$ollama_model\", \"messages\": [{\"role\": \"system\", \"content\": \"$escaped_sys\"}, {\"role\": \"user\", \"content\": \"$escaped_usr\"}], \"stream\": false, \"options\": {\"temperature\": 0.1, \"num_ctx\": 2048}}"
        else
            echo "{\"systemInstruction\": {\"parts\": [{\"text\": \"$escaped_sys\"}]}, \"contents\": [{\"role\": \"user\", \"parts\": [{\"text\": \"$escaped_usr\"}]}], \"generationConfig\": {\"temperature\": 0.1, \"maxOutputTokens\": 1000}}"
        fi
    fi
}

# --- Helper function to parse JSON response ---
parse_json_response() {
    local mode=$1
    local json_str=$2
    if command -v jq >/dev/null 2>&1; then
        if [ "$mode" = "ollama" ]; then
            echo "$json_str" | jq -r '.message.content // empty'
        else
            echo "$json_str" | jq -r '.candidates[0].content.parts[0].text // empty'
        fi
    elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        local py_cmd="python3"
        command -v python3 >/dev/null 2>&1 || py_cmd="python"
        if [ "$mode" = "ollama" ]; then
            echo "$json_str" | $py_cmd -c 'import json, sys; print(json.load(sys.stdin)["message"]["content"])' 2>/dev/null
        else
            echo "$json_str" | $py_cmd -c 'import json, sys; print(json.load(sys.stdin)["candidates"][0]["content"]["parts"][0]["text"])' 2>/dev/null
        fi
    else
        # fallback grep
        if [ "$mode" = "ollama" ]; then
            echo "$json_str" | grep -oP '"content"\s*:\s*"\K[^"]+' | head -n 1
        else
            echo "$json_str" | grep -oP '"text"\s*:\s*"\K[^"]+' | head -n 1
        fi
    fi
}

get_ollama_commit() {
    echo "🤖 Calling Ollama ($ollama_model)..." >&2
    local payload=$(build_json_payload "ollama")
    local response=$(curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$ollama_url")
    parse_json_response "ollama" "$response"
}

get_gemini_commit() {
    if [ -z "$gemini_api_key" ]; then
        echo "Warning: Gemini API key is not configured." >&2
        return 1
    fi
    echo "🤖 Calling Gemini ($gemini_model)..." >&2
    local gemini_url="https://generativelanguage.googleapis.com/v1beta/models/${gemini_model}:generateContent?key=${gemini_api_key}"
    local payload=$(build_json_payload "gemini")
    local response=$(curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$gemini_url")
    parse_json_response "gemini" "$response"
}

commitMsg=""
success=false

if [ "$provider" = "ollama" ]; then
    commitMsg=$(get_ollama_commit)
    [ -n "$commitMsg" ] && success=true
elif [ "$provider" = "gemini" ]; then
    commitMsg=$(get_gemini_commit)
    [ -n "$commitMsg" ] && success=true
elif [ "$provider" = "both" ]; then
    commitMsg=$(get_gemini_commit || echo "")
    if [ -n "$commitMsg" ]; then
        success=true
    else
        echo "🔄 Falling back to Ollama..." >&2
        commitMsg=$(get_ollama_commit)
        [ -n "$commitMsg" ] && success=true
    fi
else
    echo "Error: Unknown provider '$provider' in configuration." >&2
    exit 1
fi

if [ "$success" = false ] || [ -z "$commitMsg" ]; then
    echo "Error: Failed to generate commit message from all attempted providers." >&2
    exit 1
fi

# --- Step 4: Cleanup & Formatting ---
# Clean the message
commitMsg=$(echo "$commitMsg" | sed -E 's/^```.*$//g' | sed -E 's/```$//g')
commitMsg=$(echo "$commitMsg" | sed -E '/^(diff --git|index [0-9a-f]|--- a\/|\+\+\+ b\/)/,$d')
# trim whitespace
commitMsg=$(echo "$commitMsg" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# Extract ticket ID if enabled
if [ "$ticket_integration" = "true" ] && [ -n "$BRANCH_NAME" ]; then
    # find first sequence of digits
    ticketId=$(echo "$BRANCH_NAME" | grep -oE '[0-9]+' | head -n 1 || echo "")
    if [ -n "$ticketId" ]; then
        # Replace $ticketId in format (or similar syntax)
        prefix=$(echo "$ticket_format" | sed "s/\$ticketId/$ticketId/g")
        commitMsg="$prefix$commitMsg"
    fi
fi

# --- Step 5: Save & Output ---
mkdir -p "$(dirname "$OUTPUT_FILE")"
echo "$commitMsg" > "$OUTPUT_FILE"

echo -e "\n\033[0;32m--------------------------"
echo "$commitMsg"
echo -e "--------------------------\033[0m\n"
echo "Generated commit message saved to: $OUTPUT_FILE"
