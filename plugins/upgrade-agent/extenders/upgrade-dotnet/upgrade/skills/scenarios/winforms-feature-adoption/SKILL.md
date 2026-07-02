---
name: winforms-feature-adoption
description: >
  Adopts modern WinForms features in .NET 8+ applications including dark mode
  (Application.SetColorMode, SystemColors), async APIs (Control.InvokeAsync,
  Form.ShowDialogAsync, TaskDialog.ShowDialogAsync), and MVVM patterns (ViewModels,
  INotifyPropertyChanged, Commands, DataContext). Use when user requests "modernize WinForms",
  "add dark mode to WinForms", "implement WinForms MVVM", "add async to WinForms", "use
  InvokeAsync", "adopt modern WinForms features", or as a post-upgrade enhancement after
  dotnet-version-upgrade scenario completes. Also triggers for "Application.SetColorMode",
  "WinForms dark theme", "WinForms async patterns", "WinForms MVVM architecture",
  "modernize WinForms UI", and "enhance WinForms application". Prerequisite: projects must
  already target .NET 8+ (dark mode and async require .NET 9+).
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: medium
  weight: 8500
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & WindowsForms
  scenarioTraitsSet: [.NET, WindowsForms]
---

# WinForms Feature Adoption Scenario

Modernize WinForms applications with framework features introduced in .NET 8+ — dark mode support, modern async APIs, and MVVM data binding patterns.

**Prerequisite:** Projects must already target .NET 8+ (use dotnet-version-upgrade scenario first if needed).

## Scenario Overview

**Goal**: Enhance existing WinForms applications with modern features that improve user experience, code quality, and maintainability.

## Available Features by .NET Version

| Feature | .NET Version | Impact | Scope |
|---------|--------------|--------|-------|
| **Dark Mode** | 9.0+ | UI appearance | Application-level + per-control adjustments |
| **Async APIs** | 9.0+ | Code quality | Per-form/control async patterns |
| **MVVM** | 8.0+ | Architecture | Form-by-form or application-wide |

## Workflow Stages

```
┌──────────────────────────────────────────────────┐
│ 0. PRE-INITIALIZATION                            │
│    Validate TFM, detect WinForms projects        │
│    → Uses: scenario-initialization system skill  │
└───────────────────────┬──────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────┐
│ 1. FEATURE SELECTION                             │
│    Determine which features to adopt             │
│    → Creates: feature-selection.md               │
└───────────────────────┬──────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────┐
│ 2. PLANNING                                      │
│    Identify forms/controls to modernize          │
│    → Creates: plan.md, scenario-instructions.md  │
└───────────────────────┬──────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────┐
│ 3. EXECUTION                                     │
│    Apply feature adoption to codebase            │
│    → Uses: WinForms lazy skills                  │
└──────────────────────────────────────────────────┘
```

## Pre-Initialization

### Tools to Call

⛔ **Step 1**: Validate environment:
- Call `get_solution_path()` to identify solution
- Scan all WinForms projects (`.csproj` files with `<UseWindowsForms>true</UseWindowsForms>`)
- Check each project's `<TargetFramework>`:
  - Must be `net8.0` or higher
  - If below net8.0, inform user and suggest dotnet-version-upgrade first

⛔ **Step 2**: Present feature availability based on detected TFMs:

**If all WinForms projects are net9.0+:**
```
Available Features:
- ✅ Dark Mode Support (.NET 9+)
- ✅ Modern Async APIs (.NET 9+)
- ✅ MVVM Pattern (.NET 8+)
```

**If all WinForms projects are net8.0:**
```
Available Features:
- ❌ Dark Mode Support (requires .NET 9+ — upgrade first)
- ❌ Modern Async APIs (requires .NET 9+ — upgrade first)
- ✅ MVVM Pattern (.NET 8+)
```

**If mixed TFMs (some net8.0, some net9.0+):**
```
Available Features (varies by project):
- ⚠️ Dark Mode: available for net9.0+ projects only
- ⚠️ Async APIs: available for net9.0+ projects only
- ✅ MVVM Pattern: available for all .NET 8+ projects
```

⛔ **Step 3**: Ask user which features to adopt:
- Present checkboxes for available features
- Get scope preference: "Application-wide" or "Selected forms only"
- If "Selected forms only", list detected forms and get user selection

## Stage Instructions

### Stage 1: Feature Selection
**When entering this stage, load**: [feature-selection.md](feature-selection.md)

Determines which features to apply and to which forms/controls:
- Scan for existing Forms and UserControls
- Detect current patterns (existing async usage, data binding, color handling)
- Identify good candidates for each feature

### Stage 2: Planning
**When entering this stage, load**: [planning.md](planning.md)

Creates the execution plan:
- Task breakdown per feature (Dark Mode → Async → MVVM order)
- Dependency analysis (which forms depend on which)
- Risk assessment (Designer compatibility, breaking changes)
- Commit strategy (per-feature or per-form)

### Stage 3: Execution
**When entering this stage, load**: [execution.md](execution.md)

Applies the features using lazy-loaded WinForms skills:
- **Dark Mode**: Uses `building-winforms-applications` skill for `Application.SetColorMode()`, control color adjustments
- **Async APIs**: Uses `managing-winforms-async-apis` skill for `InvokeAsync` patterns, async event handlers
- **MVVM**: Uses `managing-winforms-mvvm` skill for ViewModel setup, data binding, Command patterns

## Success Criteria

- [ ] Selected features applied to target forms/controls
- [ ] Application builds without errors
- [ ] Designer can open and edit modified forms
- [ ] All tests pass
- [ ] Visual verification completed (for dark mode)

## Feature-Specific Validation

### Dark Mode
- [ ] `Application.SetColorMode()` called in Program.cs
- [ ] `SystemColors` used for automatic theming
- [ ] Custom colors have light/dark variants
- [ ] Manually verify appearance in both modes

### Async APIs
- [ ] All `Control.Invoke` replaced with `Control.InvokeAsync`
- [ ] Async event handlers wrapped in try/catch
- [ ] Cancellation tokens passed where applicable
- [ ] No blocking calls on UI thread

### MVVM
- [ ] ViewModels implement INotifyPropertyChanged (or use ObservableObject)
- [ ] Forms set DataContext to ViewModel
- [ ] Commands wired to UI actions
- [ ] Business logic separated from UI code

## Error Handling

**Designer compatibility breaks**:
1. Check that Designer code follows managing-winforms-designer-code rules
2. Verify no modern C# features in InitializeComponent
3. Revert problematic changes and apply them in regular code files only

**Build errors after MVVM adoption**:
1. Verify NuGet packages installed (CommunityToolkit.Mvvm if used)
2. Check DataContext binding paths match ViewModel properties
3. Ensure event handlers aren't removed when using Commands

## Notes

- This scenario is **opt-in enhancement** - not required for functional applications
- Features can be adopted incrementally (start with one form, expand later)
- Each feature is independent - can adopt dark mode without MVVM, etc.
- Always validate in the Designer after changes
