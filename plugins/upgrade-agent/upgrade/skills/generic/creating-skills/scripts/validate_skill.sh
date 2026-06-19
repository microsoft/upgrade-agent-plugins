#!/usr/bin/env bash
#
# Validates a skill directory against Anthropic's best practices.
#
# Usage:
#   ./validate_skill.sh /path/to/skill-directory
#
# Checks structure, frontmatter, line counts, file paths, reference depth,
# and common anti-patterns. Subjective quality checks (conciseness, freedom
# calibration) require human review.
#
# Exit code: 0 if no blocking failures, 1 otherwise.

set -euo pipefail

# --- Colors (disabled if not a terminal) ---
if [ -t 1 ]; then
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
else
    RED='' YELLOW='' GREEN='' NC=''
fi

# --- Result tracking ---
declare -a PASSES=()
declare -a WARNINGS=()
declare -a FAILS=()

pass()  { PASSES+=("[$1] $2"); }
warn()  { WARNINGS+=("[$1] $2"); }
fail()  { FAILS+=("[$1] $2"); }

report() {
    echo ""
    echo "============================================================"
    echo "SKILL VALIDATION REPORT"
    echo "============================================================"

    if [ ${#PASSES[@]} -gt 0 ]; then
        echo ""
        echo -e "${GREEN}PASSED:${NC}"
        for item in "${PASSES[@]}"; do
            echo -e "${GREEN}   $item${NC}"
        done
    fi

    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}WARNINGS:${NC}"
        for item in "${WARNINGS[@]}"; do
            echo -e "${YELLOW}   $item${NC}"
        done
    fi

    if [ ${#FAILS[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}FAILURES (must fix):${NC}"
        for item in "${FAILS[@]}"; do
            echo -e "${RED}   $item${NC}"
        done
    fi

    echo ""
    echo "------------------------------------------------------------"
    echo "Summary: ${#PASSES[@]} passed, ${#WARNINGS[@]} warnings, ${#FAILS[@]} failures"

    if [ ${#FAILS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -le 2 ]; then
        echo -e "${GREEN}Status: READY FOR REVIEW${NC}"
    elif [ ${#FAILS[@]} -eq 0 ]; then
        echo -e "${YELLOW}Status: FIX WARNINGS before review${NC}"
    else
        echo -e "${RED}Status: BLOCKING ISSUES - must fix${NC}"
    fi
}

# --- Input validation ---
SKILL_DIR="${1:-}"
if [ -z "$SKILL_DIR" ]; then
    echo "Usage: $0 /path/to/skill-directory"
    exit 1
fi

if [ ! -d "$SKILL_DIR" ]; then
    echo "Error: '$SKILL_DIR' is not a directory"
    exit 1
fi

# Normalize path (remove trailing slash)
SKILL_DIR="${SKILL_DIR%/}"

SKILL_MD="$SKILL_DIR/SKILL.md"

# --- 1. SKILL.md exists ---
if [ ! -f "$SKILL_MD" ]; then
    fail "Structure" "SKILL.md not found at skill root"
    report
    exit 1
fi

pass "Structure" "SKILL.md exists"

CONTENT=$(cat "$SKILL_MD")

# --- 2. Frontmatter parsing ---
if ! echo "$CONTENT" | head -1 | grep -q "^---"; then
    fail "Frontmatter" "No valid YAML frontmatter found (must start with ---)"
    report
    exit 1
fi

pass "Frontmatter" "YAML frontmatter present"

# Extract frontmatter block (between first and second ---)
FRONTMATTER=$(echo "$CONTENT" | sed -n '2,/^---$/p' | head -n -1)

# Extract name and description from frontmatter
NAME=$(echo "$FRONTMATTER" | grep -E "^name:" | head -1 | sed 's/^name:\s*//' | sed 's/^["'"'"']\|["'"'"']$//g' | tr -d '\r')
DESC=$(echo "$FRONTMATTER" | grep -E "^description:" | head -1 | sed 's/^description:\s*//' | sed 's/^["'"'"']\|["'"'"']$//g' | tr -d '\r')

# --- Name checks ---
if [ -z "$NAME" ]; then
    fail "Frontmatter" "\`name\` field is missing or empty"
elif [ ${#NAME} -gt 64 ]; then
    fail "Frontmatter" "\`name\` is ${#NAME} chars (max 64)"
elif ! echo "$NAME" | grep -qE "^[a-z0-9-]+$"; then
    fail "Frontmatter" "\`name\` contains invalid characters: '$NAME' (only lowercase, numbers, hyphens)"
elif echo "$NAME" | grep -qE "(anthropic|claude)"; then
    fail "Frontmatter" "\`name\` contains reserved word: '$NAME'"
elif echo "$NAME" | grep -q "<"; then
    fail "Frontmatter" "\`name\` contains XML tags"
else
    pass "Frontmatter" "\`name\` is valid: '$NAME'"

    # Naming quality check (warning, not blocking)
    GERUND_PREFIXES="migrating- converting- managing- integrating- modifying- processing- analyzing- creating- generating- configuring- deploying- testing- building- validating- upgrading-"
    STARTS_WITH_GERUND=false
    for prefix in $GERUND_PREFIXES; do
        if [[ "$NAME" == "$prefix"* ]]; then
            STARTS_WITH_GERUND=true
            break
        fi
    done

    if [ "$STARTS_WITH_GERUND" = false ] && [ -n "$NAME" ]; then
        warn "Naming" "\`name\` '$NAME' does not start with a gerund verb (e.g., migrating-, converting-, managing-)"
    fi
fi

# --- Description checks ---
if [ -z "$DESC" ]; then
    fail "Frontmatter" "\`description\` field is missing or empty"
elif [ ${#DESC} -gt 1024 ]; then
    fail "Frontmatter" "\`description\` is ${#DESC} chars (max 1024)"
elif echo "$DESC" | grep -qE "<[^>]+>"; then
    fail "Frontmatter" "\`description\` appears to contain XML tags"
else
    pass "Frontmatter" "\`description\` present (${#DESC} chars)"

    # Third person check
    if echo "$DESC" | grep -qiE "^(I |I can|You |You can)"; then
        warn "Description" "Should be third person ('Processes files' not 'I can help' or 'You can use')"
    else
        pass "Description" "Written in third person"
    fi

    # Trigger context check
    HAS_TRIGGER=false
    for tw in "use when" "use this" "trigger" "when the user" "also use" "mention"; do
        if echo "$DESC" | grep -qi "$tw"; then
            HAS_TRIGGER=true
            break
        fi
    done

    if [ "$HAS_TRIGGER" = true ]; then
        pass "Description" "Includes trigger context"
    else
        warn "Description" "No trigger context found - add 'Use when...' phrases for better discovery"
    fi

    # Vague description check
    for vp in "helps with" "does stuff" "processes data" "works with files" "general purpose"; do
        if echo "$DESC" | grep -qi "$vp"; then
            warn "Description" "Description seems vague - be more specific about capabilities and triggers"
            break
        fi
    done
fi

# --- 3. Line count ---
# Get body after second ---
BODY=$(echo "$CONTENT" | sed -n '/^---$/,/^---$/d;p' | tail -n +1)
# Alternative: skip everything up to and including the second ---
SECOND_MARKER=$(echo "$CONTENT" | grep -n "^---$" | sed -n '2p' | cut -d: -f1)
if [ -n "$SECOND_MARKER" ]; then
    BODY=$(echo "$CONTENT" | tail -n +"$((SECOND_MARKER + 1))")
fi

BODY_LINES=$(echo "$BODY" | wc -l | tr -d ' ')

if [ "$BODY_LINES" -gt 500 ]; then
    warn "Structure" "SKILL.md body is $BODY_LINES lines (recommended max 500)"
else
    pass "Structure" "SKILL.md body is $BODY_LINES lines"
fi

# --- 4. File path checks (backslashes in content files) ---
BACKSLASH_FILES=""
while IFS= read -r -d '' f; do
    ext="${f##*.}"
    case "$ext" in
        md|js|ts)
            # Skip SKILL.md — it may legitimately contain Windows path examples
            [ "$(basename "$f")" = "SKILL.md" ] && continue
            if grep -qE '["\x27][^"\x27]*\\[^"\x27]*["\x27]' "$f" 2>/dev/null; then
                rel="${f#$SKILL_DIR/}"
                BACKSLASH_FILES="$BACKSLASH_FILES $rel"
            fi
            ;;
    esac
done < <(find "$SKILL_DIR" -type f \( -name "*.md" -o -name "*.js" -o -name "*.ts" \) -print0 2>/dev/null)

if [ -n "$BACKSLASH_FILES" ]; then
    warn "Paths" "Possible Windows-style backslash paths in:$BACKSLASH_FILES"
else
    pass "Paths" "No Windows-style paths detected in content files"
fi

# --- 5. Reference depth check ---
NESTED_REFS=""
while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    REF_FILE="$SKILL_DIR/$ref"
    if [ -f "$REF_FILE" ] && echo "$ref" | grep -q "\.md$"; then
        SUB_REFS=$(grep -oE '\[.*?\]\(((?:references|scripts|templates)/[^)]+)\)' "$REF_FILE" 2>/dev/null | grep -oE '(references|scripts|templates)/[^)]+' || true)
        if [ -n "$SUB_REFS" ]; then
            NESTED_REFS="$NESTED_REFS; $ref -> [$SUB_REFS]"
        fi
    fi
done < <(grep -oE '\((references|scripts|templates)/[^)]+\)' "$SKILL_MD" 2>/dev/null | tr -d '()' || true)

if [ -n "$NESTED_REFS" ]; then
    warn "Disclosure" "Nested references detected (max 1 level deep):$NESTED_REFS"
else
    pass "Disclosure" "References are at most one level deep"
fi

# --- 6. Reference file TOC check ---
while IFS= read -r -d '' f; do
    [ "$(basename "$f")" = "SKILL.md" ] && continue
    LINE_COUNT=$(wc -l < "$f" | tr -d ' ')
    if [ "$LINE_COUNT" -gt 100 ]; then
        TOP20=$(head -20 "$f")
        if ! echo "$TOP20" | grep -qi "contents\|table of contents"; then
            rel="${f#$SKILL_DIR/}"
            warn "Disclosure" "$rel is $LINE_COUNT lines but has no table of contents"
        fi
    fi
done < <(find "$SKILL_DIR" -type f -name "*.md" -print0 2>/dev/null)

# --- 7. Time-sensitive content ---
if echo "$BODY" | grep -qiE "(before|after|as of|starting)\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+[0-9]{4}"; then
    warn "Content" "Time-sensitive language detected - consider using an 'old patterns' section"
fi

# --- 8. Too many options ---
if echo "$BODY" | grep -qiE "(you can use|options?:?).*,\s*or\s+.*,\s*or\s+"; then
    warn "Content" "Multiple equivalent options offered without a clear default"
fi

# --- Report ---
report

if [ ${#FAILS[@]} -gt 0 ]; then
    exit 1
else
    exit 0
fi
