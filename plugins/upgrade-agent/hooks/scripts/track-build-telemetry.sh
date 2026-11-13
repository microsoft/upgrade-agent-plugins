#!/bin/bash

write_success() {
    echo '{"continue":true}'
    exit 0
}

PHASE="$1"
if [ "$#" -gt 1 ]; then
    INPUT=$2
else
    INPUT=$(cat)
fi
if [ -z "$INPUT" ]; then
    write_success
fi

PYTHON=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then
    PYTHON="python3"
elif command -v python >/dev/null 2>&1 && python -c 'import json' >/dev/null 2>&1; then
    PYTHON="python"
else
    write_success
fi

TEMP_ROOT="${DOTNET_UPGRADEASSISTANT_DIAGNOSTICS_ROOT_PATH:-${TMPDIR:-/tmp}}"
TELEMETRY_DIR="${TEMP_ROOT%/}/UA/upgrades/build-observations"

PHASE="$PHASE" TELEMETRY_DIR="$TELEMETRY_DIR" "$PYTHON" -c '
import datetime
import hashlib
import json
import os
import re
import shlex
import sys
import time
import uuid

SHELL_TOOLS = {"bash", "Bash", "powershell", "PowerShell", "run_in_terminal", "execute", "shell"}

def utc_now_text():
    return datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")

def value(source, *names):
    if not isinstance(source, dict):
        return None
    for name in names:
        if source.get(name) is not None:
            return source[name]
    return None

def without_quoted_text(command):
    characters = list(command)
    quote = None
    index = 0
    while index < len(characters):
        character = characters[index]
        if quote is None:
            if character in (chr(39), "\""):
                quote = character
                characters[index] = " "
            elif character == "\\" and index + 1 < len(characters):
                characters[index] = " "
                index += 1
                characters[index] = " "
        else:
            characters[index] = " "
            if quote == "\"" and character == "\\" and index + 1 < len(characters):
                index += 1
                characters[index] = " "
            elif character == quote:
                quote = None
        index += 1
    return "".join(characters)

def calls(payload):
    envelope = value(payload, "input")
    if not isinstance(envelope, dict):
        envelope = payload
    batched = value(envelope, "toolCalls", "tool_calls")
    if isinstance(batched, list):
        session_id = value(envelope, "sessionId", "session_id")
        cwd = value(envelope, "cwd", "workingDirectory", "working_directory") or ""
        for call in batched:
            yield {
                "session_id": session_id,
                "cwd": cwd,
                "event_id": value(call, "id", "tool_use_id", "toolUseId", "tool_call_id", "toolCallId"),
                "name": value(call, "name", "toolName", "tool_name") or "",
                "args": value(call, "args", "toolArgs", "tool_input") or {},
                "response": value(call, "result", "toolResult", "tool_result", "toolResponse", "tool_response") or {},
            }
        return
    yield {
        "session_id": value(envelope, "session_id", "sessionId"),
        "cwd": value(envelope, "cwd", "working_directory", "workingDirectory") or "",
        "event_id": value(envelope, "tool_use_id", "toolUseId", "tool_call_id", "toolCallId", "timestamp"),
        "name": value(envelope, "tool_name", "toolName") or "",
        "args": value(envelope, "tool_input", "toolArgs") or {},
        "response": value(envelope, "tool_response", "toolResponse", "tool_result", "toolResult", "result") or {},
    }

def path_is_within(path, root):
    try:
        path = os.path.normcase(os.path.abspath(path))
        root = os.path.normcase(os.path.abspath(root))
        return os.path.commonpath([path, root]) == root
    except Exception:
        return False

def parse_session_id(candidate):
    try:
        if candidate:
            return str(uuid.UUID(candidate))
    except Exception:
        pass
    return None

def effective_session_id(payload_session_id, cwd, telemetry_dir):
    if os.path.isabs(cwd):
        matches = set()
        route_dir = os.path.join(telemetry_dir, "routes")
        try:
            route_names = os.listdir(route_dir)
        except OSError:
            route_names = []
        now = datetime.datetime.now(datetime.timezone.utc)
        for route_name in route_names:
            if not route_name.endswith(".json"):
                continue
            try:
                with open(os.path.join(route_dir, route_name), encoding="utf-8") as handle:
                    route = json.load(handle)
                updated = datetime.datetime.fromisoformat(str(route.get("updatedUtc", "")).replace("Z", "+00:00"))
                if updated.tzinfo is None:
                    updated = updated.replace(tzinfo=datetime.timezone.utc)
                if updated < now - datetime.timedelta(minutes=1) or updated > now + datetime.timedelta(minutes=5):
                    continue
                if not any(path_is_within(cwd, root) for root in route.get("workspaceRoots", []) if root):
                    continue
                session_id = parse_session_id(route.get("sessionId"))
                if session_id:
                    matches.add(session_id)
            except Exception:
                pass
        if len(matches) == 1:
            return next(iter(matches))
        if len(matches) > 1:
            return None

    session_id = parse_session_id(payload_session_id)
    if session_id:
        cache_root = os.path.dirname(telemetry_dir)
        try:
            with open(os.path.join(cache_root, "sessions", session_id, "session.json"), encoding="utf-8") as handle:
                session = json.load(handle)
            workspace = session.get("workspace") or {}
            roots = [workspace.get("repoRoot"), workspace.get("workspaceFolder")]
            if not os.path.isabs(cwd) or any(path_is_within(cwd, root) for root in roots if root):
                return session_id
        except Exception:
            pass
    return None

