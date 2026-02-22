#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-alert-sink-config.sh [options]

Options:
  --config-file <path>        Alert sink config JSON path.
  --category <name>           Resolve routing for a specific escalation category.
  --severity <level>          Event severity override for route resolution (info|warning|critical).
  --list-sinks                List sink ids, types, and enabled flags.
  --no-env-check              Skip fail-closed checks for enabled sink secret env vars.
  --pretty                    Pretty-print output JSON.
  --help                      Show this help message.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "missing required command: $cmd"
  fi
}

severity_rank() {
  case "$1" in
    info) echo 1 ;;
    warning) echo 2 ;;
    critical) echo 3 ;;
    *) return 1 ;;
  esac
}

config_file=""
category=""
severity=""
list_only="0"
env_check="1"
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-file)
      config_file="${2:-}"
      shift 2
      ;;
    --category)
      category="${2:-}"
      shift 2
      ;;
    --severity)
      severity="${2:-}"
      shift 2
      ;;
    --list-sinks)
      list_only="1"
      shift
      ;;
    --no-env-check)
      env_check="0"
      shift
      ;;
    --pretty)
      pretty="1"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

need_cmd jq

if [[ "$list_only" == "1" && -n "$category" ]]; then
  die "--list-sinks cannot be combined with --category"
fi
if [[ -z "$category" && -n "$severity" ]]; then
  die "--severity requires --category"
fi
if [[ -n "$severity" ]] && ! severity_rank "$severity" >/dev/null; then
  die "--severity must be one of: info, warning, critical"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

if [[ -z "$config_file" ]]; then
  config_file="${OPS_MANAGER_ALERT_SINKS_FILE:-$root_dir/config/ops-manager-alert-sinks.v1.json}"
fi
if [[ ! -f "$config_file" ]]; then
  die "alert sink config file not found: $config_file"
fi

config_json=$(jq -c '.' "$config_file" 2>/dev/null) || die "invalid alert sink config JSON: $config_file"

