# Upgrade Strategy

**Category**: Strategy

**Applicable when**:
- Always — every upgrade needs a strategy

**Not applicable when**:
- Never — this option is always evaluated

This option determines how projects are ordered and grouped during the upgrade.
It appears **first** in upgrade-options.md, before all other options.

## Options

- **All-at-Once** — Upgrade all projects simultaneously in a single atomic pass.
  Fastest approach, no multi-targeting overhead, but the solution may be
  temporarily broken until all projects are updated.

- **Bottom-Up** — Upgrade leaf-node libraries first, then work upward through
  the dependency graph tier by tier. Each tier is validated independently.
  Only applicable when crossing the .NET Framework → modern .NET boundary,
  where each layer has genuinely different upgrade mechanics.

- **Top-Down** — Upgrade entry-point applications first, temporarily
  multi-targeting shared libraries so the solution stays buildable throughout.
  Libraries are consolidated in a second phase after all apps are upgraded.

## Default Logic

Evaluate in this order — **first match wins**:

### .NET Framework detected

| Condition | → Strategy | Rationale |
|-----------|-----------|-----------|
| Single project (1 total) | **All-at-Once** | No dependency graph to manage |
| Multiple projects (2+) | **Bottom-Up** (fixed — no alternatives shown) | Framework→Core boundary requires different upgrade mechanics per layer; tier-by-tier validation pays for itself |

> When Bottom-Up is fixed, show only one row in the values table with no
> alternative. The user cannot change this selection.

### All projects on `net6.0+`

| Condition | → Strategy | Rationale |
|-----------|-----------|-----------|
| ≤15 projects + ≤2 high-risk migrations + ≤3-tier depth + no CI-green constraint | **All-at-Once** | Small scope, mechanical TFM bump, incremental approach adds overhead without benefit |
| Business urgency on specific apps (security, perf, deployment deadline) | **Top-Down** | Get critical apps on new framework first |
| 15+ projects, or deep graph, or many high-risk migrations | **Top-Down** | Incremental buildability needed at scale |
| CI must stay green during migration | **Top-Down** | Only incremental strategy that keeps solution buildable |
| Multiple teams working concurrently in repo | **Top-Down** | Incremental mergeability needed |

When multiple All-at-Once / Top-Down conditions match, **Top-Down wins** (it's
the safer default for modern-to-modern when there's any complexity signal).

> **Why not Bottom-Up for modern-to-modern?** Bottom-Up's core value is between-tier
> validation: after upgrading Tier 1, verify Tier 2+ still builds on the old
> framework. When upgrading between modern versions (e.g., `net6.0` to a newer
> TFM), a Tier 1 library on the new TFM cannot be consumed by Tier 2 projects
> still on the old TFM — the solution is broken until all tiers complete.
> This eliminates the incremental safety benefit.

### Ambiguous signals

If signals don't clearly match a single row (e.g., 14 projects with moderate
complexity), default to **All-at-Once** for ≤15 projects or **Top-Down** for
16+ projects. Present both as alternatives in the values table so the user
can override.

## Strategy Interaction

- **Project Approach = Side-by-side** → injects scaffold/migrate tasks into
  whichever strategy is selected (modifier, not a strategy change)
- **Bottom-Up** is only available when .NET Framework projects are detected —
  do not show it as an alternative for modern-to-modern solutions

## What is NOT configurable

- Bottom-Up for .NET Framework 2+ project solutions is fixed — cannot be overridden
- The strategy modifiers (side-by-side web migration, pilot approach, group segmentation)
  are not part of this option — they're handled by other options or planning rules

**Stored as**: `Upgrade Options > Strategy > Upgrade Strategy`
