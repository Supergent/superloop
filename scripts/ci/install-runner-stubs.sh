#!/usr/bin/env bash
set -euo pipefail

config_path="${1:-.superloop/config.json}"
stub_dir="${2:-${RUNNER_TEMP:-/tmp}/superloop-runner-stubs}"

if [[ ! -f "$config_path" ]]; then
  echo "[ci] config not found at $config_path; skipping runner stubs"
  exit 0
fi

mkdir -p "$stub_dir"

mapfile -t commands < <(
  jq -r '.runners // {} | to_entries[] | .value.command[0] // empty' "$config_path" | sort -u
)

if [[ ${#commands[@]} -eq 0 ]]; then
  echo "[ci] no runners found in $config_path; skipping runner stubs"
  exit 0
fi

for cmd in "${commands[@]}"; do
  if [[ -z "$cmd" || "$cmd" == */* ]]; then
    continue
  fi

  cat > "$stub_dir/$cmd" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    echo "superloop-ci-runner-stub 0.0.0"
    ;;
  --help)
    echo "superloop-ci-runner-stub"
    ;;
  *)
    # Intentionally no-op. These stubs only satisfy CI PATH/static checks.
    ;;
esac

exit 0
EOF
  chmod +x "$stub_dir/$cmd"
done

if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$stub_dir" >> "$GITHUB_PATH"
fi

echo "[ci] installed runner stubs in $stub_dir"
