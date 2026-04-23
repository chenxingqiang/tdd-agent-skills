#!/bin/bash
# install.sh — One-click installer for tdd-agent-skills
#
# Usage (curl — no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool cursor
#
# Usage (local clone):
#   bash install.sh                          # interactive guided mode
#   bash install.sh --tool cursor            # install for a specific tool
#   bash install.sh --tool all               # install for all tools
#   bash install.sh --tool cursor,windsurf   # install for multiple tools
#   bash install.sh --target /path/to/proj   # set target project directory
#   bash install.sh --global                 # install to user home config dirs
#   bash install.sh --help                   # show usage

set -e

# ─── Bootstrap (supports: curl -fsSL .../install.sh | bash) ──────────────────
#
# When piped through curl there is no local skills/ tree.  Detect that, clone
# the repo to a temp directory, and re-execute the real script from there.
# The _TDD_BOOTSTRAPPED guard prevents infinite recursion.

if [[ -z "${_TDD_BOOTSTRAPPED:-}" ]]; then
  _self="${BASH_SOURCE[0]:-}"
  if [[ -n "$_self" && "$_self" != "bash" ]]; then
    _src_dir="$(cd "$(dirname "$_self")" && pwd)"
  else
    _src_dir=""
  fi

  if [[ -z "$_src_dir" ]] || [[ ! -d "$_src_dir/skills" ]]; then
    if ! command -v git &>/dev/null; then
      echo "  ✗ git is required but was not found. Install git and retry." >&2
      exit 1
    fi
    _tmp="$(mktemp -d)"
    trap 'rm -rf "$_tmp"' EXIT INT TERM
    echo "  → Fetching tdd-agent-skills from GitHub…" >&2
    git clone --depth=1 --quiet \
      https://github.com/chenxingqiang/tdd-agent-skills.git "$_tmp/repo" >&2
    export _TDD_BOOTSTRAPPED=1
    exec bash "$_tmp/repo/install.sh" "$@"
  fi
fi

# ─── Color helpers ───────────────────────────────────────────────────────────

if [ -t 1 ]; then
  BOLD="\033[1m"; RESET="\033[0m"
  GREEN="\033[32m"; CYAN="\033[36m"; YELLOW="\033[33m"; RED="\033[31m"; DIM="\033[2m"
else
  BOLD=""; RESET=""; GREEN=""; CYAN=""; YELLOW=""; RED=""; DIM=""
fi

info()    { echo -e "${CYAN}  →${RESET} $*"; }
success() { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${RESET} $*"; }
error()   { echo -e "${RED}  ✗${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }
dim()     { echo -e "${DIM}$*${RESET}"; }

# ─── Locate script source dir ────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/skills"
AGENTS_DIR="$SCRIPT_DIR/agents"

if [ ! -d "$SKILLS_DIR" ]; then
  error "skills/ directory not found. Run this script from the tdd-agent-skills repo root."
  exit 1
fi

SKILL_NAMES=()
while IFS= read -r -d '' dir; do
  SKILL_NAMES+=("$(basename "$dir")")
done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

# ─── Argument parsing ─────────────────────────────────────────────────────────

TARGET_DIR="$(pwd)"
TARGET_DIR_EXPLICIT=false
TOOLS=""
GLOBAL=false

usage() {
  cat <<EOF

${BOLD}tdd-agent-skills installer${RESET}

${BOLD}Usage (curl — no clone needed):${RESET}
  curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/chenxingqiang/tdd-agent-skills/main/install.sh | bash -s -- --tool cursor

${BOLD}Usage (local clone):${RESET}
  bash install.sh [options]

${BOLD}Options:${RESET}
  --tool <name>     Tool(s) to install for (comma-separated).
                    Supported: cursor, windsurf, gemini, copilot, opencode, kiro, claude
                    Use "all" to install for every supported tool.
  --target <path>   Target project directory (default: current directory)
  --global          Install to user-level config directories instead of the project
  --help            Show this help message

${BOLD}Examples:${RESET}
  bash install.sh                        # Interactive: choose tool interactively
  bash install.sh --tool cursor          # Install for Cursor
  bash install.sh --tool all             # Install for all tools
  bash install.sh --tool cursor,windsurf # Install for Cursor and Windsurf
  bash install.sh --tool copilot --target ~/myproject
  bash install.sh --tool gemini --global

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)    TOOLS="$2";                              shift 2 ;;
    --target)  TARGET_DIR="$2"; TARGET_DIR_EXPLICIT=true; shift 2 ;;
    --global)  GLOBAL=true;      shift   ;;
    --help|-h) usage; exit 0            ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# ─── Tool list ────────────────────────────────────────────────────────────────

