# Upgrade Options

Configurable upgrade decisions, loaded selectively during planning based on
what signals have surfaced about the solution.

> **Used by planning.md Step 1.5 only.**
> Do not load these files during assessment or execution.

---

## Option Files

Each option is a self-contained file with applicability conditions, default logic,
and recognized values. Only load the files whose trigger condition is met.

| Option | Category | File |
|--------|----------|------|
| Upgrade Strategy | Strategy | [strategy.md](strategy.md) |
| Project Approach | Project Structure | [project-approach.md](project-approach.md) |
| Package Management | Project Structure | [package-management.md](package-management.md) |
| Unsupported Packages | Compatibility | [unsupported-packages.md](unsupported-packages.md) |
| Unsupported API Handling | Compatibility | [unsupported-api-handling.md](unsupported-api-handling.md) |
| Windows Native APIs | Compatibility | [windows-native-apis.md](windows-native-apis.md) |
| System.Web Adapters | Compatibility | [system-web-adapters.md](system-web-adapters.md) |
| Configuration Migration | Modernization | [configuration-migration.md](configuration-migration.md) |
| Logging Framework | Modernization | [logging-framework.md](logging-framework.md) |
| Dependency Injection | Modernization | [dependency-injection.md](dependency-injection.md) |
| Assembly Binding Redirects | Modernization | [binding-redirects.md](binding-redirects.md) |
| Nullable Reference Types | Modernization | [nullable-reference-types.md](nullable-reference-types.md) |
| Entity Framework | Modernization | [entity-framework.md](entity-framework.md) |

---

## Trigger Index

Only load option files whose trigger condition is met.
**Upgrade Strategy is always loaded** — it is not subject to the Simple skip.
All other options: **skip the entire index** if the upgrade is classified as Simple (see planning.md).

Triggers describe **what** makes an option relevant. The “Likely source” column
hints at where evidence may come from — but any source is valid (assessment data,
project files, user input, tool output, conversation history). Do not proactively
inspect files just to check triggers; only load an option if the signal has already
surfaced.

| Trigger | Condition | Likely source | Option file |
|---------|-----------|---------------|-------------|
| Always | Every upgrade needs a strategy | — | [strategy.md](strategy.md) |
| Trigger | Condition | Likely source | Option file |
|---------|-----------|---------------|-------------|
| .NET Framework project | Any project targets .NET Framework | Assessment, project files | [project-approach.md](project-approach.md) |
| Multiple projects without CPM | ≥ 2 projects and no centralized package management | Assessment, repo structure | [package-management.md](package-management.md) |
| Incompatible packages | Packages with no compatible version for the target TFM | Assessment | [unsupported-packages.md](unsupported-packages.md) |
| Breaking API changes | APIs removed or changed in the target TFM (binary or source incompatible) | Assessment | [unsupported-api-handling.md](unsupported-api-handling.md) |
| Windows-specific APIs | P/Invoke, Registry, System.Drawing, Win32 API usage | Assessment, code | [windows-native-apis.md](windows-native-apis.md) |
| System.Web / ASP.NET Framework | System.Web references, ASP.NET MVC or WebAPI on .NET Framework | Assessment, project files | [system-web-adapters.md](system-web-adapters.md) |
| Complex configuration | Custom config sections, transforms, encrypted settings, high key count | Project files, user input | [configuration-migration.md](configuration-migration.md) |
| Third-party logging | log4net, NLog, ELMAH, Common.Logging in use | Assessment, project files, user input | [logging-framework.md](logging-framework.md) |
| Third-party DI container | Autofac, Unity, Ninject, Castle Windsor, StructureMap, SimpleInjector in use | Assessment, project files, user input | [dependency-injection.md](dependency-injection.md) |
| Binding redirects | assemblyBinding entries in config files | Project files, user input | [binding-redirects.md](binding-redirects.md) |
| Nullable not enabled | Target is net5.0+, C# project, nullable not already enabled | Project files | [nullable-reference-types.md](nullable-reference-types.md) |
| Entity Framework 6 | EF6 6.x in use and target is net5.0+ | Assessment, project files | [entity-framework.md](entity-framework.md) |

---

## How to Evaluate Options

For each loaded option file:

1. **Evaluate the Applicability Condition** against available evidence
2. **If not applicable** — skip entirely (do not mention in the file)
3. **If applicable** — evaluate the Default Logic to determine recommendation
4. **Write to options file** using the format below

