# Entity Framework

**Category**: Modernization

**Applicable when**:
- Entity Framework 6.x is in use, AND
- Target TFM is `net5.0`+

**Not applicable when**:
- Already using EF Core (`Microsoft.EntityFrameworkCore` package reference)
- No Entity Framework detected at all
- EF6 version < 6.3 (does not support .NET Core — upgrade EF6 first,
  handled as a package update task, not an option)

**Default logic**:
- Recommend **Keep EF6** always when applicable — EF6 6.3+ runs on .NET Core.
  Migrating EF6 → EF Core simultaneously with the .NET upgrade introduces two
  sources of breaking changes (query behavior, lazy loading, LINQ translation,
  migration tooling). Sequencing .NET upgrade first, EF Core migration second
  is safer and easier to debug.
- Recommend **Migrate to EF Core** only if:
  - User explicitly requests simultaneous migration, AND
  - Data layer is small (≤ 5 `DbContext` classes, ≤ 20 entity types), AND
  - No complex EF6 features detected (EDMX models, ObjectContext API,
    `EntitySQL`, `Database.SqlQuery` with complex mappings)

**Options**:
- **Keep EF6** *(default when applicable)* — EF6 6.3+ is compatible with
  .NET Core. Complete the .NET version upgrade first, then evaluate EF Core
  migration as a separate follow-on effort. Lowest risk.
- **Migrate to EF Core** — migrates Entity Framework simultaneously with the
  .NET upgrade. Two sources of breaking changes at once. Only appropriate for
  small, simple data layers where the team accepts the additional risk.

**Stored as**: `Upgrade Options > Modernization > Entity Framework`

**Affects**: Whether EF migration tasks are added to the plan, execution
complexity and risk level.