if ! jq -e '
  def is_severity: . == "info" or . == "warning" or . == "critical";
  (.schemaVersion == "v1")
  and (.defaultMinSeverity | is_severity)
  and (.sinks | type == "object" and (keys | length) > 0)
  and (.routing | type == "object")
  and ((.routing.defaultSinks // null) | type == "array")
  and ((.routing.categorySeverity // null) | type == "object")
  and ((.routing.routes // []) | type == "array")
' <<<"$config_json" >/dev/null; then
  die "alert sink config has invalid top-level shape"
fi

if ! jq -e '
  def is_env_ref: type == "string" and test("^[A-Z_][A-Z0-9_]*$");
  def timeout_ok: ((. // 5) | type == "number" and . >= 1 and . <= 120);
  .sinks
  | to_entries
  | all(
      .[];
      (.value.enabled | type == "boolean")
      and (.value.type == "webhook" or .value.type == "slack" or .value.type == "pagerduty_events")
      and (.value.timeoutSeconds | timeout_ok)
      and (
        if .value.type == "webhook" then
          (.value.urlEnv | is_env_ref)
          and ((.value.authTokenEnv? // null) == null or (.value.authTokenEnv | is_env_ref))
          and ((.value.headers? // null) == null or (.value.headers | type == "object" and all(to_entries[]; (.value | type == "string"))))
        elif .value.type == "slack" then
          (.value.webhookUrlEnv | is_env_ref)
        else
          (.value.routingKeyEnv | is_env_ref)
        end
      )
    )
' <<<"$config_json" >/dev/null; then
  die "alert sink config sink definitions are invalid"
fi

if ! jq -e '
  def is_severity: . == "info" or . == "warning" or . == "critical";
  .sinks as $sinks
  | (.routing.defaultSinks // []) as $default_sinks
  | (.routing.routes // []) as $routes
  | (.routing.categorySeverity // {}) as $category_severity
  | all($default_sinks[]?; $sinks[.] != null)
    and all(
      $routes[]?;
      (.category | type == "string" and (length > 0))
      and ((.enabled? // true) | type == "boolean")
      and ((.minSeverity? // "warning") | is_severity)
      and all((.sinks // [])[]; $sinks[.] != null)
    )
    and all($category_severity | to_entries[]; (.value | is_severity))
' <<<"$config_json" >/dev/null; then
  die "alert sink config routing is invalid"
fi

mapfile -t all_secret_env_refs < <(
  jq -r '
    .sinks
    | to_entries[]
    | .value as $sink
    | if $sink.type == "webhook" then [$sink.urlEnv, ($sink.authTokenEnv // empty)]
      elif $sink.type == "slack" then [$sink.webhookUrlEnv]
      elif $sink.type == "pagerduty_events" then [$sink.routingKeyEnv]
      else []
      end
    | .[]
  ' <<<"$config_json" | awk 'NF' | sort -u
)

env_status_json='{}'
for env_ref in "${all_secret_env_refs[@]}"; do
  env_present="false"
  if [[ -n "${!env_ref-}" ]]; then
    env_present="true"
  fi
  env_status_json=$(jq -c --arg env_ref "$env_ref" --argjson env_present "$env_present" '. + {($env_ref): {present: $env_present}}' <<<"$env_status_json")
done

if [[ "$env_check" == "1" ]]; then
  mapfile -t required_secret_env_refs < <(
    jq -r '
      .sinks
      | to_entries[]
      | select(.value.enabled == true)
      | .value as $sink
      | if $sink.type == "webhook" then [$sink.urlEnv, ($sink.authTokenEnv // empty)]
        elif $sink.type == "slack" then [$sink.webhookUrlEnv]
        elif $sink.type == "pagerduty_events" then [$sink.routingKeyEnv]
        else []
        end
      | .[]
    ' <<<"$config_json" | awk 'NF' | sort -u
  )

  missing_secret_env_refs=()
  for env_ref in "${required_secret_env_refs[@]}"; do
    if [[ -z "${!env_ref-}" ]]; then
      missing_secret_env_refs+=("$env_ref")
    fi
  done

  if (( ${#missing_secret_env_refs[@]} > 0 )); then
    die "enabled sink secret env var(s) are unset: ${missing_secret_env_refs[*]}"
  fi
fi

if [[ "$list_only" == "1" ]]; then
  jq -r '.sinks | to_entries[] | "\(.key)\t\(.value.type)\t\(.value.enabled)"' <<<"$config_json"
  exit 0
fi

env_check_enabled="false"
if [[ "$env_check" == "1" ]]; then
  env_check_enabled="true"
fi

if [[ -n "$category" ]]; then
  route_json=$(jq -c --arg category "$category" '
    ((.routing.routes // []) | map(select(.category == $category and (.enabled // true) == true)) | first // null)
  ' <<<"$config_json")

  route_sink_ids_json=$(jq -c --arg category "$category" '
    ((.routing.routes // []) | map(select(.category == $category and (.enabled // true) == true)) | first // null) as $route
    | if $route != null and (($route.sinks // []) | length) > 0 then ($route.sinks)
      else (.routing.defaultSinks // [])
      end
  ' <<<"$config_json")

  min_severity=$(jq -r --arg category "$category" '
    ((.routing.routes // []) | map(select(.category == $category and (.enabled // true) == true)) | first // null) as $route
    | ($route.minSeverity // .defaultMinSeverity // "warning")
  ' <<<"$config_json")

  mapped_category_severity=$(jq -r --arg category "$category" '.routing.categorySeverity[$category] // empty' <<<"$config_json")

  event_severity="$severity"
  if [[ -z "$event_severity" ]]; then
    event_severity="$mapped_category_severity"
  fi
  if [[ -z "$event_severity" ]]; then
    event_severity="$min_severity"
  fi
  if ! severity_rank "$event_severity" >/dev/null; then
    die "resolved event severity is invalid for category '$category': $event_severity"
  fi

  selected_sinks_json=$(jq -c --argjson sink_ids "$route_sink_ids_json" '
    .sinks as $sinks
    | [
        $sink_ids[]? as $sink_id
        | $sinks[$sink_id] as $sink
        | select($sink != null)
        | {
            id: $sink_id,
            type: $sink.type,
            enabled: $sink.enabled,
            timeoutSeconds: ($sink.timeoutSeconds // 5),
            secretRefs: (
              if $sink.type == "webhook" then
                {urlEnv: $sink.urlEnv, authTokenEnv: ($sink.authTokenEnv // null)}
              elif $sink.type == "slack" then
                {webhookUrlEnv: $sink.webhookUrlEnv}
              else
                {routingKeyEnv: $sink.routingKeyEnv}
              end
            ),
            config: (
              if $sink.type == "webhook" then
                {headers: ($sink.headers // {})}
              elif $sink.type == "slack" then
                {
                  channel: ($sink.channel // null),
                  username: ($sink.username // null),
                  iconEmoji: ($sink.iconEmoji // null)
                }
              else
                {
                  source: ($sink.source // "superloop-ops-manager"),
                  component: ($sink.component // null),
                  group: ($sink.group // null),
                  class: ($sink.class // null)
                }
              end
            )
          }
      ]
  ' <<<"$config_json")

  dispatchable_sinks_json=$(jq -c '[.[] | select(.enabled == true)]' <<<"$selected_sinks_json")

  event_severity_rank=$(severity_rank "$event_severity")
  min_severity_rank=$(severity_rank "$min_severity")

  should_dispatch="false"
  if (( event_severity_rank >= min_severity_rank )); then
    should_dispatch="true"
  fi

  resolved_json=$(jq -cn \
    --arg schema_version "v1" \
    --arg source_file "$config_file" \
    --arg category "$category" \
    --arg event_severity "$event_severity" \
    --arg mapped_category_severity "$mapped_category_severity" \
    --arg min_severity "$min_severity" \
    --argjson should_dispatch "$should_dispatch" \
    --argjson route "$route_json" \
    --argjson selected_sinks "$selected_sinks_json" \
    --argjson dispatchable_sinks "$dispatchable_sinks_json" \
    --argjson env_status "$env_status_json" \
    --argjson env_check_enabled "$env_check_enabled" \
    '{
      schemaVersion: $schema_version,
      sourceFile: $source_file,
      category: $category,
      eventSeverity: $event_severity,
      categoryMappedSeverity: (if ($mapped_category_severity | length) > 0 then $mapped_category_severity else null end),
      minSeverity: $min_severity,
      shouldDispatch: $should_dispatch,
      route: $route,
      selectedSinks: $selected_sinks,
      dispatchableSinks: (if $should_dispatch == true then $dispatchable_sinks else [] end),
      envStatus: $env_status,
      validation: {
        envCheckEnabled: $env_check_enabled
      }
    } | with_entries(select(.value != null))')
else
  sinks_resolved_json=$(jq -c '
    .sinks
    | to_entries
    | map({
        id: .key,
        enabled: .value.enabled,
        type: .value.type,
        timeoutSeconds: (.value.timeoutSeconds // 5),
        secretRefs: (
          if .value.type == "webhook" then
            {urlEnv: .value.urlEnv, authTokenEnv: (.value.authTokenEnv // null)}
          elif .value.type == "slack" then
            {webhookUrlEnv: .value.webhookUrlEnv}
          else
            {routingKeyEnv: .value.routingKeyEnv}
          end
        )
      })
  ' <<<"$config_json")

  resolved_json=$(jq -cn \
    --arg schema_version "v1" \
    --arg source_file "$config_file" \
    --argjson root "$config_json" \
    --argjson sinks_resolved "$sinks_resolved_json" \
    --argjson env_status "$env_status_json" \
    --argjson env_check_enabled "$env_check_enabled" \
    '{
      schemaVersion: $schema_version,
      sourceFile: $source_file,
      defaultMinSeverity: $root.defaultMinSeverity,
      sinks: $sinks_resolved,
      enabledSinkCount: (($sinks_resolved | map(select(.enabled == true))) | length),
      routing: ($root.routing // {}),
      envStatus: $env_status,
      validation: {
        envCheckEnabled: $env_check_enabled
      }
    }')
fi

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$resolved_json"
else
  jq -c '.' <<<"$resolved_json"
fi
