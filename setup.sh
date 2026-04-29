#!/usr/bin/env bash
# ==============================================================================
# setup.sh - One-stop setup for the MCP Jira/Wiki server in VS Code
#
# Usage:  Run from the directory where you want to clone the repo:
#           sh /path/to/this/setup.sh
#         Or download and run directly:
#           sh setup.sh
#
#         Default behavior:
#           - Writes MCP config to global VS Code user path on Linux:
#             ~/.config/Code/User/mcp.json
#
#         Optional:
#           sh setup.sh --workspace-only
#           - Writes MCP config only to:
#             <repo>/.vscode/mcp.json
# ==============================================================================

set -e

CONFIG_SCOPE="global"

print_usage() {
    echo "Usage: sh setup.sh [--workspace-only]"
    echo ""
    echo "Default: writes MCP config to ~/.config/Code/User/mcp.json"
    echo "Option:  --workspace-only writes MCP config to <repo>/.vscode/mcp.json"
}

if [ "$#" -gt 1 ]; then
    print_usage
    exit 1
fi

if [ "$#" -eq 1 ]; then
    case "$1" in
        --workspace-only)
            CONFIG_SCOPE="workspace"
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo ""
            echo "ERROR: Unknown option: $1"
            echo ""
            print_usage
            exit 1
            ;;
    esac
fi

read_masked_input() {
    local prompt_text="$1"
    local value=""
    local char=""

    printf "%s" "$prompt_text"

    if [ ! -t 0 ]; then
        IFS= read -r READ_MASKED_VALUE
        return
    fi

    while IFS= read -r -s -n 1 char; do
        if [[ "$char" == "" ]]; then
            break
        fi

        if [[ "$char" == $'\177' || "$char" == $'\b' ]]; then
            if [[ -n "$value" ]]; then
                value="${value%?}"
                printf '\b \b'
            fi
            continue
        fi

        value+="$char"
        printf '*'
    done

    printf '\n'
    READ_MASKED_VALUE="$value"
}

REPO_URL="https://github.com/Jonathan-Dekraker/sooperset-mcp-atlassian.git"
REPO_NAME="sooperset-mcp-atlassian"

echo ""
echo "=============================================="
echo "  MCP Jira/Wiki Server - Setup"
echo "=============================================="

# ---------------------------------------------------------------------------
# 1. Confirm clone location with user
# ---------------------------------------------------------------------------
CLONE_PARENT="$(pwd)"

echo ""
echo "  The repository will be cloned into:"
echo "    $CLONE_PARENT/$REPO_NAME"
echo ""
printf "  Is this the correct location? [y/N]: "
read CONFIRM_CLONE

case "$CONFIRM_CLONE" in
    [yY]|[yY][eE][sS]) ;;
    *)
        echo ""
        echo "  Aborted. Navigate to the directory where you want the repo"
        echo "  cloned, then re-run this script."
        echo ""
        exit 0
        ;;
esac

# ---------------------------------------------------------------------------
# 2. Clone the repository
# ---------------------------------------------------------------------------
REPO_DIR="$CLONE_PARENT/$REPO_NAME"

if [ -d "$REPO_DIR" ]; then
    echo ""
    echo "  Directory already exists: $REPO_DIR"
    printf "  Pull latest changes instead of cloning? [y/N]: "
    read CONFIRM_PULL
    case "$CONFIRM_PULL" in
        [yY]|[yY][eE][sS])
            echo ""
            echo "  Pulling latest changes..."
            git -C "$REPO_DIR" pull
            ;;
        *)
            echo ""
            echo "  Skipping clone/pull — using existing directory."
            ;;
    esac
else
    echo ""
    echo "  Cloning $REPO_URL ..."
    git clone "$REPO_URL" "$REPO_DIR"
    echo "  Clone complete."
fi

echo ""
echo "Repository directory: $REPO_DIR"

# ---------------------------------------------------------------------------
# 3. Create/use a local virtual environment in the clone parent directory
# ---------------------------------------------------------------------------
PYTHON_BIN="/usr/intel/pkgs/python3/3.12.3/bin/python3"
VENV_DIR="$CLONE_PARENT/jira_mcp_venv_3.12.3"

if [ ! -x "$PYTHON_BIN" ]; then
    echo ""
    echo "ERROR: Required Python executable not found or not executable:"
    echo "  $PYTHON_BIN"
    exit 1
fi

if [ ! -d "$VENV_DIR" ]; then
    echo ""
    echo "Creating virtual environment:"
    echo "  $VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
else
    echo ""
    echo "Virtual environment already exists:"
    echo "  $VENV_DIR"
fi

UV_BIN="$VENV_DIR/bin/uv"

if [ ! -x "$UV_BIN" ]; then
    echo ""
    echo "Installing uv into virtual environment..."
    "$VENV_DIR/bin/python" -m pip install --upgrade pip uv
fi

if [ ! -x "$UV_BIN" ]; then
    echo ""
    echo "ERROR: 'uv' binary not found after installation attempt:"
    echo "  $UV_BIN"
    exit 1
fi

echo "Virtual environment: OK ($VENV_DIR)"

