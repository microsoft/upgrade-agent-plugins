---
name: migrating-mvc-session-state
description: >
  Migrates ASP.NET Framework session state, TempData, and application state to ASP.NET Core
  equivalents. Converts HttpSessionState to ISession with distributed cache backend, migrates
  TempData from session-based to cookie-based provider, and replaces HttpContext.Application and
  HttpRuntime.Cache with DI-based IMemoryCache or IDistributedCache. Use when upgrading MVC or
  WebAPI apps that use Session[], TempData[], HttpContext.Application[], HttpRuntime.Cache,
  or static state patterns. Also triggers for assessment signals UsesSession, UsesTempData,
  UsesApplicationState, UsesStaticState, and UsesInProcSession.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Session and State Migration

## Overview

Migrate session state, TempData, and application-level state from ASP.NET Framework to ASP.NET Core. ASP.NET Core has no in-process session by default — session requires explicit opt-in via `AddSession()` plus a distributed cache provider. Getting this wrong causes silent data loss at scale or on app restart.

> **Adapter overlay:** If the `aspnet-system-web-adapters` skill is loaded, its guidance takes precedence for `HttpSessionState` replacement during scaffold and migrate phases — the adapter provides a session shim that defers full migration. TempData and Application State are **not** covered by adapters; migrate them directly using this skill.

> **Related skill:** `migrating-global-asax` covers `Session_Start`/`Session_End` event migration to session middleware registration.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Audit state usage across project
- [ ] Step 2: Register session services and middleware
- [ ] Step 3: Migrate HttpSessionState to ISession
- [ ] Step 4: Migrate TempData provider
- [ ] Step 5: Replace Application state and HttpRuntime.Cache
- [ ] Step 6: Replace static state with DI singletons
- [ ] Step 7: Verify serialization and data round-trips
```

### Step 1: Audit State Usage

Search the codebase for all state-related patterns. Identify which migration paths apply:

| Pattern to find | Migration path |
|---|---|
| `Session[` , `HttpContext.Session` | Session State (Step 3) |
| `TempData[` , `ITempDataProvider` | TempData (Step 4) |
| `HttpContext.Application[` , `HttpApplicationState` | Application State (Step 5) |
| `HttpRuntime.Cache` , `HttpContext.Cache` | Application State (Step 5) |
| `static` fields holding request/user state | Static State (Step 6) |

Skip steps that have no matching patterns. If the adapter overlay applies, defer Step 3 and proceed with Steps 4–6.

### Step 2: Register Session Services and Middleware

Skip this step if no `Session[` usage was found in Step 1 or if the adapter overlay handles session.

Add session services and a distributed cache in `Program.cs`:

**Before (Framework — implicit, no registration needed):**
```xml
<!-- web.config — session was on by default -->
<sessionState mode="InProc" timeout="20" />
```

**After (Core — explicit opt-in required):**
```csharp
// Program.cs — service registration
builder.Services.AddDistributedMemoryCache(); // Dev only — replace for production
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(20);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});

// Middleware pipeline — order matters: after routing, before endpoints
app.UseSession();
```

⚠️ **Data loss risk:** `AddDistributedMemoryCache()` stores data in-process and loses everything on restart. For production, replace with Redis or SQL Server:

```csharp
// Redis (recommended for multi-instance deployments)
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis");
});

// SQL Server (when Redis is unavailable)
builder.Services.AddDistributedSqlServerCache(options =>
{
    options.ConnectionString = builder.Configuration.GetConnectionString("SessionDb");
    options.SchemaName = "dbo";
    options.TableName = "Sessions";
});
```

### Step 3: Migrate HttpSessionState to ISession

ASP.NET Core `ISession` has a fundamentally different API. Session values are byte arrays — there is no automatic object serialization.

**Before (Framework):**
```csharp
// Reading — returns object, cast required
var cart = (ShoppingCart)Session["Cart"];
var name = Session["UserName"] as string;

// Writing — any serializable object
Session["Cart"] = cart;
Session["UserName"] = "Alice";

// Removing
Session.Remove("Cart");
Session.Abandon();
```

**After (Core):**
```csharp
// Reading — use typed extension methods
var cart = HttpContext.Session.Get<ShoppingCart>("Cart");
var name = HttpContext.Session.GetString("UserName");

// Writing — must serialize explicitly
HttpContext.Session.Set("Cart", cart);
HttpContext.Session.SetString("UserName", "Alice");

// Removing
HttpContext.Session.Remove("Cart");
HttpContext.Session.Clear();
```

The built-in `ISession` only provides `GetString`/`SetString` and `GetInt32`/`SetInt32`. For complex objects, add a JSON extension helper:

```csharp
public static class SessionExtensions
{
    public static void Set<T>(this ISession session, string key, T value)
    {
        session.SetString(key, JsonSerializer.Serialize(value));
    }

    public static T? Get<T>(this ISession session, string key)
    {
        var value = session.GetString(key);
        return value is null ? default : JsonSerializer.Deserialize<T>(value);
    }
}
```

Place this in a shared location (e.g., `Extensions/SessionExtensions.cs`). All session reads and writes for complex types must use these helpers — without them, `Get`/`Set` of objects silently fails.

**Key API differences:**

| Framework | Core | Notes |
|---|---|---|
| `Session["key"]` | `HttpContext.Session.GetString("key")` | No indexer in Core |
| `Session["key"] = obj` | `HttpContext.Session.Set("key", obj)` | Requires JSON helper |
| `Session.Abandon()` | `HttpContext.Session.Clear()` | `Clear` removes data but keeps session ID |
| `Session.SessionID` | `HttpContext.Session.Id` | Property name change |
| `Session.Count` | `HttpContext.Session.Keys.Count()` | Must enumerate keys |

### Step 4: Migrate TempData Provider

TempData API surface is compatible between Framework and Core, but the backing store changed. Framework uses session-based TempData by default; Core uses cookie-based TempData.

**Cookie TempData (Core default) — no code changes needed if data is small:**
```csharp
// TempData usage stays the same
TempData["Message"] = "Item saved successfully";
var msg = TempData["Message"] as string;
```

⚠️ **Silent truncation risk:** Cookie-based TempData is limited to ~4096 bytes total. Large objects stored in TempData will be silently truncated or fail. If TempData stored complex objects in Framework, switch to session-based TempData provider:

```csharp
// Program.cs — switch to session-based TempData (requires AddSession)
builder.Services.AddControllersWithViews()
    .AddSessionStateTempDataProvider();
