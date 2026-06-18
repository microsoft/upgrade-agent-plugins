# All-At-Once Strategy

Upgrade all projects simultaneously in a single atomic operation.

> **This file covers 5 sections.** Read all before planning or executing.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | When to Use | Matching criteria |
> | 2 | Planning Instructions | Strategy declaration, project list |
> | 3 | Plan Structure | How plan.md tasks are organized |
> | 4 | Execution Guidelines | Operation sequence, batching, validation |
> | 5 | Anti-patterns | Common mistakes to avoid |

---

## 1. When to Use

**Ideal when:**
- All projects target `net6.0` or later
- Up to ~15 projects (can stretch to ~20 for low-complexity solutions)
- Assessment shows ≤ 2 high-risk package migrations (e.g., OData, Newtonsoft→STJ, LINQ-to-SQL→EF Core)
- Dependency graph is ≤ 3 tiers deep
- Team can tolerate a temporarily broken solution (no CI-green constraint)
- Straightforward upgrade: TFM bumps, package version bumps, behavioral code fixes

**Not recommended when:**
- Any project targets .NET Framework (`net4x`) — use Bottom-Up instead
- 15+ projects with deep dependency chains — consider Top-Down for incremental buildability
- CI must stay green during migration — use Top-Down
- Multiple teams actively working in the repo — use Top-Down for incremental mergeability

---

## 2. Planning Instructions

plan.md should be a lightweight task list — not a duplicate of assessment.md.

**Required plan.md content:**

**Strategy declaration:**
```markdown
### Selected Strategy
**All-At-Once** — All projects upgraded simultaneously in a single operation.
**Rationale**: [N] projects, all on .NET [version], clear dependency structure.
```

**Project list** — all projects in a single group (no tiers, no phases). Group by type if helpful (libraries, applications, tests).

**Don't duplicate into plan.md:** package update tables, per-project breaking changes, per-project specs. Assessment.md already has this; task.md captures execution details.

*⚡ Continue reading — Sections 3-5 cover decomposition rules, execution sequence, and anti-patterns.*

---

## 3. Plan Structure

**Core rule: All projects are upgraded together** — no tier ordering, no phased rollout.

### Task Template

> Items below are a checklist of what tasks to include — not a format to copy.
> Transform each applicable item into full plan-generation format with paragraphs
> and Done-when criteria.

1. **Prerequisites** (always)
   - SDK/toolchain verification, global.json compatibility
   - Condition: always included

2. **SDK-style conversion** (if applicable)
   - Convert non-SDK-style projects to SDK-style format on current TFM
   - Condition: assessment found non-SDK-style csproj files
   - Never merge with TFM upgrade — always a separate task
   - **Exclude** side-by-side web projects — they stay old-style throughout migration

3. **Upgrade all projects** (the core task)
   - Update TFMs, bump packages, fix code issues across all projects
   - Covers all project types in one pass (all-at-once = no phasing)
   - For ≤ 5 projects or very straightforward upgrades: single task
   - For 5-30 projects with distinct work areas: may split by concern
     (TFM updates → package updates → code fixes)
   - Breakdown hints may fire at execution time for detected technologies

   *── If side-by-side web migration: scaffold + migrate tasks insert here ──*

4. **Final validation**
   - Full solution build, test suite, document deferred recommendations

### Adaptation Rules

- If all projects are already SDK-style, skip conversion task
- For very small solutions (1-2 projects), merge prerequisites + conversion
  + upgrade into a single task
- Web projects using side-by-side approach are excluded from SDK conversion
  (they stay old-style throughout migration)

During execution, the task-execution skill may break any plan task into subtasks
(e.g., per-project) based on complexity. This plan structure defines the
**planning** granularity, not a ceiling on execution-time breakdown.

---

## 4. Execution Guidelines

**Operation sequence within the atomic upgrade task:**

1. Update all project files (TargetFramework, imports, conditional logic)
2. Update all package references across all projects
3. Restore dependencies
4. Build solution and fix all compilation errors (single bounded pass)
5. Verify: solution builds with 0 errors

**Important**: This is one pass, not a retry loop. Use "build and fix all compilation errors" — not "build → fix → rebuild → fix again" ambiguity.

Testing comes AFTER the atomic upgrade completes successfully.

---

## 5. Anti-patterns

**Don't introduce tier ordering** — all projects are upgraded together. If you find yourself ordering by dependency layer, you're doing bottom-up.

**Don't create manual validation tasks** — exclude non-automatable steps like "visually confirm UI loads".

**Don't use sequential language** — avoid "first upgrade Project A, then Project B". All projects simultaneously.
