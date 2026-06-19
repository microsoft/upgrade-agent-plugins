---
name: migrating-owin-to-aspnet-core
description: >
  Migrates OWIN/Katana middleware, authentication, pipeline components, and SignalR 2.x to native
  ASP.NET Core equivalents. Use when projects reference Microsoft.Owin, IAppBuilder, OwinMiddleware,
  Microsoft.Owin.Host.SystemWeb, OWIN-based OAuth/cookie/bearer authentication, OWIN startup
  classes, or SignalR 2.x hubs mapped via OWIN. Triggers for "migrate OWIN", "remove OWIN",
  "replace OWIN middleware", "convert OWIN pipeline", "migrate Katana", "convert OWIN auth",
  "upgrade SignalR", "replace OWIN startup", or when assessment signals include UsesOwin,
  UsesKatana, UsesOwinAuth, UsesOwinMiddleware, or UsesAppBuilder.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# OWIN / Katana → ASP.NET Core Middleware Migration

## Overview

Migrate ASP.NET MVC applications that rely on OWIN/Katana for middleware hosting, authentication, and SignalR from the Katana pipeline to native ASP.NET Core middleware. Katana (`Microsoft.Owin.Host.SystemWeb`) ran an OWIN pipeline inside IIS before the MVC pipeline — ASP.NET Core unifies both into a single middleware pipeline, making the OWIN layer unnecessary. Covers all OWIN middleware patterns: custom `OwinMiddleware` subclasses, `IAppBuilder` pipeline configuration, OWIN authentication schemes, and SignalR 2.x hub migration.

## Workflow

```
Migration Progress:
- [ ] Step 1: Audit OWIN/Katana usage
- [ ] Step 2: Migrate OWIN startup to Program.cs
- [ ] Step 3: Convert OWIN authentication to Core auth
- [ ] Step 4: Migrate SignalR 2.x to ASP.NET Core SignalR
- [ ] Step 5: Convert custom OWIN middleware
- [ ] Step 6: Remove Katana packages and clean up
```

### Step 1: Audit OWIN/Katana Usage

Search the project for Katana and OWIN dependencies. If none are found, inform the user and skip this skill.

Look for:
- `[assembly: OwinStartup(typeof(...))]` attribute in `Startup.cs` or `AssemblyInfo`
- `Startup.Configuration(IAppBuilder app)` or `Startup.ConfigureAuth(IAppBuilder app)` methods
- `Microsoft.Owin.Host.SystemWeb` package reference (Katana IIS host)
- `Microsoft.Owin.Security.*` packages (OWIN auth middleware)
- `Microsoft.AspNet.SignalR` and `Microsoft.AspNet.SignalR.Owin` packages
- `app.MapSignalR()` calls in OWIN startup
- `Startup.Auth.cs` partial class files

Categorize findings into three groups:
1. **Pipeline/hosting** — Katana startup, `IAppBuilder` configuration
2. **Authentication** — OAuth, cookie, bearer, external sign-in middleware
3. **SignalR** — Hub classes, hub configuration, client scripts

### Step 2: Migrate OWIN Startup to Program.cs

The Katana startup class splits across `Startup.cs` and often `Startup.Auth.cs`. ASP.NET Core consolidates this into `Program.cs`.

**Before** — Katana startup with `IAppBuilder`:
```csharp
[assembly: OwinStartup(typeof(MyApp.Startup))]
namespace MyApp
{
    public partial class Startup
    {
        public void Configuration(IAppBuilder app)
        {
            ConfigureAuth(app);
            app.MapSignalR();

            // Custom OWIN middleware
            app.Use<RequestLoggingMiddleware>();
        }
    }
}
```

**After** — ASP.NET Core `Program.cs`:
```csharp
var builder = WebApplication.CreateBuilder(args);

// Service registrations (auth, SignalR, etc.) go here
builder.Services.AddAuthentication(/* ... */);
builder.Services.AddSignalR();
builder.Services.AddControllersWithViews();

var app = builder.Build();

// Middleware pipeline
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<RequestLoggingMiddleware>();
app.MapHub<ChatHub>("/chatHub");
app.MapControllerRoute(name: "default", pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
```

Remove the `[assembly: OwinStartup]` attribute and the old `Startup` class once all configuration has moved to `Program.cs`.

### Step 3: Convert OWIN Authentication to Core Auth

OWIN authentication middleware registers inline on `IAppBuilder`. ASP.NET Core splits authentication into service registration (`builder.Services`) and middleware (`app.Use*`). Convert each OWIN auth scheme:

#### Cookie Authentication

**Before** — OWIN cookie auth:
```csharp
app.UseCookieAuthentication(new CookieAuthenticationOptions
{
    AuthenticationType = DefaultAuthenticationTypes.ApplicationCookie,
    LoginPath = new PathString("/Account/Login"),
    ExpireTimeSpan = TimeSpan.FromDays(14)
});
```