Keep evaluation reasoning internal — do not write reasoning to any file or to the chat.

---

## File Format

When generating `upgrade-options.md`, use the card-style structure below.
One heading per applicable option. Include only applicable options — omit
non-applicable ones entirely. Do not list or mention non-applicable options
anywhere in the file.

---

### File header

```markdown
# Upgrade Options — {solution name}

Assessment: {one line: project count, frameworks, key signals}
```

---

### Option format

Each applicable option gets a heading (### under its category ## heading),
a one-line rationale, and a values table. The agent parses the `(selected)`
marker to determine the selected value.

```markdown
### {Option Name}
{One sentence: why this option is relevant, citing a specific assessment finding}

| Value | Description |
|-------|-------------|
| **{Selected Value}** (selected) | {What happens when this is selected} |
| {Alternative Value} | {What happens when this is selected} |
```

Rules:
- `**{value}** (selected)` marks the selected value (bold, with marker after)
- Alternative values have no marker and are not bold
- Each value has a short description explaining what it does
- The user moves `(selected)` to a different row to change selection
- Descriptions come from the option file's **Options** section — use a
  concise single-sentence form, not the full paragraph

---

### Full file structure

```markdown
# Upgrade Options — {solution name}

Assessment: {one line summary}

## Strategy

### Upgrade Strategy
{rationale citing assessment signals}

| Value | Description |
|-------|-------------|
| **{value}** (selected) | {description} |
| {alternative} | {description} |

## Project Structure

### Project Approach
{rationale}

| Value | Description |
|-------|-------------|
| **{value}** (selected) | {description} |
| {alternative} | {description} |

### Package Management
{rationale}

| Value | Description |
|-------|-------------|
| **{value}** (selected) | {description} |
| {alternative} | {description} |

## Compatibility
[omit this section entirely if no compatibility options are applicable]

### {Option Name}
{rationale}

| Value | Description |
|-------|-------------|
| **{value}** (selected) | {description} |
| {alternative} | {description} |

## Modernization
[omit this section entirely if no modernization options are applicable]

### {Option Name}
{rationale}

| Value | Description |
|-------|-------------|
| **{value}** (selected) | {description} |
| {alternative} | {description} |
```

---

### scenario-instructions.md compact block

After user confirms, read all `**{value}** (selected)` markers from the option tables
and write this compact block to `scenario-instructions.md`:

```markdown
## Upgrade Options
**Source**: .github/upgrades/{scenarioId}/upgrade-options.md

### Strategy
- Upgrade Strategy: {selected value}

### Project Structure
- Project Approach: {selected value}
- Package Management: {selected value, only if applicable}

### Compatibility
[one line per applicable option only]
- Unsupported Packages: {selected value} ({N} incompatible packages)
- Unsupported API Handling: {selected value}
- Windows Native APIs: {selected value}
- System.Web Adapters: {selected value}
  Skill: aspnet-system-web-adapters [only when "Use System.Web Adapters" selected]

### Modernization
[one line per applicable option only]
- Configuration Migration: {selected value}
- Logging Framework: {selected value}
- Dependency Injection: {selected value}
- Assembly Binding Redirects: {selected value}
- Nullable Reference Types: {selected value}
- Entity Framework: {selected value}
```

Rules for writing this block:
- Omit headings whose options are all non-applicable
- Never write a placeholder — use actual confirmed values
- When System.Web Adapters selected value is "Use System.Web Adapters",
  always include the `Skill:` line beneath it
- The `**Source**:` line links execution stage back to the full file
- Custom options (from user-provided skills) go under their declared category heading

---

## Custom Upgrade Options

Users can extend the built-in options by adding `upgrade-option: {Name}` to any
custom skill's description. During Step 1.5, the agent scans Available Skills
descriptions for this prefix — only matching skills are loaded.

A matching skill must contain an `## Upgrade Option` section:

```markdown
## Upgrade Option

**Option Name**: {unique name}
**Category**: {Project Structure | Compatibility | Modernization}

**Applicable when**:
- {assessment signal condition}

**Not applicable when**:
- {condition}

**Default logic**:
- Recommend **{value}** if: {condition}

**Options**:
- **{Value A}** — {description}
- **{Value B}** — {description}

**Stored as**: `Upgrade Options > {Category} > {Option Name}`
```

Custom options go under their declared category heading in the options file and compact block.
The category determines which section of the options file the option appears in.
If a custom option duplicates a built-in option name, the custom option wins.
