---
name: migrating-webapi-odata
description: >
  Migrates legacy ASP.NET Web API OData
  (Microsoft.AspNet.WebApi.OData) to ASP.NET Core OData
  (Microsoft.AspNetCore.OData). Use ONLY when
  Microsoft.AspNet.WebApi.OData has been flagged as obsolete
  or deprecated and must be replaced — not for version-bump
  scenarios where Microsoft.AspNet.WebApi.OData is still
  supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# ASP.NET Web API OData to ASP.NET Core OData Migration

## Overview

Migrate OData services from ASP.NET Web API (`Microsoft.AspNet.WebApi.OData` or `Microsoft.AspNet.OData`) to ASP.NET Core OData (`Microsoft.AspNetCore.OData`). The core changes are registering OData via dependency injection with `AddOData()`, replacing convention-based routing with endpoint routing, and updating controllers to inherit from the ASP.NET Core `ODataController` base class. EDM model building remains similar but is wired differently.

## Package Reference Changes

### Old References (Remove)

```xml
<PackageReference Include="Microsoft.AspNet.WebApi.OData" Version="5.*" />
<PackageReference Include="Microsoft.AspNet.OData" Version="7.*" />
```

### New Reference (Add)

```xml
<PackageReference Include="Microsoft.AspNetCore.OData" Version="{version-for-target-framework}" />
```

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect OData usage
- [ ] Step 2: Update project file references
- [ ] Step 3: Register OData in DI
- [ ] Step 4: Migrate controllers
- [ ] Step 5: Update EDM model configuration
- [ ] Step 6: Migrate routing
- [ ] Step 7: Build and verify
```

### Step 1: Detect OData Usage

Scan the project for:
- `using System.Web.OData;` or `using Microsoft.AspNet.OData;` statements
- Controllers inheriting from `ODataController` or `EntitySetController`
- `ODataConventionModelBuilder` or `ODataModelBuilder` usage
- `MapODataServiceRoute` or `MapODataRoute` calls in `WebApiConfig`
- `[EnableQuery]` or `[Queryable]` attributes
- `ODataQueryOptions<T>` parameters

### Step 2: Update Project File References

Remove old packages and add the new package reference (see "Package Reference Changes" above).

### Step 3: Register OData in DI

Replace route-based OData registration with DI-based configuration in `Program.cs` or `Startup.ConfigureServices`:

```csharp
// Old: in WebApiConfig.cs
var builder = new ODataConventionModelBuilder();
builder.EntitySet<Product>("Products");
config.MapODataServiceRoute("odata", "odata", builder.GetEdmModel());

// New: in Program.cs
builder.Services.AddControllers()
    .AddOData(options =>
    {
        options.Select().Filter().OrderBy().Expand().Count().SetMaxTop(100);
        options.AddRouteComponents("odata", GetEdmModel());
    });
```

### Step 4: Migrate Controllers

1. Change `using` directives from `System.Web.OData` or `Microsoft.AspNet.OData` to `Microsoft.AspNetCore.OData.Routing.Controllers` and `Microsoft.AspNetCore.OData.Query`
2. Inherit from `Microsoft.AspNetCore.OData.Routing.Controllers.ODataController` instead of the legacy base class
3. Replace `EntitySetController<T, TKey>` with `ODataController` — implement CRUD actions manually
4. Keep `[EnableQuery]` attributes — they work in ASP.NET Core OData with the same semantics

### Step 5: Update EDM Model Configuration

`ODataConventionModelBuilder` still exists in ASP.NET Core OData with a compatible API. Extract the model builder into a helper method:

```csharp
static IEdmModel GetEdmModel()
{
    var builder = new ODataConventionModelBuilder();
    builder.EntitySet<Product>("Products");
    builder.EntitySet<Order>("Orders");
    return builder.GetEdmModel();
}
```

If using explicit `ODataModelBuilder` (non-convention), review property/navigation bindings — the API is mostly compatible but some extension methods have moved.

### Step 6: Migrate Routing

| Old Pattern | New Pattern | Notes |
|------------|------------|-------|
| `config.MapODataServiceRoute(name, prefix, model)` | `options.AddRouteComponents(prefix, model)` | Registered inside `AddOData` |
| Convention routing with `ODataRoute` | Endpoint routing via attribute routes | Use `[ODataAttributeRouting]` or convention-based with `AddRouteComponents` |
| `[ODataRoute("Products({key})")]` | `[HttpGet("Products({key})")]` or convention routing | Explicit OData route attributes still supported |
| Batch endpoint (`$batch`) | `options.AddRouteComponents(...).Services` | Enable with `routeOptions.EnableBatchRequests()` |

For debugging route issues, enable the OData route debug endpoint:

```csharp
app.UseODataRouteDebug();
```

This exposes `/$odata` to list all registered OData routes.

### Step 7: Build and Verify

1. Build the project:
   ```
   dotnet build
   ```
2. Query the OData metadata endpoint to verify the EDM model:
   ```
   curl https://localhost:5001/odata/$metadata
   ```
3. Test entity set queries with `$select`, `$filter`, and `$expand` to confirm query options work

## Troubleshooting

### 404 on OData Endpoints

Verify the route prefix in `AddRouteComponents` matches the URL path. Check `/$odata` debug endpoint for registered routes.

### $select / $filter Not Working

Ensure `Select()`, `Filter()`, and other query options are enabled in `AddOData`. ASP.NET Core OData disables all query options by default — they must be explicitly opted in.

### EntitySetController Not Found

`EntitySetController` does not exist in ASP.NET Core OData. Inherit from `ODataController` and implement standard CRUD action methods (`Get`, `Post`, `Put`, `Patch`, `Delete`).

### Serialization Differences

ASP.NET Core OData uses `System.Text.Json` by default. If entities have circular references or complex inheritance, configure serializer options or switch to `Newtonsoft.Json` via `Microsoft.AspNetCore.OData.NewtonsoftJson`.

### Missing OData Route Attribute

If controller actions return 404, add `[ODataAttributeRouting]` to the controller or ensure convention routing matches the entity set name to the controller name (e.g., `ProductsController` for entity set `Products`).
