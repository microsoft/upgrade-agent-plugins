# Unsupported API Handling

**Category**: Compatibility

**Applicable when**:
- Any BCL or framework API is flagged as removed or changed in the target TFM
  (binary or source incompatible)
- This covers .NET platform API changes, NOT package-sourced types (those are
  covered by the Unsupported Packages option)

**Not applicable when**:
- No API-level breaking changes identified
- Modern-to-modern upgrade (e.g., net8.0 → net10.0) with no flagged API changes —
  these upgrades rarely have breaking API changes

## What is NOT configurable (always happens)

- **Simple replacements**: When a known replacement API exists and the change is
  mechanical (rename, namespace move, signature change), it is applied directly —
  not stubbed, not deferred, regardless of which option is selected
- **Multi-targeted projects**: `#if` directives are added mechanically where the old
  and new TFM need different API calls — this is not a preference, it is how
  multi-targeting works

## The choice — what to do when an API replacement is complex

A replacement is "complex" when it requires research, touches many files, has
behavioral differences, or needs architectural decisions (e.g., replacing
`AppDomain` usage, `Remoting` APIs, `CodeDom` compilation).

**Default logic**:
- Recommend **Fix Inline** for most upgrades — especially modern-to-modern where
  changes are minor and few
- Recommend **Defer Complex Changes** only if:
  - Many (>5) complex API changes across multiple projects, AND
  - Bottom-up strategy selected (per-tier buildability matters)

**Options**:
- **Fix Inline** *(default)* — resolve every API change in the same task, including
  complex ones. May take longer per task but leaves no deferred work. No stubs to
  clean up later.
- **Defer Complex Changes** — apply simple replacements inline. For complex changes,
  generate a minimal compilable stub (`// STUB: replaces {API}`) to keep the project
  building and create a resolution subtask. See `execution.md` Decomposition Rules
  for stub resolution task structure.

**Stored as**: `Upgrade Options > Compatibility > Unsupported API Handling`

**Affects**: Whether complex API changes are resolved immediately or deferred to
stub resolution subtasks.
