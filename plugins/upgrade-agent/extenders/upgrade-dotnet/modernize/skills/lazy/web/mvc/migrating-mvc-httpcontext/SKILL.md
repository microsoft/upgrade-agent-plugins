---
name: migrating-mvc-httpcontext
description: >
  Migrates ASP.NET Framework HttpContext, Request, and Response usage to ASP.NET Core equivalents.
  Use when projects reference HttpContext.Current, HttpRequest.InputStream, HttpResponse.Write,
  HttpServerUtility, Request.ServerVariables, Request.Files, Response.End, Response.AddHeader,
  or ClaimsPrincipal.Current. Also triggers for "replace HttpContext.Current", "inject
  IHttpContextAccessor", "async response writing", "request body reading", or when assessment
  signals include UsesHttpContextCurrent, UsesHttpContext, UsesResponseWrite,
  UsesRequestInputStream, UsesCustomHeaders.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC HttpContext and Request/Response Migration

## Overview

Migrate `HttpContext.Current`, `HttpRequest`, `HttpResponse`, and `HttpServerUtility` usage from ASP.NET Framework to ASP.NET Core. The static `HttpContext.Current` accessor is removed in Core — all context access flows through dependency injection or controller base class properties. Response writing is async-only in Kestrel, and request reading APIs have changed types and behavior.

