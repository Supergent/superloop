#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/bootstrap-target-dev-env.sh --repo <path> --profile <name> [--force]

Profiles:
  supergent

Description:
  Copies baseline devenv/direnv files into a target repo and ensures gitignore
  contains local environment cache entries.
USAGE
}

repo=""
profile=""
force="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --profile)
      profile="${2:-}"
      shift 2
      ;;
    --force)
      force="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$repo" || -z "$profile" ]]; then
  usage
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
profile_dir="$script_dir/dev-env/profiles/$profile"

if [[ ! -d "$profile_dir" ]]; then
  echo "Unknown profile: $profile" >&2
  exit 1
fi

if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Target repo not found or not a git worktree: $repo" >&2
  exit 1
fi

copy_file() {
  local src="$1"
  local dst="$2"
  if [[ -f "$dst" && "$force" != "true" ]]; then
    echo "skip (exists): $dst"
    return
  fi
  cp "$src" "$dst"
  echo "write: $dst"
}

copy_file "$profile_dir/devenv.nix" "$repo/devenv.nix"
copy_file "$profile_dir/devenv.yaml" "$repo/devenv.yaml"
copy_file "$profile_dir/.envrc" "$repo/.envrc"
copy_file "$profile_dir/.envrc.example" "$repo/.envrc.example"

gitignore_file="$repo/.gitignore"
touch "$gitignore_file"
for entry in ".direnv/" ".devenv/" "devenv.lock"; do
  if ! rg -Fqx "$entry" "$gitignore_file"; then
    printf '%s\n' "$entry" >> "$gitignore_file"
    echo "append .gitignore: $entry"
  fi
done

echo "Bootstrap complete for profile '$profile'."
