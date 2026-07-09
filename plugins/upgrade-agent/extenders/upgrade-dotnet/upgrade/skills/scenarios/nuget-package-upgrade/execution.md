# Stage 3: Execution

Execute the plan task by task using the system task-execution skill. Each task applies the version
change for its project(s) and fixes the flagged source-breaking usages, then validates with a
build.

## Entry Criteria

- `plan.md` and `scenario-instructions.md` exist.

## Exit Criteria

- Target version(s) applied across the scoped projects (per the chosen reconciliation option).
- All flagged breaking-change usages fixed or explicitly accepted.
- Scoped projects restore and build; tests (if any) pass.

## 1. Apply the version change (CPM-aware)

For any task that changes a package version, apply the **managing-package-references** skill.
It handles CPM (`Directory.Packages.props`) vs per-project references, `VersionOverride`, and
verifying the change with `dotnet restore`/`dotnet build`. If the plan calls for moving to Central
Package Management first, apply the **converting-to-cpm** skill before the version bump.

Respect the reconciliation decision from `scenario-instructions.md`:
- Unified version → set it once (centrally under CPM, or per project otherwise).
- Per-project pins / `VersionOverride` → apply only to the projects that need them.
- Excluded projects → leave their version unchanged.

## 2. Fix breaking-change usages

The fix loop depends on which assessment mode was run.

### Quick assessment (default) — build-driven

There are **no** `PkgApi.*` incidents in quick mode. Drive fixes from build errors, using the API
diff artifacts as the reference:

1. After applying the version bump (section 1), restore and build the task's project(s).
2. For each build error, consult the package's `apidiff/{packageId}.apidiff.md` artifact — it lists
   the removed types/members and signature changes for that upgrade. Match the compiler error to the
   relevant entry.
3. Research the replacement API with `get_type_info` / `get_member_info` / `get_namespace_info`.
   > These tools resolve the API surface from the live package/compilation — they do **not** read the
   > `apidiff.md` files. Use the apidiff file to learn *what* changed; use these tools to learn *what
   > to use instead*.
4. Update the calling code to the new API. Prefer the smallest change that restores correctness.
5. Rebuild and repeat until the project compiles.

If the user wants exact locations up front instead of discovering them build-error by build-error,
offer to re-run the assessment with `fullScan=true` (see below).

### Full assessment (`fullScan=true`) — incident-driven

For each `PkgApi.0001` (removed) / `PkgApi.0002` (signature changed) finding in the task's
project(s):
1. Use `query_dotnet_assessment` to list the exact file/line incidents.
2. For each usage, research the replacement API with `get_type_info` / `get_member_info` /
   `get_namespace_info` (live API lookup, as above), cross-referencing the package's
   `apidiff/{packageId}.apidiff.md` for the specific change.
3. Update the calling code to the new API. Prefer the smallest change that restores correctness.

## 3. Validate

After applying changes for a task:
- Restore and build the affected project(s). Apply **building-projects** guidance for build-error
  triage.
- Resolve any remaining `NU`/`MSB` restore or version-conflict warnings (the
  managing-package-references skill covers CPM/version-conflict troubleshooting).
- If the project has tests, run them and report results.

## 4. Decomposition hints

Supplement the system task-execution skill with these scenario-specific breakdown rules:
- Split per project (or per dependency layer) so a failed upgrade has a small blast radius.
- When a single breaking change has many usages across files, a research subtask to settle the
  replacement pattern once (then apply it broadly) is usually worth it.
- Keep version-change tasks and code-fix tasks for the same project together — applying the bump
  without the fixes leaves the project non-compiling.

## 5. Completion

After all tasks: do a final restore + build across the scope, confirm the target version is in
effect everywhere it should be, and summarize what changed (versions, files fixed, any excluded
projects).
