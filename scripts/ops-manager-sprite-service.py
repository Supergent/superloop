#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlparse


def json_load(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default


def json_dump_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", delete=False, dir=str(path.parent)) as tmp:
        tmp.write(json.dumps(value, separators=(",", ":")))
        tmp_path = Path(tmp.name)
    tmp_path.replace(path)


def run_command(command: List[str]) -> Tuple[int, str, str]:
    proc = subprocess.run(command, capture_output=True, text=True)
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def tail_text(value: str, max_lines: int = 40) -> str:
    lines = [line.rstrip("\r") for line in value.splitlines() if line.strip()]
    if not lines:
        return ""
    return "\n".join(lines[-max_lines:])


def parse_last_json_line(value: str) -> Optional[Dict[str, Any]]:
    lines = [line.strip() for line in value.splitlines() if line.strip()]
    for line in reversed(lines):
        try:
            parsed = json.loads(line)
            if isinstance(parsed, dict):
                return parsed
        except Exception:
            continue
    return None


class ServiceConfig:
    def __init__(self, repo: Path, token: str, scripts_dir: Path):
        self.repo = repo
        self.token = token
        self.scripts_dir = scripts_dir
        self.snapshot_script = scripts_dir / "ops-manager-loop-run-snapshot.sh"
        self.poll_script = scripts_dir / "ops-manager-poll-events.sh"
        self.control_script = scripts_dir / "ops-manager-control.sh"


class OpsHandler(BaseHTTPRequestHandler):
    server_version = "OpsManagerSpriteService/0.1"

    @property
    def cfg(self) -> ServiceConfig:
        return self.server.cfg  # type: ignore[attr-defined]

    def _json(self, status: int, payload: Any) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, code: str, message: str) -> None:
        self._json(status, {"ok": False, "error": {"code": code, "message": message}})

    def _authorized(self) -> bool:
        token = self.cfg.token
        if not token:
            return True
        auth = self.headers.get("Authorization", "")
        x_token = self.headers.get("X-Ops-Token", "")
        bearer = ""
        if auth.lower().startswith("bearer "):
            bearer = auth[7:].strip()
        if bearer == token or x_token == token:
            return True
        self._error(401, "unauthorized", "missing or invalid token")
        return False

    def _loop_id_from_query(self, query: Dict[str, List[str]]) -> str:
        loop_vals = query.get("loopId", [])
        return loop_vals[0] if loop_vals else ""

    def _int_from_query(self, query: Dict[str, List[str]], key: str, default: int = 0) -> int:
        vals = query.get(key, [])
        if not vals:
            return default
        try:
            value = int(vals[0])
        except Exception:
            raise ValueError(f"query parameter '{key}' must be an integer")
        if value < 0:
            raise ValueError(f"query parameter '{key}' must be >= 0")
        return value

    def do_GET(self) -> None:  # noqa: N802
        if not self._authorized():
            return

        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)

        if parsed.path == "/healthz":
            self._json(200, {"ok": True})
            return

        if parsed.path == "/ops/snapshot":
            loop_id = self._loop_id_from_query(query)
            if not loop_id:
                self._error(400, "invalid_request", "loopId is required")
                return

            code, out, err = run_command(
                [str(self.cfg.snapshot_script), "--repo", str(self.cfg.repo), "--loop", loop_id]
            )
            if code != 0:
                self._error(502, "runtime_error", tail_text(err) or "snapshot command failed")
                return
            try:
                payload = json.loads(out)
            except Exception:
                self._error(502, "runtime_error", "snapshot output was not valid JSON")
                return

            self._json(200, payload)
            return

        if parsed.path == "/ops/events":
            loop_id = self._loop_id_from_query(query)
            if not loop_id:
                self._error(400, "invalid_request", "loopId is required")
                return

            try:
                cursor = self._int_from_query(query, "cursor", 0)
                max_events = self._int_from_query(query, "maxEvents", 0)
            except ValueError as exc:
                self._error(400, "invalid_request", str(exc))
                return

            with tempfile.TemporaryDirectory() as tmp_dir:
                cursor_file = Path(tmp_dir) / "cursor.json"
                cursor_file.write_text(
                    json.dumps(
                        {
                            "schemaVersion": "v1",
                            "repoPath": str(self.cfg.repo),
                            "loopId": loop_id,
                            "eventsFile": f".superloop/loops/{loop_id}/events.jsonl",
                            "eventLineOffset": cursor,
                            "eventLineCount": cursor,
                            "updatedAt": "",
                        },
                        separators=(",", ":"),
                    )
                )

                command = [
                    str(self.cfg.poll_script),
                    "--repo",
                    str(self.cfg.repo),
                    "--loop",
                    loop_id,
                    "--cursor-file",
                    str(cursor_file),
                ]
                if max_events > 0:
                    command += ["--max-events", str(max_events)]

                code, out, err = run_command(command)
                if code != 0:
                    self._error(502, "runtime_error", tail_text(err) or "event poll command failed")
                    return

                events: List[Dict[str, Any]] = []
                for line in out.splitlines():
                    stripped = line.strip()
                    if not stripped:
                        continue
                    try:
                        event_obj = json.loads(stripped)
                    except Exception:
                        self._error(502, "runtime_error", "event poll emitted invalid JSON")
                        return
                    if isinstance(event_obj, dict):
                        events.append(event_obj)

                cursor_json = json_load(cursor_file, {})
                if not isinstance(cursor_json, dict):
                    cursor_json = {}

                response = {
                    "ok": True,
                    "schemaVersion": "v1",
                    "source": {
                        "repoPath": str(self.cfg.repo),
                        "loopId": loop_id,
                    },
                    "events": events,
                    "cursor": {
                        "eventLineOffset": cursor_json.get("eventLineOffset", cursor),
                        "eventLineCount": cursor_json.get("eventLineCount", cursor),
                        "updatedAt": cursor_json.get("updatedAt"),
                    },
                }
                self._json(200, response)
                return

        self._error(404, "not_found", "endpoint not found")

    def do_POST(self) -> None:  # noqa: N802
        if not self._authorized():
            return

        parsed = urlparse(self.path)
        if parsed.path != "/ops/control":
            self._error(404, "not_found", "endpoint not found")
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(content_length) if content_length > 0 else b"{}"

        try:
            payload = json.loads(raw.decode("utf-8"))
        except Exception:
            self._error(400, "invalid_json", "request body must be valid JSON")
            return

        if not isinstance(payload, dict):
            self._error(400, "invalid_request", "request body must be an object")
            return

        loop_id = str(payload.get("loopId") or "").strip()
        intent = str(payload.get("intent") or "").strip()
        by = str(payload.get("by") or os.environ.get("USER", "ops-service")).strip()
        note = str(payload.get("note") or "").strip()
        idempotency_key = str(payload.get("idempotencyKey") or self.headers.get("X-Idempotency-Key", "")).strip()
        no_confirm = bool(payload.get("noConfirm", False))

        if not loop_id:
            self._error(400, "invalid_request", "loopId is required")
            return
        if intent not in {"cancel", "approve", "reject"}:
            self._error(400, "invalid_request", "intent must be cancel, approve, or reject")
            return

        ops_dir = self.cfg.repo / ".superloop" / "ops-manager" / loop_id
        idem_file = ops_dir / "service-idempotency.json"
        idem_map = json_load(idem_file, {})
        if not isinstance(idem_map, dict):
            idem_map = {}

        if idempotency_key and idempotency_key in idem_map:
            replayed_obj = idem_map[idempotency_key]
            if isinstance(replayed_obj, dict):
                replayed_obj = dict(replayed_obj)
                replayed_obj["replayed"] = True
                self._json(200, replayed_obj)
                return

        command = [
            str(self.cfg.control_script),
            "--repo",
            str(self.cfg.repo),
            "--loop",
            loop_id,
            "--intent",
            intent,
            "--by",
            by,
        ]
        if note:
            command += ["--note", note]
        if no_confirm:
            command += ["--no-confirm"]

        code, out, err = run_command(command)
        result_obj = parse_last_json_line(out)

        response: Dict[str, Any] = {
            "ok": code == 0,
            "exitCode": code,
            "result": result_obj,
            "stderr": tail_text(err) or None,
            "replayed": False,
        }

        # Remove null keys
        response = {k: v for k, v in response.items() if v is not None}

        if idempotency_key:
            idem_map[idempotency_key] = response
            json_dump_atomic(idem_file, idem_map)

        if code == 0:
            self._json(200, response)
        elif code == 2:
            self._json(409, response)
        else:
            self._json(500, response)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Ops Manager Sprite service transport")
    parser.add_argument("--repo", required=True, help="Target repo path (contains .superloop)")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host")
    parser.add_argument("--port", type=int, default=8787, help="Bind port")
    parser.add_argument(
        "--token",
        default=os.environ.get("OPS_MANAGER_SERVICE_TOKEN", ""),
        help="Auth token (optional; when set, requests must provide it)",
    )
    parser.add_argument(
        "--scripts-dir",
        default=str(Path(__file__).resolve().parent),
        help="Directory containing ops-manager scripts",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo = Path(args.repo).resolve()
    if not repo.exists():
        raise SystemExit(f"repo path not found: {repo}")

    scripts_dir = Path(args.scripts_dir).resolve()
    cfg = ServiceConfig(repo=repo, token=args.token, scripts_dir=scripts_dir)

    for required in [cfg.snapshot_script, cfg.poll_script, cfg.control_script]:
        if not required.exists():
            raise SystemExit(f"required script not found: {required}")

    server = ThreadingHTTPServer((args.host, args.port), OpsHandler)
    server.cfg = cfg  # type: ignore[attr-defined]
    print(f"ops-manager sprite service listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
