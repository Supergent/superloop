select_python() {
  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    echo "python"
    return 0
  fi
  return 1
}

validate_cmd() {
  local repo="$1"
  local config_path="$2"
  local schema_path="$3"
  local static_only="${4:-0}"

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi
  if [[ ! -f "$schema_path" ]]; then
    die "schema not found: $schema_path"
  fi

  local python_bin=""
  python_bin=$(select_python || true)
  if [[ -z "$python_bin" ]]; then
    die "missing python3/python for schema validation"
  fi

  # Run schema validation first
  "$python_bin" - "$schema_path" "$config_path" <<'PY'
import json
import sys


def error(message, path):
    sys.stderr.write("schema validation error at {}: {}\n".format(path, message))
    return False


def is_integer(value):
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value):
    return (isinstance(value, int) or isinstance(value, float)) and not isinstance(value, bool)


def validate(instance, schema, path):
    if "enum" in schema:
        if instance not in schema["enum"]:
            return error("expected one of {}".format(schema["enum"]), path)

    schema_type = schema.get("type")
    if schema_type == "object":
        if not isinstance(instance, dict):
            return error("expected object", path)
        props = schema.get("properties", {})
        required = schema.get("required", [])
        for key in required:
            if key not in instance:
                return error("missing required property '{}'".format(key), "{}.{}".format(path, key))
        additional = schema.get("additionalProperties", True)
        for key, value in instance.items():
            if key in props:
                if not validate(value, props[key], "{}.{}".format(path, key)):
                    return False
            else:
                if additional is False:
                    return error("unexpected property '{}'".format(key), "{}.{}".format(path, key))
                if isinstance(additional, dict):
                    if not validate(value, additional, "{}.{}".format(path, key)):
                        return False
        return True

    if schema_type == "array":
        if not isinstance(instance, list):
            return error("expected array", path)
        if "minItems" in schema and len(instance) < schema["minItems"]:
            return error("expected at least {} items".format(schema["minItems"]), path)
        item_schema = schema.get("items")
        if item_schema is not None:
            for index, item in enumerate(instance):
                if not validate(item, item_schema, "{}[{}]".format(path, index)):
                    return False
        return True

    if schema_type == "string":
        if not isinstance(instance, str):
            return error("expected string", path)
        return True

    if schema_type == "integer":
        if not is_integer(instance):
            return error("expected integer", path)
        return True

    if schema_type == "number":
        if not is_number(instance):
            return error("expected number", path)
        return True

    if schema_type == "boolean":
        if not isinstance(instance, bool):
            return error("expected boolean", path)
        return True

    return True


def load_json(path):
    with open(path, "r") as handle:
        return json.load(handle)


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("usage: validate <schema> <config>\n")
        return 2
    schema_path = sys.argv[1]
    config_path = sys.argv[2]
    try:
        schema = load_json(schema_path)
    except Exception as exc:
        sys.stderr.write("error: failed to read schema {}: {}\n".format(schema_path, exc))
        return 1
    try:
        config = load_json(config_path)
    except Exception as exc:
        sys.stderr.write("error: failed to read config {}: {}\n".format(config_path, exc))
        return 1

    if not validate(config, schema, "$"):
        return 1
    print("ok: config matches schema")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
  local schema_rc=$?
  if [[ $schema_rc -ne 0 ]]; then
    return 1
  fi

  local probe_mode="${5:-0}"

  # Run static validation if requested (--static or --probe)
  if [[ "$static_only" == "1" || "$static_only" == "--static" || "$probe_mode" == "1" ]]; then
    echo ""
    echo "Running static analysis..."
    if ! validate_static "$repo" "$config_path"; then
      return 1
    fi
    echo "ok: static analysis passed"
  fi

  # Run probe validation if requested (--probe)
  if [[ "$probe_mode" == "1" ]]; then
    echo ""
    echo "Running probe validation (this may take a moment)..."
    if ! validate_probe "$repo" "$config_path"; then
      return 1
    fi
    echo "ok: probe validation passed"
  fi
}

