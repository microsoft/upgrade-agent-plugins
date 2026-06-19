# Bottom-Up (Dependency-First) Strategy

Upgrade projects sequentially from leaf nodes upward through the dependency chain.

> **This file covers 5 sections.** Read all before planning or executing.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | When to Use | Matching criteria |
> | 2 | Planning Instructions | Tier determination, dependency graph, per-tier summary |
> | 3 | Plan Structure | How plan.md tasks are organized per tier |
> | 4 | Execution Guidelines | Tier ordering, validation, operation batching |
> | 5 | Anti-patterns | Common mistakes to avoid |

---

## 1. When to Use

**Ideal when:**
- Solution contains projects targeting .NET Framework (`net4x`, `netframework`)
- Non-SDK-style csproj files are present
- Classic ASP.NET MVC/WebAPI projects requiring side-by-side migration
- The framework gap creates genuinely different upgrade mechanics per layer
  (different project systems, hosting models, API surfaces)
- Need to validate each layer independently because upgrade operations
  differ by project type

**Not recommended when:**
- All projects already target `net6.0+` — Bottom-Up’s between-tier validation
  does not work for modern-to-modern upgrades. Upgrading a leaf library to a
  newer TFM breaks all higher-tier projects still on the old TFM.
  The solution stays broken until the entire graph is complete, eliminating
  the safety benefit. Use All-At-Once (≤15 projects) or Top-Down (larger
  solutions) instead.
- Business urgency requires specific applications upgraded first — use Top-Down

> **Why not modern-to-modern?** Bottom-Up’s core value is between-tier validation:
> after upgrading Tier 1, you verify that Tier 2+ still builds on the old framework
> before proceeding. When upgrading between modern versions (e.g., `net6.0` to a
> newer TFM), a Tier 1 library on the new TFM cannot be consumed by Tier 2 projects
> still on the old TFM — the solution is broken until all tiers are complete. This
> eliminates the incremental safety benefit. For modern-to-modern upgrades that need
> incremental buildability, use Top-Down with multi-targeting instead.

---

## 2. Planning Instructions

plan.md should be a lightweight task list — not a duplicate of assessment.md.

### Tier determination

Build a dependency graph and assign tiers:
- **Tier 1**: Projects with zero internal project references (leaf nodes)
- **Tier N+1**: Projects depending only on Tiers 1 through N
- Verify no circular dependencies (if found, stop and present options to user)

**Required plan.md content:**

**Strategy declaration:**
```markdown
### Selected Strategy
**Bottom-Up (Dependency-First)** — Upgrade from leaf nodes to root applications, tier by tier.
**Rationale**: [N] projects with [M]-tier dependency graph.
```

**Dependency graph visualization:**
```
Tier 3: [WebAPI] [WorkerService]
         ↓           ↓
Tier 2: [BusinessLogic] [Services]
         ↓           ↓
Tier 1: [Domain] [Utilities] [Contracts]
```

**Per-tier summary** — for each tier:
- Projects included
- Dependencies on previous tiers
- Tier completion criteria

**Don't duplicate into plan.md:** per-tier package updates, per-project breaking changes. Assessment.md already has this; task.md captures execution details.

*⚡ Continue reading — Sections 3-5 cover task boundaries, execution rules, and anti-patterns.*

---

## 3. Plan Structure

**Each tier is a milestone.** In plan.md, organize tasks by tier.

**Task naming**: Name tier tasks by their content, not their tier number. Use descriptive names like `02-foundation-libs`, `03-business-logic`, `04-web-apps` — not `02-tier1`, `03-tier2`, `04-tier3`. The tier concept is structural; the task name should tell users what gets upgraded.

### Task Template

> Items below are a checklist of what tasks to include — not a format to copy.
> Transform each applicable item into full plan-generation format with paragraphs
> and Done-when criteria.

1. **Prerequisites** (always)
   - SDK/toolchain verification, global.json compatibility

2. **SDK-style conversion** (if applicable)
   - Convert non-SDK-style projects to SDK-style format on current TFM
   - Condition: assessment found non-SDK-style csproj files
   - Never merge with TFM upgrade — always a separate task
   - **Exclude** side-by-side web projects — they stay old-style throughout migration

3. **Upgrade per tier** (one task per tier)
   - Upgrade all projects in the tier (TFM, packages, code fixes)
   - Tier ordering: leaf nodes first, then projects depending on them
   - Each tier task includes build validation + test execution
   - Between-tier validation: confirm higher tiers still build on old framework

   *── If side-by-side web migration: scaffold + migrate tasks insert here ──*

4. **Remaining projects** (if applicable)
   - Projects not covered by tier tasks (standalone apps, test projects
     testing higher-tier projects, etc.)
   - Check assessment's full project list against tasks generated so far

5. **Final validation**
   - Full solution build, test suite, document deferred recommendations

### Adaptation Rules

- If only one tier exists (flat dependency graph), use All-at-Once instead
- Tier tasks can be broken into per-project subtasks at execution time
  if the tier has many projects or complexity warrants it
- Test projects should be in the same tier as the projects they test,
  or immediately after

During execution, any tier task can be broken into subtasks. This plan
structure defines the **planning** granularity only.

---

## 4. Execution Guidelines

### Strict tier ordering

Cannot start Tier N+1 until Tier N is validated. This is the core safety property of the strategy.

### Per-tier flow

1. Review tier's projects and check dependencies are stable
2. Update project files + packages for all projects in tier (single operation)
3. Restore, build, fix compilation errors
4. Run unit tests for the tier
5. Validate that higher tiers (still on old framework) still build
6. Mark tier complete, proceed to next

### Between-tier validation

After completing each tier:
- All projects in tier build successfully
- All tier tests pass
- Higher tiers still build and pass their tests (on old framework)

---

## 5. Anti-patterns

**Don't create per-project plan tasks within a tier** — a tier is the planning unit. During execution, per-project subtasks are fine if complexity warrants it.

**Don't skip between-tier validation** — the whole point of bottom-up is that each tier is a stable foundation.

**Don't ignore test dependencies** — tests for Tier 1 projects should be in Tier 1 or immediately after. Don't defer all tests to the end.

**Watch for phantom dependencies** — projects that appear independent but share state via files, config, or databases.

**Multi-project tiers** — projects in the same tier can typically be upgraded in parallel within one task. If ordering within a tier exists, document it.
