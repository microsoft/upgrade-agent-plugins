---
name: semantic-kernel-to-agents-framework
description: >
  Migrates .NET projects from Semantic Kernel to the Microsoft Agents Framework.
  Use when user wants to migrate Semantic Kernel agents, upgrade from SK to Agents Framework,
  or replace ChatCompletionAgent/OpenAIAssistantAgent with Agent Framework equivalents.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: medium
  traits: .NET|CSharp|VisualBasic|DotNetCore
  scenarioTraitsSet: [.NET]
---

# Semantic Kernel to Agents Framework Migration

## 1. Assessment

Scan the solution to build a complete picture of SK agent usage. Capture findings in `assessment.md`.

### Packages to Scan For

Search all project files and package management files (`Directory.Packages.props`) for:
- `Microsoft.SemanticKernel.Agents.Core`
- `Microsoft.SemanticKernel.Agents.OpenAI`
- `Microsoft.SemanticKernel.Agents.AzureAI`
- `Microsoft.SemanticKernel` — check if used solely for agents or also for other SK features (prompts, memory, connectors)

### File Inventory

Search all code files across the solution for `using Microsoft.SemanticKernel.Agents`. Record which files in which projects contain these usings — this gives a quick per-project file count that drives planning.

### Code Patterns to Identify

For each project with SK agent references, scan code files for:

| Pattern | What to Record |
|---------|---------------|
| Agent types (`ChatCompletionAgent`, `OpenAIAssistantAgent`, `AzureAIAgent`, `OpenAIResponseAgent`, `A2AAgent`) | Which types, how many instances |
| Provider usage (OpenAI, Azure OpenAI, Azure AI Foundry) | Provider per agent — determines target AF package |
| Tool/function registration (`KernelPlugin`, `KernelFunction`, `[KernelFunction]`) | Agent-specific vs shared kernel plugins |
| Thread management (`AgentGroupChat`, `AgentThread`, manual thread passing) | Multi-agent orchestration complexity |
| `InnerContent` access | Breaking-glass pattern — needs `RawRepresentation` migration |
| DI registration of agents or SK services | How agents are wired into the application |

### Risk Indicators

Flag these as higher complexity in the assessment:
- **Mixed SK usage**: Project uses SK for both agents AND other features (prompts, memory, connectors) — cannot remove `Microsoft.SemanticKernel` package entirely
- **Multi-agent orchestration**: `AgentGroupChat` or custom agent-to-agent patterns — thread management differs significantly in AF
- **Custom channel implementations**: Extending SK agent channels — no direct AF equivalent
- **Test projects mocking SK agent types**: Test seams change with AF interfaces

### Assessment Output

Create `assessment.md` in the workflow folder with this structure:

```markdown
# Assessment: Semantic Kernel to Agents Framework

## Affected Projects
| Project | SK Agent Packages | Agent Types | Provider | Risk |
|---------|-------------------|-------------|----------|------|
| MyApp.Agents | Agents.Core, Agents.OpenAI | ChatCompletionAgent (2) | Azure OpenAI | Low |
| MyApp.Tests | (transitive) | Mocks ChatCompletionAgent | — | Medium |

## Transitive Consumers
Projects that reference affected projects but don't directly use SK agents:
- [list or "none"]

## Key Findings
- [Notable patterns, risks, or decisions needed]
```

## 2. Planning

Based on the assessment, create `plan.md` with a task per project ordered bottom-up (leaf dependencies first, then consumers).

For each task include:
- Project name and path
- What changes are needed (packages, code patterns)
- The AF provider package to use (based on assessed provider)
- Risk level and anything requiring user decision

Projects that are transitive-only consumers (no direct SK agent code) still need a task if their code references types from affected projects that will change.

## 3. Execution

Execute the plan task by task. For any task that involves migrating SK agent code or packages, apply the **migrating-semantic-kernel-to-agents** feature skill. It provides:
- Package replacement mappings
- API and namespace transformations (`references/api-mappings.md`)
- Provider-specific patterns (`references/provider-patterns.md`)
- Validation checklist

After completing all tasks, do a final solution-wide search for any remaining `Microsoft.SemanticKernel.Agents` references and fix stragglers.

## 4. Validation

- Build the full solution — zero errors required
- No remaining `Microsoft.SemanticKernel.Agents` namespace references in code
- If the project had tests, run them and report results
