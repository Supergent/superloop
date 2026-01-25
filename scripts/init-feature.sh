#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/init-feature.sh <feature-name> [slug]

Arguments:
  <feature-name>  Required. Kebab-case feature name (e.g., environment-matrix).
  [slug]          Optional. Defaults to "initiation". Use a meaningful slug for follow-on work.
USAGE
}

feature_name="${1:-}"
slug="${2:-initiation}"

if [[ -z "$feature_name" ]]; then
  usage
  exit 1
fi

if [[ "$feature_name" =~ [[:space:]] ]]; then
  echo "error: feature-name must not contain spaces (use kebab-case)" >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATES_DIR="$ROOT_DIR/handbook/features/templates"
PLAN_TEMPLATE="$TEMPLATES_DIR/PLAN.MD"
PHASE_TEMPLATE="$TEMPLATES_DIR/PHASE_1.MD"

FEATURE_PATH="$ROOT_DIR/feat/$feature_name/$slug"
TASKS_DIR="$FEATURE_PATH/tasks"

mkdir -p "$TASKS_DIR"

if [[ -f "$PLAN_TEMPLATE" ]]; then
  if [[ ! -f "$FEATURE_PATH/PLAN.MD" ]]; then
    cp "$PLAN_TEMPLATE" "$FEATURE_PATH/PLAN.MD"
  fi
else
  if [[ ! -f "$FEATURE_PATH/PLAN.MD" ]]; then
    cat > "$FEATURE_PATH/PLAN.MD" <<'PLAN_FALLBACK'
# Feature: <Feature Name>

## Goal
<One clear sentence describing the objective.>

## Scope
- <What's included>

## Non-Goals (this iteration)
- <Explicitly out of scope>

## Primary References
- `<path/to/file>` - <purpose>

## Architecture
<High-level description of components and interactions.>

## Decisions
- <Key decision + rationale>

## Risks / Constraints
- <Known risk or constraint>

## Phases
- **Phase 1**: <Brief description>
PLAN_FALLBACK
  fi
fi

if [[ -f "$PHASE_TEMPLATE" ]]; then
  if [[ ! -f "$TASKS_DIR/PHASE_1.MD" ]]; then
    cp "$PHASE_TEMPLATE" "$TASKS_DIR/PHASE_1.MD"
  fi
else
  if [[ ! -f "$TASKS_DIR/PHASE_1.MD" ]]; then
    cat > "$TASKS_DIR/PHASE_1.MD" <<'PHASE_FALLBACK'
# Phase 1 - <Phase Title>

## P1.1 <Task Group Name>
1. [ ] <Atomic task>

## P1.V Validation
1. [ ] <Validation criterion>
PHASE_FALLBACK
  fi
fi

branch="feat/${feature_name}/${slug}"
feature_path="feat/${feature_name}/${slug}/"
phase_path="feat/${feature_name}/${slug}/tasks/PHASE_1.MD"

cat <<ISSUE_SNIPPET
Issue checklist snippet:
- Feature Path: ${feature_path}
- Branch: ${branch}
- Scope:
  - [ ] ${phase_path}
- Related PRs:
  - Initiation PR: <add link>
ISSUE_SNIPPET

printf '\nScaffold complete:\n'
printf ' - %s\n' "${feature_path}PLAN.MD" "${feature_path}tasks/PHASE_1.MD"
printf '\nRecommended branch:\n - %s\n' "$branch"

if [[ "$slug" != "initiation" ]]; then
  echo "note: initiation slug is reserved for first pass; ensure initiation exists first." >&2
fi