**After** — ASP.NET Core cookie auth:
```csharp
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.LoginPath = "/Account/Login";
        options.ExpireTimeSpan = TimeSpan.FromDays(14);
    });
```

#### OAuth Bearer / JWT

**Before** — OWIN bearer auth:
```csharp
app.UseOAuthBearerAuthentication(new OAuthBearerAuthenticationOptions
{
    AccessTokenFormat = new JwtFormat(tokenValidationParameters, issuer)
});
```

**After** — ASP.NET Core JWT bearer:
```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = "https://myissuer.example.com",
            ValidateAudience = true,
            ValidAudience = "my-api",
            ValidateLifetime = true,
            IssuerSigningKey = new SymmetricSecurityKey(keyBytes)
        };
    });
```

#### External Sign-In / OAuth Server

**Before** — OWIN external sign-in:
```csharp
app.UseExternalSignInCookie(DefaultAuthenticationTypes.ExternalCookie);
app.UseGoogleAuthentication(clientId: "...", clientSecret: "...");
```

**After** — ASP.NET Core external auth:
```csharp
builder.Services.AddAuthentication()
    .AddCookie()
    .AddGoogle(options =>
    {
        options.ClientId = builder.Configuration["Auth:Google:ClientId"];
        options.ClientSecret = builder.Configuration["Auth:Google:ClientSecret"];
    });
```

#### OWIN OAuth Authorization Server

If the project hosts its own OAuth token endpoint via `app.UseOAuthAuthorizationServer()`, this has no built-in ASP.NET Core equivalent. Replace with a dedicated identity server library (OpenIddict or Duende IdentityServer). This is a significant architectural change — flag it to the user and provide guidance:

1. Add the chosen library's NuGet packages
2. Configure token endpoints, scopes, and client registrations
3. Migrate token validation parameters from the old `OAuthAuthorizationServerOptions`
4. Update client applications to use the new token endpoint URLs

### Step 4: Migrate SignalR 2.x to ASP.NET Core SignalR

SignalR 2.x (OWIN-hosted) and ASP.NET Core SignalR share concepts but differ in API surface, client library, and connection lifecycle.

#### Hub Class Changes

**Before** — SignalR 2.x hub:
```csharp
using Microsoft.AspNet.SignalR;

public class ChatHub : Hub
{
    public void Send(string name, string message)
    {
        Clients.All.broadcastMessage(name, message);
    }

    public override Task OnConnected()
    {
        Groups.Add(Context.ConnectionId, "general");
        return base.OnConnected();
    }
}
```

**After** — ASP.NET Core SignalR hub:
```csharp
using Microsoft.AspNetCore.SignalR;

public class ChatHub : Hub
{
    public async Task Send(string name, string message)
    {
        await Clients.All.SendAsync("BroadcastMessage", name, message);
    }

    public override async Task OnConnectedAsync()
    {
        await Groups.AddToGroupAsync(Context.ConnectionId, "general");
        await base.OnConnectedAsync();
    }
}
```

Key API differences:
- `Clients.All.broadcastMessage(...)` → `Clients.All.SendAsync("BroadcastMessage", ...)`
- Dynamic proxy calls become string-based `SendAsync` invocations
- `OnConnected` → `OnConnectedAsync`, `OnDisconnected(bool)` → `OnDisconnectedAsync(Exception)`
- `Groups.Add()` → `Groups.AddToGroupAsync()`

#### Hub Registration

**Before** — OWIN startup:
```csharp
app.MapSignalR();
// or with custom path:
app.MapSignalR("/messaging", new HubConfiguration());
```

**After** — `Program.cs`:
```csharp
builder.Services.AddSignalR();
// ...
app.MapHub<ChatHub>("/chatHub");
```

Each hub is mapped individually in ASP.NET Core instead of a single `MapSignalR()` call. Map each hub class to its own route path.

#### IHubContext Injection

**Before** — SignalR 2.x static resolver:
```csharp
var context = GlobalHost.ConnectionManager.GetHubContext<ChatHub>();
context.Clients.All.broadcastMessage("system", "Hello");
```

**After** — ASP.NET Core dependency injection:
```csharp
public class NotificationService
{
    private readonly IHubContext<ChatHub> _hubContext;

    public NotificationService(IHubContext<ChatHub> hubContext)
    {
        _hubContext = hubContext;
    }

    public async Task NotifyAll(string message)
    {
        await _hubContext.Clients.All.SendAsync("BroadcastMessage", "system", message);
    }
}
```

#### Client Library

Replace the old jQuery-based SignalR client with the `@microsoft/signalr` npm package:

**Before** — SignalR 2.x client:
```html
<script src="~/Scripts/jquery.signalR-2.4.3.min.js"></script>
<script src="~/signalr/hubs"></script>
<script>
    var hub = $.connection.chatHub;
    hub.client.broadcastMessage = function (name, message) { /* ... */ };
    $.connection.hub.start();
</script>
```

