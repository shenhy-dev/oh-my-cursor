#!/usr/bin/env bash
{ # ensure entire script is downloaded before execution

set -euo pipefail

VERSION="0.5.2"
CURSOR_MODE_LABEL="Team Avatar (Cursor Plugin)"
PLUGIN_NAME="oh-my-cursor"

AGENT_FILES=(aang.md sokka.md katara.md zuko.md toph.md appa.md momo.md iroh.md)
PROTOCOL_FILES=(protocols/team-avatar.md)
COMMAND_FILES=(plan.md build.md search.md fix.md tasks.md scout.md cactus-juice.md doc.md image.md)
HOOK_FILES=(post-edit-lint.js pre-commit-check.js guard-shell.js hooks.json)
LEGACY_HOOK_FILES=(post-edit-lint.sh pre-commit-check.sh guard-shell.sh)
PLUGIN_MANIFEST_FILES=(plugin.json marketplace.json)
RULE_FILE="orchestrator.mdc"
SKILL_DIRS=(
  architect
  codebase-search
  create-an-asset
  cursor-image-generation
  debugging
  design-patterns-implementation
  docs-write
  documentation-engineer
  documentation-writing
  exploring-codebases
  frontend-builder
  implementing-figma-designs
  mgrep-code-search
  planning
  refactoring
  refactoring-patterns
  technical-roadmap-planning
  vercel-composition-patterns
  vercel-react-best-practices
  web-design-guidelines
)

LEGACY_AGENT_FILES=(atlas.md explore.md generalPurpose.md hephaestus.md librarian.md metis.md momus.md multimodal-looker.md oracle.md prometheus.md sisyphus.md)
LEGACY_PROTOCOL_FILES=(protocols/swarm-coordinator.md)

FORCE=false
DRY_RUN=false
VERBOSE=false
SCOPE="user"
UNINSTALL=false
DISABLE=false
ENABLE=false
ALSO_CLAUDE=false
ALSO_CODEX=false
WITH_SKILLS=true

WORK_DIR=""

BOLD="" DIM="" GREEN="" RED="" YELLOW="" RESET=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

cleanup() {
  if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

setup_colors() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    GREEN=$'\033[0;32m'
    RED=$'\033[0;31m'
    YELLOW=$'\033[0;33m'
    RESET=$'\033[0m'
  fi
}

log() {
  printf '%s\n' "$*"
}

log_verbose() {
  if [ "$VERBOSE" = true ]; then
    printf '%s%s%s\n' "$DIM" "$*" "$RESET"
  fi
}

remove_path() {
  local target="$1"
  local label="${2:-$1}"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$DRY_RUN" = true ]; then
      log "  ${RED}[remove]${RESET} ${label}"
    else
      rm -rf "$target"
      log "  ${RED}[removed]${RESET} ${label}"
    fi
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
${BOLD}oh-my-cursor installer${RESET} v${VERSION}
${DIM}${CURSOR_MODE_LABEL}${RESET}

Install Team Avatar as a Cursor plugin (rules, agents, commands, hooks, skills).

${BOLD}USAGE${RESET}
  curl -fsSL https://raw.githubusercontent.com/tmcfarlane/oh-my-cursor/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/tmcfarlane/oh-my-cursor/main/install.sh | bash -s -- [OPTIONS]
  bash install.sh [OPTIONS]

${BOLD}OPTIONS${RESET}
  --user          Install the Cursor plugin to ~/.cursor/plugins/local/${PLUGIN_NAME} [default]
  --project       Install to project scope (./.cursor/) for this repo and cloud agents
  --claude        Also install to .claude/ for Claude Code compatibility
  --codex         Also install to .codex/ for Codex compatibility
  --no-skills     Skip installing bundled agent skills (skills are installed by default)
  -f, --force     Overwrite existing files
  -n, --dry-run   Show what would be done without making changes
  -v, --verbose   Enable verbose output
  --uninstall     Remove the plugin and leftover v0.4 injection files
  --disable       Disable orchestration (rename rule so Cursor stops applying it)
  --enable        Re-enable orchestration (rename rule back)
  -h, --help      Show this help message
  --version       Print version

${BOLD}EXAMPLES${RESET}
  bash install.sh
  bash install.sh --project
  bash install.sh --force
  bash install.sh --dry-run
  bash install.sh --uninstall
  bash install.sh --disable
  bash install.sh --enable
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing & directory resolution
# ---------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--force)    FORCE=true ;;
      -n|--dry-run)  DRY_RUN=true ;;
      -v|--verbose)  VERBOSE=true ;;
      --user)        SCOPE="user" ;;
      --project)     SCOPE="project" ;;
      --claude)       ALSO_CLAUDE=true ;;
      --codex)        ALSO_CODEX=true ;;
      --with-skills)  WITH_SKILLS=true ;;  # no-op for backwards compatibility
      --no-skills)    WITH_SKILLS=false ;;
      --uninstall)    UNINSTALL=true ;;
      --disable)     DISABLE=true ;;
      --enable)      ENABLE=true ;;
      -h|--help)     usage; exit 0 ;;
      --version)     printf '%s\n' "$VERSION"; exit 0 ;;
      *)
        log "${RED}Unknown option: $1${RESET}" >&2
        log "" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

