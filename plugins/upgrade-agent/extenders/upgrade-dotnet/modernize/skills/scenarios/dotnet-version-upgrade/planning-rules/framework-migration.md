# Planning Rules — .NET Framework Migration

Rules for generating top-level tasks when any project targets .NET Framework.
These supplement the common planning rules and the chosen strategy's task template.

---

## Strategy override for .NET Framework solutions

When any project targets .NET Framework, strategy selection is constrained:

| Solution shape | → Strategy |
|---------------|-----------|
| Single project (1 project total) | All-at-Once |
| Multiple projects (2+) | Bottom-Up — **non-negotiable** |

These rules override the general decision matrix in the planning stage.
Top-Down is not applicable to .NET Framework solutions (multi-targeting
across Framework and modern .NET is too fragile for libraries).

---

## SDK-style conversion

- Generate as a **separate** task from TFM upgrade — never merge these
- Condition: assessment found non-SDK-style csproj files in projects that need
  conversion (check SDK Style indicator per project)
- SDK conversion = structural change, stays on current TFM
- TFM upgrade = API surface change, new compilation errors
- These have different failure modes and must not be conflated
- Do NOT generate if all projects are already SDK-style

> ⛔ **Side-by-side web projects are EXCLUDED from SDK-style conversion.**
> When Project Approach = Side-by-side for a web project, that project keeps
> its old-style csproj throughout migration. The new Core project created during
> scaffold is already SDK-style. Count only non-web projects when writing the
> task scope (e.g., "Convert 3 projects" not "Convert all 4 projects").

## TFM upgrade (all project types)

- Generate as a **separate** task AFTER SDK-style conversion
- This task covers ALL projects that need TFM changes — not just libraries:
  - **Libraries** that serve both old and new consumers → add multi-targeting
  - **Libraries** with no old consumers remaining → in-place TFM change
  - **Console apps / Worker services** → in-place TFM change
  - **Test projects** → TFM update to match the projects they test
  - **Other non-web projects** → in-place TFM change
- The approach per project (multi-targeting vs in-place) is determined by the
  Project Approach upgrade option and the dependency graph — not by the plan.
  The task description should say "upgrade all project TFMs" and let the
  executor determine the right approach per project at execution time.
- Processing order (dependency-based grouping) is a **breakdown concern**,
  not a planning concern. The plan has one task; breakdown creates subtasks
  by dependency tier or project group when scope inventory reveals many projects.

> ⛔ **Side-by-side web projects are EXCLUDED from the TFM upgrade task.**
> They get their own scaffold/migrate tasks (see below).
> Count only non-web projects when writing the task scope.

## packages.config migration

- Projects with `packages.config` must be converted to `PackageReference`
  as part of SDK-style conversion — this is handled by the conversion tooling
- Do NOT generate a separate task for this — it's part of the SDK-style
  conversion task

## Web project approach

- Web projects on .NET Framework have specific migration approaches (side-by-side
  vs in-place) determined by the Project Approach upgrade option
- In-place web projects are included in the main upgrade task
- Side-by-side web projects get scaffold/migrate task pairs —
  see next section

## Side-by-side web project tasks

When the **Project Approach** upgrade option selects **Side-by-side** for a web
project, inject three additional tasks per web project into the plan. These
supplement whatever strategy was chosen — they slot into the plan at the
appropriate position within the strategy's task ordering.

### Task pair per web project

| Task | Name pattern | Description |
|------|-------------|-------------|
| Scaffold | `NN-scaffold-{project-short-name}` | Create new ASP.NET Core project alongside the old one, configure YARP proxy |
| Migrate | `NN-migrate-{project-short-name}` | Move all web assets incrementally (broken into subtasks at execution time) |

> **Old project removal** is NOT a plan task. After all migration and validation
> is complete, final validation documents removal as a post-upgrade step for the
> user to perform when they've confirmed production readiness. The agent performs
> reference cleanup (re-pointing test projects, removing multi-targeting) as part
> of the migrate task, but does not delete the old project.

### Positioning within the plan

- **Scaffold** comes after SDK-style conversion + TFM upgrade of non-web projects
- **Migrate** comes immediately after scaffold

If **multiple web projects** exist, order them so that any web project depended on
by another is scaffolded and at least partially migrated first.

### Dependency libraries

Libraries depended on by the web project are **not** given separate scaffold/migrate
tasks. They are handled as part of the migrate task for the web project that depends on
them. The task description should note which libraries are in scope so the executor and
project-type skill can handle them in the correct order within the migrate task breakdown.

### Planning constraints

- Don't enumerate controllers or features in the migrate task — subtask breakdown
  happens at execution time via the `migrating-aspnet-framework-to-core` project-type
  skill and breakdown hints
- Don't merge scaffold and migrate into one task — they have different completion
  criteria and different rollback implications
- The migrate task description should list which dependency libraries are in scope
- Reference cleanup (re-pointing test projects to new Core project, removing
  multi-targeting from libraries) is part of the migrate task's final subtasks —
  not a separate plan task

### Execution constraints (save to scenario-instructions.md)

When side-by-side tasks are generated, add these constraints to
`scenario-instructions.md`:

```markdown
### Side-by-Side Web Migration Constraints
- Scaffold task must complete and validate (builds, stub 200 response) before migrate starts
- Old Framework project remains live and deployable throughout entire migrate phase
- Migrate task will be broken into subtasks at execution time — load migrating-aspnet-framework-to-core skill
- Libraries in migrate task scope are handled in dependency order before web layer assets
- Reference cleanup (test projects, multi-targeting) is part of migrate, not a separate task
- Old project is NOT deleted by the agent — documented as post-upgrade step for user
```
