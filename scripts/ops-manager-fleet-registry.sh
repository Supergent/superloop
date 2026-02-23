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
  def is_known_policy_category:
    . == "reconcile_failed"
    or . == "health_critical"
    or . == "health_degraded";
  def is_known_policy_intent:
    . == "cancel";
  def is_known_severity:
    . == "critical"
    or . == "warning"
    or . == "info";
  def is_known_confidence:
    . == "high"
    or . == "medium"
    or . == "low";
  def is_valid_iso8601:
    (type == "string")
    and (
      try (fromdateiso8601 | type == "number")
      catch false
    );

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
    if ((.policy.mode // "advisory") == "advisory" or (.policy.mode // "advisory") == "guarded_auto") then []
    else ["policy.mode must be advisory or guarded_auto"]
    end
  )
  + (
    if ((.policy.noiseControls // {}) | type) != "object" then
      ["policy.noiseControls must be an object when present"]
    else
      []
    end
  )
  + (
    if (
      (.policy.noiseControls.dedupeWindowSeconds // null) == null
      or (
        ((.policy.noiseControls.dedupeWindowSeconds // null) | type) == "number"
        and ((.policy.noiseControls.dedupeWindowSeconds // null) >= 0)
        and ((.policy.noiseControls.dedupeWindowSeconds // null) == ((.policy.noiseControls.dedupeWindowSeconds // null) | floor))
      )
    ) then
      []
    else
      ["policy.noiseControls.dedupeWindowSeconds must be an integer >= 0 when present"]
    end
  )
  + (
    if ((.policy.autonomous // {}) | type) != "object" then
      ["policy.autonomous must be an object when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.allow // {}) | type) != "object" then
      ["policy.autonomous.allow must be an object when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.allow.categories // null) == null) then
      []
    elif ((.policy.autonomous.allow.categories // null) | type) != "array" then
      ["policy.autonomous.allow.categories must be an array when present"]
    elif ([.policy.autonomous.allow.categories[] | type] | all(. == "string")) | not then
      ["policy.autonomous.allow.categories entries must be strings"]
    elif ([.policy.autonomous.allow.categories[] | select(is_known_policy_category | not)] | length) > 0 then
      ["policy.autonomous.allow.categories contains unsupported categories"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.allow.intents // null) == null) then
      []
    elif ((.policy.autonomous.allow.intents // null) | type) != "array" then
      ["policy.autonomous.allow.intents must be an array when present"]
    elif ([.policy.autonomous.allow.intents[] | type] | all(. == "string")) | not then
      ["policy.autonomous.allow.intents entries must be strings"]
    elif ([.policy.autonomous.allow.intents[] | select(is_known_policy_intent | not)] | length) > 0 then
      ["policy.autonomous.allow.intents contains unsupported intents"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.thresholds // {}) | type) != "object" then
      ["policy.autonomous.thresholds must be an object when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.thresholds.minSeverity // null) == null) then
      []
    elif ((.policy.autonomous.thresholds.minSeverity // null) | type) != "string" then
      ["policy.autonomous.thresholds.minSeverity must be a string when present"]
    elif ((.policy.autonomous.thresholds.minSeverity // "") | is_known_severity | not) then
      ["policy.autonomous.thresholds.minSeverity must be one of critical, warning, info"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.thresholds.minConfidence // null) == null) then
      []
    elif ((.policy.autonomous.thresholds.minConfidence // null) | type) != "string" then
      ["policy.autonomous.thresholds.minConfidence must be a string when present"]
    elif ((.policy.autonomous.thresholds.minConfidence // "") | is_known_confidence | not) then
      ["policy.autonomous.thresholds.minConfidence must be one of high, medium, low"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.safety // {}) | type) != "object" then
      ["policy.autonomous.safety must be an object when present"]
    else
      []
    end
  )
  + (
    if (
      (.policy.autonomous.safety.maxActionsPerRun // null) == null
      or (
        ((.policy.autonomous.safety.maxActionsPerRun // null) | type) == "number"
        and ((.policy.autonomous.safety.maxActionsPerRun // null) >= 0)
        and ((.policy.autonomous.safety.maxActionsPerRun // null) == ((.policy.autonomous.safety.maxActionsPerRun // null) | floor))
      )
    ) then
      []
    else
      ["policy.autonomous.safety.maxActionsPerRun must be an integer >= 0 when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.safety.maxActionsPerLoop // null) == null
      or (
        ((.policy.autonomous.safety.maxActionsPerLoop // null) | type) == "number"
        and ((.policy.autonomous.safety.maxActionsPerLoop // null) >= 0)
        and ((.policy.autonomous.safety.maxActionsPerLoop // null) == ((.policy.autonomous.safety.maxActionsPerLoop // null) | floor))
      )
    ) then
      []
    else
      ["policy.autonomous.safety.maxActionsPerLoop must be an integer >= 0 when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.safety.cooldownSeconds // null) == null
      or (
        ((.policy.autonomous.safety.cooldownSeconds // null) | type) == "number"
        and ((.policy.autonomous.safety.cooldownSeconds // null) >= 0)
        and ((.policy.autonomous.safety.cooldownSeconds // null) == ((.policy.autonomous.safety.cooldownSeconds // null) | floor))
      )
    ) then
      []
    else
      ["policy.autonomous.safety.cooldownSeconds must be an integer >= 0 when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.safety.killSwitch // null) == null
      or ((.policy.autonomous.safety.killSwitch // null) | type) == "boolean"
    ) then
      []
    else
      ["policy.autonomous.safety.killSwitch must be boolean when present"]
    end
  )
  + (
    if ((.policy.autonomous.governance // {}) | type) != "object" then
      ["policy.autonomous.governance must be an object when present"]
    else
      []
    end
  )
  + (
    if (
      (.policy.autonomous.governance.actor // null) == null
      or ((.policy.autonomous.governance.actor // null) | is_non_empty_string)
    ) then
      []
    else
      ["policy.autonomous.governance.actor must be a non-empty string when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.governance.approvalRef // null) == null
      or ((.policy.autonomous.governance.approvalRef // null) | is_non_empty_string)
    ) then
      []
    else
      ["policy.autonomous.governance.approvalRef must be a non-empty string when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.governance.rationale // null) == null
      or ((.policy.autonomous.governance.rationale // null) | is_non_empty_string)
    ) then
      []
    else
      ["policy.autonomous.governance.rationale must be a non-empty string when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.governance.changedAt // null) == null
      or ((.policy.autonomous.governance.changedAt // null) | is_valid_iso8601)
    ) then
      []
    else
      ["policy.autonomous.governance.changedAt must be an ISO-8601 timestamp when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.governance.reviewBy // null) == null
      or ((.policy.autonomous.governance.reviewBy // null) | is_valid_iso8601)
    ) then
      []
    else
      ["policy.autonomous.governance.reviewBy must be an ISO-8601 timestamp when present"]
    end
  )
  + (
    if (
      ((.policy.autonomous.governance.changedAt // null) | is_valid_iso8601)
      and ((.policy.autonomous.governance.reviewBy // null) | is_valid_iso8601)
      and ((.policy.autonomous.governance.reviewBy | fromdateiso8601) <= (.policy.autonomous.governance.changedAt | fromdateiso8601))
    ) then
      ["policy.autonomous.governance.reviewBy must be after policy.autonomous.governance.changedAt"]
    else
      []
    end
  )
  + (
    if ((.policy.mode // "advisory") != "guarded_auto") then
      []
    else
      (.policy.autonomous.governance // null) as $gov
      | (if ($gov | type) == "object" then $gov else {} end) as $gov_obj
      | [
          if ($gov | type) != "object" then
            "policy.autonomous.governance is required when policy.mode is guarded_auto"
          else
            empty
          end,
          if ((($gov_obj.actor // null) | is_non_empty_string) | not) then
            "policy.autonomous.governance.actor is required when policy.mode is guarded_auto"
          else
            empty
          end,
          if ((($gov_obj.approvalRef // null) | is_non_empty_string) | not) then
            "policy.autonomous.governance.approvalRef is required when policy.mode is guarded_auto"
          else
            empty
          end,
          if ((($gov_obj.rationale // null) | is_non_empty_string) | not) then
            "policy.autonomous.governance.rationale is required when policy.mode is guarded_auto"
          else
            empty
          end,
          if ((($gov_obj.changedAt // null) | is_valid_iso8601) | not) then
            "policy.autonomous.governance.changedAt must be an ISO-8601 timestamp when policy.mode is guarded_auto"
          else
            empty
          end,
          if ((($gov_obj.reviewBy // null) | is_valid_iso8601) | not) then
            "policy.autonomous.governance.reviewBy must be an ISO-8601 timestamp when policy.mode is guarded_auto"
          else
            empty
          end,
          if (
            (($gov_obj.changedAt // null) | is_valid_iso8601)
            and (($gov_obj.reviewBy // null) | is_valid_iso8601)
            and (($gov_obj.reviewBy | fromdateiso8601) <= ($gov_obj.changedAt | fromdateiso8601))
          ) then
            "policy.autonomous.governance.reviewBy must be after policy.autonomous.governance.changedAt when policy.mode is guarded_auto"
          else
            empty
          end,
          if (
            (($gov_obj.reviewBy // null) | is_valid_iso8601)
            and (($gov_obj.reviewBy | fromdateiso8601) <= now)
          ) then
            "policy.autonomous.governance.reviewBy must be in the future when policy.mode is guarded_auto"
          else
            empty
          end
        ]
    end
  )
  + (
    if ((.policy.autonomous.rollout // {}) | type) != "object" then
      ["policy.autonomous.rollout must be an object when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.rollout.canaryPercent // null) == null) then
      []
    elif (
      ((.policy.autonomous.rollout.canaryPercent // null) | type) != "number"
      or ((.policy.autonomous.rollout.canaryPercent // null) != ((.policy.autonomous.rollout.canaryPercent // null) | floor))
      or ((.policy.autonomous.rollout.canaryPercent // null) < 0)
      or ((.policy.autonomous.rollout.canaryPercent // null) > 100)
    ) then
      ["policy.autonomous.rollout.canaryPercent must be an integer between 0 and 100 when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.rollout.scope // {}) | type) != "object" then
      ["policy.autonomous.rollout.scope must be an object when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.rollout.scope.loopIds // null) == null) then
      []
    elif ((.policy.autonomous.rollout.scope.loopIds // null) | type) != "array" then
      ["policy.autonomous.rollout.scope.loopIds must be an array when present"]
    elif ([.policy.autonomous.rollout.scope.loopIds[] | type] | all(. == "string")) | not then
      ["policy.autonomous.rollout.scope.loopIds entries must be strings"]
    elif ([.policy.autonomous.rollout.scope.loopIds[] | select(length == 0)] | length) > 0 then
      ["policy.autonomous.rollout.scope.loopIds entries must be non-empty strings"]
    elif ((.policy.autonomous.rollout.scope.loopIds | length) != ((.policy.autonomous.rollout.scope.loopIds | unique) | length)) then
      ["policy.autonomous.rollout.scope.loopIds entries must be unique"]
    else
      (
        (.loops // []) as $loops
        | ([ $loops[]? | .loopId // empty ] | map(select(type == "string" and length > 0)) | unique) as $declared_loop_ids
        | (
            [
              .policy.autonomous.rollout.scope.loopIds[] as $scope_loop_id
              | select(($declared_loop_ids | index($scope_loop_id)) == null)
            ]
            | if (length) > 0 then
                ["policy.autonomous.rollout.scope.loopIds entries must reference declared loopIds"]
              else
                []
              end
          )
      )
    end
  )
  + (
    if ((.policy.autonomous.rollout.selector // {}) | type) != "object" then
      ["policy.autonomous.rollout.selector must be an object when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.rollout.selector.salt // null) == null) then
      []
    elif ((.policy.autonomous.rollout.selector.salt // null) | type) != "string" then
      ["policy.autonomous.rollout.selector.salt must be a string when present"]
    elif ((.policy.autonomous.rollout.selector.salt // "") | length) == 0 then
      ["policy.autonomous.rollout.selector.salt must be non-empty when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.rollout.pause // {}) | type) != "object" then
      ["policy.autonomous.rollout.pause must be an object when present"]
    else
      []
    end
  )
  + (
    if (
      (.policy.autonomous.rollout.pause.manual // null) == null
      or ((.policy.autonomous.rollout.pause.manual // null) | type) == "boolean"
    ) then
      []
    else
      ["policy.autonomous.rollout.pause.manual must be boolean when present"]
    end
  )
  + (
    if ((.policy.autonomous.rollout.autoPause // {}) | type) != "object" then
      ["policy.autonomous.rollout.autoPause must be an object when present"]
    else
      []
    end
  )
  + (
    if (
      (.policy.autonomous.rollout.autoPause.enabled // null) == null
      or ((.policy.autonomous.rollout.autoPause.enabled // null) | type) == "boolean"
    ) then
      []
    else
      ["policy.autonomous.rollout.autoPause.enabled must be boolean when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.rollout.autoPause.lookbackExecutions // null) == null
      or (
        ((.policy.autonomous.rollout.autoPause.lookbackExecutions // null) | type) == "number"
        and ((.policy.autonomous.rollout.autoPause.lookbackExecutions // null) >= 1)
        and ((.policy.autonomous.rollout.autoPause.lookbackExecutions // null) == ((.policy.autonomous.rollout.autoPause.lookbackExecutions // null) | floor))
      )
    ) then
      []
    else
      ["policy.autonomous.rollout.autoPause.lookbackExecutions must be an integer >= 1 when present"]
    end
  )
  + (
    if (
      (.policy.autonomous.rollout.autoPause.minSampleSize // null) == null
      or (
        ((.policy.autonomous.rollout.autoPause.minSampleSize // null) | type) == "number"
        and ((.policy.autonomous.rollout.autoPause.minSampleSize // null) >= 1)
        and ((.policy.autonomous.rollout.autoPause.minSampleSize // null) == ((.policy.autonomous.rollout.autoPause.minSampleSize // null) | floor))
      )
    ) then
      []
    else
      ["policy.autonomous.rollout.autoPause.minSampleSize must be an integer >= 1 when present"]
    end
  )
  + (
    if ((.policy.autonomous.rollout.autoPause.ambiguityRateThreshold // null) == null) then
      []
    elif (
      ((.policy.autonomous.rollout.autoPause.ambiguityRateThreshold // null) | type) != "number"
      or ((.policy.autonomous.rollout.autoPause.ambiguityRateThreshold // null) < 0)
      or ((.policy.autonomous.rollout.autoPause.ambiguityRateThreshold // null) > 1)
    ) then
      ["policy.autonomous.rollout.autoPause.ambiguityRateThreshold must be a number between 0 and 1 when present"]
    else
      []
    end
  )
  + (
    if ((.policy.autonomous.rollout.autoPause.failureRateThreshold // null) == null) then
      []
    elif (
      ((.policy.autonomous.rollout.autoPause.failureRateThreshold // null) | type) != "number"
      or ((.policy.autonomous.rollout.autoPause.failureRateThreshold // null) < 0)
      or ((.policy.autonomous.rollout.autoPause.failureRateThreshold // null) > 1)
    ) then
      ["policy.autonomous.rollout.autoPause.failureRateThreshold must be a number between 0 and 1 when present"]
    else
      []
    end
  )
  + (
    if ((.policy.suppressions // {}) | type) != "object" then
      ["policy.suppressions must be an object mapping loopId to category arrays"]
    else
      (
        (.loops // []) as $loops
        | ([ $loops[]? | .loopId // empty ] | map(select(type == "string" and length > 0)) | unique) as $declared_loop_ids
        | [ (.policy.suppressions // {}) | to_entries[]?
            | .key as $supp_key
            | if ($supp_key != "*" and (($declared_loop_ids | index($supp_key)) == null)) then
                "policy.suppressions.\($supp_key) key must reference a declared loopId or *"
              elif (.value | type) != "array" then
                "policy.suppressions.\($supp_key) must be an array"
              elif ([.value[] | type] | all(. == "string")) | not then
                "policy.suppressions.\($supp_key) entries must be strings"
              elif ([.value[] | select(is_known_policy_category | not)] | length) > 0 then
                "policy.suppressions.\($supp_key) contains unknown categories"
              else
                empty
              end
          ]
      )
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
        suppressions: ($registry.policy.suppressions // {}),
        noiseControls: {
          dedupeWindowSeconds: ($registry.policy.noiseControls.dedupeWindowSeconds // 300)
        },
        autonomous: {
          enabled: (($registry.policy.mode // "advisory") == "guarded_auto"),
          allow: {
            categories: ($registry.policy.autonomous.allow.categories // ["reconcile_failed", "health_critical"]),
            intents: ($registry.policy.autonomous.allow.intents // ["cancel"])
          },
          thresholds: {
            minSeverity: ($registry.policy.autonomous.thresholds.minSeverity // "critical"),
            minConfidence: ($registry.policy.autonomous.thresholds.minConfidence // "high")
          },
          safety: {
            maxActionsPerRun: ($registry.policy.autonomous.safety.maxActionsPerRun // 1),
            maxActionsPerLoop: ($registry.policy.autonomous.safety.maxActionsPerLoop // 1),
            cooldownSeconds: ($registry.policy.autonomous.safety.cooldownSeconds // 300),
            killSwitch: ($registry.policy.autonomous.safety.killSwitch // false)
          },
          governance: (
            {
              actor: ($registry.policy.autonomous.governance.actor // null),
              approvalRef: ($registry.policy.autonomous.governance.approvalRef // null),
              rationale: ($registry.policy.autonomous.governance.rationale // null),
              changedAt: ($registry.policy.autonomous.governance.changedAt // null),
              reviewBy: ($registry.policy.autonomous.governance.reviewBy // null)
            }
            | .reviewWindowDays = (
                if (.changedAt // null) == null or (.reviewBy // null) == null then
                  null
                else
                  (((.reviewBy | fromdateiso8601) - (.changedAt | fromdateiso8601)) / 86400 | floor)
                end
              )
            | with_entries(select(.value != null))
          ),
          rollout: {
            canaryPercent: ($registry.policy.autonomous.rollout.canaryPercent // 100),
            scope: {
              loopIds: ($registry.policy.autonomous.rollout.scope.loopIds // [])
            },
            selector: {
              salt: ($registry.policy.autonomous.rollout.selector.salt // "fleet-autonomous-rollout-v1")
            },
            pause: {
              manual: ($registry.policy.autonomous.rollout.pause.manual // false)
            },
            autoPause: {
              enabled: ($registry.policy.autonomous.rollout.autoPause.enabled // true),
              lookbackExecutions: ($registry.policy.autonomous.rollout.autoPause.lookbackExecutions // 5),
              minSampleSize: ($registry.policy.autonomous.rollout.autoPause.minSampleSize // 3),
              ambiguityRateThreshold: ($registry.policy.autonomous.rollout.autoPause.ambiguityRateThreshold // 0.4),
              failureRateThreshold: ($registry.policy.autonomous.rollout.autoPause.failureRateThreshold // 0.4)
            }
          }
        }
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
