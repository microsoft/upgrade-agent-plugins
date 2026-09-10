# Breakdown Hints — Test

Hints for tasks that involve test projects or modify projects with test dependents.
Load this file when test projects are in scope or when modified projects have
test projects referencing them.

---

### hint: test-project-lifecycle
**Applies to task types**: any task that moves code between projects or modifies
project references
**Condition**: Test projects exist that reference projects being modified in
the current task
**Detection**:
- Find test projects (xUnit, NUnit, MSTest references or `<IsTestProject>true</IsTestProject>`)
- Check if they reference any project being modified in current task scope
**Recommendation**: When code moves from old project to new project, test
references must be updated as part of the same subtask — not deferred.
Break test updates into a subtask if:
- Multiple test projects are affected
- Tests need significant rework (not just reference changes)
Do NOT leave test projects in a broken state between subtasks.
**Priority**: MUST

---

### hint: test-framework-upgrade
**Applies to task types**: TFM upgrade, multi-targeting
**Condition**: Test project targets a framework that doesn't support the test
framework version in use
**Detection**:
- Test project references old test framework packages (e.g., MSTest V1,
  old xUnit/NUnit versions)
- Test runner adapter packages need upgrading for the new TFM
**Recommendation**: Test framework package upgrades are mechanical but must
happen alongside or before the TFM change. Include as part of the project's
upgrade subtask, not as a separate concern.
**Priority**: SHOULD
