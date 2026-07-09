# Stage 1: Assessment

Resolve target versions, reconcile them across the scoped projects, detect source-breaking API
changes between the current and target versions of each package, and record everything in
`assessment.md`.

## Entry Criteria

- Pre-initialization complete (scope, package list, and version policy confirmed by the
  `scenario-initialization` skill).
- `initialize_scenario` already called — working folder exists at `.github/upgrades/{scenarioId}/`.
- If git repo: on the correct working branch.

## Exit Criteria

- `assessment.md` created in the workflow folder.
- **Guided mode**: user has reviewed and approved the assessment.
- **Automatic mode**: assessment summary surfaced to the user; proceed to planning immediately.

## Steps

### Step 1 — Run the assessment tool (quick by default)

Call `generate_package_upgrade_assessment` with:
- `inputMode`: `solution` | `projects` | `folder` (from the confirmed scope).
- `paths`: semicolon-separated scope paths.
- `packages`: the list of `{ name, version? }`. Include `version` only when the user specified
  one; omit it to let the tool resolve the newest version supported by each project.
- `fullScan`: **omit / `false` by default**. Only pass `true` when the user explicitly opts into
  the full code scan (see Step 4).
- `includePrerelease`: **omit / `false` by default** (latest **stable** only). Pass `true` **only**
  when the user explicitly asked for a preview/prerelease/beta/rc version. If the user asked for
  "latest" or "latest stable", leave it false so a preview is never picked. (An explicit preview
  `version` in `packages` is always honored regardless of this flag.)

The tool will, for each package and each scoped project:
1. Determine the **current** version from the project's resolved references.
2. Determine the **proposed** version (the user's version — validated against the project's target
   framework — or the newest supported version).
3. **Reconcile** proposed versions across projects and classify the result as **Unified** (one
   version works for all) or **Divergent** (projects need or support different versions).
4. Diff the old→new public API of each package and write a per-package artifact at
   `apidiff/{packageId}.apidiff.md` in the scenario folder listing every removed type/member and
   signature change. **This happens in both quick and full mode.**
5. **Quick mode (default):** does **not** run the expensive per-project semantic scan, so
   `PkgApi.0001` / `PkgApi.0002` incidents are **not** produced. The apidiff files (removed/changed
   API per package) plus the `Pkg.0001` presence findings are the breaking-change reference; exact
   call sites come from a build or from a full scan.
6. **Full mode (`fullScan=true`):** additionally run the semantic code scan and emit exact
   `PkgApi.0001` (removed) and `PkgApi.0002` (signature-changed) incidents at precise source
   locations.
7. Write findings to `assessment.md` (+ JSON).

### Step 2 — Interpret the result

Read the tool's summary and the generated `assessment.md`, and open the per-package
`apidiff/{packageId}.apidiff.md` files — these are the primary breaking-change reference in quick
mode. You can query details with `query_dotnet_assessment` (e.g. list issues for a project or file).

Key things to capture:
- **Recommended version per package**, and whether it is **Unified** or **Divergent**.
- **`Pkg.0001` (project references an upgraded package)** findings — one per affected project. This
  is the backbone of the assessment: it lists every project that references a package being upgraded,
  even when no breaking API changes were detected. (Produced in both modes.)
- **`Pkg.0003` (version divergence)** findings — projects that require different versions. This is
  the most common blocker; it must be resolved in planning. (Produced in both modes.)
- **API diff summary** from each `apidiff/{packageId}.apidiff.md` — how many types/members were
  removed or changed.
- **Types moved (namespace changed) are NOT removals.** The apidiff files report a type whose
  namespace changed but whose name is unchanged as a **Type moved** entry (`Old.Namespace.TypeName`
  → `New.Namespace.TypeName`), separate from the "Types removed" count. Treat these as a
  `using`-directive fix (and any listed member changes), **not** as a deleted type. Do not tell the
  user a type was removed when the apidiff shows it was moved.
- **`PkgApi.0001` / `PkgApi.0002`** findings — concrete source locations. **Only present in full
  mode.** In quick mode there will be none; do not treat their absence as "no breaking changes".
- Any project where a **user-provided version is incompatible** with the target framework.

### Step 3 — Summarize for the user

Present a short summary: the package(s), current → proposed version, Unified/Divergent status, and
the API-diff impact per package (counts from the apidiff files; exact incident counts in full mode).
Flag divergence and incompatibilities explicitly — they require a decision in planning.

**Always offer the full scan.** In quick mode, explicitly tell the user something like: "This was a
quick assessment based on the package API diff. If you want, I can run a full code scan to pinpoint
the exact source location of every breaking-change usage across the repo — it's slower, so it's
opt-in." Only re-run with `fullScan=true` if the user asks.

### Step 4 — (Optional) Full code scan

If the user opts in, re-run `generate_package_upgrade_assessment` with the same arguments plus
`fullScan=true`. This regenerates `assessment.md`/JSON with exact `PkgApi.0001`/`PkgApi.0002`
incidents and refreshes the apidiff files.

> Note: This scenario writes its own **concise, package-focused** `assessment.md` (recommended
> versions, per-package API-change counts linking to the `apidiff/*.apidiff.md` files, and the
> breaking-change posture). The machine-readable `assessment.json` (+ `dependencies-health.json`)
> uses the shared shape, so `query_dotnet_assessment` and the dashboard Assessment view work
> unchanged. The `apidiff/*.apidiff.md` files are additional scenario-local artifacts.

## Known limitations

The API breaking-change data is best-effort. Treat a clean result as "no high-confidence breaks
found", not a guarantee. Current caveats:

- **Quick mode does not locate call sites.** The default quick assessment reports the package API
  diff (removed/changed types and members per package) and the `Pkg.0001` presence findings only —
  it does not scan source, so it produces no per-line usage data. Use `fullScan=true` for exact,
  semantically-resolved locations, or drive fixes from build errors.
- **Overloaded members are skipped** (full scan). When a member name is overloaded in the current
  package version, the scanner cannot attribute a call site to a specific overload by name, so
  changes to overloaded members are not reported. Single-overload signature/parameter changes are
  still reported.
- **Nested public types are not captured.** Only top-level public types enter the API graph, so
  breaks involving nested public types are not detected.
- **Inconclusive scans report nothing.** If either package version cannot be downloaded or scanned,
  the diff is treated as inconclusive (empty) rather than reporting every API as removed.

When breaking changes matter, still review the package's own release notes/changelog before
upgrading.
