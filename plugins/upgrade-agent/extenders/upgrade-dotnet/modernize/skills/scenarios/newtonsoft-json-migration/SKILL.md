---
name: newtonsoft-json-migration
description: >
  Migrates .NET projects from Newtonsoft.Json to System.Text.Json.
  Use when user wants to replace Newtonsoft.Json, switch to System.Text.Json,
  migrate JSON library, or modernize JSON serialization.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: low
  traits: .NET|CSharp|VisualBasic|DotNetCore
  scenarioTraitsSet: [.NET]
---

# Newtonsoft.Json to System.Text.Json Migration

## 1. Assessment

Scan the solution to build a complete picture of Newtonsoft.Json usage. Capture findings in `assessment.md`.

### Packages to Scan For

Search all project files and package management files (`Directory.Packages.props`) for:
- `Newtonsoft.Json` (direct package reference)
- `Newtonsoft.Json.Bson`, `Newtonsoft.Json.Schema`, or other Newtonsoft extension packages
- Third-party packages that depend on Newtonsoft.Json (these may force a dual-library situation)

### File Inventory

Search all code files across the solution for `using Newtonsoft.Json` (and variations like `using Newtonsoft.Json.Linq`). Record which files in which projects contain these usings — this gives a quick per-project file count that drives planning.

### Code Patterns to Identify

The patterns below help gauge complexity per project. You don't need to search for each one separately — note them as you encounter them during the usings scan or during execution:

| Pattern | What to Record |
|---------|---------------|
| `JsonConvert.SerializeObject` / `DeserializeObject` | Count and locations — most common migration target |
| `JsonSerializer` (Newtonsoft) usage | Direct serializer use, especially with custom settings |
| `[JsonProperty]`, `[JsonConverter]`, `[JsonIgnore]` | Attribute-heavy models — bulk replacement needed |
| Custom `JsonConverter` implementations | High complexity — System.Text.Json converters have different API surface |
| `JObject`, `JArray`, `JToken` manipulation | Needs `JsonDocument`/`JsonElement` or `JsonNode` replacement |
| `JsonSerializerSettings` configuration | Settings like `NullValueHandling`, `ReferenceLoopHandling`, `ContractResolver` |
| Public API types using Newtonsoft types | Downstream consumers affected — higher risk |

### Risk Indicators

Flag these as higher complexity in the assessment:
- **Public API exposure**: Methods/properties returning or accepting `JObject`, `JToken`, or Newtonsoft-attributed types — downstream breaking change
- **Custom converters**: `JsonConverter<T>` subclasses — API surface differs significantly between libraries  
- **Dynamic/JToken manipulation**: Heavy use of `JObject.Parse`, LINQ-to-JSON — requires structural rewrite to `JsonDocument` or `JsonNode`
- **Non-default serializer settings**: Custom `ContractResolver`, `ReferenceLoopHandling`, or `PreserveReferencesHandling` — some have no direct System.Text.Json equivalent

### Assessment Output

Create `assessment.md` in the workflow folder with this structure:

```markdown
# Assessment: Newtonsoft.Json to System.Text.Json

## Affected Projects
| Project | Newtonsoft Packages | Key Patterns | Public API Exposure | Risk |
|---------|---------------------|-------------|---------------------|------|
| MyApp.Core | Newtonsoft.Json | JObject manipulation, custom converters | Yes — API returns JObject | High |
| MyApp.Web | Newtonsoft.Json | JsonConvert, [JsonProperty] | No | Low |

## Transitive Consumers
Projects that reference affected projects but don't directly use Newtonsoft:
- [list or "none"]

## Key Findings
- [Notable patterns, risks, or decisions needed]
```

## 2. Planning

Based on the assessment, create `plan.md` with tasks ordered bottom-up (leaf dependencies first, then consumers).

For each task include:
- Which projects or groups of projects are covered
- What changes are needed (packages, code patterns)
- Risk level and anything requiring user decision

Projects exposing Newtonsoft types in public APIs should be migrated before their consumers. Projects that are transitive-only consumers still need a task if their code references types that will change.

## 3. Execution

Execute the plan task by task. For any task that involves migrating Newtonsoft.Json code or packages, apply the **migrating-newtonsoft-to-system-text-json** feature skill. It provides API mappings, package changes, code transformations, and validation steps.

After completing all tasks, do a final solution-wide search for any remaining `Newtonsoft.Json` references and fix stragglers.

## 4. Validation

- Build the full solution — zero errors required
- No remaining `Newtonsoft.Json` namespace references in code
- If the project had tests, run them and report results