> **Adapter precedence**: If the `aspnet-system-web-adapters` skill is loaded, its guidance takes precedence over HttpContext.Current, Request Access, Response Access, and ClaimsPrincipal.Current sections during scaffold and migrate task phases.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Inventory HttpContext usage patterns
- [ ] Step 2: Eliminate HttpContext.Current
- [ ] Step 3: Migrate request access patterns
- [ ] Step 4: Migrate response access patterns
- [ ] Step 5: Replace HttpServerUtility calls
- [ ] Step 6: Migrate ClaimsPrincipal.Current
- [ ] Step 7: Remove legacy references
```

### Step 1: Inventory HttpContext Usage Patterns

Scan the project for all HttpContext-related usage:

- `HttpContext.Current` — static access in controllers, services, libraries, and helpers
- `HttpContext.Current.Request` / `.Response` — direct request/response property access
- `HttpContext.Current.Server` — `HttpServerUtility` calls (`MapPath`, `HtmlEncode`, `UrlEncode`)
- `HttpContext.Current.User` / `ClaimsPrincipal.Current` — identity access
- `HttpContext.Current.Items` — per-request storage
- `Request.InputStream`, `Request.Files`, `Request.ServerVariables` — changed APIs
- `Response.Write()`, `Response.End()`, `Response.AddHeader()` — removed or changed methods

Categorize each usage site by location: controller, service/library, middleware, or static helper. Location determines the migration strategy.

### Step 2: Eliminate HttpContext.Current

`HttpContext.Current` does not exist in ASP.NET Core. The replacement depends on where the access occurs.

**In controllers** — use the `HttpContext` property directly:

Before:
```csharp
public class ProductController : Controller
{
    public ActionResult Index()
    {
        var userId = HttpContext.Current.User.Identity.Name;
        HttpContext.Current.Items["LastAccess"] = DateTime.UtcNow;
        return View();
    }
}
```

After:
```csharp
public class ProductController : Controller
{
    public IActionResult Index()
    {
        var userId = HttpContext.User.Identity?.Name;
        HttpContext.Items["LastAccess"] = DateTime.UtcNow;
        return View();
    }
}
```

**In services and libraries** — inject `IHttpContextAccessor`:

Before:
```csharp
public class AuditService
{
    public string GetCurrentUser()
    {
        return HttpContext.Current.User.Identity.Name;
    }
}
```

After:
```csharp
public class AuditService
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public AuditService(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public string GetCurrentUser()
    {
        return _httpContextAccessor.HttpContext?.User.Identity?.Name ?? string.Empty;
    }
}
```

Register the accessor in `Program.cs`:
```csharp
builder.Services.AddHttpContextAccessor();
```

> **Threading concern**: `IHttpContextAccessor` uses `AsyncLocal<T>`. In singleton services, always access `.HttpContext` at call time — never cache the `HttpContext` reference in a field. A cached reference may belong to a completed request and produce null-reference or cross-request data leaks.

**In static helpers or libraries with no DI** — this requires an architectural change. Pass `HttpContext` (or the specific value needed) as a method parameter from the call site. Avoid wrapping `IHttpContextAccessor` in a static accessor because it reintroduces the same coupling.

### Step 3: Migrate Request Access Patterns

Request APIs changed types and behavior between Framework and Core:

**QueryString** — `NameValueCollection` → `IQueryCollection`:

Before:
```csharp
string page = Request.QueryString["page"];
```

After:
```csharp
string page = Request.Query["page"].ToString();
```

`IQueryCollection` indexer returns `StringValues`; call `.ToString()` or use `.FirstOrDefault()` for a single value.

**Form data** — async reading required:

Before:
```csharp
string name = Request.Form["name"];
```

After:
```csharp
var form = await Request.ReadFormAsync();
string name = form["name"].ToString();
```

In controller actions, prefer model binding (`[FromForm]` attribute) over manual form reading.

**Request body (InputStream)** — `Stream` → `HttpRequest.Body`:

Before:
```csharp
using (var reader = new StreamReader(Request.InputStream))
{
    string body = reader.ReadToEnd();
}
```

After:
```csharp
using var reader = new StreamReader(Request.Body);
string body = await reader.ReadToEndAsync();
```

Enable request buffering if the body must be read multiple times:
```csharp
Request.EnableBuffering();
```

**File uploads** — `HttpFileCollection` → `IFormFileCollection`:

Before:
```csharp
HttpPostedFileBase file = Request.Files["upload"];
file.SaveAs(Server.MapPath("~/uploads/" + file.FileName));
```

After:
```csharp
IFormFile file = Request.Form.Files["upload"];
using var stream = new FileStream(Path.Combine(uploadPath, file.FileName), FileMode.Create);
await file.CopyToAsync(stream);
```

**ServerVariables** — no direct equivalent. Map to specific properties:

| `Request.ServerVariables[key]` | ASP.NET Core Equivalent |
|---|---|
| `REMOTE_ADDR` | `HttpContext.Connection.RemoteIpAddress` |
| `SERVER_NAME` | `Request.Host.Host` |
| `SERVER_PORT` | `Request.Host.Port` |
| `HTTP_HOST` | `Request.Headers["Host"]` |
| `PATH_INFO` | `Request.Path` |
| `QUERY_STRING` | `Request.QueryString.Value` |
| `CONTENT_TYPE` | `Request.ContentType` |
| `CONTENT_LENGTH` | `Request.ContentLength` |

### Step 4: Migrate Response Access Patterns

**Response.Write()** — sync writing is not supported by Kestrel:

Before:
```csharp
Response.Write("<html><body>Hello</body></html>");
Response.Write(jsonString);
```

After:
```csharp
await Response.WriteAsync("<html><body>Hello</body></html>");
await Response.WriteAsync(jsonString);
```

In controller actions, prefer returning `IActionResult` (e.g., `Content()`, `Json()`, `View()`) instead of writing directly to the response stream.

**Response.End()** — removed, no direct equivalent:

Before:
```csharp
Response.Write(data);
Response.End();
```

After — in middleware, return without calling `next()`. In controllers, return an `IActionResult`:
```csharp
await Response.WriteAsync(data);
return; // In middleware — do not call next()
```

To forcefully abort a connection (rare), use `HttpContext.Abort()`.

**Response.AddHeader() / AppendHeader()** — use `Headers.Append()`:

Before:
```csharp
Response.AddHeader("X-Custom-Header", "value");
Response.AppendHeader("Cache-Control", "no-cache");
```

After:
```csharp
Response.Headers.Append("X-Custom-Header", "value");
Response.Headers.Append("Cache-Control", "no-cache");
```

Headers must be set before writing to the response body. In Framework this was loosely enforced; in Core, writing headers after the response has started throws an `InvalidOperationException`.

**Response.Redirect()** — compatible but behavior differs:

Before:
```csharp
Response.Redirect("~/home");       // Redirect + Response.End()
Response.Redirect("~/home", false); // Redirect without ending
```

After:
```csharp
Response.Redirect("/home");         // Sets 302, does NOT abort
return;                              // Must explicitly return
```

Core's `Redirect` does not end the response or call `Response.End()`. Always return from the action or middleware after calling `Redirect()` to prevent further processing.

**Response buffering** — Core does not buffer responses by default. For scenarios requiring buffering (e.g., setting headers after partial writes), use `Response.StartAsync()` awareness or enable response buffering middleware.

### Step 5: Replace HttpServerUtility Calls

`HttpContext.Current.Server` (`HttpServerUtility`) has no single replacement in Core. Replace method by method:

| `Server.` Method | ASP.NET Core Replacement |
|---|---|
| `Server.MapPath("~/path")` | `IWebHostEnvironment.ContentRootPath` or `.WebRootPath` + `Path.Combine()` |
| `Server.HtmlEncode(s)` | `System.Net.WebUtility.HtmlEncode(s)` or `HtmlEncoder.Default.Encode(s)` |
| `Server.HtmlDecode(s)` | `System.Net.WebUtility.HtmlDecode(s)` |
| `Server.UrlEncode(s)` | `System.Net.WebUtility.UrlEncode(s)` or `Uri.EscapeDataString(s)` |
| `Server.UrlDecode(s)` | `System.Net.WebUtility.UrlDecode(s)` or `Uri.UnescapeDataString(s)` |
| `Server.Transfer(url)` | No equivalent — rewrite as redirect or internal rewrite middleware |
| `Server.Execute(url)` | No equivalent — refactor to call the target logic directly |
| `Server.GetLastError()` | `IExceptionHandlerFeature` in exception handler middleware |
| `Server.ScriptTimeout` | `RequestTimeoutOptions` or `CancellationToken` with timeout |

For `MapPath`, inject `IWebHostEnvironment`:

Before:
```csharp
string path = HttpContext.Current.Server.MapPath("~/Content/data.json");
```

After:
```csharp
public class DataService
{
    private readonly IWebHostEnvironment _env;

