#!/bin/bash

# Older Bash disables process substitution in POSIX mode, including when sourced by sh.
set +o posix

# Return success and exit. The hook must never block the host tool call,
# so all error paths funnel through this function.
write_success() {
    echo '{"continue":true}'
    exit 0
}

# The wrapper passes buffered JSON; direct script calls still read stdin.
if [ "$#" -gt 0 ]; then
    INPUT=$1
else
    INPUT=$(cat)
fi
if [ -z "$INPUT" ]; then
    write_success
fi

# Last-resort extraction when no JSON parser is installed.
extract_field_regex() {
    local json="$1"
    shift
    local key

    # Last-resort: naive regex after flattening JSON to one line.
    # Searches anywhere in the payload, so works for nested fields.
    # Limitation: won't handle escaped quotes within string values.
    for key in "$@"; do
        local val
        val=$(printf '%s' "$json" \
            | tr -d '\n' \
            | grep -oE "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
            | head -n 1 \
            | sed -E "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/")
        if [ -n "$val" ]; then
            # JSON escapes Windows separators even when no parser is installed.
            val="${val//\\\\/\\}"
            echo "$val"
            return
        fi
    done
}

# NUL-delimited fields preserve spaces, tabs and newlines without evaluating input.
extract_fields() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$INPUT" | jq -j '
            def field($keys):
                . as $input |
                first($keys[] as $k |
                    ($input[$k] // $input.tool_input[$k]? // $input.toolArgs[$k]? // empty) |
                    select(type == "string" and length > 0)) // "";
            [field(["tool_name", "toolName"]),
             field(["file_path", "filePath", "path"]),
             field(["session_id"]),
             ""] |
            select(all(.[]; index("\u0000") == null)) |
            .[] | ., "\u0000"
        ' 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$INPUT" | python3 -c "
import sys, json
from datetime import datetime
try:
    d = json.load(sys.stdin)
except (ValueError, UnicodeError):
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)
def field(keys):
    for k in keys:
        for src in (d, d.get('tool_input'), d.get('toolArgs')):
            if isinstance(src, dict):
                v = src.get(k)
                if isinstance(v, str) and v:
                    return v
    return ''
values = (field(('tool_name', 'toolName')),
          field(('file_path', 'filePath', 'path')),
          field(('session_id',)),
          datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3])
if any('\0' in value for value in values):
    sys.exit(0)
for value in values:
    sys.stdout.write(value + '\0')
" 2>/dev/null
    else
        printf '%s\0' \
            "$(extract_field_regex "$INPUT" tool_name toolName)" \
            "$(extract_field_regex "$INPUT" file_path filePath path)" \
            "$(extract_field_regex "$INPUT" session_id)" \
            ""
    fi
}

TOOL_NAME=""
FILE_PATH=""
SESSION_ID=""
TIMESTAMP=""
{
    IFS= read -r -d '' TOOL_NAME
    IFS= read -r -d '' FILE_PATH
    IFS= read -r -d '' SESSION_ID
    IFS= read -r -d '' TIMESTAMP
} < <(extract_fields)

# Only log file-read tools
case "$TOOL_NAME" in
    read_file|view|Read) ;;
    *) write_success ;;
esac

if [ -z "$FILE_PATH" ]; then
    write_success
fi

# Normalize path separators for comparison
FILE_PATH_NORMALIZED="${FILE_PATH//\\//}"

# Match SKILL.md paths in known layouts:
# 1) VS Code extension: .../extensions/ms-dotnettools.upgrade-agent-*/skills/**/SKILL.md
# 2) Plugin: .../upgrade/skills/**/SKILL.md
# 3) Either host's extenders: .../upgrade/*/skills/**/SKILL.md
#    (both hosts stage extenders under the same `upgrade` prefix, so
#    one alternative covers the VSIX and the CLI plugin)
if echo "$FILE_PATH_NORMALIZED" | grep -qiE '(/extensions/ms-dotnettools\.upgrade-agent-[^/]+/skills/|/upgrade/([^/]+/)?skills/)([^/]+/)*[^/]+/SKILL\.md$'; then
    # Setup log directory only for a matching skill read.
    TEMP_ROOT="${TMPDIR:-/tmp}"
    LOG_DIR="${TEMP_ROOT%/}/UA/upgrades/skills-loaded"
    mkdir -p "$LOG_DIR" 2>/dev/null

    # Extract skill name from the parent directory of SKILL.md
    SKILL_NAME=$(basename "$(dirname "$FILE_PATH_NORMALIZED")")

    # Use "unknown" if session_id not provided
    if [ -z "$SESSION_ID" ]; then
        SESSION_ID="unknown"
    fi
    
    # Generate timestamp
    if [ -z "$TIMESTAMP" ]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    fi

    # Log in format: timestamp, skillname
    LOG_FILE="$LOG_DIR/progressive-loads-$SESSION_ID.txt"
    echo "$TIMESTAMP, $SKILL_NAME" >> "$LOG_FILE"
fi

write_success
