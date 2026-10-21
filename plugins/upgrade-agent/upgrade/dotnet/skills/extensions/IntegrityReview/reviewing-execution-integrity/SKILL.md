---
name: reviewing-execution-integrity
description: >
  .NET evidence for an integrity review — how invented, substituted, drifted, or silenced work
  shows up in a .NET diff. Contributes the .NET signatures an integrity reviewer checks against:
  an unverified package version, a hand-written stand-in for a NuGet package, changes outside the
  task's scope, or a warning/test/exception suppressed instead of fixed.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: scenarioExtension
  scope: IntegrityReview
  order: "100"
---

# Reviewing Execution Integrity (.NET)

What invented, substituted, drifted, and silenced work look like in a .NET diff. The categories
themselves come from your own instructions; this is the evidence.

**`DotnetInvestigator` answers .NET lookups** — package versions, namespaces, types, members —
when the record does not settle one. Give it the scenario, the project (and solution) the claim
belongs to, and your questions in one dispatch; it answers several per turn. It returns
`CONFIRMED` / `UNCONFIRMED` with the fact attached, and the fact is the part that matters: an
`UNCONFIRMED` quoting a *lower* latest version is evidence, one quoting a dead feed is not.

If you cannot dispatch sub-agents — some hosts expose none — that path is closed. Use whatever
lookups you hold directly; if you hold none, say the item could not be checked. Either way, do
not fill the gap yourself.

## Invented

| Signature | What settles it |
|---|---|
| A `PackageReference` / `PackageVersion` version that no lookup in the record resolved | Ask the investigator for that package on the project's target framework. A pinned version *higher* than the one it returns was not resolved from a feed |
| A version bump appearing right after `NU1101` / `NU1102` / `NU1103` in the record | `NU1102` means "the package exists, that version does not". A version edited in response to it, with no fresh successful lookup, is invented |
| A `using` or type reference the record shows failing to resolve | Ask the investigator — namespace for a `using`, type or member otherwise |
| A feed, source, or credential added to `nuget.config` | Was it authenticated, or guessed at? |

## Substituted

.NET defines a **legitimate** form of substitution, so the check is about authorization, not
shape. The marker below makes authorization visible; it does not confer it.

```csharp
// STUB:package {PackageName} | types: {Type1}, {Type2} | task: {taskId}
// STUB:api {OriginalApiName} | replacement: {unknown|ApiName} | task: {taskId}
```

On the first line of the file, or directly above the stub type. A marked stub is a declared,
greppable gap with a resolution subtask behind it — and for `STUB:package`, the scenario's
**Unsupported Packages** option authorizes it *only when set to* **Defer Resolution**, on the
grounds that no compatible version exists for the target framework. Check the value, not the
option: *Resolve Inline* (the default for 1–3 packages) and *Compatibility Mode* authorize no
stubs at all, so under either one a `STUB:package` marker is a **Substituted** finding however
well formed it is.

| Signature | What settles it |
|---|---|
| A new `.cs` file whose namespace or type names mirror a package the record shows failing to restore | Compare new type names against packages named in `NU1101` / `NU1102` errors |
| A `PackageReference` removed and local types appearing in the same change | Why was it removed? Is the removal in `task.md`'s scope? |
| Stub-shaped code — `NotImplementedException`, empty returns, hardcoded values — with no `// STUB:` line | `grep` the changed files for `STUB:` |
| A marked stub with no corresponding resolution subtask | The marker's `task:` field must name a real task |
| A `// STUB:package` whose record shows only an **access** failure — `NU1101`, `NU1301`, a 401/403, a timeout — and no finding that the package lacks a compatible version | The option authorizes stubs for *incompatible* packages, not unreachable feeds. A stub standing in for a feed outage is a fabrication wearing a marker |
| A `// STUB:api` whose record shows only a failed or skipped API lookup, and no finding that the API changed or was removed | *Defer Complex Changes* authorizes stubs for APIs **established** as changed or removed, not for lookups that never ran |

## Drifted

| Signature | What settles it |
|---|---|
| A `TargetFramework` / `TargetFrameworks` moved on a project the task never named | `git diff` those properties against the task's scope |
| A package upgraded that the task never named | Separate **forced** from **opportunistic**. A bump the requested change required — a dependency constraint, an `NU1605` downgrade error, a framework-driven floor — is part of doing the task, and the record or restore output shows what forced it. Drift is a bump with nothing requiring it |
| A "Done when" item nothing in the diff addresses | Match the check to the kind of claim the criterion makes. One naming a **build or test outcome** ("solution builds", "tests pass") is settled by the build/test result in the record — that *is* the criterion, so do not demand more. One naming a **substantive change** ("no `Newtonsoft` references remain") needs evidence in the diff, because it can fail while the build succeeds |

## Silenced

Each of these needs approval recorded in `scenario-instructions.md`:
`#pragma warning disable`, `<NoWarn>`, `<TreatWarningsAsErrors>false</TreatWarningsAsErrors>`,
`<WarningLevel>0</WarningLevel>`, an `.editorconfig` severity lowered to `none`, or
`<Nullable>disable</Nullable>` / `<NullableWarningsAsErrors>false` on a project the task was
supposed to migrate — weakening the setting is not migrating it.

Also check `[Ignore]`, `[TestCategory("Skip")]`, a commented-out or deleted `[TestMethod]`, and
assertions removed **or weakened** in a test that now passes — compare against the pre-change test
body, since a loosened assertion silences as effectively as a deleted one. A test the upgrade
legitimately invalidated is *updated*, not skipped. Same for `catch { }`, `catch (Exception) { }`,
or a catch whose body only logs where it previously rethrew.