    public DataService(IWebHostEnvironment env)
    {
        _env = env;
    }

    public string GetDataPath()
    {
        return Path.Combine(_env.WebRootPath, "Content", "data.json");
    }
}
```

### Step 6: Migrate ClaimsPrincipal.Current

`ClaimsPrincipal.Current` is a static thread-based accessor that does not work reliably in ASP.NET Core's async pipeline.

**In controllers** — use the `User` property:

Before:
```csharp
var claims = ClaimsPrincipal.Current.Claims;
```

After:
```csharp
var claims = User.Claims;
```

**In services** — inject `IHttpContextAccessor`:

Before:
```csharp
public class PermissionService
{
    public bool HasRole(string role)
    {
        return ClaimsPrincipal.Current.IsInRole(role);
    }
}
```

After:
```csharp
public class PermissionService
{
    private readonly IHttpContextAccessor _accessor;

    public PermissionService(IHttpContextAccessor accessor)
    {
        _accessor = accessor;
    }

    public bool HasRole(string role)
    {
        return _accessor.HttpContext?.User.IsInRole(role) ?? false;
    }
}
```

Custom `ClaimsPrincipal` factories that set `ClaimsPrincipal.Current` should be replaced with claims transformation. Register an `IClaimsTransformation` implementation:

```csharp
builder.Services.AddTransient<IClaimsTransformation, CustomClaimsTransformation>();
```

### Step 7: Remove Legacy References

Remove all legacy HttpContext artifacts:

- Remove `using System.Web` statements that are no longer needed
- Remove any custom `HttpContextBase` / `HttpContextWrapper` abstractions
- Remove `HttpContext.Current` shim or facade classes
- Search for remaining references to `HttpContext.Current`, `ClaimsPrincipal.Current`, `HttpServerUtility`, `Request.ServerVariables`, `Response.Write(` (sync overload), and `Response.End()`

## Success Criteria

- No references to `HttpContext.Current` remain in the project
- `IHttpContextAccessor` registered and injected where services need `HttpContext`
- No singleton services cache `HttpContext` references in fields
- All `Request.InputStream` reads converted to async `Request.Body` reads
- All `Response.Write()` calls converted to `await Response.WriteAsync()` or `IActionResult`
- `Response.End()` calls removed and replaced with return statements or `HttpContext.Abort()`
- `HttpServerUtility` calls replaced with Core equivalents
- `ClaimsPrincipal.Current` replaced with `User` property or `IHttpContextAccessor`
- No `Request.ServerVariables` access remains
- Headers set before writing to response body
- Project builds without errors
