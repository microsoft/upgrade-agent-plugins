---
name: migrating-aspnet-signalr
description: >
  Migrates the obsolete ASP.NET SignalR
  (Microsoft.AspNet.SignalR) to ASP.NET Core SignalR
  (Microsoft.AspNetCore.SignalR) for real-time
  communication. Use ONLY when Microsoft.AspNet.SignalR has
  been flagged as obsolete or deprecated and must be
  replaced — not for version-bump scenarios where
  Microsoft.AspNet.SignalR is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# ASP.NET SignalR to ASP.NET Core SignalR Migration

## Overview

Migrate real-time communication code from ASP.NET SignalR (`Microsoft.AspNet.SignalR`) to ASP.NET Core SignalR (`Microsoft.AspNetCore.SignalR`). The core changes are a new hub base class, endpoint routing instead of `MapSignalR`, removal of `HubPipeline`, and an updated client connection API. Most hub method signatures remain the same, but the server and client wiring changes significantly.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.AspNet.SignalR" Version="2.*" />
<PackageReference Include="Microsoft.AspNet.SignalR.Core" Version="2.*" />
<PackageReference Include="Microsoft.AspNet.SignalR.JS" Version="2.*" />
<PackageReference Include="Microsoft.AspNet.SignalR.SystemWeb" Version="2.*" />
```

### New References (Add)

```xml
<PackageReference Include="Microsoft.AspNetCore.SignalR" Version="{version-for-target-framework}" />

<!-- Optional: for MessagePack binary protocol support -->
<PackageReference Include="Microsoft.AspNetCore.SignalR.Protocols.MessagePack" Version="{version}" />
```

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect SignalR usage
- [ ] Step 2: Update project file references
- [ ] Step 3: Migrate hub classes
- [ ] Step 4: Update route configuration
- [ ] Step 5: Migrate client code
- [ ] Step 6: Handle removed features
- [ ] Step 7: Build and verify
```

### Step 1: Detect SignalR Usage

Scan the project for:
- `using Microsoft.AspNet.SignalR;` statements
- Types inheriting from `Hub` or `Hub<T>`
- `PersistentConnection` subclasses
- `HubPipelineModule` implementations
- `MapSignalR()` or `MapHubs()` calls in OWIN startup
- jQuery SignalR client references (`$.connection`, `$.hubConnection`)

### Step 2: Update Project File References

Remove old packages and add the new package reference (see "Package Reference Changes" above). Remove jQuery SignalR scripts from wwwroot or bundleconfig if present.

### Step 3: Migrate Hub Classes

1. Change the `using` directive from `Microsoft.AspNet.SignalR` to `Microsoft.AspNetCore.SignalR`
2. Hub base class remains `Hub` or `Hub<T>` — no rename needed
3. Replace `Clients.All.methodName(args)` (dynamic) with `Clients.All.SendAsync("methodName", args)` or use a strongly typed hub interface
4. Remove any `HubPipelineModule` implementations — use middleware or hub filters instead

### Step 4: Update Route Configuration

Replace OWIN-based SignalR routing with ASP.NET Core endpoint routing:

```csharp
// Old: in Startup.cs OwinStartup
app.MapSignalR();

// New: in Program.cs or Startup.cs
builder.Services.AddSignalR();

app.MapHub<ChatHub>("/chatHub");
```

Register each hub explicitly with `MapHub<T>` — there is no auto-discovery equivalent to `MapSignalR()`.

### Step 5: Migrate Client Code

**JavaScript/TypeScript client** — replace the jQuery SignalR client with `@microsoft/signalr`:

```javascript
// Old
var connection = $.hubConnection();
var proxy = connection.createHubProxy('chatHub');

// New
const connection = new signalR.HubConnectionBuilder()
    .withUrl("/chatHub")
    .build();
```

**.NET client** — update the `HubConnection` builder:

```csharp
// Old
var connection = new HubConnection("https://example.com/signalr");
var proxy = connection.CreateHubProxy("chatHub");

// New
var connection = new HubConnectionBuilder()
    .WithUrl("https://example.com/chatHub")
    .Build();
```

### Step 6: Handle Removed Features

| ASP.NET SignalR | ASP.NET Core SignalR | Action |
|----------------|---------------------|--------|
| `HubPipeline` / `HubPipelineModule` | Not supported | Use hub filters (`IHubFilter`) or middleware instead |
| `PersistentConnection` | Not supported | Rewrite as a hub or use raw WebSockets |
| Automatic reconnection | Not built-in | Call `.withAutomaticReconnect()` on `HubConnectionBuilder` (JS) or implement retry logic (.NET client) |
| jQuery dependency | Removed | Use `@microsoft/signalr` npm package |
| `GlobalHost.ConnectionManager` | Not supported | Inject `IHubContext<T>` via DI to send messages from outside a hub |
| Dynamic client proxy | Removed | Use strongly typed hub interfaces or `SendAsync` |

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Verify hub endpoints respond by navigating to the hub URL with `/negotiate`
3. Test client connectivity and message round-trips

## Troubleshooting

### Hub Methods Not Invoked

Ensure client calls use the exact method name string. ASP.NET Core SignalR is case-sensitive for method names by default.

### Connection Drops Without Reconnect

ASP.NET Core SignalR does not automatically reconnect. Add `.withAutomaticReconnect()` on the JavaScript client or implement retry logic in the .NET client.

### Missing GlobalHost

Replace `GlobalHost.ConnectionManager.GetHubContext<T>()` with constructor-injected `IHubContext<T>`. The global static resolver is not available in ASP.NET Core.

### MessagePack Serialization Errors

If using the MessagePack protocol, ensure all hub method parameter and return types are MessagePack-serializable. Add `[Key]` attributes or use contractless resolution.
