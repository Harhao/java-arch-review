#!/usr/bin/env bash
# ==============================================================================
# java-arch-review - One-Click Setup Script
#
# Configures the java-arch-review skill for different AI coding agents
# in a target Java project.
#
# Usage:
#   bash setup.sh --project /path/to/java-project [--agent cursor|windsurf|copilot|gemini|cline|all]
#   bash setup.sh --project /path/to/java-project --uninstall [--agent ...]
#   bash setup.sh --list
#   bash setup.sh --help
# ==============================================================================

set -euo pipefail

# --------------- Constants ---------------
MARKER_START="# --- java-arch-review START ---"
MARKER_END="# --- java-arch-review END ---"
SUPPORTED_AGENTS=("claude" "opencode" "cursor" "windsurf" "copilot" "gemini" "cline")

# --------------- Color helpers ---------------
# Detect color support: respect NO_COLOR, skip for non-TTY
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    RESET=''
fi

info()    { printf "${CYAN}[INFO]${RESET}  %s\n" "$*"; }
success() { printf "${GREEN}[OK]${RESET}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[SKIP]${RESET}  %s\n" "$*"; }
error()   { printf "${RED}[ERR]${RESET}   %s\n" "$*" >&2; }

# --------------- Resolve SKILL_DIR ---------------
# The skill root is the parent directory of adapters/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --------------- Usage ---------------
usage() {
    cat <<EOF
${BOLD}java-arch-review setup${RESET}

Configure the architecture-review skill for AI coding agents in a Java project.

${BOLD}USAGE${RESET}
  bash setup.sh --project <path> [OPTIONS]

${BOLD}OPTIONS${RESET}
  --project PATH    Target Java project directory (required for install/uninstall)
  --agent AGENT     Agent to configure: claude, opencode, cursor, windsurf, copilot, gemini, cline
                    Default: all agents. Use --detect to auto-detect instead.
  --detect          Auto-detect agents from project layout instead of installing all
  --uninstall       Remove previously installed configurations
  --list            List supported agents and exit
  --help            Show this help message and exit

${BOLD}EXAMPLES${RESET}
  # Install all agents (default)
  bash setup.sh --project /path/to/java-project

  # Install for a specific agent only
  bash setup.sh --project /path/to/java-project --agent cursor

  # Auto-detect which agents the project uses
  bash setup.sh --project /path/to/java-project --detect

  # Remove installed configs
  bash setup.sh --project /path/to/java-project --uninstall

  # Remove configs for a specific agent
  bash setup.sh --project /path/to/java-project --uninstall --agent cursor
EOF
}

# --------------- Argument parsing ---------------
PROJECT_PATH=""
AGENT=""
UNINSTALL=false
LIST=false
DETECT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            PROJECT_PATH="$2"
            shift 2
            ;;
        --agent)
            AGENT="$2"
            shift 2
            ;;
        --detect)
            DETECT=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --list)
            LIST=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# --------------- --list ---------------
if $LIST; then
    echo ""
    printf "${BOLD}Supported agents:${RESET}\n"
    for a in "${SUPPORTED_AGENTS[@]}"; do
        printf "  - %s\n" "$a"
    done
    echo ""
    echo "Use --agent all to install for every agent."
    exit 0
fi

# --------------- Validate --project ---------------
if [[ -z "$PROJECT_PATH" ]]; then
    error "--project is required."
    echo ""
    usage
    exit 1
fi

# Resolve to absolute path
PROJECT_PATH="$(cd "$PROJECT_PATH" 2>/dev/null && pwd)" || {
    error "Project directory does not exist: $PROJECT_PATH"
    exit 1
}

if [[ ! -d "$PROJECT_PATH" ]]; then
    error "Project path is not a directory: $PROJECT_PATH"
    exit 1
fi

# Validate agent name
if [[ -n "$AGENT" ]] && [[ "$AGENT" != "all" ]]; then
    valid=false
    for a in "${SUPPORTED_AGENTS[@]}"; do
        if [[ "$a" == "$AGENT" ]]; then
            valid=true
            break
        fi
    done
    if ! $valid; then
        error "Unknown agent: $AGENT"
        error "Supported: ${SUPPORTED_AGENTS[*]}, all"
        exit 1
    fi
fi

# ==============================================================================
# Helper: replace placeholders in adapter content
# ==============================================================================
replace_placeholders() {
    local content="$1"
    # Replace {SKILL_DIR} with the actual skill directory (absolute)
    content="${content//\{SKILL_DIR\}/$SKILL_DIR}"
    # Replace {PROJECT_PATH} with . (relative, since config lives inside project)
    content="${content//\{PROJECT_PATH\}/.}"
    # Replace {MODE} with full (default)
    content="${content//\{MODE\}/full}"
    printf '%s' "$content"
}

