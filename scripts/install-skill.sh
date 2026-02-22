#!/usr/bin/env bash
#
# Install/sync Superloop shared skills for Claude Code and Codex.
#
# Source of truth lives in .claude/skills/, then syncs to:
# - ~/.claude/skills/<skill>
# - ~/.codex/skills/<skill>
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUPERLOOP_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_ROOT="$SUPERLOOP_DIR/.claude/skills"

FORCE="false"
INSTALL_ALL="true"
declare -a SELECTED_SKILLS=()

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/install-skill.sh [--force] [--all]
  scripts/install-skill.sh [--force] --skill <name> [--skill <name> ...]

Options:
  --all            Install/sync all repo skills (default)
  --skill <name>   Install/sync only the named skill (repeatable)
  --force          Overwrite existing target skills without prompting
  -h, --help       Show this help

Examples:
  scripts/install-skill.sh
  scripts/install-skill.sh --force
  scripts/install-skill.sh --skill construct-superloop --skill superloop-view
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE="true"
      shift
      ;;
    --all)
      INSTALL_ALL="true"
      SELECTED_SKILLS=()
      shift
      ;;
    --skill)
      [[ $# -ge 2 ]] || die "--skill requires a value"
      INSTALL_ALL="false"
      SELECTED_SKILLS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -d "$SKILLS_ROOT" ]] || die "Skills root not found: $SKILLS_ROOT"

confirm_overwrite() {
  local target="$1"
  if [[ "$FORCE" == "true" ]]; then
    return 0
  fi

  echo "Skill already exists at $target"
  read -r -p "Overwrite? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Skipping $target"
    return 1
  fi
  return 0
}

collect_all_skills() {
  local skill_dir
  while IFS= read -r skill_dir; do
    basename "$skill_dir"
  done < <(find "$SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort)
}

skill_exists() {
  local skill="$1"
  [[ -f "$SKILLS_ROOT/$skill/SKILL.md" ]]
}

sync_skill_to_runtime() {
  local skill="$1"
  local parent_dir="$2"
  local runtime_label="$3"
  local source="$SKILLS_ROOT/$skill"
  local target="$parent_dir/$skill"

  mkdir -p "$parent_dir"

  if [[ -d "$target" ]]; then
    if ! confirm_overwrite "$target"; then
      return 0
    fi
    rm -rf "$target"
  fi

  cp -R "$source" "$target"
  echo "Synced [$skill] to $runtime_label: $target"
}

declare -a SKILLS_TO_INSTALL=()
if [[ "$INSTALL_ALL" == "true" ]]; then
  while IFS= read -r skill_name; do
    [[ -n "$skill_name" ]] && SKILLS_TO_INSTALL+=("$skill_name")
  done < <(collect_all_skills)
else
  declare -A seen=()
  for skill in "${SELECTED_SKILLS[@]}"; do
    [[ -n "$skill" ]] || continue
    if [[ -n "${seen[$skill]:-}" ]]; then
      continue
    fi
    seen[$skill]=1
    SKILLS_TO_INSTALL+=("$skill")
  done
fi

[[ ${#SKILLS_TO_INSTALL[@]} -gt 0 ]] || die "No skills selected for installation"

for skill in "${SKILLS_TO_INSTALL[@]}"; do
  skill_exists "$skill" || die "Skill source not found: $SKILLS_ROOT/$skill/SKILL.md"
done

CLAUDE_PARENT="$HOME/.claude/skills"
CODEX_PARENT="$HOME/.codex/skills"

echo "Installing shared skills from $SKILLS_ROOT"
for skill in "${SKILLS_TO_INSTALL[@]}"; do
  sync_skill_to_runtime "$skill" "$CLAUDE_PARENT" "Claude Code"
  sync_skill_to_runtime "$skill" "$CODEX_PARENT" "Codex"
done

echo
echo "Skill sync complete. Installed:"
for skill in "${SKILLS_TO_INSTALL[@]}"; do
  echo "- $skill"
done

echo
echo "Claude usage examples:"
for skill in "${SKILLS_TO_INSTALL[@]}"; do
  echo "- /$skill"
done

echo "Codex note: restart Codex to pick up newly installed skills."
