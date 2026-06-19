# Project Approach

**Category**: Project Structure

**Applicable when**:
- Any project in the solution targets .NET Framework
  (`net35`, `net40`, `net45`, `net451`, `net452`, `net46`, `net461`, `net462`,
  `net47`, `net471`, `net472`, `net48`, `net481`)

**Not applicable when**:
- All projects already target modern .NET (`net5.0`+, `netcoreapp*`, `netstandard*`)
- Solution has no projects on .NET Framework at all

This option has **different choices depending on project type**. Evaluate per project
category and present the combined recommendation.

## Web Projects (MVC / WebAPI with System.Web)

Multi-targeting is not viable for ASP.NET Framework web projects. The two framework
stacks (`System.Web` vs ASP.NET Core) are architecturally incompatible and cannot
coexist in a single compiled output. The choice is between migration approaches:

**Default logic**:
- Recommend **Side-by-side** if:
  - Large web surface area (> 10 controllers OR > 10k LOC in web layer), OR
  - Continuous deployment required (old app must stay live during migration), OR
  - Assessment shows high-risk breaking changes (incremental approach safer)
- Recommend **In-place rewrite** if:
  - Small web project (≤ 10 controllers, minimal middleware), AND
  - Team has confirmed acceptable downtime, AND
  - Low complexity assessment

**Options**:
- **Side-by-side** *(default when applicable)* — creates a new ASP.NET Core project
  alongside the existing Framework project. Assets migrate incrementally while the
  old project stays live. Injects scaffold/migrate tasks into the plan.
- **In-place rewrite** — replaces the Framework web project entirely in one pass.
  Higher risk, faster for small projects with low complexity.

## Class Libraries (no System.Web dependency)

**Default logic**:
- Recommend **Multi-targeting** if:
  - Library has dependents still on .NET Framework (must serve both during transition), OR
  - Solution has web projects using Side-by-side (libraries need to support both apps)
- Recommend **In-place** if:
  - No Framework dependents remain (all consumers are migrating together), OR
  - Library is leaf-level with no downstream consumers

**Options**:
- **Multi-targeting** *(default when applicable)* — adds new TFM alongside existing
  (`net48;net8.0`). Library serves both Framework and Core consumers during transition.
- **In-place** — replaces TFM directly. Clean but requires all consumers to migrate first.

## Class Libraries (with System.Web dependency)

Multi-targeting with `System.Web` is impractical — requires `#if` conditional compilation
for divergent code paths, producing a gutted Core target. Always migrate in-place.

**Default logic**:
- Always recommend **In-place** — migrate the library to remove System.Web dependency
  entirely before the web project that consumes it.

**Options**:
- **In-place** *(only option)* — replaces `System.Web` API surface with abstractions
  injectable via DI. Must complete before the consuming web project's Phase 5.

## Strategy Interaction

The web project approach choice does **not** determine the upgrade strategy —
strategy is selected based on solution shape (see
[planning-rules/framework-migration.md](../planning-rules/framework-migration.md)
for .NET Framework override rules).

The web project approach determines **how** each web project is handled within
whatever strategy was chosen:
- **Side-by-side** → scaffold/migrate tasks are injected into the plan
  as a modifier (see framework-migration planning rules)
- **In-place rewrite** → web project is included in the main upgrade task
- Present this connection explicitly when showing options

**Stored as**: `Upgrade Options > Project Structure > Project Approach`

```
- Web Projects: [Side-by-side | In-place rewrite]
- Class Libraries: [Multi-targeting | In-place]
- System.Web Libraries: In-place (fixed)
```

**Affects**: Task structure (Side-by-side → scaffold/migrate task injection),
library migration ordering, web project scaffold approach.
