---
name: migrating-mvc-controllers
description: >
  Migrates ASP.NET Framework controllers and action results to ASP.NET Core equivalents, covering
  both MVC (Controller) and WebAPI (ApiController) patterns. Use when upgrading controllers that
  return HttpResponseMessage, IHttpActionResult, use ApiController base class, use
  Request.CreateResponse(), ResponseTypeAttribute, ChildActionOnlyAttribute, or AsyncController.
  Also triggers for "convert WebAPI controller", "migrate action results", "replace
  HttpResponseMessage", "IActionResult migration", and controller return type rewrite.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# Controllers and Action Results Migration

## Overview

Migrate ASP.NET Framework MVC and WebAPI controllers to ASP.NET Core. The return type system changed completely between frameworks — `HttpResponseMessage` is gone, status code helpers differ, and the `ApiController` vs `ControllerBase` distinction changes request processing behavior. Wrong choices produce incorrect HTTP responses that compile but fail at runtime.

## Workflow

```
Migration Progress:
- [ ] Step 1: Inventory controllers and classify (MVC vs WebAPI)
- [ ] Step 2: Change base classes and namespaces
- [ ] Step 3: Rewrite return types and response helpers
- [ ] Step 4: Apply [ApiController] attribute where appropriate
- [ ] Step 5: Migrate async action patterns
- [ ] Step 6: Convert child actions to ViewComponents
- [ ] Step 7: Verify build and endpoint behavior
```

### Step 1: Inventory Controllers

Classify each controller as MVC or WebAPI based on its base class and usage:

| Signal | Classification |
|--------|---------------|
| Inherits `ApiController` | WebAPI |
| Inherits `Controller` (System.Web.Mvc) | MVC |
| Returns `HttpResponseMessage` | WebAPI |
| Returns `IHttpActionResult` | WebAPI |
| Returns `ViewResult` or calls `View()` | MVC |
| Uses `[ChildActionOnly]` | MVC |

Some projects have hybrid controllers inheriting `Controller` but returning JSON for AJAX calls. Classify these as MVC — they use `Controller` (with view support), not `ControllerBase`.

### Step 2: Change Base Classes and Namespaces

Replace all `System.Web.Mvc` and `System.Web.Http` namespace imports with `Microsoft.AspNetCore.Mvc`.

**WebAPI controllers:**

```csharp
// Before
using System.Web.Http;
public class OrdersController : ApiController

// After
using Microsoft.AspNetCore.Mvc;
[Route("api/[controller]")]
public class OrdersController : ControllerBase
```

**MVC controllers:** Keep `Controller` as the base class. ASP.NET Core's `Controller` inherits from `ControllerBase` and adds view support (`View()`, `PartialView()`, `ViewBag`, `TempData`).

```csharp
// Before
using System.Web.Mvc;
public class HomeController : Controller

// After
using Microsoft.AspNetCore.Mvc;
public class HomeController : Controller
```

### Step 3: Rewrite Return Types and Response Helpers

This is the highest-risk step. The response construction API changed entirely for WebAPI controllers.

#### WebAPI Return Type Mapping

| Old (System.Web.Http) | New (ASP.NET Core) |
|------------------------|--------------------|
| `HttpResponseMessage` | `IActionResult` or `ActionResult<T>` |
| `IHttpActionResult` | `IActionResult` |
| `Task<HttpResponseMessage>` | `Task<IActionResult>` or `Task<ActionResult<T>>` |
| `Request.CreateResponse(HttpStatusCode.OK, data)` | `Ok(data)` |
| `Request.CreateResponse(HttpStatusCode.Created, data)` | `CreatedAtAction(...)` or `Created(uri, data)` |
| `Request.CreateResponse(HttpStatusCode.NotFound)` | `NotFound()` |
| `Request.CreateResponse(HttpStatusCode.BadRequest)` | `BadRequest()` |
| `Request.CreateErrorResponse(status, message)` | `Problem(detail: message, statusCode: status)` |
| `ResponseMessage(response)` | Build equivalent with `StatusCode(code)` |
| `Content(HttpStatusCode.OK, data)` | `Ok(data)` |
| `Content(status, data, formatter, mediaType)` | `Ok(data)` (content negotiation is automatic) |
| Raw `T` return (implicit 200) | Raw `T` return (still works) |