# ==============================================================================
# Helper: append a marked section to a file
# Appends the content wrapped in START/END markers. If the markers already exist,
# replaces the existing section.
# ==============================================================================
append_marked_section() {
    local target_file="$1"
    local content="$2"

    local block
    block="$(printf '\n%s\n%s\n%s\n' "$MARKER_START" "$content" "$MARKER_END")"

    if [[ -f "$target_file" ]]; then
        if grep -qF "$MARKER_START" "$target_file" 2>/dev/null; then
            # Replace existing section
            remove_marked_section "$target_file"
        fi
        # Append
        printf '%s\n' "$block" >> "$target_file"
    else
        # Create parent directory if needed
        mkdir -p "$(dirname "$target_file")"
        printf '%s\n' "$block" > "$target_file"
    fi
}

# ==============================================================================
# Helper: remove the marked section from a file
# ==============================================================================
remove_marked_section() {
    local target_file="$1"

    if [[ ! -f "$target_file" ]]; then
        return 0
    fi

    if ! grep -qF "$MARKER_START" "$target_file" 2>/dev/null; then
        return 0
    fi

    # Use a temp file to avoid issues across platforms
    local tmpfile
    tmpfile="$(mktemp "${target_file}.tmp.XXXXXX")"

    local inside_block=false
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"$MARKER_START"* ]]; then
            inside_block=true
            continue
        fi
        if [[ "$line" == *"$MARKER_END"* ]]; then
            inside_block=false
            continue
        fi
        if ! $inside_block; then
            printf '%s\n' "$line" >> "$tmpfile"
        fi
    done < "$target_file"

    # Remove trailing empty lines left behind
    # (portable: just move the file back)
    mv "$tmpfile" "$target_file"

    # If the file is now empty (or only whitespace), remove it
    if [[ ! -s "$target_file" ]] || ! grep -q '[^[:space:]]' "$target_file" 2>/dev/null; then
        rm -f "$target_file"
    fi
}

# ==============================================================================
# Install / Uninstall per agent
# ==============================================================================

install_claude() {
    local plugin_dest_dir="$PROJECT_PATH/.claude-plugin"
    local plugin_file="$plugin_dest_dir/plugin.json"
    local cmd_dest_dir="$PROJECT_PATH/commands"
    local cmd_file="$cmd_dest_dir/java-arch-review.md"
    local src_plugin="$SKILL_DIR/adapters/claude/plugin.json"
    local src_cmd="$SKILL_DIR/adapters/claude/java-arch-review.md"

    if [[ ! -f "$src_plugin" ]]; then
        error "Claude adapter plugin.json not found: $src_plugin"
        return 1
    fi

    # Install plugin.json
    mkdir -p "$plugin_dest_dir"
    cp "$src_plugin" "$plugin_file"

    # Install slash command
    if [[ -f "$src_cmd" ]]; then
        mkdir -p "$cmd_dest_dir"
        local content
        content="$(cat "$src_cmd")"
        content="$(replace_placeholders "$content")"
        printf '%s\n' "$content" > "$cmd_file"
    fi

    success "Claude Code: installed $plugin_file + $cmd_file"
}

uninstall_claude() {
    local removed=false
    if [[ -f "$PROJECT_PATH/.claude-plugin/plugin.json" ]]; then
        rm -f "$PROJECT_PATH/.claude-plugin/plugin.json"
        rmdir "$PROJECT_PATH/.claude-plugin" 2>/dev/null || true
        removed=true
    fi
    if [[ -f "$PROJECT_PATH/commands/java-arch-review.md" ]]; then
        rm -f "$PROJECT_PATH/commands/java-arch-review.md"
        rmdir "$PROJECT_PATH/commands" 2>/dev/null || true
        removed=true
    fi
    if $removed; then
        success "Claude Code: removed plugin and command files"
    else
        warn "Claude Code: nothing to remove"
    fi
}

install_opencode() {
    local dest_dir="$PROJECT_PATH/.opencode/plugins"
    local dest_file="$dest_dir/java-arch-review.js"
    local pkg_file="$PROJECT_PATH/.opencode/package.json"
    local src_file="$SKILL_DIR/adapters/opencode/java-arch-review.js"

    if [[ ! -f "$src_file" ]]; then
        error "OpenCode adapter file not found: $src_file"
        return 1
    fi

    mkdir -p "$dest_dir"
    cp "$src_file" "$dest_file"

    # Ensure package.json exists for the plugin system
    if [[ ! -f "$pkg_file" ]]; then
        echo '{}' > "$pkg_file"
    fi

    success "OpenCode: installed $dest_file"
}

uninstall_opencode() {
    local dest_file="$PROJECT_PATH/.opencode/plugins/java-arch-review.js"
    if [[ -f "$dest_file" ]]; then
        rm -f "$dest_file"
        success "OpenCode: removed $dest_file"
    else
        warn "OpenCode: nothing to remove"
    fi
}

