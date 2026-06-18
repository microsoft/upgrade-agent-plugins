---
name: sdk-style-conversion
description: >
  Converts legacy .NET projects to SDK-style project format.
  Use when user wants to convert to SDK-style, modernize project files,
  or migrate from legacy csproj format. Does not change target frameworks.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  traits: .NET|CSharp|VisualBasic|DotNetCore|DotNetFramework
  scenarioTraitsSet: [.NET]
---

# SDK-style Project Conversion

## 1. Assessment

Scan the solution to identify which projects need conversion and what complications to expect. Capture findings in `assessment.md`.

### How to Identify Non-SDK-Style Projects

A project is non-SDK-style if it has any of:
- No `Sdk` attribute on the `<Project>` element
- Explicit file includes (`<Compile Include="...">` for every source file)
- `packages.config` file in the project directory
- `<Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />` or similar explicit tool imports

### Patterns to Identify

For each non-SDK-style project, record:

| Pattern | What to Record |
|---------|---------------|
| `packages.config` | Present? — must be migrated to `PackageReference` |
| Explicit file includes (`Compile`, `Content`, `None`, `EmbeddedResource`) | Count — SDK-style uses globbing, these become implicit |
| Custom `Import` elements | Which targets are imported — may need preservation |
| `AssemblyInfo.cs` with assembly attributes | SDK-style auto-generates these — potential duplication |
| Multi-targeting (`TargetFrameworks` plural) | Already SDK-like, may be partial conversion |
| WPF/WinForms markers (`<UseWPF>`, `<UseWindowsForms>`, XAML files) | Needs `Microsoft.NET.Sdk.WindowsDesktop` or `net*-windows` TFM handling |
| Web project type GUIDs (`{349c5851-...}`) | ASP.NET projects have special post-conversion considerations |
| Custom build events or targets | Must be preserved through conversion |

### Risk Indicators

Flag these as higher complexity:
- **ASP.NET Framework web projects**: SDK-style conversion is technically possible, but .NET tooling (Visual Studio, `dotnet build`) does not fully support SDK-style projects targeting ASP.NET Framework (non-Core). Custom MSBuild techniques or workarounds may be needed to maintain build and publish behavior. NuGet compatibility issues can also arise post-conversion
- **Heavy custom MSBuild logic**: Custom targets, conditional imports, or property manipulation that might conflict with SDK defaults
- **Shared projects or linked files**: File linking patterns change in SDK-style

### Assessment Output

Create `assessment.md` in the workflow folder with this structure:

```markdown
# Assessment: SDK-style Conversion

## Projects to Convert
| Project | Path | packages.config | Custom Imports | Special Type | Risk |
|---------|------|----------------|----------------|-------------|------|
| MyApp.Core | src/Core/MyApp.Core.csproj | Yes | None | Class library | Low |
| MyApp.Web | src/Web/MyApp.Web.csproj | Yes | 2 custom targets | ASP.NET | High |

## Already SDK-style (no action needed)
- [list or "none"]

## Baseline
- Solution builds: Yes/No
- Warning count: [number]

## Key Findings
- [Notable patterns, risks, or decisions needed]
```

## 2. Planning

Based on the assessment, create `plan.md` with tasks ordered topologically (leaf dependencies first, so each project can build after conversion).

For each task include:
- Which projects or groups of projects are covered
- What complications are expected (packages.config, custom imports, special project types)
- Risk level and anything requiring user decision

**Hard constraint**: Do not change TargetFramework during conversion — that is a separate scenario (dotnet-version-upgrade).

## 3. Execution

Execute the plan task by task. For any task that involves converting a project to SDK-style, apply the **converting-to-sdk-style** feature skill. It provides a dedicated conversion tool and a two-phase workflow (planning + execution with per-project checklist).

Verify the solution builds after each project or group is converted — catching errors early prevents cascading failures in dependent projects.

## 4. Validation

- Build the full solution — zero errors required (or no regressions from baseline)
- All `packages.config` files removed from converted projects
- No TargetFramework values changed
- If the project had tests, run them and report results