# ---------------------------------------------------------------------------
# 4. Check for CA certificate bundle (needed for SSL to internal Jira)
# ---------------------------------------------------------------------------
CA_BUNDLE="/var/lib/ca-certificates/ca-bundle.pem"
if [ ! -f "$CA_BUNDLE" ]; then
    echo ""
    echo "WARNING: CA certificate bundle not found at $CA_BUNDLE"
    echo "  SSL connections to Jira may fail."
    echo "  If you have a custom CA bundle, update REQUESTS_CA_BUNDLE in"
    echo "  .vscode/mcp.json after setup."
    echo ""
else
    echo "CA certificate bundle: OK ($CA_BUNDLE)"
fi

# ---------------------------------------------------------------------------
# 5. Prompt for Jira Personal Access Token
# ---------------------------------------------------------------------------
echo ""
echo "----------------------------------------------"
echo "  Jira Personal Access Token (PAT)"
echo "----------------------------------------------"
echo "  Your PAT is required to authenticate with Jira."
echo "  To create one, visit:"
echo "    https://jira.devtools.intel.com/secure/ViewProfile.jspa"
echo "    -> Personal Access Tokens -> Create token"
echo ""
read_masked_input "  Enter your Jira PAT (or press Enter to skip and fill in later): "
JIRA_PAT="$READ_MASKED_VALUE"

if [ -z "$JIRA_PAT" ]; then
    JIRA_PAT="<your personal access token>"
    PAT_SET=false
    echo "  Skipping — you will need to update mcp.json manually before use."
else
    PAT_SET=true
    echo "  PAT received."
fi

# ---------------------------------------------------------------------------
# 6. Generate mcp.json (global by default, workspace with --workspace-only)
# ---------------------------------------------------------------------------
if [ "$CONFIG_SCOPE" = "workspace" ]; then
    MCP_DIR="$REPO_DIR/.vscode"
    MCP_JSON="$MCP_DIR/mcp.json"
    MCP_SCOPE_LABEL="workspace-level"
else
    MCP_DIR="$HOME/.config/Code/User"
    MCP_JSON="$MCP_DIR/mcp.json"
    MCP_SCOPE_LABEL="global user-level"
fi

mkdir -p "$MCP_DIR"

if [ -f "$MCP_JSON" ]; then
    BACKUP="$MCP_JSON.bak.$(date +%Y%m%d%H%M%S)"
    echo ""
    echo "Existing mcp.json found — backing up to:"
    echo "  $BACKUP"
    cp "$MCP_JSON" "$BACKUP"
fi

cat > "$MCP_JSON" << ENDOFJSON
{
  "servers": {
    "wiki-jira-mcp": {
      "command": "${UV_BIN}",
      "args": ["run", "--directory", "${REPO_DIR}", "mcp-atlassian"],
      "env": {
        "JIRA_URL": "https://jira.devtools.intel.com",
        "JIRA_PERSONAL_TOKEN": "${JIRA_PAT}",
        "JIRA_SSL_VERIFY": "true",
        "REQUESTS_CA_BUNDLE": "${CA_BUNDLE}",
        "JIRA_AUTH_TYPE": "bearer",
        "TOOLSETS": "jira_issues,jira_projects",
        "READ_ONLY_MODE": "true",
        "NO_PROXY": ".devtools.intel.com,.ith.intel.com"
      }
    }
  }
}
ENDOFJSON

echo ""
echo "Created: $MCP_JSON"
echo "Scope: $MCP_SCOPE_LABEL"

# ---------------------------------------------------------------------------
# 7. Done — print next steps
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "  Next steps:"
echo ""

if [ "$PAT_SET" = "false" ]; then
    echo "  [1] SET YOUR JIRA PERSONAL ACCESS TOKEN (required)"
    echo ""
    echo "      Open: $MCP_JSON"
    echo '      Find: "JIRA_PERSONAL_TOKEN": "<your personal access token>"'
    echo "      Replace the placeholder with your actual PAT."
    echo ""
    echo "      To create a PAT, visit:"
    echo "        https://jira.devtools.intel.com/secure/ViewProfile.jspa"
    echo "        -> Personal Access Tokens -> Create token"
    echo ""
    echo "  [2] Open the repo folder in VS Code:"
    echo "        code $REPO_DIR"
    echo "      Then open $MCP_JSON and click the 'Start' button that"
    echo "      appears above the wiki-jira-mcp server entry to start the"
    echo "      MCP server."
    echo ""
    echo "  [3] Open GitHub Copilot Chat, then click the tools icon"
    echo "      (fork/spoon icon) at the bottom of the chat input bar."
    echo "      Verify that 'wiki-jira-mcp' is listed and checked."
else
    echo "  [1] Open the repo folder in VS Code:"
    echo "        code $REPO_DIR"
    echo ""
    echo "  [2] Open $MCP_JSON and click the 'Start' button that appears"
    echo "      above the wiki-jira-mcp server entry to start the MCP"
    echo "      server."
    echo ""
    echo "  [3] Open GitHub Copilot Chat, then click the tools icon"
    echo "      (fork/spoon icon) at the bottom of the chat input bar."
    echo "      Verify that 'wiki-jira-mcp' is listed and checked."
    echo ""
fi

echo ""
echo "=============================================="