**Before (WebAPI):**

```csharp
public HttpResponseMessage Get(int id)
{
    var order = _repo.Find(id);
    if (order == null)
        return Request.CreateResponse(HttpStatusCode.NotFound);
    return Request.CreateResponse(HttpStatusCode.OK, order);
}
```

**After (ASP.NET Core):**

```csharp
public ActionResult<Order> Get(int id)
{
    var order = _repo.Find(id);
    if (order == null)
        return NotFound();
    return Ok(order);
}
```

Prefer `ActionResult<T>` over `IActionResult` when the success type is known — it enables OpenAPI schema generation and type safety.

#### MVC Return Types

MVC return types are mostly compatible. Key differences:

| Old | New | Notes |
|-----|-----|-------|
| `ActionResult` | `IActionResult` | `ActionResult` still exists but `IActionResult` is idiomatic |
| `JsonResult` via `Json(data)` | `Json(data)` | **Silent behavior change**: default serializer is System.Text.Json, not Newtonsoft. Property casing changes from PascalCase to camelCase by default. |
| `Json(data, JsonRequestBehavior.AllowGet)` | `Json(data)` | Second parameter removed — GET requests always allowed in Core |
| `new HttpStatusCodeResult(code)` | `StatusCode(code)` | Different class, same behavior |
| `new HttpNotFoundResult()` | `NotFound()` | Helper method preferred |

**JsonResult serialization gotcha**: If frontend JavaScript expects PascalCase property names, configure the serializer:

```csharp
builder.Services.AddControllersWithViews()
    .AddJsonOptions(options =>
        options.JsonSerializerOptions.PropertyNamingPolicy = null);
```

Or add Newtonsoft compatibility if the project has complex serialization requirements. See `migrating-newtonsoft-to-system-text-json` for details.

#### ResponseTypeAttribute Migration

Replace `[ResponseType]` with `[ProducesResponseType]`. The new attribute requires an explicit status code:

```csharp
// Before
[ResponseType(typeof(Order))]
public IHttpActionResult Get(int id) { ... }

// After
[ProducesResponseType(typeof(Order), StatusCodes.Status200OK)]
[ProducesResponseType(StatusCodes.Status404NotFound)]
public ActionResult<Order> Get(int id) { ... }
```

When using `ActionResult<T>`, the 200 response type is inferred — only non-success types need explicit attributes:

```csharp
[ProducesResponseType(StatusCodes.Status404NotFound)]
public ActionResult<Order> Get(int id) { ... }
```

### Step 4: Apply [ApiController] Attribute

Add `[ApiController]` to WebAPI controllers. This attribute changes several behaviors silently — understand each before applying:

| Behavior | Without [ApiController] | With [ApiController] |
|----------|------------------------|---------------------|
| Invalid ModelState | Must check `ModelState.IsValid` manually | Automatic 400 response before action executes |
| Binding source | Must specify `[FromBody]`, `[FromQuery]` | Inferred: complex types from body, simple types from query/route |
| Problem details | Returns plain text errors | Returns RFC 7807 ProblemDetails JSON |

**If the existing code has custom ModelState validation logic** that returns something other than a plain 400 (e.g., custom error shapes, redirects, or partial success), do not apply `[ApiController]` without adjusting that logic — the automatic 400 will short-circuit the action before custom validation runs.

Suppress automatic 400 for specific actions if needed:

```csharp
builder.Services.AddControllers()
    .ConfigureApiBehaviorOptions(options =>
        options.SuppressModelStateInvalidFilter = true);
```

### Step 5: Migrate Async Action Patterns

