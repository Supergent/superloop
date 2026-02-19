#!/usr/bin/env bash
set -euo pipefail

# Consume prompt payload and emit deterministic root Python code for rlms_worker.
cat >/dev/null

cat <<'PY'
files = list_files()
target = files[0] if files else ""
snippet = read_file(target, 1, 120) if target else ""

if snippet:
    child = sub_rlm("summarize:\n" + snippet, depth=1)
    append_highlight("subcall:" + str(child))

append_highlight("mock_root_complete")

if target:
    lines = snippet.split("\n") if snippet else [""]
    end_line = min(3, len(lines)) if len(lines) > 0 else 1
    add_citation(target, 1, end_line, "semantic_match", snippet)

set_final({"highlights": ["mock_root_complete"], "citations": []})
PY
