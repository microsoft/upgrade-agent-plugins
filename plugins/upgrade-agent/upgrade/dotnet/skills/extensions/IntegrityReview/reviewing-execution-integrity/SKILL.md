---
name: reviewing-execution-integrity
description: >
  .NET evidence for an integrity review — how invented, substituted, drifted, or silenced work
  shows up in a .NET diff. Contributes the .NET signatures an integrity reviewer checks against:
  a nonexistent package version, a hand-written stand-in for a NuGet package, changes outside the
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
for concrete concerns in changed code or dependencies. Missing lookup records alone are not findings.
Give it the scenario, project/solution, and your questions in one dispatch; it answers several per turn. It returns
`CONFIRMED` / `UNCONFIRMED` with the fact attached, and the fact is the part that matters: an
`UNCONFIRMED` quoting a *lower* latest version is evidence, one quoting a dead feed is not.

If you cannot dispatch sub-agents — some hosts expose none — that path is closed. Use whatever
lookups you hold directly; an unavailable lookup does not establish a defect.

## Behavioral API notices

Use available `Behavioral API review` dispositions. Reuse still-current evidence as context.
Do not audit execution records. Investigate only concrete risks in affected code/configuration.
Do not demand a code change or new runtime test for an evidenced not-applicable
or low-impact advisory notice.
Significant risk remains blocking without a targeted resolution or explicit user decision;
a passing build alone does not settle runtime risk.

## Invented

| Signature | What settles it |
|---|---|
| A changed `PackageReference` / `PackageVersion` conflicting with package metadata or the target framework | Resolve the specific version/framework discrepancy with the investigator |
| A version bump appearing after `NU1101` / `NU1102` / `NU1103` | Check the selected version, not whether its lookup was recorded; the earlier failure alone does not invalidate the replacement |
| A `using` or type reference the record shows failing to resolve | Ask the investigator — namespace for a `using`, type or member otherwise |
| A feed, source, or credential added to `nuget.config` | Check the endpoint/configuration and authorization, not whether authentication was logged |

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
| A `// STUB:package` replacing a package because its feed is inaccessible rather than the package being incompatible | The option authorizes stubs for *incompatible* packages, not unreachable feeds; check the substitute and its authorization |
| A `// STUB:api` replacing an API that remains available and compatible | *Defer Complex Changes* authorizes stubs for changed or removed APIs; a failed lookup alone neither authorizes the substitute nor proves it wrong |

## Drifted

| Signature | What settles it |
|---|---|
| A `TargetFramework` / `TargetFrameworks` moved on a project the task never named | `git diff` those properties against the task's scope |
| A package upgraded that the task never named | Separate **forced** from **opportunistic**. A bump the requested change required — a dependency constraint, an `NU1605` downgrade error, a framework-driven floor — is part of doing the task, and the record or restore output shows what forced it. Drift is a bump with nothing requiring it |
| A required implementation change absent from the diff, such as remaining `Newtonsoft` references after a requested removal | Inspect affected code for the missing change; build/test completion checks belong to execution/validation, not review |

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