**After** — ASP.NET Core SignalR client:
```html
<script src="~/lib/microsoft/signalr/dist/browser/signalr.min.js"></script>
<script>
    const connection = new signalR.HubConnectionBuilder()
        .withUrl("/chatHub")
        .build();
    connection.on("BroadcastMessage", (name, message) => { /* ... */ });
    connection.start();
</script>
```

The auto-generated `/signalr/hubs` proxy no longer exists. Client method names are registered explicitly with `connection.on()`.

### Step 5: Convert Custom OWIN Middleware

For each custom `OwinMiddleware` subclass, convert to ASP.NET Core middleware. The core pattern change is constructor injection of `RequestDelegate` replacing the `OwinMiddleware` base class:

**Before** — OWIN middleware:
```csharp
public class RequestTimingMiddleware : OwinMiddleware
{
    public RequestTimingMiddleware(OwinMiddleware next) : base(next) { }

    public override async Task Invoke(IOwinContext context)
    {
        var sw = Stopwatch.StartNew();
        await Next.Invoke(context);
        sw.Stop();
        context.Response.Headers.Add("X-Timing", new[] { sw.ElapsedMilliseconds.ToString() });
    }
}
```

**After** — ASP.NET Core middleware:
```csharp
public class RequestTimingMiddleware
{
    private readonly RequestDelegate _next;

    public RequestTimingMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var sw = Stopwatch.StartNew();
        await _next(context);
        sw.Stop();
        context.Response.Headers["X-Timing"] = sw.ElapsedMilliseconds.ToString();
    }
}
```

Register in `Program.cs` with `app.UseMiddleware<RequestTimingMiddleware>();`.

### Step 6: Remove Katana Packages and Clean Up

1. Remove all Katana and OWIN NuGet packages from project files:
   - `Microsoft.Owin`
   - `Microsoft.Owin.Host.SystemWeb`
   - `Microsoft.Owin.Security`
   - `Microsoft.Owin.Security.Cookies`
   - `Microsoft.Owin.Security.OAuth`
   - `Microsoft.Owin.Security.Google` (and other provider-specific packages)
   - `Microsoft.AspNet.SignalR`
   - `Microsoft.AspNet.SignalR.Owin`
   - `Owin`
2. Delete `Startup.cs` and `Startup.Auth.cs` if all logic has moved to `Program.cs`
3. Remove the `[assembly: OwinStartup(...)]` attribute from `AssemblyInfo` or `Startup.cs`
4. Delete old SignalR client scripts (`jquery.signalR-*.js`) from `Scripts/` or `wwwroot/`
5. Search for remaining `using Microsoft.Owin` and `using Microsoft.AspNet.SignalR` directives and remove them

## OWIN → ASP.NET Core API Reference

| OWIN / Katana | ASP.NET Core |
|---------------|--------------|
| `IAppBuilder` | `IApplicationBuilder` (via `WebApplication`) |
| `app.Use()` (OWIN delegate) | `app.Use()` (Core delegate) or `app.UseMiddleware<T>()` |
| `OwinMiddleware` | Middleware class with `RequestDelegate` |
| `IOwinContext` | `HttpContext` |
| `Startup.Configuration(IAppBuilder)` | `Program.cs` pipeline |
| `[assembly: OwinStartup]` | Not needed — `Program.cs` is the entry point |
| `app.UseCookieAuthentication()` | `AddAuthentication().AddCookie()` |
| `app.UseOAuthBearerAuthentication()` | `AddAuthentication().AddJwtBearer()` |
| `app.UseExternalSignInCookie()` | `AddAuthentication().AddCookie()` + `.AddGoogle()` / etc. |
| `app.UseOAuthAuthorizationServer()` | OpenIddict or Duende IdentityServer |
| `app.MapSignalR()` | `app.MapHub<T>("/path")` |
| `GlobalHost.ConnectionManager` | `IHubContext<T>` via DI |
| `Hub.Clients.All.method()` | `Hub.Clients.All.SendAsync("Method", ...)` |
| `Groups.Add()` | `Groups.AddToGroupAsync()` |

## Success Criteria

- No `Microsoft.Owin.*`, `Owin`, or `Microsoft.AspNet.SignalR` package references remain
- No `IAppBuilder`, `IOwinContext`, `OwinMiddleware`, or `OwinStartup` references in code
- Authentication uses ASP.NET Core `AddAuthentication()` service pattern
- SignalR hubs use `Microsoft.AspNetCore.SignalR` with `SendAsync` pattern
- SignalR client uses `@microsoft/signalr` instead of `jquery.signalR`
- Custom middleware uses `RequestDelegate` and `InvokeAsync(HttpContext)` pattern
- All middleware is registered in `Program.cs`
- Project builds without errors
