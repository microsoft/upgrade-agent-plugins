# Stage 3: Execution

Execute the plan task by task using the system `task-execution` skill. Each task applies its ARM64
fix (project-file, RID, package, or intrinsic guard), then validates with a host build. Supplements
the `task-execution` skill — does not replace it.

## Contents

- [Entry Criteria](#entry-criteria)
- [Exit Criteria](#exit-criteria)
- [1. Clear 32-bit interop that gates `Arm64.0001` (`Arm64.0012`)](#1-clear-32-bit-interop-that-gates-arm640001-arm640012)
- [2. Project-file & RID fixes (`0001`, `0002`, `0003`)](#2-project-file--rid-fixes-0001-0002-0003)
- [3. NuGet native-asset fixes (`0004`, `0005`)](#3-nuget-native-asset-fixes-0004-0005)
- [4. Guard x86 hardware intrinsics (`Arm64.0006`)](#4-guard-x86-hardware-intrinsics-arm640006)
- [5. Annotate flag-only findings (`0007`, `0008`, `0009`, residual `0012`)](#5-annotate-flag-only-findings-0007-0008-0009-residual-0012)
- [6. Infra findings (`Arm64.0010`)](#6-infra-findings-arm640010)
- [7. Validate (per task, host build)](#7-validate-per-task-host-build)
- [8. Decomposition hints](#8-decomposition-hints)
- [9. Completion](#9-completion)

## Entry Criteria

- `plan.md`, `tasks.md`, and `scenario-instructions.md` exist and (in guided mode) are approved.
- The `0001`↔`0012` ordering and CPM blast-radius decisions are recorded.

## Exit Criteria

- All auto-fixable and approved guided edits applied.
- Flag-only findings recorded as annotated tasks (not modified).
- Scoped projects restore and build clean on the host. The arm64 cross-compile Gate and any native
  run/test happen in [validation.md](validation.md).

## 1. Clear 32-bit interop that gates `Arm64.0001` (`Arm64.0012`)

Where the plan flagged `0001` as guided because `0012` interop is present, resolve the interop
**first**: replace or 64-bit-enable the `<COMReference>` / VSTO / Office add-in / native x86
P/Invoke, or confirm with the user that the interop is being removed. Only after the interop is
gone does `0001` become applicable for that project.

## 2. Project-file & RID fixes (`0001`, `0002`, `0003`)

- **`Arm64.0002` (RID)** — add the same-OS arm64 RID **additively**. **Keep the existing singular
  `<RuntimeIdentifier>` line verbatim** so the default (no-`-r`) build/publish output path is
  unchanged, and **add a separate `<RuntimeIdentifiers>` (plural) line** containing the arm64 RID.
  Normalize any `ARM64` casing to lowercase `arm64`. If an MSBuild condition is tied to the singular
  form, treat the change as guided.

  A project with `<RuntimeIdentifier>win-x64</RuntimeIdentifier>` becomes:

  ```xml
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <RuntimeIdentifiers>win-arm64</RuntimeIdentifiers>
  ```

  Do **not** convert, replace, or collapse the singular into a single plural such as
  `<RuntimeIdentifiers>win-x64;win-arm64</RuntimeIdentifiers>`: removing the singular
  `<RuntimeIdentifier>` drops the default RID and silently changes the default build/publish
  output path. When you add this RID on net8+, also pin the explicit framework-dependent default
  `<SelfContained>false</SelfContained>` per `Arm64.0003` below (never `true` without user approval).
- **`Arm64.0001` (platform target)** — remove `PlatformTarget=x86` / `Prefer32Bit=true`, but only
  when `0012` is clear for that project (auto) or after the interop cleanup in section 1 (guided).
- **`Arm64.0003` (SelfContained)** — the hard boundary is **"never make the app self-contained
  without an explicit user decision."** In every Flow Mode, including Automatic, do **not** write
  `<SelfContained>true</SelfContained>` and do **not** otherwise switch the effective deployment to self-contained
  (e.g. via `<PublishSelfContained>true</PublishSelfContained>` or a self-contained `dotnet publish`). Going self-contained
  is a deployment-mode change that is the user's call — surface it and record it as a **flag-only**
  review item (§5); only set it to `true` after the user explicitly asks, then record that request.

  Writing the **framework-dependent default explicitly is allowed and preferred** for transparency and
  consistency. When you add (or the project already has) an arm64 RID on net8+, pin
  `<SelfContained>false</SelfContained>` alongside it so the deployment mode is visible in the project
  file and identical across every run — direct or post-modernization. `false` is byte-for-byte the
  net8 framework-dependent default, so this changes no behavior; it only makes the existing default
  explicit. A project with `<RuntimeIdentifier>win-x64</RuntimeIdentifier>` becomes:

  ```xml
  <RuntimeIdentifier>win-x64</RuntimeIdentifier>
  <RuntimeIdentifiers>win-arm64</RuntimeIdentifiers>
  <SelfContained>false</SelfContained>
  ```

  The prohibition is specifically against silently making the app self-contained — not against
  recording the default. Never flip to self-contained on your own; always pin `false` when adding a
  RID unless the user asked for self-contained.

For classic (non-SDK) projects that need an `ARM64` `Configuration|Platform` mapping for the Gate,
that mapping is a guided project-file edit — see [validation.md](validation.md).

## 3. NuGet native-asset fixes (`0004`, `0005`)

- **`Arm64.0004` safe bump** — raise the package to the safe arm64-capable version the assessment
  resolved. For version changes, apply the **`managing-package-references`** skill (it handles CPM
  vs per-project references, `VersionOverride`, and restore/build verification). When the project
  uses Central Package Management, edit `Directory.Packages.props` and honor the CPM blast-radius
  guard from planning; if the plan calls for moving to CPM first, apply the **`converting-to-cpm`**
  skill before the bump. Only apply a central bump automatically when the plan cleared it.
- **`Arm64.0004` guided / `Arm64.0005`** — apply the user's chosen option: a major bump, a package
  replacement + the implied API changes, or a TFM raise. When a TFM change is involved, apply the
  **`managing-target-frameworks`** skill. Do not silently take a major/replace path the user did
  not approve.

## 4. Guard x86 hardware intrinsics (`Arm64.0006`)

For each unguarded `System.Runtime.Intrinsics.X86` use, scaffold the `…IsSupported` guard around
the x86 path and add the branch for the fallback — but the **author writes the fallback logic**.
Never silently rewrite the intrinsic or drop the fast path. Present each guard for review.

## 5. Annotate flag-only findings (`0007`, `0008`, `0009`, residual `0012`)

Record the awareness (`0007`/`0008`), concurrency (`0009`), and any residual `0012` findings as
annotated review tasks with their locations. Do **not** modify this code — these surface for human
inspection and, for concurrency, only reproduce on real arm64 hardware.

## 6. Infra findings (`Arm64.0010`)

`0010` remediation is **guided with opt-in auto-apply**, scoped by finding kind and target OS. Apply
these during Execution; the container-image inspection and emulated Smoke that _verify_ the result
live in [validation.md](validation.md).

### 6.1 Linux Dockerfiles → multi-arch cross-compile (auto-apply-capable)

When a Linux Dockerfile builds a single (non-arm64) architecture and the migration targets a
`linux-*-arm64` RID, convert it to the buildx multi-arch cross-compile pattern: stay on the native
`$BUILDPLATFORM` builder, publish for `$TARGETARCH`, and let the runtime base image resolve per-arch.

```dockerfile
# build stage: native builder, cross-publish for the requested target arch
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:<ver> AS build
ARG TARGETARCH
WORKDIR /src
COPY . .
RUN dotnet publish -a $TARGETARCH -c Release -o /app

# runtime stage: the arm64 variant is selected automatically when building --platform linux/arm64
FROM mcr.microsoft.com/dotnet/aspnet:<ver>
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "<App>.dll"]
```

Here `-a $TARGETARCH` is correct **because buildx sets `TARGETARCH`** — this is the reverse of the
host Gate rule in [validation.md](validation.md), where you pass an explicit `-r <rid>` and must not
add `-a`. Present the diff for review (guided); apply automatically only when the plan cleared it.

### 6.2 win-arm64 → CI-only (no Dockerfile remediation)

There is **no Windows Server ARM64 container base image**, so do **not** rewrite a Dockerfile for a
win-arm64 target. Enable win-arm64 through the CI leg instead (6.3) and leave the Dockerfile as an
annotated note explaining why it was skipped.

### 6.3 CI pipelines → arm64 build+test leg

- **GitHub Actions (auto-apply-capable)** — call the `scaffold_arm64_ci_leg` tool with the repo root
  and the confirmed arm64 `targetRids`. It writes an idempotent `.github/workflows/arm64.yml`
  build+test job (runner selected per target OS, with a hosted-vs-self-hosted availability note) and
  is safe to re-run: same RIDs → no change, a changed RID set → regenerated in place, a pre-existing
  hand-authored workflow → left untouched. Resolve the posture by **host match first, then Flow Mode**
  (see [validation.md](validation.md) Step 3): when the build host did **not** match the arm64 target
  RID, the CI leg is the only durable runtime path — **Automatic** Flow Mode scaffolds **by default**
  (record it in the run summary) and **Guided** Flow Mode presents it for review first. When the host
  **matched** the target RID and a native arm64 run already happened, the CI leg is durable regression
  coverage only — **recommend/offer** it in every Flow Mode (including Automatic) and scaffold only
  after the user opts in. Skip whenever a GitHub Actions arm64 leg already exists.
- **Other providers (Azure Pipelines / GitLab CI / other — detect + guided)** — the scaffolder does
  **not** edit these. Describe the equivalent arm64 job (an arm64 pool/runner plus
  `dotnet build/test -r <arm64-rid>`) and let the user add it. Never silently rewrite a non-GitHub
  pipeline.

## 7. Validate (per task, host build)

After applying each task's edits:
- Restore and build the affected project(s) on the host. Apply **`building-projects`** guidance for
  build-error triage.
- Resolve any remaining `NU`/`MSB` restore or version-conflict warnings (the
  `managing-package-references` skill covers CPM/version-conflict troubleshooting).
- If the project has tests, run them and report results.

A clean host build here is **necessary but not sufficient** — it does not prove arm64 packaging or
compilation. That is the cross-compile Gate's job in [validation.md](validation.md).

## 8. Decomposition hints

Supplement the system `task-execution` skill with these scenario-specific breakdown rules:
- Keep the `0012` interop cleanup and the dependent `0001` platform-target removal **in order** —
  never apply `0001` before the interop it depends on is gone.
- Split per project (or per dependency layer) so a failed fix has a small blast radius.
- Group a package's bump and the code fixes its API change implies into the same task — a bump
  without the fixes leaves the project non-compiling.

## 9. Completion

After all tasks: do a final restore + host build across the scope, confirm every scoped project
declares its arm64 RID with correct casing, and summarize what changed (project-file edits, RID
additions, package versions, intrinsic guards, and the annotated review/flag items left for the
user). Then transition to **Stage 4: Validation** — load [validation.md](validation.md) to run the
cross-compile Gate and any host-matched native run/test.