resolve_dirs() {
  if [ "$SCOPE" = "user" ]; then
    CURSOR_DIR="${HOME}/.cursor"
    PLUGIN_DIR="${CURSOR_DIR}/plugins/local/${PLUGIN_NAME}"
    AGENTS_DIR="${PLUGIN_DIR}/agents"
    RULES_DIR="${PLUGIN_DIR}/rules"
    COMMANDS_DIR="${PLUGIN_DIR}/commands"
    HOOKS_DIR="${PLUGIN_DIR}/hooks"
    SKILLS_DIR="${PLUGIN_DIR}/skills"
    MANIFEST_DIR="${PLUGIN_DIR}/.cursor-plugin"
  else
    CURSOR_DIR="./.cursor"
    PLUGIN_DIR=""
    AGENTS_DIR="${CURSOR_DIR}/agents"
    RULES_DIR="${CURSOR_DIR}/rules"
    COMMANDS_DIR="${CURSOR_DIR}/commands"
    HOOKS_DIR="${CURSOR_DIR}/hooks"
    SKILLS_DIR="${CURSOR_DIR}/skills"
    MANIFEST_DIR=""
  fi
}

RULE_FILE_DISABLED="${RULE_FILE}.disabled"

orchestrator_rule_paths() {
  # User-scope plugin copy, then leftover v0.4 injection, then project .cursor/.
  if [ "$SCOPE" = "user" ]; then
    printf '%s\n' "${PLUGIN_DIR}/rules"
    printf '%s\n' "${HOME}/.cursor/rules"
  else
    printf '%s\n' "${RULES_DIR}"
  fi
}

# Toggle orchestration rule so Cursor loads it (--enable) or ignores it (--disable).
toggle_orchestrator_rule() {
  log "${BOLD}oh-my-cursor${RESET} v${VERSION}"
  log "${DIM}${CURSOR_MODE_LABEL}${RESET}"
  log ""

  local found=false
  local rules_dir rule_path disabled_path
  while IFS= read -r rules_dir; do
    [ -z "$rules_dir" ] && continue
    rule_path="${rules_dir}/${RULE_FILE}"
    disabled_path="${rules_dir}/${RULE_FILE_DISABLED}"
    if [ ! -f "$rule_path" ] && [ ! -f "$disabled_path" ]; then
      continue
    fi
    found=true

    if [ "$DISABLE" = true ]; then
      if [ -f "$rule_path" ]; then
        if [ "$DRY_RUN" = true ]; then
          log "  ${YELLOW}[would disable]${RESET} ${RULE_FILE} in ${rules_dir}"
        else
          mv "$rule_path" "$disabled_path"
          log "  ${GREEN}[disabled]${RESET} ${rule_path} — orchestration off. Agents and commands still available."
        fi
      else
        log "  ${DIM}Already disabled${RESET} (${disabled_path})"
      fi
    else
      if [ -f "$disabled_path" ]; then
        if [ "$DRY_RUN" = true ]; then
          log "  ${YELLOW}[would enable]${RESET} ${RULE_FILE} in ${rules_dir}"
        else
          mv "$disabled_path" "$rule_path"
          log "  ${GREEN}[enabled]${RESET} ${rule_path} — Team Avatar orchestration on."
        fi
      else
        log "  ${DIM}Already enabled${RESET} (${rule_path})"
      fi
    fi
  done < <(orchestrator_rule_paths)

  if [ "$found" = false ]; then
    log "  ${YELLOW}No orchestrator rule found.${RESET} Install first, then retry --disable/--enable."
  fi
  log ""
}

# ---------------------------------------------------------------------------
# Embedded source files
# ---------------------------------------------------------------------------

SOURCE_BASE_URL_DEFAULT="https://raw.githubusercontent.com/tmcfarlane/oh-my-cursor/main"
# Override for forks/dev:
#   OH_MY_CURSOR_SOURCE_BASE_URL="https://raw.githubusercontent.com/<you>/<repo>/<ref>" bash install.sh
OH_MY_CURSOR_SOURCE_BASE_URL="${OH_MY_CURSOR_SOURCE_BASE_URL:-$SOURCE_BASE_URL_DEFAULT}"