ALL_TOOLS="cursor windsurf gemini copilot opencode kiro claude"

# ─── Interactive selection ────────────────────────────────────────────────────

interactive_select_tools() {
  header "tdd-agent-skills — one-click installer"
  echo ""
  echo "  Which AI coding tool would you like to install skills for?"
  echo ""
  local i=1
  declare -A idx_map
  for t in $ALL_TOOLS; do
    case $t in
      cursor)   label="Cursor" ;;
      windsurf) label="Windsurf" ;;
      gemini)   label="Gemini CLI" ;;
      copilot)  label="GitHub Copilot" ;;
      opencode) label="OpenCode" ;;
      kiro)     label="Kiro IDE / CLI" ;;
      claude)   label="Claude Code" ;;
    esac
    echo "    [$i] $label"
    idx_map[$i]=$t
    ((i++))
  done
  echo "    [$i] All tools"
  local all_idx=$i
  echo ""
  read -r -p "  Enter number(s), comma-separated [1-$i]: " choice </dev/tty
  echo ""

  if [[ "$choice" == "$all_idx" ]]; then
    TOOLS="all"
    return
  fi

  local selected=()
  IFS=',' read -ra parts <<< "$choice"
  for part in "${parts[@]}"; do
    part=$(echo "$part" | tr -d ' ')
    if [[ -n "${idx_map[$part]}" ]]; then
      selected+=("${idx_map[$part]}")
    else
      warn "Ignored unknown selection: $part"
    fi
  done

  TOOLS=$(IFS=','; echo "${selected[*]}")
}

# ─── File helpers ─────────────────────────────────────────────────────────────

copy_skill() {
  local skill="$1" dest="$2"
  local src="$SKILLS_DIR/$skill/SKILL.md"
  if [ ! -f "$src" ]; then
    warn "Skill not found: $skill — skipped"
    return
  fi
  mkdir -p "$dest"
  cp "$src" "$dest/$skill.md"
  success "Installed skill: $skill → $dest/$skill.md"
}

copy_all_skills() {
  local dest="$1"
  mkdir -p "$dest"
  for skill in "${SKILL_NAMES[@]}"; do
    local src="$SKILLS_DIR/$skill/SKILL.md"
    [ -f "$src" ] && cp "$src" "$dest/$skill.md" && success "  $skill"
  done
}

append_skill() {
  local skill="$1" dest_file="$2"
  local src="$SKILLS_DIR/$skill/SKILL.md"
  if [ ! -f "$src" ]; then
    warn "Skill not found: $skill — skipped"
    return
  fi
  { echo ""; echo "---"; echo ""; cat "$src"; } >> "$dest_file"
  success "Appended skill: $skill → $dest_file"
}

# ─── Installers ───────────────────────────────────────────────────────────────

install_cursor() {
  header "Installing for Cursor"

  local dest
  if $GLOBAL; then
    dest="$HOME/.cursor/rules"
  else
    dest="$TARGET_DIR/.cursor/rules"
  fi

  info "Copying all skills to $dest/"
  copy_all_skills "$dest"
  success "Cursor setup complete."
  dim "  → Rules in $dest/ are auto-loaded by Cursor."
  dim "  → See docs/cursor-setup.md for tips on selective loading."
}

install_windsurf() {
  header "Installing for Windsurf"

  local dest_file
  if $GLOBAL; then
    dest_file="$HOME/.windsurfrules"
  else
    dest_file="$TARGET_DIR/.windsurfrules"
  fi

  info "Creating $dest_file with core TDD skills"

  local core_skills=("test-driven-development" "incremental-implementation" "code-review-and-quality")

  # Initialize new file with header or append section header to existing file
  if [ ! -f "$dest_file" ]; then
    echo "# tdd-agent-skills — installed by install.sh" > "$dest_file"
    echo "# Full skill list: https://github.com/chenxingqiang/tdd-agent-skills" >> "$dest_file"
  else
    { echo ""; echo "# --- tdd-agent-skills (appended by install.sh) ---"; } >> "$dest_file"
  fi

  for skill in "${core_skills[@]}"; do
    append_skill "$skill" "$dest_file"
  done

  success "Windsurf setup complete."
  dim "  → $dest_file is loaded automatically by Windsurf."
  dim "  → Add more skills manually with: cat skills/<name>/SKILL.md >> $dest_file"
  dim "  → See docs/windsurf-setup.md for recommended configuration."
}