**Async void actions** — not supported in ASP.NET Core. Change return type to `Task`:

```csharp
// Before — compiles but crashes in Core (unobserved exception kills the request)
public async void SendNotification(int id) { ... }

// After
public async Task<IActionResult> SendNotification(int id)
{
    // ... async work ...
    return Ok();
}
```

**AsyncController base class** — remove it. ASP.NET Core controllers support async natively without a special base class. Change `AsyncController` to `Controller` (MVC) or `ControllerBase` (API).

**Synchronous IO in action methods** — Kestrel disables synchronous IO by default. Actions that read `Request.Body` synchronously or write to `Response.Body` synchronously throw `InvalidOperationException` at runtime. Fix by using async stream methods, or as a temporary escape hatch:

```csharp
builder.Services.Configure<KestrelServerOptions>(options =>
    options.AllowSynchronousIO = true);
```

Prefer fixing the async pattern over enabling the escape hatch — synchronous IO blocks the thread pool under load.

### Step 6: Convert Child Actions to ViewComponents

ASP.NET Core removed child actions entirely. `ChildActionOnlyAttribute` has no equivalent. Convert `[ChildActionOnly]` action methods to ViewComponents:

```csharp
// Before — MVC 5 child action
[ChildActionOnly]
public ActionResult RecentOrders()
{
    var orders = _repo.GetRecent();
    return PartialView("_RecentOrders", orders);
}
// Invoked in view: @Html.Action("RecentOrders", "Orders")
```

```csharp
// After — ASP.NET Core ViewComponent
public class RecentOrdersViewComponent : ViewComponent
{
    private readonly IOrderRepository _repo;

    public RecentOrdersViewComponent(IOrderRepository repo) => _repo = repo;

    public IViewComponentResult Invoke()
    {
        var orders = _repo.GetRecent();
        return View("_RecentOrders", orders);
    }
}
// Invoked in view: @await Component.InvokeAsync("RecentOrders")
```

Place ViewComponent classes in a `ViewComponents/` folder by convention. Move the associated partial view to `Views/Shared/Components/RecentOrders/_RecentOrders.cshtml` (or `Default.cshtml` to use the convention-based name).

ViewComponents support constructor injection natively. Async ViewComponents return `Task<IViewComponentResult>` from an `InvokeAsync` method.

### Step 7: Verify Build and Endpoint Behavior

1. Build the project and fix compilation errors
2. Check each endpoint returns the expected HTTP status codes
3. Verify JSON response shapes — property casing and date formats may differ with System.Text.Json
4. Confirm `[ApiController]` auto-validation produces acceptable error responses
5. Test any ViewComponents render correctly in their host views

## Binding Attribute Quick Reference

| Old (System.Web.Http) | New (ASP.NET Core) |
|------------------------|--------------------|
| `[FromUri]` | `[FromQuery]` or `[FromRoute]` (choose based on where the value comes from) |
| `[FromBody]` | `[FromBody]` (same, but inferred for complex types with `[ApiController]`) |
| No attribute on complex param | Bound from URI in WebAPI; bound from body with `[ApiController]` in Core |

This binding source change is a **silent breaking change** when `[ApiController]` is applied. A complex parameter that previously bound from query string values now binds from the request body. If the controller receives `null` for previously-working parameters, check binding source inference.

## Success Criteria

- All controllers compile against `Microsoft.AspNetCore.Mvc` with no `System.Web` references
- WebAPI controllers use `ControllerBase` (or `Controller` if views needed) instead of `ApiController`
- `HttpResponseMessage` and `IHttpActionResult` return types fully replaced
- `Request.CreateResponse()` calls replaced with status code helpers (`Ok()`, `NotFound()`, etc.)
- `[ApiController]` applied to API controllers with binding/validation behavior verified
- `[ChildActionOnly]` methods converted to ViewComponents
- No `async void` action methods remain
- JSON serialization behavior validated (property casing, date formats)
- Project builds without errors
