# Stage 1: Assessment

Detect every ARM64 migration concern across the scoped projects — project-file settings,
NuGet native assets, source-code hazards, and infrastructure — and record them in
`assessment.md` (+ JSON).

## Entry Criteria

- Pre-initialization complete (scope, target RID(s), and the .NET Framework decision gate
  resolved by the `scenario-initialization` skill).
- `initialize_scenario` already called — working folder exists at `.github/upgrades/{scenarioId}/`.
- Any `< 4.8.1` Framework project that declined modernization is **already excluded** from scope.
- If git repo: on the correct working branch.

## Exit Criteria

- `assessment.md` created in the workflow folder.
- **Guided mode**: user has reviewed and approved the assessment.
- **Automatic mode**: assessment summary surfaced to the user; proceed to planning immediately.

## Steps

### Step 1 — Run the assessment tool

Call `generate_arm64_migration_assessment` with:
- `inputMode`: `solution` | `projects` | `folder` (from the confirmed scope).
- `paths`: semicolon-separated scope paths.
- `targetRids` (optional): the confirmed subset of `{ win-arm64, linux-arm64, linux-musl-arm64,
  osx-arm64 }`. **Omit** to let the tool infer per project from project type and current RIDs.
  Pass it only when the user named specific targets. RIDs are always **lowercase**; never pass
  `linux-musl-arm64` unless the user explicitly asked for musl/Alpine.
- `excludedProjects` (optional): semicolon-separated project paths already removed from scope at
  Pre-Init (e.g. a blocked `< 4.8.1` Framework project). Alternatively, downgrade a
  `solution`/`folder` scope to `inputMode=projects` with only the surviving paths.

The tool will, over the scope:
1. Resolve scope → project set.
2. Read each project's **project-file** signals (PlatformTarget, Prefer32Bit, TFM, RIDs,
   SelfContained) and project-file 32-bit interop markers (`<COMReference>`, VSTO / Office
   add-in references).
3. Walk the **package graph**: for each package with `runtimes/*/native/`, check arm64 asset
   presence per target RID and resolve a **safe** arm64-supporting version via NuGet (lowest
   version that keeps the TFM, avoids a major-version jump, and carries no deprecation/security
   advisory — else guided). A missing **musl-specific** asset when `linux-musl-arm64` is targeted
   is a guided/potential concern, not merely informational.
4. Scan **infra** (Dockerfiles, CI YAML) for single-arch patterns / a missing native-arm leg.
5. Run a focused analysis pass so **only** the ARM64 (`Arm64.*`) providers fire, write
   `assessment.json`, and compose a tailored ARM64 `assessment.md`.

> **Overwrite policy.** This tool **replaces** the shared `assessment.md`/`assessment.json`
> for the current run (last-writer-wins, matching `generate_package_upgrade_assessment`). In a
> mixed session where other projects were just version- or package-upgraded, this overwrites
> that view — re-run the other scenario's assessment to regenerate it. This is intentional.

### Step 2 — Interpret the result

The tool's tailored `assessment.md` already lists every finding, grouped by surface (project
settings → native packaging → architecture-sensitive code → infrastructure). Read it plus the
tool's summary; you can query details with `query_dotnet_assessment` (e.g. list issues for a
project or file). You do **not** need to re-classify findings here — the auto-fix / guided /
flag triage happens in Planning. Focus on reading the four surfaces and the one cross-stage signal:

- **Project surface** — RID/platform settings (`Arm64.0001`–`0003`) and the 32-bit interop
  inventory (`Arm64.0012`).
- **NuGet surface** — native packages missing an arm64 build or that are arm64-incompatible
  (`Arm64.0004`/`0005`), with the safe-version the tool resolved.
- **Code surface** — the x86 hardware-intrinsic, bitness, unaligned-access, and concurrency
  candidates (`Arm64.0006`–`0009`).
- **Infra surface** — single-arch Dockerfile / CI findings (`Arm64.0010`, detection only here).

⚠️ **The one signal to carry into Planning:** whether `Arm64.0012` reported any 32-bit interop.
It is the ordering input that decides whether the `Arm64.0001` platform-target fix is automatic or
guided — note its presence/absence now so Planning can correlate the two.

> **Expect over-selection on the awareness rules.** `Arm64.0007`–`0009` are deliberately
> conservative and will flag call sites that are already arm64-correct. That is by design — they
> are review prompts, never auto-fixes. Do not treat their count as a defect count.

### Step 3 — Summarize for the user

Present a short summary grouped by surface: how many project / NuGet / code / infra findings, the
target RID(s) per project, and the packages needing an arm64 version. Explicitly call out any
`Arm64.0012` 32-bit interop, because it gates the `Arm64.0001` platform-target fix in Planning.

State the Gate boundary up front: this assessment plus the Milestone A Gate prove packaging and
compile for arm64, **not** runtime correctness — native load, P/Invoke resolution, and
concurrency behavior still need matching-RID execution (native run, Smoke, or CI).

## Known limitations

- **The awareness rules over-select** (`0007`–`0009`) — treat them as review candidates.
- **`Arm64.0004` missing-asset detection is static.** A package that is simply *missing* an arm64
  native asset is caught here and by runtime Smoke/CI — the cross-compile Gate **cannot** fail on a
  missing asset (it publishes silently). Do not rely on the Gate alone to catch a missing asset.
- **`Arm64.0012` is conservative.** It flags any detected 32-bit interop and never tries to prove a
  64-bit successor exists — expect it to over-flag rather than miss.
