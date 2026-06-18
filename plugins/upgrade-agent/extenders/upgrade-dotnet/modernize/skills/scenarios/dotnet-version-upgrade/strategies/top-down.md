# Top-Down (Application-First) Strategy

Upgrade entry-point applications first, temporarily multi-targeting shared libraries.

> **This file covers 5 sections.** Read all before planning or executing.
>
> | # | Section | Key Content |
> |---|---------|-------------|
> | 1 | When to Use | Matching criteria |
> | 2 | Planning Instructions | Two-phase structure, app/library classification |
> | 3 | Plan Structure | How plan.md tasks are organized per phase |
> | 4 | Execution Guidelines | Application priority, multi-targeting flow, Phase 2 cleanup |
> | 5 | Anti-patterns | Common mistakes to avoid |

---

## 1. When to Use

**Ideal when:**
- All projects target `net6.0` or later
- Solution is too large for All-At-Once (15+ projects, deep dependency graph,
  or many high-risk migrations)
- Business urgency — specific applications need the new framework first
  (security, performance, deployment deadlines)
- CI pipeline must stay green during migration
- Multiple teams working concurrently in the repo (incremental mergeability needed)
- Libraries can multi-target cleanly between current and target frameworks

**Not recommended when:**
- Solution contains .NET Framework projects — use Bottom-Up (multi-targeting
  across the `net4x` ↔ `net8.0+` boundary doesn’t work cleanly for web projects
  with different hosting stacks)
- Small solution (≤15 projects) with no CI-green constraint — All-At-Once is
  simpler and faster
- Libraries have heavy use of framework-specific APIs that prevent clean
  multi-targeting

---

## 2. Planning Instructions

plan.md should be a lightweight task list — not a duplicate of assessment.md.

### Two-phase structure

**Phase 1: Application upgrades** — upgrade each application to target framework. Libraries get multi-targeting added just before they're needed.

**Phase 2: Library consolidation** — remove old framework targets from all libraries, clean up conditional compilation.

**Required plan.md content:**

**Strategy declaration:**
```markdown
### Selected Strategy
**Top-Down (Application-First)** — Applications upgraded first, libraries multi-targeted temporarily.
**Rationale**: [Business urgency reason]. Applications on .NET [version], libraries can multi-target cleanly.
```

**Application vs library classification** — list applications (with priority order) and libraries that will need multi-targeting.

**Application dependency map** — which libraries each application depends on.

**Phase 2 trigger** — when multi-targeting can be removed (typically: all applications upgraded).

**Don't duplicate into plan.md:** per-library multi-targeting specs (current → intermediate → final), conditional compilation details, package updates. These are execution-time concerns for task.md.

*⚡ Continue reading — Sections 3-5 cover task boundaries, execution rules, and anti-patterns.*

---

## 3. Plan Structure

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

3. **Upgrade application** (per application, in priority order)
   - Add multi-targeting to required libraries (done as part of this task
     or as a preceding task if many libraries are involved)
   - Upgrade the application TFM and fix issues
   - Each application task includes its library dependencies

4. **Library consolidation** (Phase 2)
   - Remove multi-targeting from all libraries
   - Clean up conditional compilation
   - Condition: all applications upgraded, no consumers need old TFM

5. **Remaining projects** (if applicable)
   - Projects not covered by application tasks or consolidation
   - Check assessment's full project list against tasks generated so far

6. **Final validation**
   - Full solution build, test suite, document deferred recommendations

### Adaptation Rules

- If only one application exists, the plan simplifies to:
  SDK conversion → upgrade app (including libraries) → consolidation
- If an application has many library dependencies, consider a separate
  "prepare libraries for {app}" task before the app upgrade task
- Phase 2 only starts when ALL applications are upgraded
- Test projects should be updated alongside the application they test

During execution, any task can be broken into subtasks. This plan structure
defines the **planning** granularity only.

---

## 4. Execution Guidelines

### Application priority order

Prioritize by:
1. Business criticality — most important apps first
2. Security needs — apps with urgent security updates
3. Dependency simplicity — apps with fewer library dependencies first

### Multi-targeting flow

When adding multi-target support to libraries:
1. Start with leaf libraries (no internal dependencies)
2. Move up the dependency chain
3. Batch at same dependency level

**Library multi-targeting:**
```xml
<TargetFrameworks>net7.0;net8.0</TargetFrameworks>
```

Note: Adding the second target may require conditional package references or `#if` blocks for framework-specific code.

### Phase transition

Phase 1 → Phase 2 when ALL applications are upgraded. Don't start removing multi-targeting until no consumers need the old framework.

---

## 5. Anti-patterns

**Don't multi-target libraries prematurely** — add multi-targeting only when an application that depends on them is being upgraded.

**Don't forget Phase 2** — plan must explicitly include library consolidation. Don't leave multi-targeting indefinitely.

**Don't ignore build complexity** — multi-targeted libraries increase build time and create two sets of DLLs. Tests should run against the new framework target.

**Don't upgrade libraries before their consumers** — the whole point is apps first. If you find yourself upgrading libraries independently, you're doing bottom-up.
