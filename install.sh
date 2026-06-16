#!/bin/bash
# install.sh
# Installer script for AI Commit for Lazygit (Linux/macOS version)

set -e

# Colors for output
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}Installing AI Commit for Lazygit on Linux/macOS${NC}"
echo -e "${CYAN}=============================================${NC}"

# --- Define Paths ---
INSTALL_DIR="$HOME/.ai-commit-lazygit"
CONFIG_DIR="$HOME/.config/ai-commit-lazygit"
CONFIG_FILE="$CONFIG_DIR/config.json"
GENERATOR_SCRIPT="$INSTALL_DIR/ai-commit-lazygit.sh"
MESSAGE_FILE="$CONFIG_DIR/commit_msg.txt"

# 1. Create installation directories
echo "Creating directories..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONFIG_DIR"

# 2. Copy the generator script and make it executable
echo "Copying files..."
cp ai-commit-lazygit.sh "$GENERATOR_SCRIPT"
chmod +x "$GENERATOR_SCRIPT"

# 3. Create default config if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Initializing default config..."
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
    echo -e "${GREEN}✓ Default configuration created at $CONFIG_FILE${NC}"
else
    echo -e "${GREEN}✓ Configuration already exists at $CONFIG_FILE${NC}"
fi

# 4. Check for Ollama model
echo -e "\nChecking Ollama status..."
if command -v curl >/dev/null 2>&1; then
    if response=$(curl -s --max-time 3 http://localhost:11434/api/tags 2>/dev/null); then
        if echo "$response" | grep -q "granite4:7b-a1b-h"; then
            echo -e "${GREEN}✓ Ollama model 'granite4:7b-a1b-h' is installed.${NC}"
        else
            echo -e "${YELLOW}⚠ Ollama model 'granite4:7b-a1b-h' was not found in local models.${NC}"
            read -p "Would you like to pull the model 'granite4:7b-a1b-h' now? (y/n) [default: y] " pullChoice
            pullChoice=${pullChoice:-y}
            if [ "$pullChoice" = "y" ] || [ "$pullChoice" = "Y" ]; then
                echo "Pulling model 'granite4:7b-a1b-h'... This may take several minutes."
                ollama pull granite4:7b-a1b-h
                echo -e "${GREEN}✓ Model pulled successfully.${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ Ollama is not running or not installed. Please start Ollama, then run: ollama pull granite4:7b-a1b-h${NC}"
    fi
else
    echo -e "${YELLOW}⚠ curl is not installed. Skipping Ollama model pre-check.${NC}"
fi

# 5. Configure Lazygit
echo -e "\nConfiguring Lazygit integration..."
LAZYGIT_CONFIG_DIR=""
if command -v lazygit >/dev/null 2>&1; then
    LAZYGIT_CONFIG_DIR=$(lazygit --print-config-dir 2>/dev/null || echo "")
fi

if [ -z "$LAZYGIT_CONFIG_DIR" ]; then
    # Fallbacks
    if [ -d "$HOME/.config/lazygit" ]; then
        LAZYGIT_CONFIG_DIR="$HOME/.config/lazygit"
    elif [ -d "$HOME/Library/Application Support/lazygit" ]; then
        LAZYGIT_CONFIG_DIR="$HOME/Library/Application Support/lazygit"
    fi
fi

if [ -z "$LAZYGIT_CONFIG_DIR" ] || [ ! -d "$LAZYGIT_CONFIG_DIR" ]; then
    echo -e "${YELLOW}Warning: Could not locate Lazygit configuration directory. Please configure custom commands manually.${NC}"
    echo "For manual configuration, add the following to your Lazygit config.yml:"
    cat <<EOF
customCommands:
  - key: "a"
    description: "Generate AI Commit"
    context: "files"
    loadingText: "Generating AI commit message..."
    command: 'sh -c "$GENERATOR_SCRIPT && git commit -e -F $MESSAGE_FILE"'
    output: terminal
EOF
else
    LAZYGIT_CONFIG_FILE="$LAZYGIT_CONFIG_DIR/config.yml"
    echo "Lazygit config file located: $LAZYGIT_CONFIG_FILE"

    # Run Python script to modify config.yml safely
    PY_CMD=""
    if command -v python3 >/dev/null 2>&1; then
        PY_CMD="python3"
    elif command -v python >/dev/null 2>&1; then
        PY_CMD="python"
    fi

    if [ -n "$PY_CMD" ]; then
        $PY_CMD -c '
import os, sys

config_path = sys.argv[1]
generator_path = sys.argv[2]
msg_path = sys.argv[3]

if os.path.exists(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
else:
    lines = []

if os.path.exists(config_path):
    import shutil
    shutil.copy2(config_path, config_path + ".bak")
    print(f"[OK] Backed up existing Lazygit config to {config_path}.bak")

new_lines = []
in_match_block = False
i = 0
while i < len(lines):
    line = lines[i]
    if line.strip().startswith("- key:"):
        j = i
        is_match = False
        while j < len(lines):
            if j > i and (lines[j].strip().startswith("- key:") or (lines[j].strip() and not lines[j].startswith(" ") and not lines[j].startswith("\t"))):
                break
            if any(p in lines[j] for p in ["ai-commit-lazygit.sh", "ai-commit-lazygit.ps1", "Get-GeminiCommit.sh", "Get-GeminiCommit.ps1", "Get-OllamaCommit.ps1"]):
                is_match = True
                break
            j += 1
        if is_match:
            in_match_block = True
            i = j
            continue
    elif line.strip() and not line.startswith(" ") and not line.startswith("\t") and not line.startswith("customCommands:"):
        in_match_block = False
    
    if not in_match_block:
        new_lines.append(line)
    i += 1

block = [
    "  - key: \"a\"\n",
    "    description: \"Generate AI Commit\"\n",
    "    context: \"files\"\n",
    "    loadingText: \"Generating AI commit message...\"\n",
    f"    command: \"sh -c '\''{generator_path} && git commit -e -F {msg_path}'\''\"\n",
    "    output: terminal\n"
]

hdr_idx = -1
for idx, line in enumerate(new_lines):
    if line.strip().startswith("customCommands:"):
        hdr_idx = idx
        break

if hdr_idx != -1:
    new_lines = new_lines[:hdr_idx+1] + block + new_lines[hdr_idx+1:]
else:
    if len(new_lines) > 0 and not new_lines[-1].endswith("\n"):
        new_lines[-1] += "\n"
    new_lines.append("customCommands:\n")
    new_lines.extend(block)

with open(config_path, "w", encoding="utf-8") as f:
    f.writelines(new_lines)
' "$LAZYGIT_CONFIG_FILE" "$GENERATOR_SCRIPT" "$MESSAGE_FILE"
        echo -e "${GREEN}✓ Updated Lazygit config.yml successfully with key 'a'.${NC}"
    else
        echo -e "${YELLOW}Warning: Python is not installed. Appending lazygit command block to config.yml using bash.${NC}"
        # Fallback simple append using cat
        if [ -f "$LAZYGIT_CONFIG_FILE" ]; then
            cp "$LAZYGIT_CONFIG_FILE" "$LAZYGIT_CONFIG_FILE.bak"
            echo -e "${GREEN}✓ Backed up existing Lazygit config to $LAZYGIT_CONFIG_FILE.bak${NC}"
        fi
        
        # Check if customCommands header exists
        if grep -q "^customCommands:" "$LAZYGIT_CONFIG_FILE" 2>/dev/null; then
            echo -e "${YELLOW}Warning: customCommands block already exists in config.yml. Please insert the following block manually:${NC}"
            cat <<EOF
  - key: "a"
    description: "Generate AI Commit"
    context: "files"
    loadingText: "Generating AI commit message..."
    command: "sh -c '$GENERATOR_SCRIPT && git commit -e -F $MESSAGE_FILE'"
    output: terminal
EOF
        else
            echo "" >> "$LAZYGIT_CONFIG_FILE"
            echo "customCommands:" >> "$LAZYGIT_CONFIG_FILE"
            echo "  - key: \"a\"" >> "$LAZYGIT_CONFIG_FILE"
            echo "    description: \"Generate AI Commit\"" >> "$LAZYGIT_CONFIG_FILE"
            echo "    context: \"files\"" >> "$LAZYGIT_CONFIG_FILE"
            echo "    loadingText: \"Generating AI commit message...\"" >> "$LAZYGIT_CONFIG_FILE"
            echo "    command: \"sh -c '\$GENERATOR_SCRIPT && git commit -e -F \$MESSAGE_FILE'\"" >> "$LAZYGIT_CONFIG_FILE"
            echo "    output: terminal" >> "$LAZYGIT_CONFIG_FILE"
            echo -e "${GREEN}✓ Appended customCommand block to config.yml.${NC}"
        fi
    fi
fi

echo -e "${CYAN}=============================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo "To configure/add Gemini API Key or change settings, edit:"
echo -e "  ${YELLOW}$CONFIG_FILE${NC}"
echo -e "To use inside Lazygit, stage your changes, then press ${YELLOW}'a'${NC}!"
echo -e "${CYAN}=============================================${NC}"