report_cmd() {
  local repo="$1"
  local config_path="$2"
  local loop_id="$3"
  local out_path="$4"

  need_cmd jq

  if [[ ! -f "$config_path" ]]; then
    die "config not found: $config_path"
  fi

  if [[ -z "$loop_id" ]]; then
    loop_id=$(jq -r '.loops[0].id // ""' "$config_path")
    if [[ -z "$loop_id" || "$loop_id" == "null" ]]; then
      die "loop id not found in config"
    fi
  else
    local match
    match=$(jq -r --arg id "$loop_id" '.loops[]? | select(.id == $id) | .id' "$config_path" | head -n1)
    if [[ -z "$match" ]]; then
      die "loop id not found: $loop_id"
    fi
  fi

  local loop_dir="$repo/.superloop/loops/$loop_id"
  local summary_file="$loop_dir/run-summary.json"
  local timeline_file="$loop_dir/timeline.md"
  local events_file="$loop_dir/events.jsonl"
  local gate_summary="$loop_dir/gate-summary.txt"
  local evidence_file="$loop_dir/evidence.json"
  local reviewer_packet="$loop_dir/reviewer-packet.md"
  local approval_file="$loop_dir/approval.json"
  local decisions_md="$loop_dir/decisions.md"
  local decisions_jsonl="$loop_dir/decisions.jsonl"
  local usage_file="$loop_dir/usage.jsonl"
  local report_file="$out_path"
  if [[ -z "$report_file" ]]; then
    report_file="$loop_dir/report.html"
  fi

  local python_bin=""
  python_bin=$(select_python || true)
  if [[ -z "$python_bin" ]]; then
    die "missing python3/python for report generation"
  fi

  "$python_bin" - "$loop_id" "$summary_file" "$timeline_file" "$events_file" "$gate_summary" "$evidence_file" "$reviewer_packet" "$approval_file" "$decisions_md" "$decisions_jsonl" "$usage_file" "$report_file" <<'PY'
import datetime
import html
import json
import os
import sys


def read_text(path):
    if not path or not os.path.exists(path):
        return ""
    with open(path, "r") as handle:
        return handle.read()


def read_json(path):
    if not path or not os.path.exists(path):
        return None
    try:
        with open(path, "r") as handle:
            return json.load(handle)
    except Exception as exc:
        return {"_error": str(exc)}


def escape_block(text):
    return html.escape(text or "")


def json_block(value):
    if value is None:
        return ""
    try:
        return json.dumps(value, indent=2, sort_keys=True)
    except Exception:
        return str(value)


def read_jsonl(path):
    if not path or not os.path.exists(path):
        return []
    entries = []
    with open(path, "r") as handle:
        for line in handle:
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except Exception:
                    pass
    return entries


def aggregate_usage(entries):
    totals = {
        "input_tokens": 0,
        "output_tokens": 0,
        "thinking_tokens": 0,
        "reasoning_output_tokens": 0,
        "cached_input_tokens": 0,
        "cache_read_input_tokens": 0,
        "cache_creation_input_tokens": 0,
        "total_cost_usd": 0.0,
        "total_duration_ms": 0,
    }
    by_role = {}
    by_runner = {}

    for entry in entries:
        usage = entry.get("usage", {})
        cost = entry.get("cost_usd", 0) or 0
        duration = entry.get("duration_ms", 0) or 0
        role = entry.get("role", "unknown")
        runner = entry.get("runner", "unknown")

        totals["input_tokens"] += usage.get("input_tokens", 0) or 0
        totals["output_tokens"] += usage.get("output_tokens", 0) or 0
        totals["thinking_tokens"] += usage.get("thinking_tokens", 0) or 0
        totals["reasoning_output_tokens"] += usage.get("reasoning_output_tokens", 0) or 0
        totals["cached_input_tokens"] += usage.get("cached_input_tokens", 0) or 0
        totals["cache_read_input_tokens"] += usage.get("cache_read_input_tokens", 0) or 0
        totals["cache_creation_input_tokens"] += usage.get("cache_creation_input_tokens", 0) or 0
        totals["total_cost_usd"] += cost
        totals["total_duration_ms"] += duration

        if role not in by_role:
            by_role[role] = {"cost_usd": 0.0, "duration_ms": 0, "count": 0}
        by_role[role]["cost_usd"] += cost
        by_role[role]["duration_ms"] += duration
        by_role[role]["count"] += 1

        if runner not in by_runner:
            by_runner[runner] = {"cost_usd": 0.0, "count": 0}
        by_runner[runner]["cost_usd"] += cost
        by_runner[runner]["count"] += 1

    return totals, by_role, by_runner


def format_duration(ms):
    if ms < 1000:
        return "{}ms".format(ms)
    secs = ms / 1000
    if secs < 60:
        return "{:.1f}s".format(secs)
    mins = secs / 60
    if mins < 60:
        return "{:.1f}m".format(mins)
    hours = mins / 60
    return "{:.1f}h".format(hours)


def format_tokens(n):
    if n >= 1000000:
        return "{:.1f}M".format(n / 1000000)
    if n >= 1000:
        return "{:.1f}K".format(n / 1000)
    return str(n)


loop_id = sys.argv[1]
summary_path = sys.argv[2]
timeline_path = sys.argv[3]
events_path = sys.argv[4]
gate_path = sys.argv[5]
evidence_path = sys.argv[6]
reviewer_packet_path = sys.argv[7]
approval_path = sys.argv[8]
decisions_md_path = sys.argv[9]
decisions_jsonl_path = sys.argv[10]
usage_path = sys.argv[11]
out_path = sys.argv[12]

summary = read_json(summary_path)
timeline = read_text(timeline_path)
gate_summary = read_text(gate_path).strip()
evidence = read_json(evidence_path)
reviewer_packet = read_text(reviewer_packet_path).strip()
approval = read_json(approval_path)
decisions_md = read_text(decisions_md_path).strip()
decisions_jsonl = read_text(decisions_jsonl_path).strip()
usage_entries = read_jsonl(usage_path)
usage_totals, usage_by_role, usage_by_runner = aggregate_usage(usage_entries)

events_lines = []
if os.path.exists(events_path):
    with open(events_path, "r") as handle:
        events_lines = handle.read().splitlines()

latest_entry = None
if isinstance(summary, dict):
    entries = summary.get("entries") or []
    if entries:
        latest_entry = entries[-1]

generated_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

sections = []

overview = [
    "<div class='meta'>",
    "<div><strong>Loop:</strong> {}</div>".format(html.escape(loop_id)),
    "<div><strong>Generated:</strong> {}</div>".format(html.escape(generated_at)),
    "<div><strong>Summary file:</strong> {}</div>".format(html.escape(summary_path)),
    "</div>",
]
sections.append("<h2>Overview</h2>" + "".join(overview))

# Usage & Cost section
if usage_entries:
    usage_html = ["<div class='usage-grid'>"]

    # Summary row
    usage_html.append("<div class='usage-summary'>")
    usage_html.append("<div class='usage-stat'><span class='label'>Total Cost</span><span class='value'>${:.4f}</span></div>".format(usage_totals["total_cost_usd"]))
    usage_html.append("<div class='usage-stat'><span class='label'>Duration</span><span class='value'>{}</span></div>".format(format_duration(usage_totals["total_duration_ms"])))
    usage_html.append("<div class='usage-stat'><span class='label'>Iterations</span><span class='value'>{}</span></div>".format(len(usage_entries)))
    usage_html.append("</div>")

    # Token breakdown
    usage_html.append("<h3>Token Usage</h3>")
    usage_html.append("<table class='usage-table'>")
    usage_html.append("<tr><th>Type</th><th>Count</th></tr>")
    usage_html.append("<tr><td>Input Tokens</td><td>{}</td></tr>".format(format_tokens(usage_totals["input_tokens"])))
    usage_html.append("<tr><td>Output Tokens</td><td>{}</td></tr>".format(format_tokens(usage_totals["output_tokens"])))
    if usage_totals["thinking_tokens"] > 0:
        usage_html.append("<tr><td>Thinking Tokens (Claude)</td><td>{}</td></tr>".format(format_tokens(usage_totals["thinking_tokens"])))
    if usage_totals["reasoning_output_tokens"] > 0:
        usage_html.append("<tr><td>Reasoning Tokens (Codex)</td><td>{}</td></tr>".format(format_tokens(usage_totals["reasoning_output_tokens"])))
    cache_tokens = usage_totals["cached_input_tokens"] + usage_totals["cache_read_input_tokens"]
    if cache_tokens > 0:
        usage_html.append("<tr><td>Cache Read Tokens</td><td>{}</td></tr>".format(format_tokens(cache_tokens)))
    if usage_totals["cache_creation_input_tokens"] > 0:
        usage_html.append("<tr><td>Cache Write Tokens</td><td>{}</td></tr>".format(format_tokens(usage_totals["cache_creation_input_tokens"])))
    usage_html.append("</table>")

    # Cost by role
    if usage_by_role:
        usage_html.append("<h3>Cost by Role</h3>")
        usage_html.append("<table class='usage-table'>")
        usage_html.append("<tr><th>Role</th><th>Runs</th><th>Duration</th><th>Cost</th></tr>")
        for role in ["planner", "implementer", "tester", "reviewer"]:
            if role in usage_by_role:
                r = usage_by_role[role]
                usage_html.append("<tr><td>{}</td><td>{}</td><td>{}</td><td>${:.4f}</td></tr>".format(
                    role.capitalize(), r["count"], format_duration(r["duration_ms"]), r["cost_usd"]))
        usage_html.append("</table>")

    # Cost by runner
    if usage_by_runner:
        usage_html.append("<h3>Cost by Runner</h3>")
        usage_html.append("<table class='usage-table'>")
        usage_html.append("<tr><th>Runner</th><th>Runs</th><th>Cost</th></tr>")
        for runner, r in sorted(usage_by_runner.items()):
            usage_html.append("<tr><td>{}</td><td>{}</td><td>${:.4f}</td></tr>".format(
                runner.capitalize(), r["count"], r["cost_usd"]))
        usage_html.append("</table>")

    usage_html.append("</div>")
    sections.append("<h2>Usage &amp; Cost</h2>" + "\n".join(usage_html))
else:
    sections.append("<h2>Usage &amp; Cost</h2><p>No usage data found.</p>")

if gate_summary:
    sections.append("<h2>Gate Summary</h2><pre>{}</pre>".format(escape_block(gate_summary)))
else:
    sections.append("<h2>Gate Summary</h2><p>No gate summary found.</p>")

if latest_entry is not None:
    sections.append("<h2>Latest Iteration</h2><pre>{}</pre>".format(escape_block(json_block(latest_entry))))
else:
    sections.append("<h2>Latest Iteration</h2><p>No run summary entries found.</p>")

if timeline:
    sections.append("<h2>Timeline</h2><pre>{}</pre>".format(escape_block(timeline)))
else:
    sections.append("<h2>Timeline</h2><p>No timeline found.</p>")

if events_lines:
    tail = events_lines[-40:]
    sections.append("<h2>Recent Events</h2><pre>{}</pre>".format(escape_block("\n".join(tail))))
else:
    sections.append("<h2>Recent Events</h2><p>No events found.</p>")

if evidence is not None:
    sections.append("<h2>Evidence Manifest</h2><pre>{}</pre>".format(escape_block(json_block(evidence))))
else:
    sections.append("<h2>Evidence Manifest</h2><p>No evidence manifest found.</p>")

if reviewer_packet:
    sections.append("<h2>Reviewer Packet</h2><pre>{}</pre>".format(escape_block(reviewer_packet)))
else:
    sections.append("<h2>Reviewer Packet</h2><p>No reviewer packet found.</p>")

if approval is not None:
    sections.append("<h2>Approval Request</h2><pre>{}</pre>".format(escape_block(json_block(approval))))
else:
    sections.append("<h2>Approval Request</h2><p>No approval request found.</p>")

if decisions_md:
    sections.append("<h2>Decisions</h2><pre>{}</pre>".format(escape_block(decisions_md)))
elif decisions_jsonl:
    sections.append("<h2>Decisions</h2><pre>{}</pre>".format(escape_block(decisions_jsonl)))
else:
    sections.append("<h2>Decisions</h2><p>No decisions found.</p>")

html_doc = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Supergent Report - {loop_id}</title>
  <style>
    body {{
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      margin: 24px;
      color: #111;
      background: #f8f6f2;
    }}
    h1 {{
      font-size: 22px;
      margin-bottom: 8px;
    }}
    h2 {{
      margin-top: 24px;
      border-bottom: 1px solid #ddd;
      padding-bottom: 6px;
    }}
    pre {{
      background: #fff;
      border: 1px solid #e2e2e2;
      padding: 12px;
      overflow: auto;
      white-space: pre-wrap;
    }}
    .meta {{
      background: #fff;
      border: 1px solid #e2e2e2;
      padding: 12px;
      margin-bottom: 12px;
    }}
    .usage-grid {{
      background: #fff;
      border: 1px solid #e2e2e2;
      padding: 16px;
    }}
    .usage-summary {{
      display: flex;
      gap: 24px;
      margin-bottom: 16px;
      padding-bottom: 16px;
      border-bottom: 1px solid #e2e2e2;
    }}
    .usage-stat {{
      display: flex;
      flex-direction: column;
    }}
    .usage-stat .label {{
      font-size: 12px;
      color: #666;
    }}
    .usage-stat .value {{
      font-size: 20px;
      font-weight: bold;
    }}
    .usage-table {{
      border-collapse: collapse;
      margin: 8px 0 16px 0;
    }}
    .usage-table th,
    .usage-table td {{
      border: 1px solid #e2e2e2;
      padding: 6px 12px;
      text-align: left;
    }}
    .usage-table th {{
      background: #f5f5f5;
    }}
    h3 {{
      margin: 16px 0 8px 0;
      font-size: 14px;
    }}
  </style>
</head>
<body>
  <h1>Supergent Report</h1>
  {sections}
</body>
</html>
""".format(loop_id=html.escape(loop_id), sections="\n".join(sections))

with open(out_path, "w") as handle:
    handle.write(html_doc)
PY

  echo "Wrote report to $report_file"
}