install_gemini() {
  header "Installing for Gemini CLI"

  local dest
  if $GLOBAL; then
    dest="$HOME/.gemini/skills"
  else
    dest="$TARGET_DIR/.gemini/skills"
  fi

  info "Copying all skills to $dest/"
  copy_all_skills "$dest"
  success "Gemini CLI setup complete."
  dim "  → Skills in $dest/ are auto-discovered by Gemini CLI."
  dim "  → Verify with: gemini /skills list"
  dim "  → See docs/gemini-cli-setup.md for GEMINI.md persistent context options."
}

install_copilot() {
  header "Installing for GitHub Copilot"

  local skills_dest agents_dest instructions_file
  if $GLOBAL; then
    warn "--global is not supported for GitHub Copilot (project-scoped only). Proceeding with installation to $TARGET_DIR instead."
  fi

  skills_dest="$TARGET_DIR/.github/skills"
  agents_dest="$TARGET_DIR/.github/agents"
  instructions_file="$TARGET_DIR/.github/copilot-instructions.md"

  info "Copying all skills to $skills_dest/"
  copy_all_skills "$skills_dest"

  info "Copying agent personas to $agents_dest/"
  mkdir -p "$agents_dest"
  for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    cp "$agent_file" "$agents_dest/$(basename "$agent_file")"
    success "  $(basename "$agent_file")"
  done

  if [ ! -f "$instructions_file" ]; then
    info "Creating $instructions_file"
    mkdir -p "$(dirname "$instructions_file")"
    cat > "$instructions_file" <<'INSTR'
# Project Coding Standards (tdd-agent-skills)

## Testing
- Write tests before code (TDD)
- For bugs: write a failing test first, then fix (Prove-It pattern)
- Test hierarchy: unit > integration > e2e (use the lowest level that captures the behavior)
- Run the full test suite after every change

## Code Quality
- Review across five axes: correctness, readability, architecture, security, performance
- Every PR must pass: lint, type check, tests, build
- No secrets in code or version control

## Implementation
- Build in small, verifiable increments
- Each increment: implement → test → verify → commit
- Never mix formatting changes with behavior changes

## Boundaries
- Always: Run tests before commits, validate user input
- Ask first: Database schema changes, new dependencies
- Never: Commit secrets, remove failing tests, skip verification
INSTR
    success "Created $instructions_file"
  else
    warn "$instructions_file already exists — not overwritten."
  fi

  success "GitHub Copilot setup complete."
  dim "  → Skills: $skills_dest/"
  dim "  → Agents: invoke with @code-reviewer, @test-engineer, @security-auditor in Copilot Chat"
  dim "  → See docs/copilot-setup.md for more details."
}

install_opencode() {
  header "Installing for OpenCode"

  local agents_md_src="$SCRIPT_DIR/AGENTS.md"

  if $GLOBAL; then
    warn "--global is not supported for OpenCode (project-scoped only). Proceeding with installation to $TARGET_DIR instead."
  fi

  # Copy AGENTS.md to target project
  if [ -f "$agents_md_src" ]; then
    if [ "$TARGET_DIR" != "$SCRIPT_DIR" ]; then
      cp "$agents_md_src" "$TARGET_DIR/AGENTS.md"
      success "Copied AGENTS.md → $TARGET_DIR/AGENTS.md"
    else
      info "AGENTS.md already present in source repo."
    fi
  fi

  # Copy skills/ directory
  local skills_dest="$TARGET_DIR/skills"
  if [ "$TARGET_DIR" != "$SCRIPT_DIR" ]; then
    info "Copying skills/ to $skills_dest/"
    cp -r "$SKILLS_DIR" "$skills_dest"
    success "Copied skills/ → $skills_dest/"
  else
    info "skills/ already present in source repo."
  fi

  success "OpenCode setup complete."
  dim "  → Open $TARGET_DIR in OpenCode."
  dim "  → The agent reads AGENTS.md and skills/ automatically."
  dim "  → See docs/opencode-setup.md for the full workflow."
}

install_kiro() {
  header "Installing for Kiro"

  local dest
  if $GLOBAL; then
    dest="$HOME/.kiro/skills"
  else
    dest="$TARGET_DIR/.kiro/skills"
  fi

  info "Copying all skills to $dest/"
  copy_all_skills "$dest"
  success "Kiro setup complete."
  dim "  → Skills in $dest/ are loaded by Kiro automatically."
  dim "  → See https://kiro.dev/docs/skills/ for Kiro skill documentation."
}

