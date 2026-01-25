main() {
  local cmd="${1:-}"
  if [[ "$cmd" == "--version" || "$cmd" == "-v" ]]; then
    print_version
    return 0
  fi
  shift || true

  local repo="."
  local config_path=""
  local schema_path=""
  local loop_id=""
  local out_path=""
  local summary=0
  local force=0
  local fast=0
  local dry_run=0
  local json_output=0
  local approver=""
  local note=""
  local reject=0
  local static=0
  local skip_validate=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        repo="$2"
        shift 2
        ;;
      --config)
        config_path="$2"
        shift 2
        ;;
      --schema)
        schema_path="$2"
        shift 2
        ;;
      --loop)
        loop_id="$2"
        shift 2
        ;;
      --summary)
        summary=1
        shift
        ;;
      --json)
        json_output=1
        shift
        ;;
      --out)
        out_path="$2"
        shift 2
        ;;
      --by)
        approver="$2"
        shift 2
        ;;
      --note)
        note="$2"
        shift 2
        ;;
      --reject)
        reject=1
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      --fast)
        fast=1
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --static)
        static=1
        shift
        ;;
      --skip-validate)
        skip_validate=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  : "${repo:=.}"
  repo=$(cd "$repo" && pwd)

  if [[ -z "$config_path" ]]; then
    config_path="$repo/.superloop/config.json"
  fi
  if [[ -z "$schema_path" ]]; then
    schema_path="$repo/schema/config.schema.json"
  fi

  case "$cmd" in
    init)
      init_cmd "$repo" "$force"
      ;;
    list)
      list_cmd "$repo" "$config_path"
      ;;
    run)
      run_cmd "$repo" "$config_path" "$loop_id" "$fast" "$dry_run" "$skip_validate"
      ;;
    status)
      status_cmd "$repo" "$summary" "$loop_id" "$config_path"
      ;;
    usage)
      usage_cmd "$repo" "$loop_id" "$config_path" "$json_output"
      ;;
    approve)
      approve_cmd "$repo" "$loop_id" "$approver" "$note" "$reject"
      ;;
    cancel)
      cancel_cmd "$repo"
      ;;
    validate)
      validate_cmd "$repo" "$config_path" "$schema_path" "$static"
      ;;
    report)
      report_cmd "$repo" "$config_path" "$loop_id" "$out_path"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