install_cursor() {
    local dest_dir="$PROJECT_PATH/.cursor/rules"
    local dest_file="$dest_dir/java-arch-review.mdc"
    local src_file="$SKILL_DIR/adapters/cursor/java-arch-review.mdc"

    if [[ ! -f "$src_file" ]]; then
        error "Cursor adapter file not found: $src_file"
        return 1
    fi

    mkdir -p "$dest_dir"

    local content
    content="$(cat "$src_file")"
    content="$(replace_placeholders "$content")"

    printf '%s\n' "$content" > "$dest_file"
    success "Cursor: installed $dest_file"
}

uninstall_cursor() {
    local dest_file="$PROJECT_PATH/.cursor/rules/java-arch-review.mdc"
    if [[ -f "$dest_file" ]]; then
        rm -f "$dest_file"
        success "Cursor: removed $dest_file"
    else
        warn "Cursor: nothing to remove"
    fi
}

install_windsurf() {
    local dest_file="$PROJECT_PATH/.windsurfrules"
    local src_file="$SKILL_DIR/adapters/windsurf/windsurfrules.md"

    if [[ ! -f "$src_file" ]]; then
        error "Windsurf adapter file not found: $src_file"
        return 1
    fi

    local content
    content="$(cat "$src_file")"
    content="$(replace_placeholders "$content")"

    append_marked_section "$dest_file" "$content"
    success "Windsurf: configured $dest_file"
}

uninstall_windsurf() {
    local dest_file="$PROJECT_PATH/.windsurfrules"
    if [[ -f "$dest_file" ]] && grep -qF "$MARKER_START" "$dest_file" 2>/dev/null; then
        remove_marked_section "$dest_file"
        success "Windsurf: removed section from $dest_file"
    else
        warn "Windsurf: nothing to remove"
    fi
}

install_copilot() {
    local dest_dir="$PROJECT_PATH/.github"
    local dest_file="$dest_dir/copilot-instructions.md"
    local src_file="$SKILL_DIR/adapters/copilot/copilot-instructions.md"

    if [[ ! -f "$src_file" ]]; then
        error "Copilot adapter file not found: $src_file"
        return 1
    fi

    local content
    content="$(cat "$src_file")"
    content="$(replace_placeholders "$content")"

    append_marked_section "$dest_file" "$content"
    success "Copilot: configured $dest_file"
}

uninstall_copilot() {
    local dest_file="$PROJECT_PATH/.github/copilot-instructions.md"
    if [[ -f "$dest_file" ]] && grep -qF "$MARKER_START" "$dest_file" 2>/dev/null; then
        remove_marked_section "$dest_file"
        success "Copilot: removed section from $dest_file"
    else
        warn "Copilot: nothing to remove"
    fi
}

install_gemini() {
    local dest_file="$PROJECT_PATH/GEMINI.md"
    local src_file="$SKILL_DIR/adapters/gemini/GEMINI.md"

    if [[ ! -f "$src_file" ]]; then
        error "Gemini adapter file not found: $src_file"
        return 1
    fi

    local content
    content="$(cat "$src_file")"
    content="$(replace_placeholders "$content")"

    append_marked_section "$dest_file" "$content"
    success "Gemini: configured $dest_file"
}

uninstall_gemini() {
    local dest_file="$PROJECT_PATH/GEMINI.md"
    if [[ -f "$dest_file" ]] && grep -qF "$MARKER_START" "$dest_file" 2>/dev/null; then
        remove_marked_section "$dest_file"
        success "Gemini: removed section from $dest_file"
    else
        warn "Gemini: nothing to remove"
    fi
}

install_cline() {
    local dest_file="$PROJECT_PATH/.clinerules"
    local src_file="$SKILL_DIR/adapters/cline/clinerules.md"

    if [[ ! -f "$src_file" ]]; then
        error "Cline adapter file not found: $src_file"
        return 1
    fi

    local content
    content="$(cat "$src_file")"
    content="$(replace_placeholders "$content")"

    append_marked_section "$dest_file" "$content"
    success "Cline: configured $dest_file"
}

uninstall_cline() {
    local dest_file="$PROJECT_PATH/.clinerules"
    if [[ -f "$dest_file" ]] && grep -qF "$MARKER_START" "$dest_file" 2>/dev/null; then
        remove_marked_section "$dest_file"
        success "Cline: removed section from $dest_file"
    else
        warn "Cline: nothing to remove"
    fi
}

