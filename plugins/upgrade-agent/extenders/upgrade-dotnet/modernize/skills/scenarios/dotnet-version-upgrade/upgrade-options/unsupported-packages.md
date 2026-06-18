# Unsupported Packages

**Category**: Compatibility

**Applicable when**:
- Any NuGet package has no compatible version for the target TFM

**Not applicable when**:
- All packages have compatible versions available for the target TFM

## What is NOT configurable (always happens)

- **Multi-targeted projects**: Old TFM keeps old package reference via MSBuild
  `Condition`; the resolution choice below applies only to the new-TFM side.
  In practice this means "remove" becomes "condition out" — the package stays
  for `net48` and is excluded for `net10.0`.
- **Replace with known alternative**: When assessment identifies a direct replacement
  package (e.g., `System.Drawing` → `System.Drawing.Common`), that replacement is
  applied automatically — it is not a preference

## The choice — default resolution when no known replacement exists

**Default logic**:
- Recommend **Defer Resolution** if:
  - > 3 packages without known replacements (too many to research in one pass), OR
  - Bottom-up strategy selected (per-tier buildability matters)
- Recommend **Resolve Inline** if:
  - 1-3 packages without known replacements — small enough to research inline
- Recommend **Compatibility Mode** only if:
  - Package is a transitive dependency not directly referenced, OR
  - Package is Windows-only and Windows Compatibility Pack already selected (Windows Native APIs option)

**Options**:
- **Resolve Inline** *(default for small count)* — research and resolve each
  incompatible package within the same task. For single-TFM projects: removes old
  reference, adds replacement or rewrites consuming code. For multi-targeted
  projects: conditions the old reference to the old TFM and adds the replacement
  for the new TFM. No deferred work.
- **Defer Resolution** *(default for large count)* — make the project compile
  without the package by generating minimal type stubs, then create follow-up
  tasks for real replacements. For single-TFM projects: removes incompatible
  package reference. For multi-targeted projects: conditions the package to the
  old TFM only. See `execution.md` Decomposition Rules for stub resolution
  task structure.
- **Compatibility Mode** — keeps .NET Framework reference, adds
  `Microsoft.NETFramework.ReferenceAssemblies` and suppresses `NU1701`.
  May cause runtime failures. Use only for transitive dependencies where consuming
  code does not call package APIs directly.

**Stored as**: `Upgrade Options > Compatibility > Unsupported Packages`

**Affects**: Task decomposition (stub resolution subtasks when deferred),
execution approach for package failures.