```

**TempData in WebAPI controllers:** TempData never existed in WebAPI. If Framework code used workarounds (e.g., storing values between redirects in a Web API context), replace with query string parameters, response headers, or a distributed cache lookup.

### Step 5: Replace Application State and HttpRuntime.Cache

ASP.NET Core has no `HttpApplicationState` or `HttpRuntime.Cache`. Replace with dependency-injected services.

#### Application State → DI Singleton

**Before (Framework):**
```csharp
// Writing — typically in Global.asax Application_Start
HttpContext.Application["SiteSettings"] = LoadSettings();
HttpContext.Application.Lock();
HttpContext.Application["VisitorCount"] = (int)HttpContext.Application["VisitorCount"] + 1;
HttpContext.Application.UnLock();

// Reading — anywhere
var settings = HttpContext.Application["SiteSettings"] as SiteSettings;
```

**After (Core):**
```csharp
// Define a service to hold shared state
public class AppStateService
{
    private int _visitorCount;
    public SiteSettings SiteSettings { get; set; } = new();
    public int IncrementVisitors() => Interlocked.Increment(ref _visitorCount);
}

// Register as singleton in Program.cs
builder.Services.AddSingleton<AppStateService>();

// Inject where needed
public class HomeController : Controller
{
    private readonly AppStateService _appState;
    public HomeController(AppStateService appState) => _appState = appState;
}
```

Application state with `Lock()`/`UnLock()` patterns needs thread-safe replacements — use `Interlocked`, `ConcurrentDictionary`, or `lock` in the singleton service. The `Lock()`/`UnLock()` API does not exist in Core.

#### HttpRuntime.Cache → IMemoryCache

**Before (Framework):**
```csharp
HttpRuntime.Cache.Insert("Products", products, null,
    DateTime.Now.AddMinutes(30), Cache.NoSlidingExpiration);
var cached = HttpRuntime.Cache["Products"] as List<Product>;
```

**After (Core):**
```csharp
// Program.cs
builder.Services.AddMemoryCache();

// In controller or service — inject IMemoryCache
public class ProductService
{
    private readonly IMemoryCache _cache;
    public ProductService(IMemoryCache cache) => _cache = cache;

    public List<Product> GetProducts()
    {
        return _cache.GetOrCreate("Products", entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30);
            return LoadProductsFromDb();
        })!;
    }
}
```

For multi-instance deployments, use `IDistributedCache` instead of `IMemoryCache` to avoid cache inconsistencies across instances.

### Step 6: Replace Static State with DI Singletons

Static fields holding per-application state are a common pattern in Framework apps. These work in single-instance deployments but break in multi-instance or container environments.

**Before (Framework):**
```csharp
public static class AppConfig
{
    public static string ConnectionString { get; set; }
    public static Dictionary<string, object> Settings = new();
}
```

**After (Core):**
```csharp
public class AppConfig
{
    public string ConnectionString { get; set; } = string.Empty;
    public Dictionary<string, object> Settings { get; } = new();
}

// Program.cs
builder.Services.AddSingleton<AppConfig>();
```

Convert all static field access to constructor injection. If static access is needed in non-DI contexts (e.g., extension methods), expose the service through `IServiceProvider` at the call site rather than reverting to static state.

### Step 7: Verify Serialization and Data Round-Trips

After migrating, verify that data survives a full write-read cycle:

1. **Session data** — Write a complex object to session, read it back, and confirm all properties match. Test after app restart to confirm the distributed cache retains data (in-memory cache will not).
2. **TempData** — Store a value, perform a redirect, and verify the value is available on the destination page. Test with objects that approach the 4096-byte cookie limit if using cookie-based TempData.
3. **Cache entries** — Verify expiration behavior matches the original `web.config` settings.

Build the project and run existing tests to confirm no regressions.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Session` is always null | Missing `app.UseSession()` or `AddSession()` | Add both to `Program.cs` |
| Session data lost on restart | Using `AddDistributedMemoryCache()` in production | Switch to Redis or SQL Server cache |
| TempData silently empty after redirect | Cookie exceeds 4096 bytes | Switch to `AddSessionStateTempDataProvider()` |
| `HttpContext.Application` compile error | No equivalent in Core | Replace with DI singleton (Step 5) |
| `HttpRuntime.Cache` compile error | No equivalent in Core | Replace with `IMemoryCache` (Step 5) |
| Thread-safety issues with singleton state | Missing synchronization | Use `ConcurrentDictionary` or `Interlocked` |

## Success Criteria

- Session services registered with `AddSession()` and `UseSession()` in `Program.cs`
- Distributed cache provider configured (not in-memory for production)
- All `Session["key"]` indexer access replaced with `ISession` extension methods
- JSON serialization helper created for complex session objects
- TempData provider chosen and configured based on data size requirements
- `HttpContext.Application` replaced with DI singleton services
- `HttpRuntime.Cache` replaced with `IMemoryCache` or `IDistributedCache`
- Static state fields converted to singleton services with DI
- No `System.Web` session or cache references remain
- Project builds without errors
