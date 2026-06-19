# Package Management

**Category**: Project Structure

**Applicable when**:
- Solution has >= 2 projects, AND
- Currently uses `packages.config` OR per-project `PackageReference` without CPM, AND
- `Directory.Packages.props` does not already exist in the repository

**Not applicable when**:
- Single-project solution (CPM overhead not justified)
- CPM already in use (`Directory.Packages.props` exists)
- Solution has only 1-2 projects with few packages (CPM overhead not justified)

**Default logic**:

CPM is **phase-aware** — the right default depends on whether the upgrade crosses
the .NET Framework → modern .NET boundary.

- Recommend **Per-Project (defer CPM to post-migration)** if ANY of:
  - Solution contains non-SDK-style projects (old-style csproj with `<Project ToolsVersion=...>`)
  - Upgrade crosses .NET Framework → modern .NET boundary
    (any project currently on `net4*` targeting `net8.0`+)
  - Project Approach selects multi-targeting (old and new TFMs coexist →
    divergent dependency graphs create `VersionOverride` friction)
  - Side-by-side incremental migration selected (old Framework project and new
    Core project run in parallel with different package ecosystems)
  - `packages.config` is in use (must convert to `PackageReference` first as part
    of SDK-style conversion — CPM adds a second migration on top and creates churn)

  **Why**: CPM wants uniformity. Framework-to-modern migrations are inherently about
  *managed divergence* — old and new coexisting temporarily. Adding CPM during this
  window forces `VersionOverride` on old projects, complicates multi-targeting, and
  creates friction at every subsequent step. Add CPM after the migration stabilizes.

- Recommend **Central Package Management** if ALL of:
  - All projects are already SDK-style (or will trivially be after the upgrade), AND
  - Upgrade is within the same ecosystem (modern → modern, e.g., .NET 6 → 8, .NET 8 → 10), AND
  - No extended multi-targeting period expected, AND
  - >= 5 projects in solution OR assessment shows version conflicts across projects

**Options**:
- **Central Package Management (CPM)** — creates `Directory.Packages.props`,
  moves versions out of project files.
  Better consistency, easier maintenance at scale.
  Best applied when all projects are SDK-style and on the same ecosystem.
- **Per-Project (defer CPM to post-migration)** *(default for Framework migrations)* —
  each project retains its own versions during the active migration.
  CPM is registered as a post-migration recommendation in the plan's final
  cleanup phase. The assessment already surfaces version divergence data for
  visibility — CPM enforcement is deferred until the divergence resolves naturally.

**What is NOT configurable**:
- When "Per-Project (defer CPM)" is selected, the plan MUST include a deferred
  CPM recommendation in the final solution validation / cleanup phase with the
  rationale: "All projects are now SDK-style and on a single TFM — CPM can be
  added cleanly without VersionOverride friction."
- When CPM is selected during an active Framework migration, warn in the `Why`
  column: "User override — expect VersionOverride usage in multi-targeted projects."

**Stored as**: `Upgrade Options > Project Structure > Package Management`

**Affects**: Whether a CPM setup task is added to the plan as a prerequisite
(modern-to-modern upgrades) or as a deferred post-migration recommendation
(Framework migrations). Controls how package update tasks are structured.