get_script_dir() {
  local src="${BASH_SOURCE[0]:-}"
  if [ -n "$src" ] && [ -f "$src" ]; then
    (cd "$(dirname "$src")" && pwd)
    return 0
  fi
  return 1
}

copy_sources_from_local_repo() {
  local out_dir="$1"
  local script_dir

  script_dir="$(get_script_dir)" || return 1
  [ -d "${script_dir}/agents" ] || return 1
  [ -d "${script_dir}/rules" ] || return 1

  mkdir -p "${out_dir}/agents" "${out_dir}/rules" "${out_dir}/commands" "${out_dir}/hooks" "${out_dir}/.cursor-plugin"

  local file
  for file in "${AGENT_FILES[@]}"; do
    cp "${script_dir}/agents/${file}" "${out_dir}/agents/${file}" || return 1
  done

  for file in "${PROTOCOL_FILES[@]}"; do
    mkdir -p "${out_dir}/agents/$(dirname "$file")"
    cp "${script_dir}/agents/${file}" "${out_dir}/agents/${file}" || return 1
  done

  cp "${script_dir}/rules/${RULE_FILE}" "${out_dir}/rules/${RULE_FILE}" || return 1

  if [ -d "${script_dir}/commands" ]; then
    for file in "${COMMAND_FILES[@]}"; do
      cp "${script_dir}/commands/${file}" "${out_dir}/commands/${file}" || return 1
    done
  fi

  if [ -d "${script_dir}/hooks" ]; then
    for file in "${HOOK_FILES[@]}"; do
      cp "${script_dir}/hooks/${file}" "${out_dir}/hooks/${file}" || return 1
    done
  fi

  for file in "${PLUGIN_MANIFEST_FILES[@]}"; do
    if [ -f "${script_dir}/.cursor-plugin/${file}" ]; then
      cp "${script_dir}/.cursor-plugin/${file}" "${out_dir}/.cursor-plugin/${file}" || return 1
    fi
  done

  if [ -f "${script_dir}/permissions.json" ]; then
    cp "${script_dir}/permissions.json" "${out_dir}/permissions.json" || return 1
  fi

  if [ -d "${script_dir}/skills" ]; then
    cp -r "${script_dir}/skills" "${out_dir}/skills" || return 1
  fi

  return 0
}

download_file() {
  local url="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  curl -fsSL "$url" -o "$dest"
}

download_sources_from_github() {
  local out_dir="$1"

  if ! command -v curl >/dev/null 2>&1; then
    log_verbose "curl not found; cannot download sources"
    return 1
  fi

  local base="$OH_MY_CURSOR_SOURCE_BASE_URL"
  local file

  for file in "${AGENT_FILES[@]}"; do
    download_file "${base}/agents/${file}" "${out_dir}/agents/${file}" || return 1
  done

  for file in "${PROTOCOL_FILES[@]}"; do
    download_file "${base}/agents/${file}" "${out_dir}/agents/${file}" || return 1
  done

  download_file "${base}/rules/${RULE_FILE}" "${out_dir}/rules/${RULE_FILE}" || return 1

  for file in "${COMMAND_FILES[@]}"; do
    download_file "${base}/commands/${file}" "${out_dir}/commands/${file}" || return 1
  done

  for file in "${HOOK_FILES[@]}"; do
    download_file "${base}/hooks/${file}" "${out_dir}/hooks/${file}" || return 1
  done

  for file in "${PLUGIN_MANIFEST_FILES[@]}"; do
    download_file "${base}/.cursor-plugin/${file}" "${out_dir}/.cursor-plugin/${file}" || return 1
  done

  download_file "${base}/permissions.json" "${out_dir}/permissions.json" || return 1

  local manifest_url="${base}/skills/MANIFEST"
  local manifest_tmp
  manifest_tmp="$(mktemp)"
  if curl -fsSL "$manifest_url" -o "$manifest_tmp" 2>/dev/null; then
    mkdir -p "${out_dir}/skills"
    while IFS= read -r skill_file || [ -n "$skill_file" ]; do
      [ -z "$skill_file" ] && continue
      download_file "${base}/skills/${skill_file}" "${out_dir}/skills/${skill_file}" || true
    done < "$manifest_tmp"
    cp "$manifest_tmp" "${out_dir}/skills/MANIFEST"
  fi
  rm -f "$manifest_tmp"

  return 0
}

