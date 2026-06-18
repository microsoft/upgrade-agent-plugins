---
name: migrating-webapi-cors
description: >
  Migrates legacy ASP.NET Web API CORS
  (Microsoft.AspNet.WebApi.Cors) to ASP.NET Core CORS
  (Microsoft.AspNetCore.Cors). Use ONLY when
  Microsoft.AspNet.WebApi.Cors has been flagged as obsolete
  or deprecated and must be replaced — not for version-bump
  scenarios where Microsoft.AspNet.WebApi.Cors is still
  supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# ASP.NET Web API CORS to ASP.NET Core CORS Migration

## Overview

Migrate CORS configuration from ASP.NET Web API (`Microsoft.AspNet.WebApi.Cors`) to ASP.NET Core (`Microsoft.AspNetCore.Cors`). The core change is moving from attribute-driven CORS registered via `EnableCorsAttribute` on `HttpConfiguration` to a middleware-based approach using `services.AddCors()` and `app.UseCors()`. Named policies replace the per-attribute origin/header/method strings.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.AspNet.WebApi.Cors" Version="5.*" />
<PackageReference Include="Microsoft.AspNet.Cors" Version="5.*" />
```

### New Reference (Add)

```xml
<!-- Included in the ASP.NET Core shared framework; explicit reference only needed for class libraries -->
<PackageReference Include="Microsoft.AspNetCore.Cors" Version="{version-for-target-framework}" />
```

In ASP.NET Core web applications targeting `net6.0` or later, `Microsoft.AspNetCore.Cors` is part of the shared framework and does not need an explicit package reference. Add one only for class library projects.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect CORS usage
- [ ] Step 2: Update project file references
- [ ] Step 3: Register CORS policies in DI
- [ ] Step 4: Apply CORS middleware or attributes
- [ ] Step 5: Migrate per-controller/action attributes
- [ ] Step 6: Build and verify
```

### Step 1: Detect CORS Usage

Scan the project for:
- `using System.Web.Http.Cors;` statements
- `[EnableCors(...)]` attributes on controllers or actions
- `[DisableCors]` attributes
- `config.EnableCors()` calls in `WebApiConfig.Register`
- Custom `ICorsPolicyProvider` implementations

### Step 2: Update Project File References

Remove old packages (see "Package Reference Changes" above). For ASP.NET Core web projects, the CORS APIs are available without an explicit package reference.

### Step 3: Register CORS Policies in DI

Replace the global `config.EnableCors()` call with policy registration in `Program.cs` or `Startup.ConfigureServices`:

```csharp
// Old: in WebApiConfig.cs
var cors = new EnableCorsAttribute("https://example.com", "*", "GET,POST");
config.EnableCors(cors);

// New: in Program.cs
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowExample", policy =>
    {
        policy.WithOrigins("https://example.com")
              .AllowAnyHeader()
              .WithMethods("GET", "POST");
    });
});
```

### Step 4: Apply CORS Middleware or Attributes

Add the CORS middleware to the pipeline. Placement matters — `UseCors` must appear after `UseRouting` and before `UseAuthorization`:

```csharp
app.UseRouting();
app.UseCors("AllowExample");
app.UseAuthorization();
```

Alternatively, apply per-endpoint using `RequireCors`:

```csharp
app.MapControllers().RequireCors("AllowExample");
```

### Step 5: Migrate Per-Controller/Action Attributes

Replace the old `[EnableCors]` attribute with the ASP.NET Core version referencing a named policy:

```csharp
// Old
[EnableCors(origins: "https://example.com", headers: "*", methods: "GET")]
public class ValuesController : ApiController { }

// New
[EnableCors("AllowExample")]
public class ValuesController : ControllerBase { }
```

| Old Pattern | New Pattern | Notes |
|------------|------------|-------|
| `[EnableCors(origins, headers, methods)]` | `[EnableCors("PolicyName")]` | Define the policy in `AddCors`; reference by name |
| `[DisableCors]` | `[DisableCors]` | Same attribute name, different namespace |
| `ICorsPolicyProvider` | `ICorsPolicyProvider` | Implement the ASP.NET Core interface; register in DI |
| Global `config.EnableCors(attr)` | `app.UseCors("PolicyName")` | Middleware replaces global config |
| Wildcard origin `"*"` | `policy.AllowAnyOrigin()` | Cannot combine with `AllowCredentials` in ASP.NET Core |

### Step 6: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Send a preflight `OPTIONS` request to verify CORS headers:
   ```
   curl -X OPTIONS -H "Origin: https://example.com" -H "Access-Control-Request-Method: GET" https://localhost:5001/api/values -v
   ```
3. Confirm `Access-Control-Allow-Origin` header is present in the response

## Troubleshooting

### CORS Headers Missing

Ensure `app.UseCors()` is placed after `UseRouting()` and before `UseAuthorization()`. Middleware order matters in ASP.NET Core.

### Credentials with Wildcard Origin

ASP.NET Core rejects `AllowAnyOrigin()` combined with `AllowCredentials()`. Specify explicit origins instead of wildcards when credentials are needed.

### Preflight Requests Fail

If `OPTIONS` requests return 405, verify that the CORS middleware runs before endpoint routing rejects unknown methods. Check that `UseCors` is called at the correct pipeline position.

### Policy Not Found

If you see "No CORS policy found" errors, ensure the policy name in `[EnableCors("PolicyName")]` exactly matches the name registered in `AddCors`. Policy names are case-sensitive.
