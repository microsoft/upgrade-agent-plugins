# Planning Rules — Modern .NET Upgrade

Rules for generating top-level tasks when all projects are already on modern
.NET (net5.0+). These are simpler than Framework migration rules since no
SDK-style conversion, multi-targeting, or System.Web migration is needed.

---

## Task structure

Modern-to-modern upgrades (e.g., net6→net10, net8→net10) are typically
straightforward TFM bumps with package updates and minor API fixes. The plan
structure is usually:

1. **Prerequisites** — SDK verification, global.json update
2. **Upgrade projects** — update TFMs, bump packages, fix any breaking API changes

For small solutions (1-5 projects), these may merge into a single task.

## When to split the upgrade task

- **Many projects (10+)**: consider splitting by dependency tier or logical group
- **Mixed project types with different risk levels**: isolate higher-risk projects
  (e.g., web apps with behavioral API changes) from lower-risk ones (class libraries)
- **Large package replacement scope**: if >5 packages have breaking changes, consider
  splitting package updates from code fixes

## What NOT to generate

- No SDK-style conversion tasks (projects are already SDK-style)
- No multi-targeting tasks (no Framework ↔ modern coexistence needed)
- No scaffold/migrate tasks (no System.Web migration)
- No upgrade options evaluation (classified as Simple in Step 1.5 — skipped)
