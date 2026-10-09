---
name: migrating-newtonsoft-to-system-text-json
description: >
  Migrates .NET projects from Newtonsoft.Json to System.Text.Json, updating package references,
  code files, and handling API differences. Use when asked to "migrate Newtonsoft", "switch to
  System.Text.Json", "replace Newtonsoft.Json", or "upgrade JSON library". Triggers for
  .csproj/.vbproj files referencing Newtonsoft.Json and .cs/.vb files using Newtonsoft.Json
  namespaces. Also applies when modernizing .NET dependencies or removing third-party JSON
  libraries.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Newtonsoft.Json to System.Text.Json Migration

## Overview

Migrate .NET projects from `Newtonsoft.Json` to `System.Text.Json`, including package references, code files, and configuration changes while preserving application behavior.

## Scope Determination

- If a single project is specified, migrate that project only.
- If a solution is specified, migrate all projects in the solution referencing `Newtonsoft.Json`.
- NuGet package names, assembly names, and project names are **case-insensitive** — account for this when searching for and removing dependencies.

## Wire-Contract Gate

Before replacement in any server-side project or library serving Framework HTTP endpoints, first run the
`migrating-webapi-odata` wire-compatibility gate, including non-OData responses.
Require a scoped PASS, or evidence-backed NOT APPLICABLE from its applicability
check for code with no affected HTTP consumers. On STOP, unknown evidence, or an
unavailable gate, do not execute the conversion instructions below. Keep the
original serializer, response attributes/models, and shared dependencies intact;
preservation requires a separately agreed task, not this automatic replacement.
Carry the scoped record into child tasks with `#skill:migrating-webapi-odata`.

## Serialization Prerequisite

For MVC/Web API JSON response paths, before changing packages or serializer registrations,
load `migrating-mvc-content-negotiation` and complete its Serialization Naming
Inventory and naming recipes. For non-MVC HTTP paths, preserve the effective policy
in the options actually used by that response: Minimal API HTTP JSON options,
per-call `Results.Json` options, or manual serialization settings. MVC
`AddJsonOptions` does not configure these paths; do not add controllers to configure them.
For every HTTP path, preserve effective source defaults, explicit names, and custom
resolver behavior, then compare actual HTTP responses. Unknown policy or response
evidence requires resolution before conversion, not adopting web defaults.
For standalone calls, preserve the caller's options instead of applying web defaults.

For the MVC/Web API scope above: If this required naming skill is unavailable, STOP
before package, registration, or contract changes. Keep the current host, serializer,
and dependencies intact; do not substitute general knowledge for the inventory.
Record the blocked scope and load failure through the Retention Decision below.
Ask the owner to approve a separate preservation task or a narrower unaffected
conversion scope, and persist the decision using those same Gate Records.
Do not resume the affected conversion until the guidance is available and its
evidence requirements are satisfied. Preservation approval never waives an existing wire-gate STOP.

## Retention Decision

This decision applies to every conversion scope, including standalone libraries
and non-MVC callers. Before Step 1, if a converter, resolver, attribute, or response contract cannot be
represented faithfully in System.Text.Json, STOP conversion of the affected
project and protected consumers. Retain their Newtonsoft package references,
serializer configuration, attributes, and shared dependencies. Ask for a decision
rather than continuing removal, and reuse the wire gate's Gate Records:
record the reason and affected scope under `## Wire Compatibility` in
`progress-details.md`. In `task.md`, record `Serializer conversion: RETAINED`
for the affected scope and a relative evidence link, separately from its
wire-gate verdict (PASS / NOT APPLICABLE / STOP). RETAINED is a conversion
disposition, not wire-contract clearance; preserve the existing scoped
wire-gate verdict. Persist the
user's retention choice and approved scope immediately in `scenario-instructions.md`.
Without task state, use `.github/upgrades/wire-compatibility.md` for evidence and
decisions. Carry the record path into child tasks and read it on resume before
conversion or cleanup; do not infer approval from a missing record.

Only after the user approves a narrower conversion scope may unaffected projects
proceed. Retention approval never waives or converts a wire-gate STOP; each
remaining scope must independently satisfy the Wire-Contract Gate above.
Mark the retained scope as excluded from conversion; if none remains,
report retention rather than claiming a completed serializer migration. A newly
discovered incompatibility during conversion returns to this decision before
further edits, not to the cleanup loop.

## Workflow

Complete all steps in order without pausing between them. Continue until the migration is finished or user input is genuinely required. Ordering matters because later steps depend on earlier ones (e.g., code updates rely on package references being correct first).

```
Migration Progress:
- [ ] Step 0: Compatibility preflight
- [ ] Step 1: Update package dependencies
- [ ] Step 2: Update code files
- [ ] Step 3: Validate migration
- [ ] Step 4: Build verification
```

### Step 0: Compatibility Preflight

For all scoped projects and their consumers, including standalone libraries and
non-MVC callers, inspect compatibility before any package, CPM, registration, or contract edits:

1. Inventory Newtonsoft usage and effective caller settings: converters, resolvers, attributes,
   shared models, and features such as `JObject/JToken`, `TypeNameHandling`,
   `PreserveReferencesHandling`, and `JsonExtensionData`.
2. Determine whether each contract can be represented faithfully in System.Text.Json,
   including serialized names, omitted members, polymorphism, reference identity,
   and extension data. These features are compatibility checks, not blanket reasons to retain Newtonsoft.
