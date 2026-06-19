# Breakdown Hints — Common

Hints that apply to any project flavor during .NET version upgrade tasks.
Always load this file during breakdown assessment.

---

### hint: multi-project-dependency-ordering
**Applies to task types**: TFM upgrade, multi-targeting, package migration
**Condition**: Task affects multiple projects with dependencies between them
**Detection**:
- Task scope includes 2+ projects
- Projects have inter-project references (dependency chain)
- Task involves TFM change, multi-targeting, or significant package updates
**Recommendation**: Process projects in dependency order (leaf → root).
Each project must build on the new TFM before its dependents can be updated.
Break by dependency tier if 3+ projects are involved:
1. Leaf projects (no project references)
2. Projects depending on already-updated leaves
3. Continue up the dependency chain
**Priority**: MUST (if 3+ projects in dependency chain)

---

### hint: large-package-replacement-batch
**Applies to task types**: package migration, TFM upgrade
**Condition**: Task involves replacing >5 incompatible packages with no known
automatic replacements
**Detection**:
- Assessment shows >5 packages with no compatible version for target TFM
- These packages are NOT covered by known replacement mappings
**Recommendation**: Large batches of package replacements should be broken
by package group or by consuming project to keep each subtask focused.
Each replacement may require research, API mapping, and consumer code updates.
**Priority**: SHOULD
