# Stage 4: Validation

Prove the migration with a **host-adaptive** ladder: run whatever the host can physically execute
and surface the rest as recommended CI / manual steps — never silently skipped, never faked.

## Contents

- [Entry Criteria](#entry-criteria)
- [Exit Criteria](#exit-criteria)
- [The ladder](#the-ladder)
- [Step 0 — Detect the host RID](#step-0--detect-the-host-rid)
- [Step 1 — Gate (always, Milestone A)](#step-1--gate-always-milestone-a)
- [Step 2 — Native build + run + test (host matches the target RID)](#step-2--native-build--run--test-host-matches-the-target-rid)
- [Step 3 — Recommend real-RID validation and the CI leg](#step-3--recommend-real-rid-validation-and-the-ci-leg)
- [Milestone B — Emulated smoke & image inspection (opt-in)](#milestone-b--emulated-smoke--image-inspection-opt-in)

## Entry Criteria

- Execution complete: auto + approved-guided fixes applied; host build clean.
- Target RID(s) confirmed per project.

## Exit Criteria

- The host RID was detected (Step 0) so the native-run decision is explicit, not assumed.
- The cross-compile **Gate** (build + publish for each target RID) passed for every scoped project,
  or its failures are reported as concrete packaging/compile issues (migration not marked complete).
- Native run/test ran when the host matched the target RID; otherwise real-hardware / CI validation
  was recommended.
- The Gate boundary ("packaging/compile, not runtime correctness") was stated to the user.

## The ladder

```
Detect host RID
   → Gate: cross-compile build + publish for the target arm64 RID   (always — Milestone A)
        ↳ fails  → report unresolved packaging / native / compile issues; back to Execution
        ↳ passes → does the host RID match the target RID (OS + arch, and libc for musl)?
                      ↳ yes → Native build + run + full test suite (+ recommend a CI leg for durable coverage)
                      ↳ no  → recommend real matching-RID hardware and/or scaffold the ARM64 CI leg
```

**RID rule.** `<arm64-rid>` ∈ `{ win-arm64, linux-arm64, linux-musl-arm64, osx-arm64 }`, taken from
the confirmed `targetRids`. RIDs are always **lowercase**. Use an explicit `-r <rid>` — do **not**
also pass `-a arm64` (redundant/conflicting).

## Step 0 — Detect the host RID

The native-run decision (Step 2) depends on what the **build host** can physically execute, so
determine the host RID before running anything. Do not assume x64.

**Primary detection — ask the SDK.** Run `dotnet --info` and read the reported host **`RID:`** line
(for example `win-x64`, `osx-arm64`, `linux-x64`, or `linux-musl-x64`). That value is the SDK's own
host RID and already encodes OS, architecture, and — on Alpine — the `musl` libc flavor.

**Fallback — OS + process architecture.** If `dotnet --info` is unavailable, derive the host from the
environment: OS family (`win` / `osx` / `linux`) plus the process architecture (`x64`, `arm64`, …).
On Linux, treat the host as `musl` **only** when the SDK reports a `linux-musl-*` RID — a bare
`linux-*` host is glibc and does **not** satisfy a `linux-musl-arm64` target.

Record the host `{ os, arch, libc }`. A host is arm64 only when its architecture segment is `arm64`;
Rosetta / WOW-emulated x64 processes report `x64` and are treated as a non-matching host.

## Step 1 — Gate (always, Milestone A)

The Gate proves **restore + native-asset resolution + IL compilation** for the target RID with no
arm64 hardware. Run both a build and a publish per target RID:

| Project kind | Gate build | Gate publish |
|---|---|---|
| **SDK-style** | `dotnet build -r <arm64-rid>` | `dotnet publish -r <arm64-rid>` (framework-dependent by default on .NET 8+ when `-r` is passed; add `--self-contained true` only when the project opts into self-contained) |
| **Classic / non-SDK Framework** | `msbuild.exe /p:PlatformTarget=ARM64` after establishing an `ARM64` build platform mapping (see below) | n/a |

**Classic-Framework mapping is a guided edit.** Classic csproj uses `PlatformTarget`, not `Platform`,
and has no `ARM64` mapping by default, so the Gate cannot run until one is established. Adding it
mutates the solution and project, so treat it like `Arm64.0003` — a **guided**, persisted project
change, not a throwaway flag. Establish it by:

1. Adding an `ARM64` platform to the solution's `SolutionConfigurationPlatforms` **and** each scoped
   project's `ProjectConfigurationPlatforms` (a `Debug|ARM64` / `Release|ARM64` build+deploy mapping).
2. Adding a matching per-project condition — a `PropertyGroup` gated on the `ARM64` platform that sets
   `<PlatformTarget>ARM64</PlatformTarget>` (classic uses `PlatformTarget`, so this is where the arch
   is actually selected).

If no `ARM64` mapping can be established for a project, emit **"no Gate available"** for that project
rather than reporting a false green.

**What the Gate proves and does not prove — say this to the user.** Gate publish `-r <rid>` drives
NuGet's RID-graph resolution and **does** stage the `runtimes/<rid>/native/*` assets that *exist*, so
it exercises the present-but-mismatched-asset shape of `Arm64.0004`/`0005`. It **cannot** fail on a
package that is simply *missing* an arm64 native asset — that publishes **silently** under both
framework-dependent and self-contained modes and only fails at runtime with `DllNotFoundException`.
The static `Arm64.0004` check plus runtime Smoke/CI are what catch the missing-asset case. The Gate
is a *packaging/compile* gate, **not** an arm64 correctness certification (native load, P/Invoke
resolution, and concurrency behavior are not exercised).

**Interpreting Gate failures.** Route the failure back to the finding that explains it — do not mark
the migration complete on a red Gate:

| Failure signature | Likely cause | Route to |
|---|---|---|
| RID / runtime-pack restore error (e.g. `NETSDK1083`, "was not found ... for the specified runtime") | RID typo/casing, or no arm64 runtime pack for the TFM | `Arm64.0002` (RID/casing); confirm target RID |
| Restore resolves but a native package has no arm64 asset | Package missing an arm64 `runtimes/<rid>/native/*` | `Arm64.0004`/`0005` — bump or replace, back to Execution |
| Compile error referencing an x86/x64-only API or intrinsic | Unguarded x86 assumption reached the arm64 build | `Arm64.0006` (intrinsic guard) / `0012` (interop) |
| Classic build fails: unknown platform `ARM64` | The `ARM64` solution/project mapping was not established | Establish the mapping above, or emit "no Gate available" |

## Step 2 — Native build + run + test (host matches the target RID)

Run `dotnet test` (build + run + full suite) **only** when the detected host RID (Step 0) matches the
target RID — same OS **and** arch, and for musl targets the same libc flavor. Use this matrix:

| Target RID | Native run requires host RID |
|---|---|
| `win-arm64` | `win-arm64` |
| `osx-arm64` | `osx-arm64` |
| `linux-arm64` | `linux-arm64` (glibc) |
| `linux-musl-arm64` | `linux-musl-arm64` (a glibc `linux-arm64` host does **not** qualify) |

**Mode governs auto-run vs confirm.** In autopilot, run the native suite automatically on a matching
host; in interactive/guided mode, confirm before running it. When the host does **not** match
(different arch, different libc, or a different OS), do not fake it: go to Step 3.

## Step 3 — Recommend real-RID validation and the CI leg

- **Always** encourage validation on real ARM64 hardware — concurrency / weak-memory-model bugs
  (`Arm64.0009`) only surface there.
- **Scaffold an ARM64 CI leg** (a GitHub Actions arm64 build+test job) as the durable correctness path
  and the concrete remediation for `Arm64.0010`. How strongly to default it depends on whether Step 2
  already produced a native arm64 run, so resolve the posture by **host match first, then Flow Mode** —
  never ad-hoc:
  - **Host did *not* match the target RID (Step 2 could not run natively)** — the CI leg is usually the
    **only** durable runtime-validation path. In **Automatic** Flow Mode, scaffold it **by default** and
    **record** that you added it in the run summary; in **Guided** Flow Mode, **offer** it and scaffold
    only after the user approves. Skip only when a GitHub Actions arm64 leg already exists.
  - **Host *matched* the target RID (Step 2 ran a native arm64 build+run+test)** — you already have
    point-in-time runtime proof, so the CI leg's remaining value is **durable, team-wide regression
    coverage** (future pushes, teammates on x64, CI on x64). That is a team decision, not something to
    force-write: **recommend/offer** it in *every* Flow Mode — including Automatic — and scaffold only
    after the user opts in. Still skip when an arm64 leg already exists.

  Scaffold it with the `scaffold_arm64_ci_leg` tool (repo root + confirmed arm64 `targetRids`) — it
  writes an idempotent `.github/workflows/arm64.yml` with the runner selected per target OS and a
  hosted-vs-self-hosted availability note, and is safe to re-run. See execution [§6.3](execution.md)
  for the per-provider posture and the non-GitHub-provider path.

## Milestone B — Emulated smoke & image inspection (opt-in)

These extend validation beyond the Gate for **`linux-x64 → linux-arm64`** work. They are opt-in and
run **natively** through the agent's shell (no dedicated tool); win-arm64 / osx-arm64 bypass them
(Linux containers cannot host those targets). Always label results **approximate** — emulation does
not represent performance and will not surface weak-memory-model races (`Arm64.0009`).

### Container-image architecture inspection

After a Dockerfile is remediated ([execution §6.1](execution.md)) and an image is built for
`linux/arm64`, confirm the image actually carries an arm64 variant before trusting it — do not assume
the build platform. Inspect it natively with whichever tool is present:

- `docker buildx imagetools inspect <image>` — lists the platforms in a multi-arch manifest.
- `docker manifest inspect <image>` — shows each manifest's `platform.architecture` (expect `arm64`).
- `skopeo inspect --raw docker://<image>` — registry-side inspection when Docker is unavailable.

Report the architectures found; a `linux/arm64` entry present is the pass signal, its absence is a
finding routed back to the Dockerfile remediation.

### Emulated Smoke run

Opt-in, `linux-x64 → linux-arm64` **only**, and only when Docker with buildx/emulation is available:

1. **Detect capability.** Check `docker buildx version` (and that QEMU/binfmt emulation is
   registered). If Docker or buildx is absent, **skip gracefully** with a one-line message telling the
   user the smoke run was skipped and pointing at the CI leg as the durable path — never fail the
   migration on a missing local Docker.
2. **Build for arm64.** `docker build --platform linux/arm64 -t <app>:arm64 .` (buildx sets
   `TARGETARCH=arm64`, driving the cross-publish from execution §6.1).
3. **Run under emulation.** `docker run --rm --platform linux/arm64 <app>:arm64` — exercise a real
   startup / health path (native load + P/Invoke resolution that the Gate cannot prove).

A green emulated run raises confidence that native assets load and the app starts on arm64; it is
**not** a substitute for real-hardware or CI validation. State that explicitly.
