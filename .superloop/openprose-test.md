# OpenProse smoke test

Goal: Validate Prose Author + OpenProse execution.

Requirements:
1) Prose Author must write `.superloop/workflows/openprose.prose`.
2) The .prose program must contain exactly one `session` whose prompt writes
   `openprose ok` into `.superloop/loops/openprose-test/openprose-out.txt`.
3) Ignore unrelated repo changes; only verify the workflow file and output file.
