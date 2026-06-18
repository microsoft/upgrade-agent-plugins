# Planning Stage Instructions

## Contents

- [Step 1: Extract from Assessment](#step-1-extract-from-assessment)
- [Step 2: Determine Strategy & Generate Plan](#step-2-determine-strategy--generate-plan)
- [Step 3: Save Plan](#step-3-save-plan)
- [Edge Cases](#edge-cases)

Create an upgrade plan for .NET Framework version upgrade to net481.

---

## Step 1: Extract from Assessment

Read `assessment.md` from the workflow folder. Extract:

| Signal | Used For |
|--------|----------|
| Project count | Strategy selection (All-at-Once vs Bottom-Up) |
| Current TFMs per project | Identify which projects need upgrading |
| Project format (legacy vs SDK-style) | Determines TFM edit approach and whether conversion is out of scope |
| Package management mode | Determines package update approach |
| Dependency graph | Task ordering for Bottom-Up strategy |
| Package compatibility issues | Whether a NuGet update task is needed |
| Package retargeting needs | Whether packages.config metadata, restore, reinstall, or HintPath work is needed |

---

## Step 2: Determine Strategy & Generate Plan

### Strategy Selection

There are only two strategies. No user choice needed:

| Condition | Strategy |
|-----------|----------|
| **≤10 projects** | **All-at-Once** — upgrade all projects in a single task |
| **>10 projects** | **Bottom-Up** — upgrade in dependency order (leaves first) |

### No Options Menu

Unlike `dotnet-version-upgrade`, this scenario has **no configurable upgrade options**:
- No SDK-style conversion option unless the user explicitly requested it before planning
- No multi-targeting option
- No side-by-side web migration
- No strategy selection by user
- No CPM option

### Task Generation

#### All-at-Once Strategy (≤10 projects)

Generate two tasks:

1. **TFM Upgrade Task**: Upgrade all projects to net481.
   - List every project with its current TFM and project format.
   - Reference the TFM edit approach per project format (legacy vs SDK-style).
   - Preserve project format: legacy projects use legacy project files; SDK-style projects use SDK-style project files.

2. **SDK-style Conversion Task** (only if the user explicitly requested and confirmed conversion):
   - Route through the `sdk-style-conversion` scenario / `converting-to-sdk-style` skill.
   - Keep target framework changes separate from project-system conversion work.
   - Warn the user that ASP.NET Framework web projects can stop building, publishing, or running correctly after SDK-style conversion because classic ASP.NET Framework projects are not fully supported by SDK-style .NET tooling.

3. **Package Retargeting/Update Task** (only if assessment found compatibility issues or package retargeting needs):
   - List packages that need version updates for net481 compatibility.
   - List `packages.config` entries that need `targetFramework` retargeting, reinstall/restore, or HintPath verification.
   - Reference `managing-legacy-dotnet-packages` skill.

#### Bottom-Up Strategy (>10 projects)

1. **Order projects by dependency graph** — leaf projects (no dependencies) first, root projects last.
2. **Group into tiers** by dependency depth.
3. **Generate one TFM upgrade task per tier**.
4. **Generate SDK-style conversion tasks only if explicitly requested and confirmed**.
   - Warn the user that ASP.NET Framework web projects can stop building, publishing, or running correctly after SDK-style conversion because classic ASP.NET Framework projects are not fully supported by SDK-style .NET tooling.
5. **Generate one package retargeting/update task** (if needed) after all TFM tasks.

### Task Format

Each task in `plan.md` should follow:

```markdown
### Task {n}: {Title}

**Projects**: {list of project paths}
**Type**: TFM Upgrade | SDK-style Conversion | Package Retargeting/Update
**Strategy**: All-at-Once | Bottom-Up (Tier {n})

**Steps**:
1. {step description}
2. {step description}

**Validation**: Build with `msbuild` and verify no errors.
```

---

## Step 3: Save Plan

### plan.md

Write `plan.md` in the workflow folder with:
- Strategy used (All-at-Once or Bottom-Up)
- Ordered list of tasks with project assignments
- Validation approach (msbuild build for each tier/group)

### scenario-instructions.md

Update `scenario-instructions.md` with:
- `targetFramework: net481`
- `targetFrameworkVersion: v4.8.1`
- `strategy: all-at-once` or `strategy: bottom-up`
- `sdkConversion: false`
- `sdkStyleConversion: false` unless explicitly requested and confirmed
- `newMultiTargeting: false`
- `preserveExistingMultiTargeting: true`
- `preserveProjectFormat: true`

---

## Edge Cases

### Single project
Use All-at-Once with a single TFM upgrade task.

### Circular dependencies
Extremely rare in .NET Framework solutions. If detected, treat the circular group as a single tier and upgrade all projects in that group together.

### Projects already on net481
Exclude projects already on net481 from the plan. If all projects are already on net481, exit the scenario (should have been caught in assessment).
