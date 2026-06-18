---
name: migrating-semantic-kernel-to-agents
description: >
  Migrates .NET projects from Microsoft Semantic Kernel Agents (Microsoft.SemanticKernel.Agents)
  to Microsoft Agent Framework (Microsoft.Agents.AI). Handles NuGet package updates, namespace
  changes, agent creation, tool registration, thread management, and invocation transformations.
  Use when migrating ChatCompletionAgent, OpenAIAssistantAgent, AzureAIAgent, OpenAIResponseAgent,
  or A2AAgent to Agent Framework. Triggers for "semantic kernel to agents", "migrate SK agents",
  "upgrade agents framework", "ChatCompletionAgent to ChatClientAgent",
  "Microsoft.SemanticKernel.Agents to Microsoft.Agents.AI".
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Semantic Kernel to Agent Framework Migration

## Overview

Migrate .NET projects from `Microsoft.SemanticKernel.Agents` to `Microsoft.Agents.AI` (Agent Framework). The migration involves updating NuGet packages, namespaces, agent creation patterns, tool registration, thread management, and invocation methods.

**API mappings and code examples**: Read `references/api-mappings.md` for detailed type/method/pattern transformations.
**Provider-specific patterns**: Read `references/provider-patterns.md` for per-provider migration (OpenAI, Azure OpenAI, Assistants, Azure AI Foundry, A2A, Responses).

## Workflow

```
Migration Progress:
- [ ] Step 1: Execute
- [ ] Step 2: Validate
```

### Step 1: Execute

Execute continuously without pausing unless user interaction is truly needed.

#### 1a. Update Package References

For each project with **explicit** package dependencies (skip transitive-only consumers):

1. Read the project file to understand its structure and dependencies
2. Remove Semantic Kernel agent packages:
   - `Microsoft.SemanticKernel.Agents.Core`
   - `Microsoft.SemanticKernel.Agents.OpenAI`
   - `Microsoft.SemanticKernel.Agents.AzureAI`
   - `Microsoft.SemanticKernel` (only if used solely for agents)
3. Add Agent Framework packages based on provider (see `references/provider-patterns.md` for the mapping):
   - `Microsoft.Agents.AI.Abstractions` (always required)
   - Provider-specific package (e.g., `Microsoft.Agents.AI.OpenAI`)
4. Never guess package versions - use available tools to determine the latest stable version

**Central Package Management (CPM):**

If `PackageReference` elements lack versions or use `VersionOverride`, the project uses CPM. Handle it carefully because creating a duplicate props file or using wrong paths causes silent build failures:

- Search for `Directory.Packages.props` starting from the project folder **upward** through parent directories
- Read the existing file first to understand its structure
- Edit (never recreate) the existing file: remove old `PackageVersion` entries, add new ones
- Add `PackageReference` elements **without versions** in project files
- Always use the full absolute path when editing `Directory.Packages.props`

If projects specify versions directly in `PackageReference` elements, make all changes in the project file only.

#### 1b. Update Code Files

Find all code files in affected projects (including transitive dependents) that reference SK agent APIs. Use search tools and pass each project's root folder.

Apply transformations from `references/api-mappings.md`:

1. Search for `Microsoft.SemanticKernel.Agents` in using statements, types, and API calls (skip comments and string literals)
2. Replace agent types, method calls, configuration patterns, and namespaces
3. Handle provider-specific patterns per `references/provider-patterns.md`

**Using statement rules:**
- Replace SK agent using statements with AF equivalents
- If no other SK agent API remains in the file, remove the using instead of replacing it
- If no SK agent using statements existed originally, do not add AF using statements
- Add namespace imports for types that moved (e.g., `Microsoft.Agents.AI` for `ChatClientAgent`)

**Code preservation:**
- Never add placeholder code or remove existing comments
- Keep business logic as close to the original as possible
- Track files/lines where conversion is impossible or may cause behavioral changes

**NuGet names are case-insensitive** - account for this when searching or removing dependencies.

#### 1c. Iterate Until Clean

Search for `Microsoft.SemanticKernel.Agents` in all affected projects again. If any references remain, repeat step 1b. Continue until no SK agent references exist.

### Step 2: Validate

1. Run `dotnet build` on all modified projects - zero errors required
2. Fix all build errors without violating migration guidance
3. Verify using this checklist:
   - [ ] All `using Microsoft.SemanticKernel.Agents` statements replaced or removed
   - [ ] All `InvokeAsync` -> `RunAsync`, `InvokeStreamingAsync` -> `RunStreamingAsync`
   - [ ] Return types: `AgentRunResponse` (non-streaming), `IAsyncEnumerable<AgentRunResponseUpdate>` (streaming)
   - [ ] Thread creation uses `agent.GetNewThread()`
   - [ ] `[KernelFunction]` removed; `AIFunctionFactory.Create()` used
   - [ ] `AgentRunOptions` or `ChatClientAgentRunOptions` replaces `AgentInvokeOptions`
   - [ ] `RawRepresentation` replaces `InnerContent`

## Key Behavioral Differences

These AF behaviors differ from SK and affect migration decisions:

- **Automatic thread management**: AF manages thread state automatically. SK required manual thread updates in some scenarios (e.g., OpenAI Responses).
- **Simplified tool registration**: AF uses direct `AIFunction` registration via `AIFunctionFactory.Create()` instead of the `KernelPlugin`/`KernelFunction` system.
- **Unified return types**: Non-streaming returns `AgentRunResponse`; streaming returns `IAsyncEnumerable<AgentRunResponseUpdate>`.
- **Two-level breaking glass**: For `ChatClient`-based agents, access underlying SDK objects by casting `RawRepresentation` to `ChatResponse`, then casting `ChatResponse.RawRepresentation` to the SDK type.
- **Unified usage metadata**: Access via `response.Usage` (non-streaming) or `update.Contents.OfType<UsageContent>()` (streaming).
