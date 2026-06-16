# AI Commit with Lazygit 🤖✍️

An easy-to-use, cross-platform (Windows PowerShell & Linux/macOS) AI-powered git commit message generator integrated directly into **Lazygit**. It analyzes your staged changes and automatically writes clean, standardized **Conventional Commit** messages using either **local Ollama models** (like `granite4:7b-a1b-h` or `qwen2.5-coder`) or **Google Gemini API** (with automatic fallback options).

---

## Features

- **Cross-Platform:** Works on Windows (via PowerShell) and Linux/macOS (via Bash).
- **Ollama Support:** Use free, local, and private models run locally (defaults to `granite4:7b-a1b-h`).
- **Gemini API Support:** Supports fast and powerful models (like `gemini-2.5-flash`).
- **Smart Fallback:** Can be configured to try Gemini first, falling back to Ollama if offline or the API rate limit is hit.
- **Configured Locally:** All settings and API keys are stored locally at `~/.config/ai-commit-lazygit/config.json`. **No keys are committed to Git.**
- **Ticket ID Integration:** Automatically extracts JIRA/ticket numbers from the current branch name and prefixes the commit subject (e.g. `(#123) feat: add authentication`).
- **Review before Commit:** Opens your default editor inside Lazygit so you can edit, refine, or approve the AI-generated message before it is committed.

---

## Installation

### Prerequisites
1. **[Lazygit](https://github.com/jesseduffield/lazygit)** installed on your machine.
2. **Git** installed and configured.
3. For local AI: **[Ollama](https://ollama.com)** installed and running.
4. For cloud AI: A **[Gemini API Key](https://aistudio.google.com/)** (optional).

### 1. Clone the Repository
Clone this repository to your local machine:
```bash
git clone https://github.com/YOUR_USERNAME/ai-commit-lazygit.git
cd ai-commit-lazygit
```

### 2. Run the Installer

#### On Windows (PowerShell):
Run the installer script:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```
*The script will copy the files, initialize the local configuration, check if Ollama is running (offering to pull the `granite4:7b-a1b-h` model if it is missing), and automatically register key binding `a` in your Lazygit `config.yml`.*

#### On Linux / macOS (Bash):
Run the installer script:
```bash
./install.sh
```
*The script will set up execution permissions, configure the generator script, verify your Ollama model, and append the custom key binding `a` to your Lazygit config.*

---

## Usage

1. Open **Lazygit**.
2. Stage the changes you want to commit (using `space` on files or directories).
3. Press **`a`** (lower-case 'a' for AI Commit).
4. The loader will say `Generating AI commit message...` while your configured AI generates a commit message.
5. Your default Git editor will open with the generated message.
6. Review, make changes if necessary, and save/close to complete the commit!

---

## Configuration

Settings are saved in your user home directory at:
- **Windows:** `C:\Users\<YourUsername>\.config\ai-commit-lazygit\config.json`
- **Linux/macOS:** `~/.config/ai-commit-lazygit/config.json`

### `config.json` Options:

```json
{
  "provider": "ollama",                  // 'ollama', 'gemini', or 'both' (Gemini first with Ollama fallback)
  "gemini_api_key": "YOUR_API_KEY",      // Can also be set as GEMINI_API_KEY env variable
  "gemini_model": "gemini-2.5-flash",    // Gemini model to use
  "ollama_model": "granite4:7b-a1b-h",   // Local Ollama model to use
  "ollama_url": "http://localhost:11434/api/chat", // Ollama endpoint URL
  "ticket_integration": false,           // Prepend ticket IDs extracted from branch name
  "ticket_format": "(#$ticketId) "       // Ticket prefix format
}
```

---

## Clean Up & Uninstallation

If you wish to uninstall:
1. Open your Lazygit `config.yml` and remove the custom command block bound to the key `a`.
2. Delete the script directory: `~/.ai-commit-lazygit`
3. Delete the configuration folder: `~/.config/ai-commit-lazygit`