install_claude() {
  header "Installing for Claude Code"

  # Claude Code user-level config lives in ~/.claude/.
  # Default to that unless --target explicitly points to a project directory.
  local claude_dest
  if $TARGET_DIR_EXPLICIT && ! $GLOBAL; then
    claude_dest="$TARGET_DIR/.claude"
    info "Installing into project: $TARGET_DIR/.claude/"
  else
    claude_dest="$HOME/.claude"
    info "Installing into user config: $HOME/.claude/"
  fi

  # ── Skills ────────────────────────────────────────────────────────────────
  # Each skill is installed as its own subdirectory so Claude Code can load it
  # by name: ~/.claude/skills/<skill-name>/SKILL.md
  local skills_dest="$claude_dest/skills"
  info "Installing skills to $skills_dest/"
  mkdir -p "$skills_dest"
  for skill in "${SKILL_NAMES[@]}"; do
    local src="$SKILLS_DIR/$skill"
    if [ -d "$src" ]; then
      mkdir -p "$skills_dest/$skill"
      cp -r "$src/." "$skills_dest/$skill/"
      success "  $skill"
    fi
  done

  # ── Slash commands ────────────────────────────────────────────────────────
  local commands_dest="$claude_dest/commands"
  info "Installing commands to $commands_dest/"
  mkdir -p "$commands_dest"
  if [ -d "$SCRIPT_DIR/.claude/commands" ]; then
    cp -r "$SCRIPT_DIR/.claude/commands/." "$commands_dest/"
    success "Commands installed to $commands_dest/"
  fi

  # ── Agent personas ────────────────────────────────────────────────────────
  local agents_dest="$claude_dest/agents"
  info "Installing agents to $agents_dest/"
  mkdir -p "$agents_dest"
  for agent_file in "$AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    cp "$agent_file" "$agents_dest/$(basename "$agent_file")"
    success "  $(basename "$agent_file")"
  done

  # ── AGENTS.md / CLAUDE.md ─────────────────────────────────────────────────
  if $TARGET_DIR_EXPLICIT && ! $GLOBAL; then
    [ -f "$SCRIPT_DIR/AGENTS.md" ] && cp "$SCRIPT_DIR/AGENTS.md" "$TARGET_DIR/AGENTS.md" \
      && success "AGENTS.md → $TARGET_DIR/AGENTS.md"
    [ -f "$SCRIPT_DIR/CLAUDE.md" ] && cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md" \
      && success "CLAUDE.md → $TARGET_DIR/CLAUDE.md"
  fi

  success "Claude Code installed to $claude_dest/"
  dim "  → Skills:   $skills_dest/"
  dim "  → Commands: $commands_dest/ (available as slash commands)"
  dim "  → Agents:   $agents_dest/"
  dim "  → Start a new Claude Code session — skills and commands load automatically."
  dim "  → See README.md Quick Start → Claude Code for full instructions."
}

# ─── Dispatcher ───────────────────────────────────────────────────────────────

run_installer() {
  local tool="$1"
  case "$tool" in
    cursor)   install_cursor   ;;
    windsurf) install_windsurf ;;
    gemini)   install_gemini   ;;
    copilot)  install_copilot  ;;
    opencode) install_opencode ;;
    kiro)     install_kiro     ;;
    claude)   install_claude   ;;
    *) error "Unknown tool: $tool (supported: $ALL_TOOLS)"; exit 1 ;;
  esac
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
  if [ -z "$TOOLS" ]; then
    interactive_select_tools
  fi

  if [ -z "$TOOLS" ]; then
    warn "No tools selected. Exiting."
    exit 0
  fi

  if $GLOBAL; then
    info "Mode: global (user-level config directories)"
  else
    info "Target project: $TARGET_DIR"
  fi

  if [[ "$TOOLS" == "all" ]]; then
    for tool in $ALL_TOOLS; do
      run_installer "$tool"
    done
  else
    IFS=',' read -ra selected <<< "$TOOLS"
    for tool in "${selected[@]}"; do
      tool=$(echo "$tool" | tr -d ' ')
      run_installer "$tool"
    done
  fi

  echo ""
  header "Installation complete 🎉"
  echo ""
  echo "  Documentation: https://github.com/chenxingqiang/tdd-agent-skills"
  echo ""
}

main
