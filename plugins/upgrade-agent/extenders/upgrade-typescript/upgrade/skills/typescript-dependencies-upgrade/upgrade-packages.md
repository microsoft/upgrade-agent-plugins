# Phase 2 — Upgrade Dependencies

## Overview

For each dependency group from the upgrade plan, call the `typescript_upgrade_package_dependency_group` MCP tool. This tool handles the **full upgrade cycle** internally: modifying `package.json`, running the package manager install, compiling, and applying knowledge base fixes.

## Steps

1. **Call `typescript_upgrade_package_dependency_group`** with:
   - `rootDirectory` — the repository root
   - `packageDirectory` — the directory containing the `package.json` to upgrade
   - `dependencies` — the array of package names for this group (from the scan results)
   - `sessionId` — from the scan response

2. **Review the result.** The tool returns a summary including:
   - Which packages were successfully upgraded
   - Which packages could not be upgraded (and why)
   - Which files were modified (beyond `package.json`)
   - The tool will ask for confirmation if it modified source files

3. **If the upgrade succeeds** (`complete`), move to the next dependency group.

4. **If the tool reports `needs_regex_fixes`** (unresolved errors after knowledge base fixes):

   The response includes error groups organized by pattern, with affected files and example error messages. Your goal is to generate regex-based fixes and submit them for verification.

   **Step A — Generate regex fixes:**
   - Read the error groups from the response. Each group shares a common pattern and affects specific files.
   - Examine the affected files using your editor tools to understand the code pattern that needs to change.
   - For each error group, create a fix object containing the list of affected `files` and one or more `replacements` (each with a `pattern` and `replacement` string).
   - Prefer broad patterns that fix all occurrences across files in one replacement.
   - Use capture groups (`$1`, `$2`) to preserve parts of the original code.

   **Step B — Submit fixes for verification:**
   - Call `typescript_verify_upgrade` with:
     - `rootDirectory` and `packageDirectory` (same as above)
     - `regexFixes` — an array of fix objects, each containing:
       - `files`: array of relative file paths to apply the fix to
       - `replacements`: array of `{ "pattern": "...", "replacement": "..." }` objects

   Example `regexFixes` input:
   ```json
   [
     {
       "files": ["src/components/App.tsx", "src/components/Header.tsx"],
       "replacements": [
         { "pattern": "oldFunction\\((.*?)\\)", "replacement": "newFunction($1, options)" }
       ]
     }
   ]
   ```

   **Step C — Handle the verify result:**
   - `complete` — all errors resolved. If the response lists modified files, **inform the user which files were changed** by the regex fixes before moving to the next dependency group.
   - `needs_client_fixes` — some errors remain. The response includes remaining errors.
     - If the message indicates a **regex syntax error**, fix the pattern and retry (up to 2 retries for syntax issues).
     - If the regex was applied but **didn't resolve errors or introduced new ones**, it was automatically reverted. You may retry with different regex patterns, but **after 2 failed regex attempts, stop using `regexFixes`**. Instead, apply direct file edits to fix the remaining errors manually, then call `typescript_verify_upgrade` without `regexFixes` to verify.
     - Continue the fix → verify loop (up to 5 rounds total).
   - `failed` — stall detected or max rounds reached. The tool has already reverted all changes. Move to the next group.

5. **If the upgrade fails** due to install errors that the tool couldn't resolve:
   - Review the error output for peer dependency conflicts
   - You may need to manually adjust version ranges in `package.json` and re-run install
   - As a last resort, **revert the version changes in `package.json`**, run `typescript_install_dependencies`, and move to the next group

## NPM Audit (if enabled)

If the scan results indicate `runNpmAudit: true` and the package manager is npm, call the `typescript_npm_audit_fix_tool` MCP tool after each successful group upgrade:
- `rootDirectory` — the repository root
- `packageDirectory` — the package directory
- `upgradedPackages` — the list of packages just upgraded

This automatically fixes security vulnerabilities without introducing new build errors. If the audit fix introduces errors, the tool rolls back automatically.

## Guidelines

- **Inside the per-group verify loop only:** `typescript_verify_upgrade` compiles the project automatically, so do not call `typescript_compile_package` between `typescript_upgrade_package_dependency_group` and the matching `typescript_verify_upgrade` rounds — the verify tool already has the build result. This restriction applies *only* to the in-loop verify cycle. After all groups are done, you must still run the Phase 3 post-upgrade `typescript_compile_package` call (see SKILL.md Phase 3, step 1) to lock in the workflow-level post-upgrade snapshot.
- **Never leave unresolved errors behind.** If a group upgrade causes errors that cannot be resolved (by the tool, by your regex fixes, or by your direct edits), revert the package version changes in `package.json`, undo any source file edits, and run `typescript_install_dependencies` to restore the lockfile before moving on.
- **If `typescript_upgrade_package_dependency_group` times out** (e.g. MCP error `-32001`) instead of returning a result, the `package.json` version edits may already have been written before the timeout fired — don't assume nothing happened. Re-read `package.json` to check whether the group's versions were bumped. If they were, continue from install/compile (`typescript_install_dependencies`, then the verify loop or `typescript_compile_package`) rather than re-issuing the upgrade; if they weren't, retry the group once. Either way, don't leave the group half-applied.
- The project must compile cleanly after each group upgrade. If it doesn't, revert.
