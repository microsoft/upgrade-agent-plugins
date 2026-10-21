---
name: recovering-from-blocked-dependency-resolution
description: >
  What to do when a .NET upgrade task is blocked by something outside your control — an
  unreachable NuGet feed, expired credentials, a package or version that will not resolve, a
  restore or an API lookup that fails. Gives the recovery order, the one legitimate way to
  proceed without the dependency, and what to report when nothing works. Use when hitting
  NU1101, NU1102, NU1103, NU1301, 401/403 from a feed, "unable to load the service index", a
  failed restore, or any fact a change depends on that could not be verified. Also triggers for
  "recovering from a blocked nuget feed", "package will not resolve", "feed unreachable",
  "cannot verify package version", and "blocked on environment" in .NET work.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Recovering From a Blocked Dependency Resolution (.NET)

## The rule this exists to enforce

**Never assert a version, an API, or a type that nothing returned to you.**

A wall is not a licence to invent. If you could not verify a fact, you have three options and
only three: resolve it properly, declare the gap in the one marked form the scenarios define, or
report the blocker. Filling the gap from your own knowledge is none of them, and it is the most
expensive failure this product has — it looks like success.

## Recovery order

Work down this list. Stop at the first step that succeeds.

### 1. Authenticate the feed

Most feed failures are credentials, not outages, and this is the cheapest fix. Establish that the
feeds are reachable and authenticated **before** concluding anything is unreachable, using whichever
tool you have for it — `authenticate_nuget_feed` if it is in your roster, otherwise a restore or a
source listing. Retry the operation afterwards.

Symptoms that mean "authenticate first": `401`, `403`, `NU1301` (unable to load the service
index), "unauthorized", "credentials", or a private feed URL in the error.

### 2. Resolve the version properly

`get_supported_package_version` for the project's target framework — not the latest version, and
not a version you recall. If it returns a version, use exactly that.

`get_project_dependencies` first if you do not yet know whether the project uses Central Package
Management; editing the wrong file is a silent no-op.

### 3. Read the NU code before reacting to it

They mean different things and only one is fixed by changing a version.

| Code | Meaning | Correct response |
|---|---|---|
| `NU1101` | Package not found on **any** source | The source list is wrong or the feed is unreachable. Do **not** change the version, and do **not** stub — neither the version nor the compatibility is established by this |
| `NU1102` | Package exists, **that version** does not | Look up a version that does exist (step 2). Never guess the nearest plausible number |
| `NU1103` | No **stable** version satisfies the range | Decide with the scenario's prerelease policy. Do not silently opt into a prerelease |
| `NU1301` | Cannot load the source's service index | Feed or auth problem. Go to step 1 — not to the version, and not to a stub |

### 4. Declare the gap, if the scenario allows it

A stub is authorized only when successful assessment or lookup evidence established the gap,
**and** the matching
scenario option is set to the value that permits one: **Unsupported Packages** = *Defer
Resolution* for `STUB:package`, **Unsupported API
Handling** = *Defer Complex Changes* for `STUB:api`. The option being *present* authorizes
nothing — *Resolve Inline* (the default for 1–3 packages) and *Compatibility Mode* both forbid
stubs, and under either one a `STUB:package` marker is itself a finding. A feed you could not
reach establishes nothing — `NU1101`, `NU1301`, a 401/403 or a timeout
sends you to step 5, whatever the option says. The marker does not make a stub legitimate; the
authorization does, and the marker makes it visible. Pick the form that matches what is missing:

```csharp
// STUB:package {PackageName} | types: {Type1}, {Type2} | task: {taskId}
// STUB:api {OriginalApiName} | replacement: {unknown|ApiName} | task: {taskId}
```

Use `STUB:package` when a whole package has no compatible version for the target framework, and
`STUB:api` when successful assessment established that the BCL or framework API changed or was
removed — set `replacement:` to the API you substituted, or `unknown` if no replacement
exists. An API you merely could not confirm is not a stub: that is an unestablished fact, and it
goes to step 5. These are
the only two forms a reviewer recognises; inventing a third marker shape reads as unmarked.

Place it as the first line of the stub file, or directly above the stub type in an existing file,
and raise the resolution subtask the scenario requires. Unmarked stand-in code is a defect, not a
stub — a reviewer will flag it as a Substituted finding.

### 5. Report the blocker

If none of the above worked, stop. Record in `progress-details.md`, and state in your return:

- The exact operation that failed, and its **verbatim** error text including the NU code.
- The package, feed, or API that could not be resolved.
- Which recovery steps you tried, so nobody repeats them.
- What is consequently unverified — name the fact you could not establish.

A reported blocker is a good outcome. It is recoverable in minutes. An invented version is
discovered weeks later, in someone else's code, and costs far more.

## Never do these

- Pick a version number because it looks plausible, is the latest you know of, or matches a
  sibling project. If no tool returned it this session, it is invented.
- Hand-write types, methods, or a namespace standing in for a package you could not restore,
  without the `// STUB:package` marker and its resolution subtask.
- Stub a package because a feed was unreachable or unauthenticated. The marker does not convert a
  feed outage into an authorized gap — it only makes an authorized one visible.
- Remove a `PackageReference` to make a restore succeed, when the task never asked you to drop
  the dependency.
- Add a feed or source to `nuget.config` speculatively to make an error go away.
- Suppress the resulting warning or skip the failing test instead of reporting the blocker.
  Removing the signal does not remove the problem, and it is separately a blocking review finding.
- Report `STATUS: ready` on a task whose central fact you could not verify.
