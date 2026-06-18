# API Mappings: Semantic Kernel Agents → Agent Framework

## Contents

- [Agent Type Mappings](#agent-type-mappings)
- [Method Call Mappings](#method-call-mappings)
- [Configuration Mappings](#configuration-mappings)
- [Namespace Updates](#namespace-updates)
- [Chat Completion Abstractions](#chat-completion-abstractions)
- [Agent Creation](#agent-creation)
- [Thread Management](#thread-management)
- [Tool Registration](#tool-registration)
- [Invocation Methods](#invocation-methods)
- [Options and Configuration](#options-and-configuration)
- [Dependency Injection](#dependency-injection)
- [Thread Cleanup](#thread-cleanup)
- [Usage Metadata](#usage-metadata)
- [Breaking Glass Pattern](#breaking-glass-pattern)
- [CodeInterpreter Tool](#codeinterpreter-tool)
- [Provider-Specific Options](#provider-specific-options)
- [Common Migration Issues](#common-migration-issues)

## Agent Type Mappings

| Semantic Kernel Class | Agent Framework Replacement | Constructor Changes |
|----------------------|----------------------------|-------------------|
| `IChatCompletionService` | `IChatClient` | Convert via `chatService.AsChatClient()` |
| `ChatCompletionAgent` | `ChatClientAgent` | Remove `Kernel` parameter, add `IChatClient` |
| `OpenAIAssistantAgent` | `AIAgent` (via extension) | **New**: `OpenAIClient.GetAssistantClient().CreateAIAgent()` / **Existing**: `.GetAIAgent(assistantId)` |
| `AzureAIAgent` | `AIAgent` (via extension) | **New**: `PersistentAgentsClient.CreateAIAgent()` / **Existing**: `.GetAIAgent(agentId)` |
| `OpenAIResponseAgent` | `AIAgent` (via extension) | `OpenAIClient.GetOpenAIResponseClient().CreateAIAgent()` |
| `A2AAgent` | `AIAgent` (via extension) | `A2ACardResolver.GetAIAgentAsync()` |
| `BedrockAgent` | Not supported | Custom implementation required |

**CreateAIAgent()** — use when creating new agents in a hosted service.
**GetAIAgent(agentId)** — use when retrieving existing agents from a hosted service.

## Method Call Mappings

| Semantic Kernel Method | Agent Framework Method | Notes |
|----------------------|----------------------|-------|
| `agent.InvokeAsync(message, thread, options)` | `agent.RunAsync(message, thread, options)` | Different return type |
| `agent.InvokeStreamingAsync(message, thread, options)` | `agent.RunStreamingAsync(message, thread, options)` | Different return type |
| `new ChatHistoryAgentThread()` | `agent.GetNewThread()` | No parameters needed |
| `new OpenAIAssistantAgentThread(client)` | `agent.GetNewThread()` | No parameters needed |
| `new AzureAIAgentThread(client)` | `agent.GetNewThread()` | No parameters needed |
| `thread.DeleteAsync()` | Provider-specific cleanup | Use provider client directly |

**Return type changes:**
- Non-streaming: `IAsyncEnumerable<AgentResponseItem<ChatMessageContent>>` → `AgentRunResponse`
- Streaming: `IAsyncEnumerable<StreamingChatMessageContent>` → `IAsyncEnumerable<AgentRunResponseUpdate>`

## Configuration Mappings

| Semantic Kernel Pattern | Agent Framework Pattern |
|------------------------|------------------------|
| `AgentInvokeOptions` | `AgentRunOptions` or `ChatClientAgentRunOptions` |
| `KernelArguments` | Not supported; render prompt before calling agent |
| `[KernelFunction]` attribute | Remove; use `AIFunctionFactory.Create()` |
| `KernelPlugin` registration | Direct function list in agent creation |
| `InnerContent` property | `RawRepresentation` property |
| `content.Metadata` property | `AdditionalProperties` property |

## Namespace Updates

**Remove these Semantic Kernel namespaces:**
```csharp
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.Agents;
using Microsoft.SemanticKernel.Agents.OpenAI;
using Microsoft.SemanticKernel.Agents.AzureAI;
using Microsoft.SemanticKernel.Agents.A2A;
using Microsoft.SemanticKernel.Connectors.OpenAI;
```

**Add these Agent Framework namespaces:**
```csharp
using Microsoft.Extensions.AI;
using Microsoft.Agents.AI;
// Provider-specific (add only as needed):
using OpenAI;                        // OpenAI provider
using Azure.AI.OpenAI;               // Azure OpenAI provider
using Azure.AI.Agents.Persistent;    // Azure AI Foundry provider
using Azure.Identity;                // Azure authentication
```

## Chat Completion Abstractions

Agent Framework does not support `IChatCompletionService` directly. Convert via `AsChatClient()` or create `IChatClient` directly.

**Before:**
```csharp
IChatCompletionService completionService = kernel.GetService<IChatCompletionService>();
ChatCompletionAgent agent = new() { Instructions = "You are helpful", Kernel = kernel };
```

**After:**
```csharp
IChatClient chatClient = completionService.AsChatClient();
var agent = new ChatClientAgent(chatClient, instructions: "You are helpful");
```

## Agent Creation

**Before:**
```csharp
Kernel kernel = Kernel.CreateBuilder()
    .AddOpenAIChatCompletion(modelId, apiKey)
    .Build();
ChatCompletionAgent agent = new() { Instructions = "You are helpful", Kernel = kernel };
```

**After (direct constructor):**
```csharp
IChatClient chatClient = new OpenAIClient(apiKey).GetChatClient(modelId).AsIChatClient();
AIAgent agent = new ChatClientAgent(chatClient, instructions: "You are helpful");
```

**After (extension method — recommended):**
```csharp
AIAgent agent = new OpenAIClient(apiKey)
    .GetChatClient(modelId)
    .CreateAIAgent(instructions: "You are helpful");
```

Required changes:
1. Remove `Kernel.CreateBuilder()` and `.Build()` calls
2. Replace `ChatCompletionAgent` with `ChatClientAgent` or use extension methods
3. Remove `Kernel` property assignment
4. Pass `IChatClient` directly or use extension methods

## Thread Management

**Before:**
```csharp
AgentThread thread = new ChatHistoryAgentThread();
AgentThread thread = new OpenAIAssistantAgentThread(assistantClient);
AgentThread thread = new AzureAIAgentThread(azureClient);
```

**After (unified pattern for all agent types):**
```csharp
AgentThread thread = agent.GetNewThread();
```

## Tool Registration

**Before:**
```csharp
[KernelFunction]
[Description("Get the weather for a location")]
static string GetWeather(string location) => $"Weather in {location}";

KernelFunction function = KernelFunctionFactory.CreateFromMethod(GetWeather);
KernelPlugin plugin = KernelPluginFactory.CreateFromFunctions("WeatherPlugin", [function]);
kernel.Plugins.Add(plugin);
ChatCompletionAgent agent = new() { Kernel = kernel };
```

**After:**
```csharp
[Description("Get the weather for a location")]
static string GetWeather(string location) => $"Weather in {location}";

AIAgent agent = chatClient.CreateAIAgent(
    instructions: "You are a helpful assistant",
    tools: [AIFunctionFactory.Create(GetWeather)]);
```

Required changes:
1. Remove `[KernelFunction]` attributes (keep `[Description]`)
2. Remove `KernelFunctionFactory`, `KernelPluginFactory`, `kernel.Plugins.Add()` calls
3. Use `AIFunctionFactory.Create()` in the `tools` parameter

## Invocation Methods

**Non-streaming before:**
```csharp
await foreach (AgentResponseItem<ChatMessageContent> item in agent.InvokeAsync(userInput, thread, options))
{
    Console.WriteLine(item.Message);
}
```

**Non-streaming after:**
```csharp
AgentRunResponse result = await agent.RunAsync(userInput, thread, options);
Console.WriteLine(result);
```

**Streaming before:**
```csharp
await foreach (StreamingChatMessageContent update in agent.InvokeStreamingAsync(userInput, thread, options))
{
    Console.Write(update.Message);
}
```

**Streaming after:**
```csharp
await foreach (AgentRunResponseUpdate update in agent.RunStreamingAsync(userInput, thread, options))
{
    Console.Write(update);
}
```

Key changes:
1. `InvokeAsync` → `RunAsync`, `InvokeStreamingAsync` → `RunStreamingAsync`
2. Non-streaming: remove `await foreach`, use single `AgentRunResponse`
3. Streaming: change iteration type to `AgentRunResponseUpdate`

## Options and Configuration

**Before:**
```csharp
OpenAIPromptExecutionSettings settings = new() { MaxTokens = 1000 };
AgentInvokeOptions options = new() { KernelArguments = new(settings) };
```

**After:**
```csharp
ChatClientAgentRunOptions options = new(new ChatOptions { MaxOutputTokens = 1000 });
```

Note: `MaxTokens` → `MaxOutputTokens`.

## Dependency Injection

**Before:**
```csharp
services.AddKernel().AddOpenAIChatClient(modelId, apiKey);
services.AddTransient<ChatCompletionAgent>(sp => new()
{
    Kernel = sp.GetRequiredService<Kernel>(),
    Instructions = "You are helpful"
});
```

**After:**
```csharp
services.AddTransient<AIAgent>(sp =>
    new OpenAIClient(apiKey)
        .GetChatClient(modelId)
        .CreateAIAgent(instructions: "You are helpful"));
```

Remove `services.AddKernel()` and `sp.GetRequiredService<Kernel>()` calls.

## Thread Cleanup

**Before:**
```csharp
await thread.DeleteAsync();
```

**After (provider-specific):**
```csharp
// OpenAI Assistants:
var assistantClient = new OpenAIClient(apiKey).GetAssistantClient();
await assistantClient.DeleteThreadAsync(thread.ConversationId);

// Azure AI Foundry:
var persistentClient = new PersistentAgentsClient(endpoint, credential);
await persistentClient.Threads.DeleteThreadAsync(thread.ConversationId);

// No cleanup needed for: OpenAI/Azure OpenAI Chat Completion, OpenAI/Azure OpenAI Responses
```

Track all created threads for hosted providers for cleanup purposes.

## Usage Metadata

**Non-streaming before:**
```csharp
await foreach (var result in agent.InvokeAsync(input, thread, options))
{
    if (result.Message.Metadata?.TryGetValue("Usage", out object? usage) ?? false)
    {
        if (usage is ChatTokenUsage openAIUsage)
            Console.WriteLine($"Tokens: {openAIUsage.TotalTokenCount}");
    }
}
```

**Non-streaming after:**
```csharp
AgentRunResponse result = await agent.RunAsync(input, thread, options);
Console.WriteLine($"Tokens: {result.Usage.TotalTokenCount}");
```

**Streaming before:**
```csharp
await foreach (StreamingChatMessageContent response in agent.InvokeStreamingAsync(message, agentThread))
{
    if (response.Metadata?.TryGetValue("Usage", out object? usage) ?? false)
    {
        if (usage is ChatTokenUsage openAIUsage)
            Console.WriteLine($"Tokens: {openAIUsage.TotalTokenCount}");
    }
}
```

**Streaming after:**
```csharp
await foreach (AgentRunResponseUpdate update in agent.RunStreamingAsync(input, thread, options))
{
    if (update.Contents.OfType<UsageContent>().FirstOrDefault() is { } usageContent)
        Console.WriteLine($"Tokens: {usageContent.Details.TotalTokenCount}");
}
```

## Breaking Glass Pattern

**Before:**
```csharp
await foreach (var content in agent.InvokeAsync(userInput, thread))
{
    UnderlyingSdkType? obj = content.Message.InnerContent as UnderlyingSdkType;
}
```

**After (two-level breaking glass for ChatClient-based agents):**
```csharp
var response = await agent.RunAsync(userInput, thread);

// Level 1: Get MEAI ChatResponse
ChatResponse? chatResponse = response.RawRepresentation as ChatResponse;

// Level 2: Get underlying SDK type
UnderlyingSdkType? obj = chatResponse?.RawRepresentation as UnderlyingSdkType;
```

Replace `InnerContent` with `RawRepresentation`. For `ChatClient`-based agents, break glass twice to reach the underlying SDK type.

## CodeInterpreter Tool

**Before:**
```csharp
await foreach (var content in agent.InvokeAsync(userInput, thread))
{
    bool isCode = content.Message.Metadata?.ContainsKey(AzureAIAgent.CodeInterpreterMetadataKey) ?? false;
    Console.WriteLine($"# {content.Message.Role}{(isCode ? "\n# Generated Code:\n" : ":")}{content.Message.Content}");

    foreach (var item in content.Message.Items)
    {
        if (item is AnnotationContent annotation)
            Console.WriteLine($"[{item.GetType().Name}] {annotation.Label}: File #{annotation.ReferenceId}");
        else if (item is FileReferenceContent fileReference)
            Console.WriteLine($"[{item.GetType().Name}] File #{fileReference.FileId}");
    }
}
```

**After:**
```csharp
var result = await agent.RunAsync(userInput, thread);
Console.WriteLine(result);

// Level 1 breaking glass
var chatResponse = result.RawRepresentation as ChatResponse;

// Level 2 breaking glass for code interpreter output
var underlyingUpdates = chatResponse?.RawRepresentation as IEnumerable<object?> ?? [];

StringBuilder generatedCode = new();
foreach (object? update in underlyingUpdates)
{
    if (update is RunStepDetailsUpdate stepDetails && stepDetails.CodeInterpreterInput is not null)
        generatedCode.Append(stepDetails.CodeInterpreterInput);
}

if (!string.IsNullOrEmpty(generatedCode.ToString()))
    Console.WriteLine($"\n# Generated Code:\n{generatedCode}");
```

Code interpreter output is accessed via breaking glass, not metadata properties.

## Provider-Specific Options

For advanced settings not available in `ChatOptions`, use `RawRepresentationFactory`:

```csharp
var agentOptions = new ChatClientAgentRunOptions(new ChatOptions
{
    MaxOutputTokens = 8000,
    RawRepresentationFactory = (_) => new OpenAI.Responses.ResponseCreationOptions()
    {
        ReasoningOptions = new()
        {
            ReasoningEffortLevel = OpenAI.Responses.ResponseReasoningEffortLevel.High,
            ReasoningSummaryVerbosity = OpenAI.Responses.ResponseReasoningSummaryVerbosity.Detailed
        }
    }
});
```

Use when standard `ChatOptions` properties don't cover required model settings.

**Type-safe extension methods:**
```csharp
using OpenAI;
var chatCompletion = result.AsChatCompletion();
var openAIResponse = chatCompletion.GetRawResponse();
```

## Common Migration Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Missing using statements | Compilation errors for AF types | Add `using Microsoft.Agents.AI;`, remove SK agent usings |
| `[KernelFunction]` attributes | Compilation errors | Remove attribute, keep `[Description]` |
| Thread type mismatches | Provider-specific constructors not found | Replace all with `agent.GetNewThread()` |
| `AgentInvokeOptions` not found | Type not found error | Replace with `AgentRunOptions` or `ChatClientAgentRunOptions` |
| `Kernel` service missing | DI resolution failure | Remove `services.AddKernel()`, use direct client registration |
