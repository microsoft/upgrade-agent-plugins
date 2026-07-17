# Provider-Specific Migration Patterns

## Contents

- [1. OpenAI Chat Completion](#1-openai-chat-completion)
- [2. Azure OpenAI Chat Completion](#2-azure-openai-chat-completion)
- [3. OpenAI Assistants](#3-openai-assistants)
- [4. Azure AI Foundry](#4-azure-ai-foundry)
- [5. A2A](#5-a2a)
- [6. OpenAI Responses](#6-openai-responses)
- [7. Azure OpenAI Responses](#7-azure-openai-responses)
- [Package Reference Quick Reference](#package-reference-quick-reference)

## 1. OpenAI Chat Completion

**Packages:** Remove `Microsoft.SemanticKernel.Agents.OpenAI` → Add `Microsoft.Agents.AI.OpenAI`

**Before:**
```csharp
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.Agents;

Kernel kernel = Kernel.CreateBuilder()
    .AddOpenAIChatClient(modelId, apiKey)
    .Build();

ChatCompletionAgent agent = new()
{
    Instructions = "You are a helpful assistant",
    Kernel = kernel
};

AgentThread thread = new ChatHistoryAgentThread();
```

**After:**
```csharp
using Microsoft.Agents.AI;
using OpenAI;

AIAgent agent = new OpenAIClient(apiKey)
    .GetChatClient(modelId)
    .CreateAIAgent(instructions: "You are a helpful assistant");

AgentThread thread = agent.GetNewThread();
```

## 2. Azure OpenAI Chat Completion

**Packages:** Remove `Microsoft.SemanticKernel.Agents.OpenAI` → Add `Microsoft.Agents.AI.OpenAI`
Keep `Azure.AI.OpenAI` and `Azure.Identity` (if using `AzureCliCredential`; otherwise use `ApiKeyCredential`).

**Before:**
```csharp
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.Agents;
using Azure.Identity;

Kernel kernel = Kernel.CreateBuilder()
    .AddAzureOpenAIChatClient(deploymentName, endpoint, new AzureCliCredential())
    .Build();

ChatCompletionAgent agent = new()
{
    Instructions = "You are a helpful assistant",
    Kernel = kernel
};
```

**After:**
```csharp
using Microsoft.Agents.AI;
using Azure.AI.OpenAI;
using Azure.Identity;

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new AzureCliCredential())
    .GetChatClient(deploymentName)
    .CreateAIAgent(instructions: "You are a helpful assistant");
```

## 3. OpenAI Assistants

**Packages:** Remove `Microsoft.SemanticKernel.Agents.OpenAI` → Add `Microsoft.Agents.AI.OpenAI`

**Before:**
```csharp
using Microsoft.SemanticKernel.Agents.OpenAI;
using OpenAI.Assistants;

AssistantClient assistantClient = new(apiKey);
Assistant assistant = await assistantClient.CreateAssistantAsync(
    modelId, instructions: "You are a helpful assistant");

OpenAIAssistantAgent agent = new(assistant, assistantClient) { Kernel = kernel };
AgentThread thread = new OpenAIAssistantAgentThread(assistantClient);
```

**After (creating a new assistant):**
```csharp
using Microsoft.Agents.AI;
using OpenAI;

AIAgent agent = new OpenAIClient(apiKey)
    .GetAssistantClient()
    .CreateAIAgent(modelId, instructions: "You are a helpful assistant");

AgentThread thread = agent.GetNewThread();

// Cleanup when needed
await assistantClient.DeleteThreadAsync(thread.ConversationId);
```

**After (retrieving an existing assistant):**
```csharp
using Microsoft.Agents.AI;
using OpenAI;

AIAgent agent = new OpenAIClient(apiKey)
    .GetAssistantClient()
    .GetAIAgent(assistantId);

AgentThread thread = agent.GetNewThread();
```

## 4. Azure AI Foundry

**Packages:** Remove `Microsoft.SemanticKernel.Agents.AzureAI` → Add `Microsoft.Agents.AI.AzureAI`
Keep `Azure.Identity`.

**Before (direct AzureAIAgent creation):**
```csharp
using Microsoft.SemanticKernel.Agents.AzureAI;
using Azure.Identity;

AzureAIAgent agent = new(
    endpoint: new Uri(endpoint),
    credential: new AzureCliCredential(),
    projectId: projectId)
{
    Instructions = "You are a helpful assistant"
};

AgentThread thread = new AzureAIAgentThread(agent);
```

**Before (PersistentAgent definition):**
```csharp
PersistentAgent definition = await client.Administration.CreateAgentAsync(
    deploymentName, tools: [new CodeInterpreterToolDefinition()]);

AzureAIAgent agent = new(definition, client);
AgentThread thread = new AzureAIAgentThread(client);
```

**After (creating a new agent):**
```csharp
using Microsoft.Agents.AI;
using Azure.AI.Agents.Persistent;
using Azure.Identity;

var client = new PersistentAgentsClient(endpoint, new AzureCliCredential());

AIAgent agent = client.CreateAIAgent(
    model: deploymentName,
    instructions: "You are a helpful assistant",
    tools: [/* Azure.AI.Agents.Persistent.ToolDefinition types */]);

AgentThread thread = agent.GetNewThread();
```

**After (retrieving an existing agent):**
```csharp
using Microsoft.Agents.AI;
using Azure.AI.Agents.Persistent;
using Azure.Identity;

var client = new PersistentAgentsClient(endpoint, new AzureCliCredential());
AIAgent agent = await client.GetAIAgentAsync(agentId);
AgentThread thread = agent.GetNewThread();
```

## 5. A2A

**Packages:** Remove `Microsoft.SemanticKernel.Agents.A2A` → Add `Microsoft.Agents.AI.A2A`

**Before:**
```csharp
using var httpClient = CreateHttpClient();
var client = new A2AClient(url, httpClient);
var cardResolver = new A2ACardResolver(url, httpClient);
var agentCard = await cardResolver.GetAgentCardAsync();
var agent = new A2AAgent(client, agentCard);
```

**After:**
```csharp
A2ACardResolver agentCardResolver = new(new Uri(a2aAgentHost));
AIAgent agent = await agentCardResolver.GetAIAgentAsync();
```

## 6. OpenAI Responses

**Packages:** Remove `Microsoft.SemanticKernel.Agents.OpenAI` → Add `Microsoft.Agents.AI.OpenAI`

**Before:**
```csharp
using Microsoft.SemanticKernel.Agents.OpenAI;

OpenAIResponseAgent agent = new(new OpenAIClient(apiKey))
{
    Name = "ResponseAgent",
    Instructions = "Answer all queries in English and French.",
};

// Manual thread management required in SK
AgentThread? agentThread = null;
var responseItems = agent.InvokeAsync(new ChatMessageContent(AuthorRole.User, "Input"), agentThread);
await foreach (AgentResponseItem<ChatMessageContent> responseItem in responseItems)
{
    agentThread = responseItem.Thread; // Must manually update thread
    WriteAgentChatMessage(responseItem.Message);
}
```

**After:**
```csharp
using Microsoft.Agents.AI.OpenAI;

AIAgent agent = new OpenAIClient(apiKey)
    .GetOpenAIResponseClient(modelId)
    .CreateAIAgent(
        name: "ResponseAgent",
        instructions: "Answer all queries in English and French.",
        tools: [/* AITools */]);

AgentThread thread = agent.GetNewThread();
var result = await agent.RunAsync(userInput, thread);
// Thread is automatically updated — no manual management needed
```

## 7. Azure OpenAI Responses

**Packages:** Remove `Microsoft.SemanticKernel.Agents.OpenAI` → Add `Microsoft.Agents.AI.OpenAI`
Keep `Azure.AI.OpenAI`.

**Before:**
```csharp
using Microsoft.SemanticKernel.Agents.OpenAI;
using Azure.AI.OpenAI;

OpenAIResponseAgent agent = new(new AzureOpenAIClient(endpoint, new AzureCliCredential()))
{
    Name = "ResponseAgent",
    Instructions = "Answer all queries in English and French.",
};

// Manual thread management required in SK
AgentThread? agentThread = null;
var responseItems = agent.InvokeAsync(new ChatMessageContent(AuthorRole.User, "Input"), agentThread);
await foreach (AgentResponseItem<ChatMessageContent> responseItem in responseItems)
{
    agentThread = responseItem.Thread;
    WriteAgentChatMessage(responseItem.Message);
}
```

**After:**
```csharp
using Microsoft.Agents.AI.OpenAI;
using Azure.AI.OpenAI;

AIAgent agent = new AzureOpenAIClient(endpoint, new AzureCliCredential())
    .GetOpenAIResponseClient(modelId)
    .CreateAIAgent(
        name: "ResponseAgent",
        instructions: "Answer all queries in English and French.",
        tools: [/* AITools */]);

AgentThread thread = agent.GetNewThread();
var result = await agent.RunAsync(userInput, thread);
// Thread is automatically updated — no manual management needed
```

## Package Reference Quick Reference

| Provider | Remove Package | Add Package |
|----------|---------------|-------------|
| OpenAI Chat Completion | `Microsoft.SemanticKernel.Agents.OpenAI` | `Microsoft.Agents.AI.OpenAI` |
| Azure OpenAI Chat Completion | `Microsoft.SemanticKernel.Agents.OpenAI` | `Microsoft.Agents.AI.OpenAI` |
| OpenAI Assistants | `Microsoft.SemanticKernel.Agents.OpenAI` | `Microsoft.Agents.AI.OpenAI` |
| Azure AI Foundry | `Microsoft.SemanticKernel.Agents.AzureAI` | `Microsoft.Agents.AI.AzureAI` |
| A2A | `Microsoft.SemanticKernel.Agents.A2A` | `Microsoft.Agents.AI.A2A` |
| OpenAI Responses | `Microsoft.SemanticKernel.Agents.OpenAI` | `Microsoft.Agents.AI.OpenAI` |
| Azure OpenAI Responses | `Microsoft.SemanticKernel.Agents.OpenAI` | `Microsoft.Agents.AI.OpenAI` |
| All providers | `Microsoft.SemanticKernel.Agents.Core` | `Microsoft.Agents.AI.Abstractions` |

Always add `Microsoft.Agents.AI.Abstractions` in addition to the provider-specific package.