create_source_files() {
  local dir="$1"
  mkdir -p "$dir"

  if copy_sources_from_local_repo "$dir"; then
    log_verbose "Using local repo sources"
    return 0
  fi

  if download_sources_from_github "$dir"; then
    log_verbose "Downloaded sources from ${OH_MY_CURSOR_SOURCE_BASE_URL}"
    return 0
  fi

  log "${RED}Failed to acquire source files.${RESET}" >&2
  log "${DIM}Tried local repo checkout and GitHub raw download.${RESET}" >&2
  log "${DIM}Override the download base with OH_MY_CURSOR_SOURCE_BASE_URL=...${RESET}" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Install a set of files from src_dir to dest_dir
# ---------------------------------------------------------------------------

install_file_set() {
  local src_dir="$1"
  local dest_dir="$2"
  local label="$3"
  shift 3
  local files=("$@")
  local failed=0

  if [ ${#files[@]} -eq 0 ]; then
    return 0
  fi

  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$dest_dir"
  fi

  log "Installing ${label} to ${BOLD}${dest_dir}${RESET}"
  log ""

  local file src dest
  for file in "${files[@]}"; do
    src="${src_dir}/${file}"
    dest="${dest_dir}/${file}"

    if [ ! -f "$src" ]; then
      log_verbose "  ${DIM}[skip]${RESET} ${file} (source not found)"
      continue
    fi

    local dest_subdir
    dest_subdir="$(dirname "$dest")"
    if [ "$DRY_RUN" = false ]; then
      mkdir -p "$dest_subdir"
    fi

    if [ ! -f "$dest" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${GREEN}[new]${RESET} ${file}"
      else
        if cp "$src" "$dest" 2>/dev/null; then
          if [[ "$file" == *.sh ]]; then
            chmod +x "$dest" 2>/dev/null || true
          fi
          log "  ${GREEN}[installed]${RESET} ${file}"
        else
          log "  ${RED}[failed]${RESET} ${file}"
          failed=$((failed + 1))
          continue
        fi
      fi
    elif cmp -s "$src" "$dest"; then
      log "  ${DIM}[unchanged]${RESET} ${file}"
    elif [ "$FORCE" = true ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${YELLOW}[update]${RESET} ${file}"
      else
        if cp "$src" "$dest" 2>/dev/null; then
          if [[ "$file" == *.sh ]]; then
            chmod +x "$dest" 2>/dev/null || true
          fi
          log "  ${YELLOW}[updated]${RESET} ${file}"
        else
          log "  ${RED}[failed]${RESET} ${file}"
          failed=$((failed + 1))
          continue
        fi
      fi
    else
      log "  ${YELLOW}[skipped]${RESET} ${file} ${DIM}(use --force to overwrite)${RESET}"
    fi
  done

  log ""
  return $failed
}

write_project_hooks_json() {
  local dest="$1"
  if [ "$DRY_RUN" = true ]; then
    if [ -f "$dest" ]; then
      log "  ${YELLOW}[update]${RESET} hooks.json (project paths)"
    else
      log "  ${GREEN}[new]${RESET} hooks.json (project paths)"
    fi
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" <<'EOF'
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [
      { "command": "node .cursor/hooks/guard-shell.js", "failClosed": true }
    ],
    "afterFileEdit": [
      { "command": "node .cursor/hooks/post-edit-lint.js" }
    ]
  }
}
EOF
  log "  ${GREEN}[installed]${RESET} hooks.json (project paths)"
}

# ---------------------------------------------------------------------------
# Migrate leftover v0.4 user-scope injection (~/.cursor/{rules,agents,...})
# ---------------------------------------------------------------------------

migrate_legacy_user_injection() {
  local cursor_dir="$1"
  local migrated=0
  local file skill

  log "Checking for leftover user-scope injection in ${BOLD}${cursor_dir}${RESET}"
  log ""

  for file in "${AGENT_FILES[@]}" "${LEGACY_AGENT_FILES[@]}" "${PROTOCOL_FILES[@]}" "${LEGACY_PROTOCOL_FILES[@]}"; do
    if remove_path "${cursor_dir}/agents/${file}" "agents/${file}"; then
      migrated=$((migrated + 1))
    fi
  done

  for file in "${COMMAND_FILES[@]}"; do
    if remove_path "${cursor_dir}/commands/${file}" "commands/${file}"; then
      migrated=$((migrated + 1))
    fi
  done

  for file in "${LEGACY_HOOK_FILES[@]}"; do
    if remove_path "${cursor_dir}/hooks/${file}" "hooks/${file}"; then
      migrated=$((migrated + 1))
    fi
  done

  if remove_path "${cursor_dir}/rules/${RULE_FILE}" "rules/${RULE_FILE}"; then
    migrated=$((migrated + 1))
  fi
  if remove_path "${cursor_dir}/rules/${RULE_FILE_DISABLED}" "rules/${RULE_FILE_DISABLED}"; then
    migrated=$((migrated + 1))
  fi

  for skill in "${SKILL_DIRS[@]}"; do
    if remove_path "${cursor_dir}/skills/${skill}" "skills/${skill}/"; then
      migrated=$((migrated + 1))
    fi
  done

  if [ "$migrated" -gt 0 ]; then
    log ""
    log "  ${YELLOW}Removed ${migrated} leftover file(s) from the old ~/.cursor injection layout.${RESET}"
    if [ "$DRY_RUN" = false ]; then
      rmdir "${cursor_dir}/agents/protocols" 2>/dev/null || true
      rmdir "${cursor_dir}/agents" 2>/dev/null || true
      rmdir "${cursor_dir}/commands" 2>/dev/null || true
      rmdir "${cursor_dir}/hooks" 2>/dev/null || true
      rmdir "${cursor_dir}/rules" 2>/dev/null || true
      rmdir "${cursor_dir}/skills" 2>/dev/null || true
    fi
  else
    log "  ${DIM}None found${RESET}"
  fi
  log ""
}

# ---------------------------------------------------------------------------
# Migrate legacy agent files (Greek mythology -> ATLA)
# ---------------------------------------------------------------------------

migrate_legacy_agents() {
  local agents_dir="$1"
  local migrated=0

  for file in "${LEGACY_AGENT_FILES[@]}"; do
    local target="${agents_dir}/${file}"
    if [ -f "$target" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${YELLOW}[migrate]${RESET} removing legacy ${file}"
      else
        rm -f "$target"
        log "  ${YELLOW}[migrated]${RESET} removed legacy ${file}"
      fi
      migrated=$((migrated + 1))
    fi
  done

  for file in "${LEGACY_PROTOCOL_FILES[@]}"; do
    local target="${agents_dir}/${file}"
    if [ -f "$target" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${YELLOW}[migrate]${RESET} removing legacy ${file}"
      else
        rm -f "$target"
        log "  ${YELLOW}[migrated]${RESET} removed legacy ${file}"
      fi
      migrated=$((migrated + 1))
    fi
  done

  if [ "$migrated" -gt 0 ]; then
    log ""
    log "  ${YELLOW}Migrated from v0.1 (Greek mythology) to v0.2 (Team Avatar)${RESET}"
    log ""
  fi
}

# ---------------------------------------------------------------------------
# Install a git-native pre-commit hook (defense-in-depth backstop)
# ---------------------------------------------------------------------------
# The beforeShellExecution guard only sees shell `git commit`; Cursor's agent can also commit
# through its native git path, which bypasses that hook (observed on Cursor 3.9). A real git
# pre-commit hook catches anti-pattern commits regardless of how the commit is made.
install_git_precommit_hook() {
  local git_dir hook
  git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)" || { log "  [skip] git pre-commit hook (not a git repo)"; return 0; }
  hook="${git_dir}/hooks/pre-commit"
  if [ -f "$hook" ] && ! grep -q "oh-my-cursor" "$hook" 2>/dev/null; then
    log "  [skip] git pre-commit hook (existing non-OMC hook at ${hook})"; return 0
  fi
  if [ "$DRY_RUN" = true ]; then log "  ${GREEN}[new]${RESET} git pre-commit hook (${hook})"; return 0; fi
  mkdir -p "$(dirname "$hook")"
  cat > "$hook" <<'HOOK'
#!/usr/bin/env bash
# oh-my-cursor defense-in-depth: catch anti-pattern commits regardless of HOW the commit is made
# (shell, git CLI, or Cursor's native git path). The beforeShellExecution guard only sees shell
# `git commit`; this git-native hook covers commits that bypass the shell.
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
exec node "$root/.cursor/hooks/pre-commit-check.js"
HOOK
  chmod +x "$hook"
  log "  ${GREEN}[installed]${RESET} git pre-commit hook (${hook})"
}

# ---------------------------------------------------------------------------
# Install Cursor plugin (user scope) or scattered .cursor files (project / claude / codex)
# ---------------------------------------------------------------------------

install_cursor_plugin() {
  local dest="$1"

  migrate_legacy_user_injection "${HOME}/.cursor"
  migrate_legacy_agents "${dest}/agents"

  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$dest"
  fi

  install_file_set "${WORK_DIR}/.cursor-plugin" "${dest}/.cursor-plugin" "plugin manifest" "${PLUGIN_MANIFEST_FILES[@]}"
  install_file_set "${WORK_DIR}/agents" "${dest}/agents" "agents" "${AGENT_FILES[@]}"
  install_file_set "${WORK_DIR}/agents" "${dest}/agents" "protocols" "${PROTOCOL_FILES[@]}"
  install_file_set "${WORK_DIR}/commands" "${dest}/commands" "commands" "${COMMAND_FILES[@]}"
  install_file_set "${WORK_DIR}/hooks" "${dest}/hooks" "hooks" "${HOOK_FILES[@]}"
  for file in "${LEGACY_HOOK_FILES[@]}"; do
    remove_path "${dest}/hooks/${file}" "hooks/${file}" || true
  done
  install_file_set "${WORK_DIR}/rules" "${dest}/rules" "rules" "${RULE_FILE}"
}

install_to_dir() {
  local cursor_dir="$1"
  local agents_dir="${cursor_dir}/agents"
  local rules_dir="${cursor_dir}/rules"
  local commands_dir="${cursor_dir}/commands"
  local hooks_dir="${cursor_dir}/hooks"
  local is_project_cursor=false

  if [ "$SCOPE" = "project" ] && [ "$cursor_dir" = "$CURSOR_DIR" ]; then
    is_project_cursor=true
  fi

  migrate_legacy_agents "$agents_dir"

  install_file_set "${WORK_DIR}/agents" "$agents_dir" "agents" "${AGENT_FILES[@]}"
  install_file_set "${WORK_DIR}/agents" "$agents_dir" "protocols" "${PROTOCOL_FILES[@]}"
  install_file_set "${WORK_DIR}/commands" "$commands_dir" "commands" "${COMMAND_FILES[@]}"
  install_file_set "${WORK_DIR}/hooks" "$hooks_dir" "hook scripts" post-edit-lint.js pre-commit-check.js guard-shell.js
  for file in "${LEGACY_HOOK_FILES[@]}"; do
    remove_path "${hooks_dir}/${file}" "hooks/${file}" || true
  done
  install_file_set "${WORK_DIR}/rules" "$rules_dir" "rules" "${RULE_FILE}"

  if [ "$is_project_cursor" = true ]; then
    log "Installing project hook config to ${BOLD}${cursor_dir}${RESET}"
    log ""
    write_project_hooks_json "${cursor_dir}/hooks.json"
    if [ -f "${WORK_DIR}/permissions.json" ]; then
      install_file_set "$WORK_DIR" "$cursor_dir" "auto-review policy" permissions.json
    else
      log ""
    fi
    install_git_precommit_hook
    log ""
  fi
}

# ---------------------------------------------------------------------------
# Main install logic
# ---------------------------------------------------------------------------

install_agents() {
  if [ "$SCOPE" = "user" ]; then
    log "Installing Cursor plugin to ${BOLD}${PLUGIN_DIR}${RESET}"
    log ""
    install_cursor_plugin "$PLUGIN_DIR"
  else
    log "Installing to ${BOLD}${CURSOR_DIR}${RESET}"
    log ""
    install_to_dir "$CURSOR_DIR"
  fi

  if [ "$ALSO_CLAUDE" = true ]; then
    local claude_dir
    if [ "$SCOPE" = "user" ]; then
      claude_dir="${HOME}/.claude"
    else
      claude_dir="./.claude"
    fi
    log "${DIM}Also installing to ${claude_dir} (Claude Code compatibility)${RESET}"
    log ""
    install_to_dir "$claude_dir"
  fi

  if [ "$ALSO_CODEX" = true ]; then
    local codex_dir
    if [ "$SCOPE" = "user" ]; then
      codex_dir="${HOME}/.codex"
    else
      codex_dir="./.codex"
    fi
    log "${DIM}Also installing to ${codex_dir} (Codex compatibility)${RESET}"
    log ""
    install_to_dir "$codex_dir"
  fi

  log "${BOLD}Summary${RESET}"
  log "  ${DIM}Mode: ${CURSOR_MODE_LABEL}${RESET}"
  if [ "$WITH_SKILLS" = true ]; then
    log "  ${GREEN}Agents: ${#AGENT_FILES[@]} | Commands: ${#COMMAND_FILES[@]} | Hooks: 3 | Skills: ${#SKILL_DIRS[@]}${RESET}"
  else
    log "  ${GREEN}Agents: ${#AGENT_FILES[@]} | Commands: ${#COMMAND_FILES[@]} | Hooks: 3 | Skills: skipped${RESET}"
  fi
  log ""

  if [ "$SCOPE" = "user" ]; then
    log "  ${YELLOW}Reload Cursor (Developer: Reload Window) or restart the app.${RESET}"
    log "  ${YELLOW}Open Customize and confirm the oh-my-cursor plugin components are listed.${RESET}"
    log ""
  elif [ "$SCOPE" = "project" ]; then
    log "  ${YELLOW}Fully restart Cursor (Cmd+Q / Alt+F4) so project hooks register.${RESET}"
    log ""
  fi
}

# ---------------------------------------------------------------------------
# Uninstall logic
# ---------------------------------------------------------------------------

REMOVED_COUNT=0

uninstall_scattered() {
  local cursor_dir="$1"
  local agents_dir="${cursor_dir}/agents"
  local rules_dir="${cursor_dir}/rules"
  local commands_dir="${cursor_dir}/commands"
  local hooks_dir="${cursor_dir}/hooks"
  local skills_dir="${cursor_dir}/skills"
  local removed=0
  local file skill target

  log "Removing agents from ${BOLD}${agents_dir}${RESET}"
  log ""
  for file in "${AGENT_FILES[@]}" "${LEGACY_AGENT_FILES[@]}" "${PROTOCOL_FILES[@]}" "${LEGACY_PROTOCOL_FILES[@]}"; do
    target="${agents_dir}/${file}"
    if [ -f "$target" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${RED}[remove]${RESET} ${file}"
      else
        rm -f "$target"
        log "  ${RED}[removed]${RESET} ${file}"
      fi
      removed=$((removed + 1))
    fi
  done
  if [ -d "${agents_dir}/protocols" ]; then
    [ "$DRY_RUN" = false ] && rmdir "${agents_dir}/protocols" 2>/dev/null || true
  fi

  log ""
  log "Removing commands from ${BOLD}${commands_dir}${RESET}"
  log ""
  for file in "${COMMAND_FILES[@]}"; do
    target="${commands_dir}/${file}"
    if [ -f "$target" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${RED}[remove]${RESET} ${file}"
      else
        rm -f "$target"
        log "  ${RED}[removed]${RESET} ${file}"
      fi
      removed=$((removed + 1))
    fi
  done

  log ""
  log "Removing hooks from ${BOLD}${hooks_dir}${RESET}"
  log ""
  for file in "${HOOK_FILES[@]}" "${LEGACY_HOOK_FILES[@]}"; do
    target="${hooks_dir}/${file}"
    if [ -f "$target" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${RED}[remove]${RESET} ${file}"
      else
        rm -f "$target"
        log "  ${RED}[removed]${RESET} ${file}"
      fi
      removed=$((removed + 1))
    fi
  done

  target="${cursor_dir}/hooks.json"
  if [ -f "$target" ]; then
    if [ "$DRY_RUN" = true ]; then
      log "  ${RED}[remove]${RESET} hooks.json"
    else
      rm -f "$target"
      log "  ${RED}[removed]${RESET} hooks.json"
    fi
    removed=$((removed + 1))
  fi

  target="${cursor_dir}/permissions.json"
  if [ -f "$target" ]; then
    if [ "$DRY_RUN" = true ]; then
      log "  ${RED}[remove]${RESET} permissions.json"
    else
      rm -f "$target"
      log "  ${RED}[removed]${RESET} permissions.json"
    fi
    removed=$((removed + 1))
  fi

  log ""
  log "Removing rules from ${BOLD}${rules_dir}${RESET}"
  log ""
  for file in "${RULE_FILE}" "${RULE_FILE_DISABLED}"; do
    target="${rules_dir}/${file}"
    if [ -f "$target" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${RED}[remove]${RESET} ${file}"
      else
        rm -f "$target"
        log "  ${RED}[removed]${RESET} ${file}"
      fi
      removed=$((removed + 1))
    fi
  done

  log ""
  log "Removing skills from ${BOLD}${skills_dir}${RESET}"
  log ""
  for skill in "${SKILL_DIRS[@]}"; do
    target="${skills_dir}/${skill}"
    if [ -d "$target" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${RED}[remove]${RESET} ${skill}/"
      else
        rm -rf "$target"
        log "  ${RED}[removed]${RESET} ${skill}/"
      fi
      removed=$((removed + 1))
    fi
  done

  REMOVED_COUNT=$removed
}

uninstall_agents() {
  log "${BOLD}oh-my-cursor${RESET} v${VERSION}"
  log "${DIM}${CURSOR_MODE_LABEL}${RESET}"
  log ""

  if [ "$DRY_RUN" = true ]; then
    log "${YELLOW}Dry run mode -- no changes will be made${RESET}"
    log ""
  fi

  local removed=0

  if [ "$SCOPE" = "user" ]; then
    if [ -d "$PLUGIN_DIR" ] || [ -L "$PLUGIN_DIR" ]; then
      log "Removing Cursor plugin from ${BOLD}${PLUGIN_DIR}${RESET}"
      log ""
      if [ "$DRY_RUN" = true ]; then
        log "  ${RED}[remove]${RESET} ${PLUGIN_DIR}"
      else
        rm -rf "$PLUGIN_DIR"
        log "  ${RED}[removed]${RESET} ${PLUGIN_DIR}"
        rmdir "${HOME}/.cursor/plugins/local" 2>/dev/null || true
        rmdir "${HOME}/.cursor/plugins" 2>/dev/null || true
      fi
      removed=$((removed + 1))
      log ""
    fi
    log "Removing leftover v0.4 injection from ${BOLD}${HOME}/.cursor${RESET}"
    log ""
    uninstall_scattered "${HOME}/.cursor"
    removed=$((removed + REMOVED_COUNT))
  else
    uninstall_scattered "$CURSOR_DIR"
    removed=$((removed + REMOVED_COUNT))
  fi

  # Remove our git pre-commit hook (only if it's ours)
  local git_pc_dir
  git_pc_dir="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
  if [ -n "$git_pc_dir" ] && [ -f "${git_pc_dir}/hooks/pre-commit" ] && grep -q "oh-my-cursor" "${git_pc_dir}/hooks/pre-commit" 2>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      log "  ${RED}[remove]${RESET} git pre-commit hook"
    else
      rm -f "${git_pc_dir}/hooks/pre-commit"
      log "  ${RED}[removed]${RESET} git pre-commit hook"
    fi
    removed=$((removed + 1))
  fi

  log ""
  log "${BOLD}Summary${RESET}"
  log "  ${DIM}Mode: ${CURSOR_MODE_LABEL}${RESET}"
  if [ "$removed" -gt 0 ]; then
    log "  ${RED}Removed: ${removed}${RESET}"
  else
    log "  ${DIM}Nothing to remove${RESET}"
  fi
}

# ---------------------------------------------------------------------------
# Skills installation
# ---------------------------------------------------------------------------

install_skills() {
  local src_skills_dir="${WORK_DIR}/skills"

  if [ ! -d "$src_skills_dir" ]; then
    log "${YELLOW}Warning: bundled skills not found in work directory. Skipping.${RESET}"
    log ""
    return 0
  fi

  log "Installing skills to ${BOLD}${SKILLS_DIR}${RESET}"
  log ""

  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$SKILLS_DIR"
  fi

  local skill skill_src skill_dest

  for skill in "${SKILL_DIRS[@]}"; do
    skill_src="${src_skills_dir}/${skill}"
    skill_dest="${SKILLS_DIR}/${skill}"

    if [ ! -d "$skill_src" ]; then
      log_verbose "  ${DIM}[skip]${RESET} ${skill} (source not found)"
      continue
    fi

    if [ ! -d "$skill_dest" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${GREEN}[new]${RESET} ${skill}/"
      else
        cp -r "$skill_src" "$skill_dest"
        log "  ${GREEN}[installed]${RESET} ${skill}/"
      fi
    elif diff -rq --exclude='.DS_Store' "$skill_src" "$skill_dest" >/dev/null 2>&1; then
      log "  ${DIM}[unchanged]${RESET} ${skill}/"
    elif [ "$FORCE" = true ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  ${YELLOW}[update]${RESET} ${skill}/"
      else
        rm -rf "$skill_dest"
        cp -r "$skill_src" "$skill_dest"
        log "  ${YELLOW}[updated]${RESET} ${skill}/"
      fi
    else
      log "  ${YELLOW}[skipped]${RESET} ${skill}/ ${DIM}(use --force to overwrite)${RESET}"
    fi
  done

  log ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  setup_colors
  parse_args "$@"
  resolve_dirs

  if [ "$DISABLE" = true ] && [ "$ENABLE" = true ]; then
    log "${RED}Cannot use --disable and --enable together.${RESET}" >&2
    exit 1
  fi

  if [ "$DISABLE" = true ] || [ "$ENABLE" = true ]; then
    toggle_orchestrator_rule
    return 0
  fi

  if [ "$UNINSTALL" = true ]; then
    uninstall_agents
    return 0
  fi

  WORK_DIR=$(mktemp -d)

  log "${BOLD}oh-my-cursor${RESET} v${VERSION}"
  log "${DIM}${CURSOR_MODE_LABEL}${RESET}"
  log ""

  if [ "$DRY_RUN" = true ]; then
    log "${YELLOW}Dry run mode -- no changes will be made${RESET}"
    log ""
  fi

  log_verbose "Scope: ${SCOPE}"
  log_verbose "Target: ${CURSOR_DIR}"
  log_verbose "Force: ${FORCE}"

  create_source_files "$WORK_DIR"
  install_agents

  if [ "$WITH_SKILLS" = true ]; then
    install_skills
  fi
}

main "$@"
} # ensure entire script is downloaded before execution