def numeric_exit_code(value_to_parse):
    if isinstance(value_to_parse, bool):
        return None
    try:
        numeric = float(value_to_parse)
        if numeric.is_integer():
            return int(numeric)
    except Exception:
        pass
    return None

def response_text(response):
    if isinstance(response, str):
        return response
    return value(response, "textResultForLlm", "text_result_for_llm") or ""

def exit_code_details(payload, response, text):
    trailer_matches = re.findall(r"(?m)<shellId:\s*[^>\r\n]*?\s+completed with exit code\s+(-?\d+)>\s*$", text)
    trailer_exit = trailer_matches[-1] if trailer_matches else None
    direct = value(response, "exit_code", "exitCode")
    telemetry = value(response, "toolTelemetry", "tool_telemetry")
    metrics = value(telemetry, "metrics")
    metrics_exit = value(metrics, "exit_code", "exitCode")
    payload_exit = value(payload, "exit_code", "exitCode")
    properties = value(telemetry, "properties")
    has_nonzero_category = value(properties, "shell_error_category", "shellErrorCategory") == "command_nonzero_exit"
    result_type = value(response, "resultType", "result_type")
    result = trailer_exit
    source = "textResultTrailer"
    if result is None:
        result = direct
        source = "direct"
    if result is None:
        result = metrics_exit
        source = "metrics"
    if result is None:
        result = payload_exit
        source = "payload"
    numeric = numeric_exit_code(result)
    if numeric is not None:
        return {"code": numeric, "source": source, "hasTrailerExitCode": trailer_exit is not None, "hasDirectExitCode": direct is not None, "hasMetricsExitCode": metrics_exit is not None, "hasPayloadExitCode": payload_exit is not None, "hasNonzeroCategory": has_nonzero_category, "resultType": result_type}
    return None

def append_record(path, record):
    lock_path = path + ".lock"
    descriptor = None
    acquired = False
    try:
        for _ in range(20):
            try:
                descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                acquired = True
                break
            except FileExistsError:
                time.sleep(0.025)
        if descriptor is None:
            return
        os.close(descriptor)
        descriptor = None
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":")) + "\n")
    finally:
        if descriptor is not None:
            os.close(descriptor)
        if acquired:
            try:
                os.remove(lock_path)
            except OSError:
                pass

