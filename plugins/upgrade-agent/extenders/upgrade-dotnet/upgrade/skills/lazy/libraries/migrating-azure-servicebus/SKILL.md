---
name: migrating-azure-servicebus
description: >
  Migrates the deprecated WindowsAzure.ServiceBus to
  Azure.Messaging.ServiceBus for Azure Service Bus
  messaging. Use ONLY when WindowsAzure.ServiceBus has been
  flagged as obsolete or deprecated and must be replaced —
  not for version-bump scenarios where
  WindowsAzure.ServiceBus is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Azure Service Bus Migration

## Overview

Migrate from the legacy `WindowsAzure.ServiceBus` package to the modern `Azure.Messaging.ServiceBus` SDK. The new SDK uses a single `ServiceBusClient` as the entry point, with dedicated `ServiceBusSender`, `ServiceBusReceiver`, and `ServiceBusProcessor` types replacing the old per-entity clients. Message handling shifts from `OnMessage` callbacks to async event handlers on the processor. AMQP is the only transport protocol (NetMessaging is removed).

## Package Reference Changes

### Old Reference (Remove)

```xml
<PackageReference Include="WindowsAzure.ServiceBus" Version="{old-version}" />
```

### New Reference (Add)

```xml
<PackageReference Include="Azure.Messaging.ServiceBus" Version="{version}" />
```

Optionally add `Azure.Identity` for Azure AD–based authentication instead of connection string keys.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect legacy Service Bus usage
- [ ] Step 2: Update project file references
- [ ] Step 3: Replace client creation
- [ ] Step 4: Migrate message sending
- [ ] Step 5: Migrate message receiving
- [ ] Step 6: Build and verify
```

### Step 1: Detect Legacy Service Bus Usage

Scan the project for:
- `using Microsoft.ServiceBus;` and `using Microsoft.ServiceBus.Messaging;` statements
- Client types: `QueueClient`, `TopicClient`, `SubscriptionClient`, `MessagingFactory`
- `BrokeredMessage` usage
- `OnMessage` / `OnMessageAsync` callback registrations
- `NamespaceManager` for queue/topic administration

### Step 2: Update Project File References

Remove `WindowsAzure.ServiceBus` and add `Azure.Messaging.ServiceBus` (see "Package Reference Changes" above).

### Step 3: Replace Client Creation

The new SDK uses `ServiceBusClient` as the single entry point, then creates senders, receivers, or processors from it:

```csharp
// Old
var factory = MessagingFactory.CreateFromConnectionString(connectionString);
var queueClient = factory.CreateQueueClient("my-queue");

// New
await using var client = new ServiceBusClient(connectionString);
var sender = client.CreateSender("my-queue");
var receiver = client.CreateReceiver("my-queue");
```

`ServiceBusClient` and its child types are thread-safe and reusable — create one client per application and share it.

### Step 4: Migrate Message Sending

| WindowsAzure.ServiceBus (Old) | Azure.Messaging.ServiceBus (New) |
|-------------------------------|----------------------------------|
| `new BrokeredMessage(body)` | `new ServiceBusMessage(body)` |
| `message.MessageId` | `message.MessageId` (same) |
| `message.Properties["key"]` | `message.ApplicationProperties["key"]` |
| `message.ScheduledEnqueueTimeUtc` | `message.ScheduledEnqueueTime` (DateTimeOffset) |
| `queueClient.Send(message)` | `await sender.SendMessageAsync(message)` |
| `queueClient.SendBatch(messages)` | `await sender.SendMessagesAsync(messages)` |

All send operations are async-only in the new SDK.

### Step 5: Migrate Message Receiving

Replace `OnMessage` callbacks with `ServiceBusProcessor` event handlers:

```csharp
// Old
queueClient.OnMessage(message =>
{
    var body = message.GetBody<string>();
    message.Complete();
});

// New
var processor = client.CreateProcessor("my-queue");
processor.ProcessMessageAsync += async args =>
{
    string body = args.Message.Body.ToString();
    await args.CompleteMessageAsync(args.Message);
};
processor.ProcessErrorAsync += async args =>
{
    // Handle errors
};
await processor.StartProcessingAsync();
```

| Old Pattern | New Pattern |
|-------------|-------------|
| `message.Complete()` | `await args.CompleteMessageAsync(args.Message)` |
| `message.Abandon()` | `await args.AbandonMessageAsync(args.Message)` |
| `message.DeadLetter()` | `await args.DeadLetterMessageAsync(args.Message)` |
| `message.GetBody<T>()` | `args.Message.Body.ToObjectFromJson<T>()` |
| `OnMessage(handler)` | `processor.ProcessMessageAsync += handler` |
| `NamespaceManager` (admin) | `ServiceBusAdministrationClient` (separate package: `Azure.Messaging.ServiceBus.Administration`) |

### Step 6: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Test message send/receive against a Service Bus namespace (or use the local emulator)
3. Verify message completion, dead-lettering, and error handling work correctly
4. Confirm scheduled messages use `DateTimeOffset` instead of `DateTime`

## Troubleshooting

### Missing ProcessErrorAsync Handler

`ServiceBusProcessor` requires both `ProcessMessageAsync` and `ProcessErrorAsync` to be assigned before calling `StartProcessingAsync()`. The error handler is mandatory — omitting it throws an `InvalidOperationException`.

### Message Body Deserialization

`BrokeredMessage.GetBody<T>()` used `DataContractSerializer` by default. `ServiceBusReceivedMessage.Body` is a `BinaryData` instance — use `Body.ToObjectFromJson<T>()` for JSON or `Body.ToArray()` for raw bytes. If the old messages used `DataContractSerializer`, deserialize with `DataContractSerializer` manually from `Body.ToStream()`.

### Connection String Format

The connection string format is the same between both SDKs. However, if code used `MessagingFactory.Create(address, tokenProvider)` with separate endpoint and credentials, replace with `new ServiceBusClient(fullyQualifiedNamespace, new DefaultAzureCredential())` using `Azure.Identity`.