3. Record each project and affected consumer as conversion-eligible, retained, or unknown,
   with source evidence and the proposed equivalent behavior. Resolve unknown compatibility before editing;
   use the Retention Decision for incompatible scopes and obtain the owner's narrower-scope approval.
4. Proceed only for approved conversion-eligible scopes that also satisfy any applicable
   HTTP gates. Preserve retained/shared contracts and dependencies.

### Step 1: Update Package Dependencies

For each project marked conversion-eligible by Step 0 in the approved conversion scope with an **explicit** dependency on `Newtonsoft.Json` in the project file or imported MSBuild targets (skip projects that only receive it transitively to avoid adding unnecessary new package references):

1. Remove the `Newtonsoft.Json` package reference and assembly reference from the project file.
2. Add a `System.Text.Json` package reference with a version supporting the project's target framework. Use tools to determine the best version; fall back to manual determination if unavailable.
3. If using Central Package Management (CPM):
   - Remove the `Newtonsoft.Json` `PackageVersion` entry from `Directory.Packages.props` only after verifying that no project governed by that entry still needs it, including retained and out-of-scope projects outside the selected solution. Account for conditional references and imported or nested central files; do not expand the conversion scope. If any consumer still needs the entry or usage is uncertain, keep it.
   - Add `System.Text.Json` `PackageReference` without a version in project files.
   - Add a `System.Text.Json` `PackageVersion` entry to `Directory.Packages.props`.

### Step 2: Update Code Files

Update code files in the approved conversion scope, checking dependent projects for Newtonsoft types received through project references. Do not rewrite retained consumers or their shared contracts:

1. Search for all code files using `Newtonsoft.Json` — prefer search tools when available, passing root folders for all affected projects.
2. Replace `Newtonsoft.Json` API usage with `System.Text.Json` equivalents. Preserve business logic, comments, and formatting. Never add placeholder code.
3. Handle using statements correctly:
   - If a file still uses Newtonsoft API after partial conversion, replace `Newtonsoft.Json` usings with appropriate `System.Text.Json` usings.
   - If no Newtonsoft API remains after conversion, remove the usings entirely — do not replace them with `System.Text.Json` usings.
   - If no `Newtonsoft.Json` usings existed originally, do not add `System.Text.Json` usings.
   - Skip comments and string literal constants when checking for Newtonsoft API usage.
4. Add namespace-specific usings when replacement types live in sub-namespaces. For example, replacing `JsonPropertyAttribute` with `JsonPropertyNameAttribute` requires `using System.Text.Json.Serialization;` because the type moved from the root namespace to a child namespace.
5. If a late discovery means code cannot be converted faithfully, restore the Newtonsoft references and required central `PackageVersion` entries for the retained scope, together with its serializer configuration and contracts changed by this conversion. Preserve unrelated user changes; do not reset whole files or the repository. Then stop and replan through the Retention Decision before further conversion or cleanup; flagging the issue does not authorize removal.

### Step 3: Validate Migration

Search only the approved migration scope for remaining `Newtonsoft.Json` references.
If any are found there, return to Step 2. Do not expand cleanup into STOP scopes
or remove shared references required by protected consumers.
Recorded retained scopes are excluded from this loop; verify their Newtonsoft
references and configuration remain intact instead of treating them as leftovers.

### Step 4: Build Verification

Build all modified projects. Fix all build errors before proceeding — iterating until the build succeeds ensures the migration is mechanically correct.

## API Differences

### Key Behavioral Differences

The System.Text.Json column describes standalone calls with default
`JsonSerializerOptions`, not ASP.NET Core web defaults. MVC and Minimal API web
defaults use case-insensitive property matching (`PropertyNameCaseInsensitive = true`)
and accept quoted numbers (`NumberHandling = AllowReadingFromString`).
Explicit caller or host options can override these defaults; preserve the effective settings.

| Behavior | Newtonsoft.Json | System.Text.Json |
|----------|----------------|------------------|
| Property name matching | Case-insensitive by default | Case-sensitive by default — use `PropertyNameCaseInsensitive` if needed |
| Character escaping | Permissive | Escapes more characters for XSS protection |
| Comments/trailing commas | Allowed by default | Requires `ReadCommentHandling` and `AllowTrailingCommas` |
| Numbers in quotes | Accepted | Requires `NumberHandling` configuration |
| Quote style | Single quotes and unquoted names allowed | Requires double quotes per RFC 8259 |

### Common Type Mappings

| Newtonsoft.Json | System.Text.Json |
|-----------------|------------------|
| `JsonPropertyAttribute` | `JsonPropertyNameAttribute` (in `System.Text.Json.Serialization`) |
| `NullValueHandling.Ignore` | `DefaultIgnoreCondition` global option |
| `[JsonConstructor]` | `[JsonConstructor]` (same attribute exists) |
| `PreserveReferencesHandling` | `ReferenceHandler` global setting |
| `TypeNameHandling` | `JsonDerivedTypeAttribute` for polymorphism |
| `JsonConvert.SerializeObject()` | `JsonSerializer.Serialize()` |
| `JsonConvert.DeserializeObject()` | `JsonSerializer.Deserialize()` |

### Target Framework Support

System.Text.Json is included in:
- .NET Core 3.1+
- .NET Standard 2.0+ (via NuGet package)
- .NET Framework 4.6.2+ (via NuGet package)

## Success Criteria

- No `Newtonsoft.Json` references remain in the approved scope; protected consumers retain theirs
- Retained scopes and reasons are recorded and excluded from cleanup; partial conversion is reported as partial, not full removal
- All modified projects build without errors
- Any unconvertible patterns or behavioral changes flagged for the user