install_agents_md() {
    local dest_file="$PROJECT_PATH/AGENTS.md"
    local content
    content="$(cat <<'AGENTS_EOF'
## Java Server Architecture Review

This project uses the `java-arch-review` skill for automated architecture review.

### Quick Start
Run a full architecture review:
```bash
bash {SKILL_DIR}/scripts/arch-review.sh --project . --mode full
```

### Available Modes
| Mode  | Description |
|-------|-------------|
| full  | All 19 dimensions |
| pr    | Only git-changed files |
| focus | Specific dimensions (e.g., --dimensions "sql-injection,security") |
| quick | BLOCKER severity only |

See [{SKILL_DIR}/SKILL.md]({SKILL_DIR}/SKILL.md) for full skill definition.
AGENTS_EOF
)"
    content="$(replace_placeholders "$content")"

    append_marked_section "$dest_file" "$content"
    success "AGENTS.md: configured $dest_file"
}

uninstall_agents_md() {
    local dest_file="$PROJECT_PATH/AGENTS.md"
    if [[ -f "$dest_file" ]] && grep -qF "$MARKER_START" "$dest_file" 2>/dev/null; then
        remove_marked_section "$dest_file"
        success "AGENTS.md: removed section from $dest_file"
    else
        warn "AGENTS.md: nothing to remove"
    fi
}

# ==============================================================================
# Auto-detection: inspect the project directory to decide which agents to install
# ==============================================================================
auto_detect_agents() {
    local detected=()

    if [[ -d "$PROJECT_PATH/.claude-plugin" ]] || [[ -d "$PROJECT_PATH/commands" ]]; then
        detected+=("claude")
        info "Detected: .claude-plugin/ or commands/ → Claude Code" >&2
    fi

    if [[ -d "$PROJECT_PATH/.opencode" ]]; then
        detected+=("opencode")
        info "Detected: .opencode/ directory → OpenCode" >&2
    fi

    if [[ -d "$PROJECT_PATH/.cursor" ]]; then
        detected+=("cursor")
        info "Detected: .cursor/ directory → Cursor" >&2
    fi

    if [[ -d "$PROJECT_PATH/.windsurf" ]] || [[ -f "$PROJECT_PATH/.windsurfrules" ]]; then
        detected+=("windsurf")
        info "Detected: Windsurf configuration → Windsurf" >&2
    fi

    if [[ -d "$PROJECT_PATH/.github" ]]; then
        detected+=("copilot")
        info "Detected: .github/ directory → Copilot" >&2
    fi

    if [[ -f "$PROJECT_PATH/GEMINI.md" ]]; then
        detected+=("gemini")
        info "Detected: GEMINI.md → Gemini" >&2
    fi

    # Cline has no standard directory; detect .clinerules if present
    if [[ -f "$PROJECT_PATH/.clinerules" ]]; then
        detected+=("cline")
        info "Detected: .clinerules → Cline" >&2
    fi

    if [[ ${#detected[@]} -eq 0 ]]; then
        warn "No agent-specific configuration detected in the project." >&2
        warn "Tip: use --agent <name> to install for a specific agent, or --agent all." >&2
    fi

    printf '%s\n' "${detected[@]}"
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo ""
    printf "${BOLD}java-arch-review setup${RESET}\n"
    printf "Skill directory: %s\n" "$SKILL_DIR"
    printf "Project: %s\n" "$PROJECT_PATH"
    echo ""

    # Determine target agents
    local agents=()
    if [[ -n "$AGENT" ]]; then
        if [[ "$AGENT" == "all" ]]; then
            agents=("${SUPPORTED_AGENTS[@]}")
        else
            agents=("$AGENT")
        fi
    elif $DETECT; then
        # Auto-detect mode
        info "Auto-detecting agents..."
        while IFS= read -r a; do
            [[ -n "$a" ]] && agents+=("$a")
        done < <(auto_detect_agents)
    else
        # Default: install ALL agents
        info "Installing all agents (use --detect to auto-detect, or --agent <name> for specific agent)"
        agents=("${SUPPORTED_AGENTS[@]}")
    fi

    echo ""

    if $UNINSTALL; then
        # ---- Uninstall ----
        printf "${BOLD}Uninstalling...${RESET}\n"
        for a in "${agents[@]}"; do
            "uninstall_${a}" || true
        done
        uninstall_agents_md
    else
        # ---- Install ----
        if [[ ${#agents[@]} -eq 0 ]]; then
            info "No agents to install. Use --agent <name> or --agent all."
            echo ""
            exit 0
        fi

        printf "${BOLD}Installing...${RESET}\n"
        local any_failure=false
        for a in "${agents[@]}"; do
            if ! "install_${a}"; then
                any_failure=true
            fi
        done

        # Always update AGENTS.md
        install_agents_md

        echo ""
        if $any_failure; then
            error "Some installations failed. Check errors above."
            exit 1
        else
            success "All done! Architecture review skill is configured."
        fi
    fi

    echo ""
}

main
