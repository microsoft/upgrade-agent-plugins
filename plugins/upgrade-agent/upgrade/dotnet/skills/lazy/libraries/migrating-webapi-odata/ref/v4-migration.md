# OData v4 Migration After Compatibility Approval

Use this recipe only for the endpoint scope with a recorded PASS from the
`migrating-webapi-odata` compatibility gate. STOP if that evidence is missing or
the scope has changed. Keep packages, formatters, and serializers required by
any still-live Framework endpoint; a PASS for one endpoint is not project-wide
permission to remove shared dependencies.

## Contents

- [Overview](#overview)
- [Package Reference Changes](#package-reference-changes)
- [Workflow](#workflow)
- [Troubleshooting](#troubleshooting)

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
- OData v3 imports: `System.Web.Http.OData`, `System.Web.Http.OData.Builder`, and `System.Web.Http.OData.Query` (`using` in C#, `Imports` in Visual Basic)
- Web API OData v4 imports: `Microsoft.AspNet.OData`, `Microsoft.AspNet.OData.Builder`, and `Microsoft.AspNet.OData.Query`; earlier v4 packages used `System.Web.OData` and its `.Builder`/`.Query` namespaces
- Controllers inheriting from `ODataController` or `EntitySetController`
- `ODataConventionModelBuilder` or `ODataModelBuilder` usage
- `MapODataServiceRoute` or `MapODataRoute` calls in `WebApiConfig`
- `[EnableQuery]` or `[Queryable]` attributes
- `ODataQueryOptions<T>` parameters

### Step 2: Update Project File References

Recheck the recorded PASS before changing references. Remove old packages only
from the eligible migration target and add the new package reference (see
"Package Reference Changes" above). Do not remove a central package version or
transitive OData v3 dependency that the retained Framework host still needs.

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

1. Replace imports by the symbols each file uses, not by globally mapping every legacy OData namespace to controller/query namespaces:

   | Symbols | Legacy namespaces | Target namespace |
   | --- | --- | --- |
   | `ODataController` | `System.Web.Http.OData`, `System.Web.OData`, `Microsoft.AspNet.OData` | `Microsoft.AspNetCore.OData.Routing.Controllers` |
   | `EnableQueryAttribute` | `System.Web.Http.OData`, `System.Web.OData`, `Microsoft.AspNet.OData` | `Microsoft.AspNetCore.OData.Query` |
   | `ODataQueryOptions` | `System.Web.Http.OData.Query`, `System.Web.OData.Query`, `Microsoft.AspNet.OData.Query` | `Microsoft.AspNetCore.OData.Query` |
   | `ODataConventionModelBuilder`, `ODataModelBuilder` | `System.Web.Http.OData.Builder`, `System.Web.OData.Builder`, `Microsoft.AspNet.OData.Builder` | `Microsoft.OData.ModelBuilder` |
   | `IEdmModel` | `Microsoft.Data.Edm`, `Microsoft.OData.Edm` | `Microsoft.OData.Edm` |

2. Inherit from `Microsoft.AspNetCore.OData.Routing.Controllers.ODataController` instead of the legacy base class
3. Replace `EntitySetController<T, TKey>` with `ODataController` — implement CRUD actions manually
4. Port `[EnableQuery]` attributes, then verify allowed query options, limits, paging, and response shapes against the baseline; attribute names do not prove equivalent behavior

### Step 5: Update EDM Model Configuration

`ODataConventionModelBuilder` still exists in ASP.NET Core OData. Similar model-building APIs do not establish wire compatibility. Extract the model builder into a helper method:

```csharp
using Microsoft.OData.Edm;
using Microsoft.OData.ModelBuilder;

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
| `[ODataRoutePrefix("odata")]` | `[Route("odata")]` | Use standard ASP.NET Core attributes for the existing prefix |
| `[ODataRoute("Products({key})")]` | `[HttpGet("Products({key})")]` or convention routing | ASP.NET Core OData 8+ removed `ODataRoute`; choose the HTTP method attribute that matches the original action |
| Batch endpoint (`$batch`) | `options.AddRouteComponents(prefix, model, new DefaultODataBatchHandler())` | Also call `app.UseODataBatching()` before `app.UseRouting()` |

`DefaultODataBatchHandler` is in `Microsoft.AspNetCore.OData.Batch`. Register
the handler on the same route prefix/model being migrated, rather than adding
the prefix twice. Preserve batch limits, changeset behavior, and errors from
the baseline; verify with isolated state before moving traffic.

Remove legacy `ODataRoute` and `ODataRoutePrefix` attributes. For attribute
routing, combine the controller's `[Route]` prefix with action templates such
as `[HttpGet]` to preserve the complete URL and HTTP method.
`[ODataAttributeRouting]` opts into OData attribute routing; it does not replace
the route template or HTTP method attributes.

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
4. Complete the calling skill's wire-conformance checks before moving traffic; a successful build or `$metadata` request is not a compatibility result

## Troubleshooting

### 404 on OData Endpoints

Verify the route prefix in `AddRouteComponents` matches the URL path. Check `/$odata` debug endpoint for registered routes.

### $select / $filter Not Working

Ensure `Select()`, `Filter()`, and other query options are enabled in `AddOData`. ASP.NET Core OData disables all query options by default — they must be explicitly opted in.

### EntitySetController Not Found

`EntitySetController` does not exist in ASP.NET Core OData. Inherit from `ODataController` and implement standard CRUD action methods (`Get`, `Post`, `Put`, `Patch`, `Delete`).

### Serialization Differences

OData responses use OData formatters and serializers; ordinary MVC JSON options
do not restore an OData v3 or Atom contract. If serialization differs from the
baseline, STOP cutover and return to the compatibility gate rather than swapping
JSON libraries as a presumed wire-format fix.

### Legacy OData Route Attributes

Do not retain `ODataRoute` or `ODataRoutePrefix` in ASP.NET Core OData 8+.
Use standard `[Route]` and HTTP method attributes with the full registered
prefix, or align the controller/action names with OData convention routing.
Adding `[ODataAttributeRouting]` alone does not supply a missing route template.