def claim_hook_event(state_dir, session_id, phase, call, command):
    event_id = call["event_id"]
    if event_id is None or str(event_id).strip() == "":
        return True

    claim_dir = os.path.join(state_dir, "hook-events")
    os.makedirs(claim_dir, exist_ok=True)
    cutoff = datetime.datetime.now(datetime.timezone.utc).timestamp() - 86400
    try:
        for name in os.listdir(claim_dir):
            path = os.path.join(claim_dir, name)
            try:
                if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
                    os.remove(path)
            except OSError:
                pass
    except OSError:
        pass

    signature = "\n".join((session_id, phase, str(event_id), call["name"].lower(), command))
    claim_path = os.path.join(claim_dir, hashlib.sha256(signature.encode()).hexdigest() + ".claim")
    try:
        descriptor = os.open(claim_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(descriptor)
        return True
    except FileExistsError:
        return False

def remove_stale_states(state_dir):
    cutoff = time.time() - 86400
    try:
        names = os.listdir(state_dir)
    except OSError:
        return
    for name in names:
        path = os.path.join(state_dir, name)
        try:
            is_hook_state = re.fullmatch(r"[0-9a-fA-F]{64}-\d{20}-[0-9a-fA-F]{32}\.json(?:\.\d+\.claim)?", name)
            if os.path.isfile(path) and is_hook_state and os.path.getmtime(path) < cutoff:
                os.remove(path)
        except OSError:
            pass

phase = os.environ.get("PHASE", "")
telemetry_dir = os.environ.get("TELEMETRY_DIR", "")
state_dir = os.path.join(telemetry_dir, "state")

try:
    payload = json.load(sys.stdin)

    for call in calls(payload):
        if call["name"] not in SHELL_TOOLS:
            continue
        command = value(call["args"], "command", "script", "input") or ""
        is_async = value(call["args"], "mode") == "async" or value(call["args"], "detach") is True
        recognition_command = without_quoted_text(command)
        comment_index = recognition_command.find("#")
        invocation_command = command[:comment_index] if comment_index >= 0 else command
        recognition_command = recognition_command[:comment_index] if comment_index >= 0 else recognition_command
        if re.search(r"[;&|]|\r|\n", recognition_command):
            continue
        build = re.search(r"(?i)^\s*(?:dotnet(?:\.exe)?\s+(?P<operation>build)(?=\s|$)|(?P<msbuild>msbuild(?:\.exe)?)(?=\s|$))", recognition_command)
        if not build:
            continue
        session_id = effective_session_id(call["session_id"], call["cwd"], telemetry_dir)
        if not session_id:
            continue

        operation = "build"
        if build.group("msbuild"):
            target_match = re.search(r"""(?ix)(?:^|\s)[/-](?:t|target):(?:"(?P<double>[^"]+)"|'"'"'(?P<single>[^'"'"']+)'"'"'|(?P<bare>[^\s;&|]+))""", invocation_command)
            if target_match:
                target_value = target_match.group("double") or target_match.group("single") or target_match.group("bare")
                msbuild_targets = [item.strip().lower() for item in re.split(r"[,;]", target_value) if item.strip()]
                if not any(item in {"build", "rebuild"} for item in msbuild_targets):
                    continue
        cwd = call["cwd"]
        targets = []
        for match in re.finditer(r"""(?ix)(?:"(?P<double>[^"]+\.(?:slnx?|csproj|fsproj|vbproj))"|'"'"'(?P<single>[^'"'"']+\.(?:slnx?|csproj|fsproj|vbproj))'"'"'|(?P<bare>[^\s;&|]+\.(?:slnx?|csproj|fsproj|vbproj)))""", invocation_command):
            path = match.group("double") or match.group("single") or match.group("bare")
            if not os.path.isabs(path) and cwd:
                path = os.path.abspath(os.path.join(cwd, path))
            if os.path.isabs(path) and path not in targets:
                targets.append(path)
        if not targets and build.group("operation"):
            directory_targets = []
            ambiguous_directory_target = False
            try:
                arguments = shlex.split(invocation_command)
            except ValueError:
                arguments = []
                ambiguous_directory_target = True
            options_with_values = {
                "-a", "--arch",
                "--artifacts-path",
                "-c", "--configuration",
                "--configfile",
                "-f", "--framework",
                "-o", "--output",
                "--packages",
                "-p", "--property",
                "-r", "--runtime",
                "-s", "--source",
                "-v", "--verbosity",
            }
            skip_next_argument = False
            for path in arguments[2:]:
                if skip_next_argument:
                    skip_next_argument = False
                    continue
                if path.startswith("-"):
                    skip_next_argument = path.lower() in options_with_values
                    continue
                if not os.path.isabs(path) and cwd:
                    path = os.path.abspath(os.path.join(cwd, path))
                if os.path.isabs(path) and os.path.isdir(path) and path not in directory_targets:
                    directory_targets.append(path)
            if len(directory_targets) == 1:
                targets.append(directory_targets[0])
            elif len(directory_targets) > 1:
                ambiguous_directory_target = True
            if ambiguous_directory_target:
                continue
        if not targets and os.path.isabs(cwd):
            targets.append(cwd)

        scope = "solution" if any(re.search(r"(?i)\.slnx?$", p) for p in targets) else "project" if any(re.search(r"(?i)\.(?:csproj|fsproj|vbproj)$", p) for p in targets) else "repository"
        os.makedirs(state_dir, exist_ok=True)
        remove_stale_states(state_dir)
        signature = session_id + "\n" + call["name"].lower() + "\n" + cwd + "\n" + command
        correlation_hash = hashlib.sha256(signature.encode()).hexdigest()
        observation_path = os.path.join(telemetry_dir, "build-observations-" + session_id + ".jsonl")

        if phase == "pre":
            if is_async:
                continue

            if not claim_hook_event(state_dir, session_id, phase, call, command):
                continue

            state = {
                "attemptId": str(uuid.uuid4()),
                "startedAtUtc": utc_now_text(),
                "operation": operation,
                "scope": scope,
                "targetPaths": targets[:20],
            }
            state_name = "{}-{:020d}-{}.json".format(
                correlation_hash,
                int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000000),
                uuid.uuid4().hex)
            with open(os.path.join(state_dir, state_name), "w", encoding="utf-8") as handle:
                json.dump(state, handle, separators=(",", ":"))
            append_record(observation_path, {"recordKind": "started", "sessionId": session_id, **state})
            continue

        if not claim_hook_event(state_dir, session_id, phase, call, command):
            continue

        candidates = sorted(name for name in os.listdir(state_dir) if name.startswith(correlation_hash + "-") and name.endswith(".json"))
        if not candidates:
            continue
        state_path = os.path.join(state_dir, candidates[0])
        claim_path = state_path + "." + str(os.getpid()) + ".claim"
        try:
            os.replace(state_path, claim_path)
        except OSError:
            continue

        if is_async:
            try:
                os.remove(claim_path)
            except OSError:
                pass
            continue

        text = response_text(call["response"])
        exit_details = exit_code_details(payload, call["response"], text)
        if exit_details is None:
            try:
                os.remove(claim_path)
            except OSError:
                pass
            continue
        code = exit_details["code"]

        try:
            with open(claim_path, encoding="utf-8") as handle:
                state = json.load(handle)
        finally:
            try:
                os.remove(claim_path)
            except OSError:
                pass

        diagnostic_pattern = r"(?:CS|FS|BC|NU|MSB|NETSDK|NET|SDK|VSTEST)\d{3,5}"
        error_matches = re.findall(r"(?i)\berror\s+(" + diagnostic_pattern + r")\b", text)
        warning_matches = re.findall(r"(?i)\bwarning\s+(" + diagnostic_pattern + r")\b", text)
        error_codes = sorted(set(item.upper() for item in error_matches))[:10]
        warning_codes = sorted(set(item.upper() for item in warning_matches))[:10]
        codes = sorted(set(error_codes + warning_codes))[:10]
        errors = len(error_matches)
        warnings = len(warning_matches)
        outcome = "succeeded" if code == 0 and errors == 0 else "cancelled" if re.search(r"(?i)\bcancel(?:led|ed)?\b", text) else "timedOut" if code == 124 or re.search(r"(?i)\btimed?\s*out\b", text) else "failed"

        if any(item.startswith("NU") for item in error_codes):
            failure_phase = "restore"
        elif any(item.startswith(("CS", "FS", "BC")) for item in error_codes):
            failure_phase = "compile"
        else:
            failure_phase = "unknown"

        if outcome == "cancelled":
            category = "cancelled"
        elif outcome == "timedOut":
            category = "timeout"
        elif outcome == "succeeded":
            category = "unknown"
        elif "NU1101" in error_codes:
            category = "packageNotFound"
        elif re.search(r"(?i)\b(?:401|unauthorized|authentication)\b", text):
            category = "packageFeedAuthentication"
        elif any(item in {"NU1107", "NU1605"} for item in error_codes):
            category = "packageVersionConflict"
        elif "MSB4019" in error_codes:
            category = "missingMSBuildImport"
        elif "MSB4236" in error_codes:
            category = "missingSdk"
        elif "NETSDK1147" in error_codes:
            category = "missingWorkload"
        elif "NETSDK1045" in error_codes:
            category = "unsupportedTargetFramework"
        elif any(item.startswith(("CS", "FS", "BC")) for item in error_codes):
            category = "compilationError"
        else:
            category = "unknown"

        if exit_details["resultType"] == "success" and (code != 0 or errors > 0):
            append_record(os.path.join(telemetry_dir, "hook-classification-diagnostics.jsonl"), {
                "timestampUtc": utc_now_text(),
                "phase": "post-classification",
                "operation": state["operation"],
                "exitCodeSource": exit_details["source"],
                "parsedExitCode": code,
                "resultType": exit_details["resultType"],
                "hasTrailerExitCode": exit_details["hasTrailerExitCode"],
                "hasDirectExitCode": exit_details["hasDirectExitCode"],
                "hasMetricsExitCode": exit_details["hasMetricsExitCode"],
                "hasPayloadExitCode": exit_details["hasPayloadExitCode"],
                "hasNonzeroCategory": exit_details["hasNonzeroCategory"],
                "errorCount": errors,
                "derivedOutcome": outcome,
            })

        append_record(observation_path, {
            "recordKind": "completed",
            "sessionId": session_id,
            "attemptId": state["attemptId"],
            "startedAtUtc": state["startedAtUtc"],
            "completedAtUtc": utc_now_text(),
            "operation": state["operation"],
            "scope": state["scope"],
            "outcome": outcome,
            "failurePhase": failure_phase,
            "failureCategory": category,
            "errorCount": errors,
            "warningCount": warnings,
            "errorDiagnosticCodes": error_codes,
            "warningDiagnosticCodes": warning_codes,
            "diagnosticCodes": codes,
            "targetPaths": state["targetPaths"],
        })
except Exception as error:
    try:
        os.makedirs(telemetry_dir, exist_ok=True)
        append_record(os.path.join(telemetry_dir, "hook-diagnostics.jsonl"), {
            "timestampUtc": utc_now_text(),
            "eventName": "unhandledException",
            "phase": phase,
            "exceptionType": type(error).__name__,
        })
    except OSError:
        pass
' <<< "$INPUT" >/dev/null 2>&1

write_success
