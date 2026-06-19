# Nullable Reference Types

**Category**: Modernization

**Applicable when**:
- Target TFM supports nullable reference types (`net5.0`+), AND
- No project in the solution already has `<Nullable>enable</Nullable>` set, AND
- Solution has C# source files (not VB.NET only)

**Not applicable when**:
- Nullable already enabled across all projects
- Target TFM does not support nullable (`netcoreapp3.1` or earlier)
- VB.NET only solution

**Default logic**:
- Recommend **Leave Disabled** if:
  - Solution LOC > 10,000 (volume of warnings would be unmanageable during migration), OR
  - Solution has > 5 projects (scope too large to tackle simultaneously), OR
  - Assessment shows high-risk breaking changes (migration already demanding)
- Recommend **Enable** if:
  - Small codebase (≤ 5,000 LOC, ≤ 3 projects), AND
  - Low complexity assessment, AND
  - Team explicitly wants modern C# from day one

**Options**:
- **Leave Disabled** *(default when applicable)* — does not enable nullable.
  Maintains existing null handling. Enable separately after migration as
  a distinct effort.
- **Enable Nullable Reference Types** — adds `<Nullable>enable</Nullable>`
  to project files. Compile-time null safety. May require code updates to
  address warnings.

**Stored as**: `Upgrade Options > Modernization > Nullable Reference Types`

**Affects**: Project file modifications during upgrade tasks.
