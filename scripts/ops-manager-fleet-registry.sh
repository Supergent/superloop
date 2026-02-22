#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/ops-manager-fleet-registry.sh --repo <path> [options]

Options:
  --registry-file <path>  Fleet registry JSON path. Default: <repo>/.superloop/ops-manager/fleet/registry.v1.json
  --loop <id>             Filter output to a single loop id.
  --pretty                Pretty-print output JSON.
  --help                  Show this help message.
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

repo=""
registry_file=""
loop_id=""
pretty="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --registry-file)
      registry_file="${2:-}"
      shift 2
      ;;
    --loop)
      loop_id="${2:-}"
      shift 2
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

if [[ -z "$repo" ]]; then
  die "--repo is required"
fi

repo="$(cd "$repo" && pwd)"
if [[ -z "$registry_file" ]]; then
  registry_file="$repo/.superloop/ops-manager/fleet/registry.v1.json"
fi

if [[ ! -f "$registry_file" ]]; then
  die "fleet registry file not found: $registry_file"
fi

registry_raw=$(jq -c '.' "$registry_file" 2>/dev/null) || die "invalid fleet registry JSON: $registry_file"

validation_errors=$(jq -r '
  def is_non_empty_string: (type == "string" and (.|length) > 0);
  def loop_error($idx; $msg): "loops[\($idx)]: \($msg)";

  (
    if (.schemaVersion // "") != "v1" then ["schemaVersion must be \"v1\""] else [] end
  )
  + (
    if ((.fleetId // "default") | type) != "string" then ["fleetId must be a string when present"] else [] end
  )
  + (
    if (.loops | type) != "array" then ["loops must be an array"] else [] end
  )
  + (
    if (.loops | type) == "array" and (.loops | length) == 0 then ["loops must include at least one loop entry"] else [] end
  )
  + (
    if (.loops | type) != "array" then []
    else
      [.loops[]?] as $loops
      | ( [ $loops[] | .loopId // null ] | map(select(type == "string")) ) as $loop_ids
      | (
          if (($loop_ids | length) != (($loop_ids | unique) | length)) then
            ["loopId values must be unique"]
          else
            []
          end
        )
      + (
          [ range(0; $loops|length) as $i
            | ($loops[$i]) as $loop
            | (
                if ($loop | type) != "object" then
                  [loop_error($i; "entry must be an object")]
                else
                  []
                end
              )
            + (
                if (($loop.loopId // null) | is_non_empty_string) then []
                else [loop_error($i; "loopId must be a non-empty string")]
                end
              )
            + (
                if ($loop.enabled == null or ($loop.enabled | type) == "boolean") then []
                else [loop_error($i; "enabled must be boolean when present")]
                end
              )
            + (
                ($loop.transport // "local") as $transport
                | if ($transport == "local" or $transport == "sprite_service") then []
                  else [loop_error($i; "transport must be local or sprite_service")]
                  end
              )
            + (
                if (($loop.sprite // null) == null or ($loop.sprite | type) == "object") then []
                else [loop_error($i; "sprite must be an object when present")]
                end
              )
            + (
                if (($loop.sprite.id // null) == null or (($loop.sprite.id // null) | is_non_empty_string)) then []
                else [loop_error($i; "sprite.id must be a non-empty string when present")]
                end
              )
            + (
                if (($loop.service // null) == null or ($loop.service | type) == "object") then []
                else [loop_error($i; "service must be an object when present")]
                end
              )
            + (
                if (($loop.service.tokenEnv // null) == null or (($loop.service.tokenEnv // null) | is_non_empty_string)) then []
                else [loop_error($i; "service.tokenEnv must be a non-empty string when present")]
                end
              )
            + (
                if (($loop.service.retryAttempts // null) == null or ((($loop.service.retryAttempts // null) | type) == "number" and ($loop.service.retryAttempts >= 1))) then []
                else [loop_error($i; "service.retryAttempts must be >= 1 when present")]
                end
              )
            + (
                if (($loop.service.retryBackoffSeconds // null) == null or ((($loop.service.retryBackoffSeconds // null) | type) == "number" and ($loop.service.retryBackoffSeconds >= 0))) then []
                else [loop_error($i; "service.retryBackoffSeconds must be >= 0 when present")]
                end
              )
            + (
                ($loop.transport // "local") as $transport
                | if $transport != "sprite_service" then []
                  else
                    ($loop.service.baseUrl // $loop.sprite.serviceBaseUrl // "") as $base_url
                    | if ($base_url | is_non_empty_string) then []
                      else [loop_error($i; "sprite_service loops require service.baseUrl or sprite.serviceBaseUrl")]
                      end
                  end
              )
            + (
                if (($loop.metadata // null) == null or ($loop.metadata | type) == "object") then []
                else [loop_error($i; "metadata must be an object when present")]
                end
              )
          ] | add
        )
    end
  )
  + (
    if ((.policy // null) == null or (.policy | type) == "object") then []
    else ["policy must be an object when present"]
    end
  )
  + (
    if ((.policy.mode // "advisory") == "advisory") then []
    else ["policy.mode must be \"advisory\" in phase 8 baseline"]
    end
  )
  + (
    if ((.policy.suppressions // {}) | type) != "object" then
      ["policy.suppressions must be an object mapping loopId to category arrays"]
    else
      [ (.policy.suppressions // {}) | to_entries[]?
        | if (.value | type) != "array" then
            "policy.suppressions.\(.key) must be an array"
          elif ([.value[] | type] | all(. == "string")) then
            empty
          else
            "policy.suppressions.\(.key) entries must be strings"
          end
      ]
    end
  )
  | .[]
' <<<"$registry_raw")

if [[ -n "$validation_errors" ]]; then
  printf 'error: invalid fleet registry: %s\n' "$registry_file" >&2
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf ' - %s\n' "$line" >&2
  done <<<"$validation_errors"
  exit 1
fi

normalized_json=$(jq -cn \
  --arg source_file "$registry_file" \
  --argjson registry "$registry_raw" \
  --arg loop_filter "$loop_id" \
  '
  ($registry.loops // []) as $raw_loops
  | {
      schemaVersion: "v1",
      sourceFile: $source_file,
      fleetId: ($registry.fleetId // "default"),
      loops: (
        $raw_loops
        | map({
            loopId: .loopId,
            enabled: (.enabled // true),
            transport: (.transport // "local"),
            sprite: ({
              id: (.sprite.id // null),
              assignment: (.sprite.assignment // null),
              serviceBaseUrl: (.sprite.serviceBaseUrl // .service.baseUrl // null)
            } | with_entries(select(.value != null))),
            service: ({
              baseUrl: (.service.baseUrl // .sprite.serviceBaseUrl // null),
              tokenEnv: (.service.tokenEnv // null),
              retryAttempts: (.service.retryAttempts // 3),
              retryBackoffSeconds: (.service.retryBackoffSeconds // 1)
            } | with_entries(select(.value != null))),
            metadata: (.metadata // {})
          })
        | if ($loop_filter | length) > 0 then map(select(.loopId == $loop_filter)) else . end
      ),
      policy: {
        mode: ($registry.policy.mode // "advisory"),
        suppressions: ($registry.policy.suppressions // {})
      }
    }
  | .loopCount = (.loops | length)
  | if ($loop_filter | length) > 0 and .loopCount == 0 then
      error("loop not found in registry: " + $loop_filter)
    else
      .
    end
  ')

if [[ "$pretty" == "1" ]]; then
  jq '.' <<<"$normalized_json"
else
  jq -c '.' <<<"$normalized_json"
fi
