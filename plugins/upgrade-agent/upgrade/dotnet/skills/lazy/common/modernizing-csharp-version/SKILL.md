---
name: modernizing-csharp-version
description: >
  Upgrade C# code to use newer C# language features. Use this skill whenever the user wants to
  modernize C# code to a specific language version (e.g., "upgrade to C# 12", "use latest C# features",
  "modernize this C# code"), apply new language features from any C# version 7.0 through 15,
  or when migrating a .NET project to a newer target framework and the C# language version increases.
  Also trigger when the user asks about what C# features are available for a given version, wants to
  know which modernizations are safe to apply, or asks to "clean up" or "simplify" C# code using
  modern syntax. This includes requests like "use pattern matching", "switch to file-scoped namespaces",
  "use collection expressions", "convert to records", or any mention of specific C# language features
  by name. This skill can also be invoked as a sub-step from other scenarios (e.g., .NET TFM upgrade)
  when the C# language version changes as part of a broader migration.
---

# C# Language Modernization Skill

Upgrade C# source code to use language features available in a target C# version. This skill
handles both single-version upgrades and multi-version jumps (e.g., C# 7.0 → C# 13), applying
features cumulatively from each intermediate version.

The workflow is designed to minimize token usage: mechanical changes are batched through
`dotnet format` (zero LLM tokens), while the LLM focuses on judgment-heavy transformations
that require semantic understanding.

## Entry points

This skill supports two invocation modes:

### Standalone invocation
The user directly asks to modernize C# code. The skill handles everything: version detection,
assessment, transformation, and reporting.

### Sub-step invocation (from parent scenario)
A parent scenario (e.g., TFM upgrade) invokes this skill with a known version range. When the
version range is already determined by the caller, skip Step 1 (version detection) and begin
at Step 2 (load references). The parent scenario provides:
- **Source C# version** — the version the code currently uses
- **Target C# version** — the version to modernize to
- **Scope preference** — conservative / default / aggressive (if already known)

## Version ↔ .NET Target Framework mapping

| C# Version | .NET TFM         | LangVersion |
|-------------|------------------|-------------|
| 7.0         | .NET Framework 4.7+ / .NET Core 2.0 | 7 |
| 7.1–7.3     | .NET Core 2.0–2.1 | 7.1–7.3 |
| 8.0         | .NET Core 3.x    | 8.0 |
| 9.0         | .NET 5           | 9.0 |
| 10.0        | .NET 6           | 10.0 |
| 11.0        | .NET 7           | 11.0 |
| 12.0        | .NET 8           | 12.0 |
| 13.0        | .NET 9           | 13.0 |
| 14.0        | .NET 10          | 14.0 |
| 15.0        | .NET 11          | 15.0 |

---

## Step 1: Determine the upgrade range

*Skip this step if invoked as a sub-step with a known version range.*

Identify the **current** C# version and the **target** C# version.

**How to detect current version:**
1. Check the `.csproj` for `<LangVersion>` — if present, that's the version.
2. If absent, infer from `<TargetFramework>`:
   - `net6.0` → C# 10, `net7.0` → C# 11, `net8.0` → C# 12, `net9.0` → C# 13, `net10.0` → C# 14, `net11.0` → C# 15
   - `netcoreapp3.x` → C# 8, `net5.0` → C# 9
   - `net48` / `net472` etc. (Framework) → C# 7.3 (unless LangVersion overridden)
3. If ambiguous, ask the user.

**How to determine target version:**
- If the user specifies a version, use it.
- If they say "latest" or "modernize", use the version implied by their TFM.
- If they're also upgrading TFM, use the new TFM's default.

---

## Step 2: Load applicable reference files

Read ALL reference files from `(current_version + 1)` through `target_version`, inclusive.
Also read `dotnet-format-rules.md` which maps IDE analyzer rules to features.

For example, upgrading from C# 9 → C# 12 means reading:
- `csharp-10.md`
- `csharp-11.md`
- `csharp-12.md`
- `dotnet-format-rules.md`

Reference files are located in the same directory as this skill:
```
csharp-7.md      (covers 7.0 through 7.3)
csharp-8.md
csharp-9.md
csharp-10.md
csharp-11.md
csharp-12.md
csharp-13.md
csharp-14.md
csharp-15.md
dotnet-format-rules.md
```

Read the files using the `view` tool before scanning any code.

---

## Step 3: Review breaking changes

Each reference file includes a **Breaking changes** section listing compiler breaking changes
introduced in that C# version's SDK range. Before transforming code, review these for every
version in the upgrade range.

Breaking changes can cause:
- **Compile errors** in code that previously compiled (new diagnostics, keyword restrictions)
- **Behavioral changes** (different overload resolution, new warnings)
- **Keyword conflicts** (e.g., `field` in C# 14, `extension` in C# 14, `with()` in C# 15)

If the codebase contains patterns affected by breaking changes, fix them **before** applying
modernizations — either in the assessment report (Step 5) as a prerequisite, or as the first
action in Phase 2.

---

## Step 4: Feature tiers

Every feature in the reference files is categorized into one of three tiers:

### 🟢 ALWAYS-APPLY (Safe modernizations)
Syntactic simplifications with no semantic risk. Don't change public API surface, don't alter
runtime behavior. Apply in every upgrade unless the user explicitly opts out.

Many of these have `dotnet format` fixers (marked with IDE rule IDs in the reference files).

### 🟡 RECOMMEND (Good defaults, flag for review)
Improve code quality but involve judgment calls — may change API contracts, alter class
hierarchies, or require broader refactoring. Applied by default but flagged in the assessment
for review. Some have `dotnet format` fixers (e.g., IDE0290 for primary constructors).

### 🔴 OPT-IN (Only when explicitly requested)
Major features that affect architecture, require project-wide enabling, or have significant
trade-offs. Only applied when the user specifically asks.

---

## Step 5: Discovery scan and assessment

This is the critical token-saving step. Before transforming any code, produce an assessment
report that the user can review. The assessment uses cheap operations (grep, file listing,
compiler diagnostics) to identify what needs changing without reading every file into context.

### 5a: Quick scan with grep/find

Use shell commands to find files with modernizable patterns. Do NOT read file contents into
context yet. Examples:

```bash
# File-scoped namespaces: files with block-scoped namespace (C# 10)
grep -rl "^namespace " --include="*.cs" src/ | head -50

# Target-typed new candidates (C# 9) — lines with redundant type on new
grep -rn "= new [A-Z].*();" --include="*.cs" src/ | head -30

# Using blocks that could be declarations (C# 8)
grep -rn "using (" --include="*.cs" src/ | head -30

# Null checks that could use 'is not null' (C# 9)
grep -rn "!= null" --include="*.cs" src/ | head -30

# Old-style switch statements (C# 8 switch expressions)
grep -rn "switch (" --include="*.cs" src/ | head -30

# Array/list initializations that could use collection expressions (C# 12)
grep -rn "new List<\|new \[\]\|Array\.Empty" --include="*.cs" src/ | head -30

# ESC character literals (C# 13)
grep -rn '\\x1[Bb]\|\\u001[Bb]' --include="*.cs" src/ | head -20

# Escaped strings that might benefit from raw literals (C# 11)
grep -rn '\\\"' --include="*.cs" src/ | head -20

# Variables named 'field' in property accessors — breaking change in C# 14
grep -rn 'field' --include="*.cs" src/ | head -20

# Collection expressions with with() calls — potential C# 15 breaking change
grep -rn 'with(' --include="*.cs" src/ | head -20
```

Adapt grep patterns to the actual version range — skip patterns for versions not in scope.
These counts feed the assessment without consuming tokens on file content.

### 5b: Optionally run dotnet format in dry-run mode

If the project builds successfully, run `dotnet format` in verify mode to get an exact count
of what it can fix:

```bash
dotnet format <solution.sln> --verify-no-changes --severity info \
  --diagnostics IDE0090 IDE0063 IDE0161 IDE0083 IDE0300 IDE0301 IDE0306 \
  2>&1 | tail -20
```

The output lists every file that would be changed and which diagnostic triggered it.

### 5c: Write the assessment file

Write a `csharp-language-modernization-assessment.md` file to the project root (or working directory).
This file serves as both the plan for the user to review and the execution checklist for
subsequent steps.

**Assessment file structure:**

```markdown
# C# Modernization Assessment

**Project:** {solution/project name}
**Current version:** C# {X}
**Target version:** C# {Y}
**Date:** {date}

## Summary

| Category | Est. files | Method |
|----------|-----------|--------|
| ⚠️ BREAKING CHANGES | ~{N} | Fix manually — must resolve first |
| 🟢 ALWAYS-APPLY (dotnet format) | ~{N} | `dotnet format` — automated |
| 🟢 ALWAYS-APPLY (LLM-only) | ~{N} | LLM — no fixer available |
| 🟡 RECOMMEND | ~{N} | LLM — flagged for review |
| 🔴 OPT-IN (not applied) | ~{N} | Not applied unless requested |

## Phase 0: Breaking changes (must resolve first)

These are compiler breaking changes that may cause build failures or behavioral changes
when upgrading the C# version. Fix before applying any modernizations.

| Breaking change | C# Ver | Est. files | Severity | Mitigation |
|----------------|--------|-----------|----------|------------|
| {description} | {ver} | ~{N} | error/warning/behavior | {fix} |

## Phase 1: dotnet format (automated, zero LLM tokens)

These changes are mechanical and handled entirely by Roslyn analyzers.

### .editorconfig additions:
{generated .editorconfig snippet — see dotnet-format-rules.md}

### Diagnostics to apply:
| IDE Rule | Feature | Est. files | Tier |
|----------|---------|-----------|------|
| IDE0161 | File-scoped namespaces | ~{N} | 🟢 |
| IDE0090 | Target-typed `new` | ~{N} | 🟢 |
| IDE0083 | `is not null` pattern | ~{N} | 🟢 |
| IDE0300–0306 | Collection expressions | ~{N} | 🟢 |
| IDE0290 | Primary constructors | ~{N} | 🟡 |
| ... | ... | ... | ... |

### Command:
```
dotnet format {solution} --severity info --diagnostics {IDs}
```

## Phase 2: LLM transformations

These require semantic understanding — no automated fixer exists.

### 🟢 ALWAYS-APPLY (LLM-only, no fixer)
| Feature | C# Ver | Est. files | Detection signal |
|---------|--------|-----------|-----------------|
| Raw string literals | 11 | ~{N} | Escaped quotes in strings |
| List patterns | 11 | ~{N} | Length/index checks |
| ... | ... | ... | ... |

### 🟡 RECOMMEND (LLM, flagged for review)
| Feature | C# Ver | Est. files | Trade-off |
|---------|--------|-----------|-----------|
| Record conversion | 9 | ~{N} | Changes equality semantics |
| init-only setters | 9 | ~{N} | Blocks post-construction mutation |
| Global usings | 10 | ~{N} | Reduces per-file explicitness |
| required members | 11 | ~{N} | Must verify framework support |
| ... | ... | ... | ... |

## Phase 3: Opt-in (not applied unless requested)

| Feature | C# Ver | Impact | Notes |
|---------|--------|--------|-------|
| Nullable reference types | 8 | ~{N} files | Project-wide, many warnings |
| Generic math interfaces | 11 | ~{N} types | Reshapes type hierarchy |
| ... | ... | ... | ... |

## Recommended execution order

0. Phase 0 → fix breaking changes → build → commit
1. Phase 1 → build → test → commit (mechanical changes)
2. Confirm Phase 2 scope with user
3. Phase 2 → build → test → commit (LLM changes)
4. Phase 3 if requested → build → test → commit
```

---

## Step 6: Handle user scope preferences

The user may indicate scope in several ways:

- **"Apply all features"** / **"go aggressive"** → Apply ALWAYS + RECOMMEND + OPT-IN.
  Include 🟡 tier IDE rules (like IDE0290) in the dotnet format pass too.
- **"Just safe changes"** / **"conservative"** → Apply only ALWAYS-APPLY (both format and LLM).
  Exclude 🟡 tier IDE rules from dotnet format.
- **"Upgrade to C# 12"** (no qualifier) → Default: ALWAYS + RECOMMEND.
  Include 🟡 tier IDE rules in dotnet format where available.
- **"Enable NRT"** or names a specific feature → Apply that feature (even if OPT-IN) plus
  all ALWAYS-APPLY changes.
- **"What can I modernize?"** → Discovery mode. Run Steps 1–5 only, produce the assessment
  file, stop. Don't transform anything.

After the assessment is written, present the summary to the user and ask them to confirm
scope before proceeding to execution — unless they've already indicated a clear preference.

---

## Step 7: Execute Phase 1 — dotnet format

### 7a: Prepare the .editorconfig

Check if an `.editorconfig` already exists in the project/solution root.

- **If it exists:** Merge the needed rules. Don't overwrite existing settings — only add rules
  for features the project doesn't already configure. Note any conflicts in the assessment.
- **If it doesn't exist:** Create a minimal `.editorconfig` with the required rules.

Use `dotnet-format-rules.md` to look up the exact option names and values. Only
include rules for versions in the upgrade range (source+1 through target).

### 7b: Run dotnet format

```bash
dotnet format <solution.sln> --severity info --diagnostics <IDs>
```

Build the diagnostic ID list from `dotnet-format-rules.md`, filtered to the
relevant version range and the appropriate tier based on user scope preference.

### 7c: Build and verify

```bash
dotnet build <solution.sln>
```

If build fails after `dotnet format`, inspect errors. Most common issues:
- Collection expressions producing type ambiguity → revert those specific changes
- Primary constructors conflicting with partial classes → revert
- Expression-bodied members exceeding readability for complex bodies → revert

### 7d: Update the assessment file

Mark Phase 1 items as complete. Record actual change counts from `dotnet format` output.

---

## Step 8: Execute Phase 2 — LLM transformations

Now read and transform files that need LLM judgment. Process files one-at-a-time to minimize
context window usage.

### Processing order

1. Work through features in ascending C# version order (older first) — some later features
   build on earlier ones.
2. Within a version, process 🟢 ALWAYS-APPLY first, then 🟡 RECOMMEND.
3. Group related files when possible (e.g., all record candidates together).

### For each file

1. Read the file content into context.
2. Apply all applicable transformations from the loaded reference files.
3. Follow "when NOT to apply" guidance from the reference files.
4. For 🟡 RECOMMEND changes, note what changed and why in the assessment file.
5. Write the transformed file.
6. Release — don't keep old file content in context for subsequent files.

### Preserve semantics

Never change runtime behavior. If a transformation is ambiguous (e.g., a class looks like a
record candidate but has mutable state and side-effectful methods), skip it and note why in
the assessment file under a "Skipped" section.

---

## Step 9: Final report

Update the assessment file with execution results:

```markdown
## Execution results

### Phase 1 (dotnet format): ✅ Complete
- {N} files modified
- Diagnostics applied: {list}

### Phase 2 (LLM): ✅ Complete
| Feature | Files changed | Notes |
|---------|--------------|-------|
| Raw string literals | 4 | JSON templates in Services/ |
| Record conversion | 3 | PersonDto, OrderDto, AddressDto |
| ... | ... | ... |

### Skipped (with reasons)
| File | Feature | Reason |
|------|---------|--------|
| OrderService.cs | Primary constructor | Complex init, 12 dependencies |
| MathHelper.cs | Generic math | Would reshape type hierarchy |

### Not applied (opt-in)
- Nullable reference types: ~47 files affected. Enable with `<Nullable>enable</Nullable>`.
```

---

## Important considerations

### Feature interactions across versions
Some features from later versions enhance earlier-version features. Apply them together:
- C# 9 `is not null` + C# 11 list patterns → richer pattern matching chains
- C# 10 file-scoped namespaces + C# 12 primary constructors → dramatically shorter files
- C# 9 records + C# 10 record structs → complete value-type story

### Don't over-modernize
Not every piece of code benefits from every feature. The reference files include "when NOT to
apply" guidance for each feature — follow it.

### Respect existing code style
Check for an existing `.editorconfig` that may encode team preferences. If the codebase
consistently uses a pattern (e.g., explicit types over `var`), don't force modernization on
style-preference features unless the user says to.

### NRT is special
Nullable reference types are always 🔴 OPT-IN. If the user asks to "modernize to C# 8+" and
doesn't mention NRT, note it in the assessment but don't enable it.

### Commit strategy
Recommend the user commit in phases for clean git history and easy revert boundaries:
1. **Commit 1:** `.editorconfig` changes + `dotnet format` results (mechanical)
2. **Commit 2:** LLM-driven 🟢 ALWAYS-APPLY changes
3. **Commit 3:** LLM-driven 🟡 RECOMMEND changes
4. **Commit 4:** Any 🔴 OPT-IN changes (if requested)
