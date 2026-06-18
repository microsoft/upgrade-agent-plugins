---
name: migrating-to-msmq-messaging
description: >
  Migrates .NET projects from System.Messaging to MSMQ.Messaging for .NET Core compatibility.
  Use when upgrading projects that reference System.Messaging, MessageQueue, XmlMessageFormatter,
  or when migrating MSMQ queue code from .NET Framework to .NET Core/.NET 5+. Also triggers for
  queue configuration migration from web.config/app.config to appsettings.json and replacing
  ConfigurationManager with dependency injection for queue settings.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# System.Messaging to MSMQ Migration

Migrate .NET projects from `System.Messaging` to `MSMQ.Messaging` for .NET Core compatibility. The APIs are nearly identical (same class names, different namespace), so migration focuses on reference updates, configuration changes, and dependency injection adoption.

## Workflow

First verify the project actually uses `System.Messaging`. If it does not, inform the user there is nothing to do.

```
Task Progress:
- [ ] Step 1: Remove System.Messaging references
- [ ] Step 2: Update using statements and code
- [ ] Step 3: Migrate queue configuration
- [ ] Step 4: Verify and clean up
```

### Step 1: Remove System.Messaging References

Remove `System.Messaging` assembly references from project files (.csproj/.vbproj). These are not needed because `MSMQ.Messaging` provides the replacement types.

### Step 2: Update Using Statements and Code

Find all usages of `System.Messaging` in the project and update them:

1. Replace `using System.Messaging` with `using MSMQ.Messaging` in all files
2. Update `MessageQueue`, `Message`, and `XmlMessageFormatter` usage to the MSMQ.Messaging equivalents (same class names, different namespace — see API Mapping below)
3. Update message sending/receiving code for any MSMQ API differences in method signatures or properties
4. If method signatures changed, update all callers across the solution

### Step 3: Migrate Queue Configuration

Move queue settings from `web.config`/`app.config` to `appsettings.json` because `ConfigurationManager` is not available in .NET Core — configuration must use the options pattern with dependency injection instead.

**appsettings.json:**
```json
{
  "MessageQueue": {
    "QueuePath": "./private$/myqueue"
  }
}
```

**Configuration model class:**
```csharp
public class MessageQueueOptions
{
    public string QueuePath { get; set; }
}
```

**Registration in Program.cs:**
```csharp
builder.Services.Configure<MessageQueueOptions>(
    builder.Configuration.GetSection("MessageQueue"));
```

Inject `IOptions<MessageQueueOptions>` into classes that need queue configuration, replacing any `ConfigurationManager` usage.

### Step 4: Verify and Clean Up

Build the project and search for any remaining `System.Messaging` references. Fix any remaining compilation errors.

## API Mapping

| System.Messaging | MSMQ.Messaging |
|------------------|----------------|
| `MessageQueue` | `MessageQueue` (same name, different namespace) |
| `Message` | `Message` (same name, different namespace) |
| `XmlMessageFormatter` | `XmlMessageFormatter` (same name, different namespace) |

## Success Criteria

- No remaining `System.Messaging` references
- All queue code uses `MSMQ.Messaging`
- Queue configuration in `appsettings.json` (not web.config/app.config)
- Configuration accessed via dependency injection (no `ConfigurationManager`)
- Project builds without errors
