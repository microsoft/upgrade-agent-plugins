---
name: converting-to-sdk-style
description: >
  Converts legacy non-SDK-style .NET project files (.csproj, .vbproj, .fsproj) to modern SDK-style
  format while preserving target frameworks, dependencies, and build behavior. Use when converting
  old-format .NET projects, migrating from packages.config to PackageReference, or modernizing
  project files. Also triggers for "convert to SDK style", "modernize csproj", "update project
  format", "legacy project migration", and "SDK-style conversion".
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# SDK Style Conversion

## Overview

Guide the step-by-step conversion of legacy (non SDK-style) project files to SDK-style while preserving existing target frameworks, behavior, and build output. This is a structural-only conversion — no target framework changes or functional refactors.

## Hard Constraints

- Do not change, add, remove, or upgrade TargetFramework/TargetFrameworks values — this conversion is format-only, not an upgrade
- Do not introduce new package versions unrelated to conversion — package drift causes subtle runtime issues
- Only convert the project format using the provided tools and fix build issues directly caused by the conversion

## Available Tools

- **Project ordering tool**: Use a tool capability to obtain the topological (dependency) order. Do not hand-compute and stop if unsuccessful
- **SDK style conversion tool**: Use the dedicated conversion tool for each project. Do not manually rewrite XML and stop if unsuccessful

## Workflow

### Execution

Use appropriate tools (not direct file reads) to gather project information. For each project in topological order, convert **one project at a time** — never invoke the conversion tool for multiple projects in parallel (the underlying MSBuild engine uses shared global state that is not safe for concurrent access):

1. Invoke the SDK style conversion tool and **wait for it to complete**
2. Build the converted project directly (not the solution) — solution-level builds introduce noise from unconverted downstream projects. If build fails, see "Common Issues" below. If warnings/errors exceed context window capacity, process them in chunks
3. If failures persist and cannot be resolved without violating constraints, mark Status = Blocked, record the blocker in the plan file, and stop — do not proceed past a blocked dependency since downstream projects depend on it
4. If the project does not build after fix attempts, stop and let the user resolve it
5. Verify the `packages.config` file is removed from the project
6. Commit or checkpoint changes after each successful project (atomic progression)

### Per-Project Checklist

```
- [ ] Used ordering tool output (not manual guess)
- [ ] Conversion tool executed (not a hand rewrite)
- [ ] No TargetFramework/TargetFrameworks modifications
- [ ] Project builds successfully
- [ ] Directly related tests pass
- [ ] Plan file status updated
- [ ] Minimal diff (only removed redundant legacy metadata now implicit in SDK style)
```

## Common Issues

### ItemGroup with removed items that shouldn't be included with globbing

The conversion tool adds a special label to ItemGroups tracking files excluded from globbing. After a successful build, check for this condition unless told to ignore it. If found, list the files for the user and get confirmation before removing them. If declined, leave as-is and continue.

### Missing packages

If the converted project is missing packages, identify and restore them. Keep all package versions identical — version changes are out of scope for format conversion.

## Handling Blockers

When a project fails to build after reasonable, minimal fixes:

1. Revert any speculative edits unrelated to conversion
2. Capture error messages in the plan file's Notes column
3. Mark Status = Blocked and stop — escalate or request user input before proceeding to dependent projects
4. When uncertain, ask the user for guidance

## Success Criteria

- All projects converted from legacy to SDK-style format
- All projects build successfully with no target framework changes
- Plan file shows all projects as "Done" or has documented blockers
- All packages.config files removed from converted projects

Follow these instructions exactly. Ask for guidance if an action would require modifying target frameworks or performing broader upgrades.
