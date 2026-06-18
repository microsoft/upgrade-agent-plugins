---
name: migrating-mvc-validation
description: >
  Migrates ASP.NET Framework validation to ASP.NET Core including data annotations, custom
  ValidationAttribute classes, ModelState handling, client-side unobtrusive validation, and
  FluentValidation integration. Use when upgrading projects that use DataAnnotations,
  IValidatableObject, RemoteAttribute, custom validation attributes with service dependencies,
  jquery.validate.unobtrusive, or FluentValidation. Also triggers for ModelState.IsValid migration,
  ApiController automatic 400 responses, ValidationProblemDetails, and client-side validation
  script setup in Razor views.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Validation Migration

## Overview

Migrate validation logic from ASP.NET Framework to ASP.NET Core. Most `DataAnnotations` attributes transfer directly, but custom validators with service dependencies, client-side validation infrastructure, `[Remote]` attribute configuration, and `[ApiController]` automatic model validation require targeted changes.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Audit validation usage
- [ ] Step 2: Migrate data annotations and custom attributes
- [ ] Step 3: Update ModelState handling for API controllers
- [ ] Step 4: Migrate client-side validation scripts
- [ ] Step 5: Migrate Remote validation
- [ ] Step 6: Migrate FluentValidation integration
- [ ] Step 7: Verify validation behavior
```

### Step 1: Audit Validation Usage

Search the project for validation patterns to determine which steps apply:

| Signal | Search pattern | Indicates |
|--------|---------------|-----------|
| Data annotations | `using System.ComponentModel.DataAnnotations` | Step 2 |
| Custom validators | `: ValidationAttribute` | Step 2 |
| IValidatableObject | `: IValidatableObject` | Step 2 (compatible) |
| ModelState in APIs | `ModelState.IsValid` in `ApiController` classes | Step 3 |
| Client-side validation | `jquery.validate`, `jquery.validate.unobtrusive` | Step 4 |
| Remote validation | `[Remote(` | Step 5 |
| FluentValidation | `AbstractValidator<`, `FluentValidation` | Step 6 |

Skip steps that have no matching signals.

### Step 2: Migrate Data Annotations and Custom Attributes

**Standard data annotations** (`[Required]`, `[StringLength]`, `[Range]`, `[RegularExpression]`, `[Compare]`, `[EmailAddress]`) work identically in ASP.NET Core. No changes needed.

**`IValidatableObject`** is fully compatible. No changes needed.

**Custom `ValidationAttribute` subclasses** that override `IsValid(object, ValidationContext)` are compatible, but service resolution changed:

Before (ASP.NET Framework — service locator via `DependencyResolver`):

```csharp
public class UniqueEmailAttribute : ValidationAttribute
{
    protected override ValidationResult IsValid(object value, ValidationContext validationContext)
    {
        var userService = DependencyResolver.Current.GetService<IUserService>();
        if (userService.EmailExists((string)value))
        {
            return new ValidationResult(ErrorMessage);
        }
        return ValidationResult.Success;
    }
}
```

After (ASP.NET Core — services via `ValidationContext.GetService`):

```csharp
public class UniqueEmailAttribute : ValidationAttribute
{
    protected override ValidationResult IsValid(object value, ValidationContext validationContext)
    {
        var userService = (IUserService)validationContext.GetService(typeof(IUserService));
        if (userService.EmailExists((string)value))
        {
            return new ValidationResult(ErrorMessage);
        }
        return ValidationResult.Success;
    }
}
```

The key change: replace `DependencyResolver.Current.GetService<T>()` with `validationContext.GetService(typeof(T))`. This works because ASP.NET Core populates `ValidationContext.Items` and the service provider from the DI container automatically.

For attributes with complex service dependencies, consider moving the validation logic into a service-layer class or FluentValidation validator instead, to avoid the service locator pattern.

### Step 3: Update ModelState Handling for API Controllers

**MVC controllers** (`Controller` base class): `ModelState.IsValid` checks work the same way. No changes needed.

**API controllers** with `[ApiController]`: ASP.NET Core automatically returns a 400 response with `ValidationProblemDetails` when model state is invalid, before the action method executes. This means manual `ModelState.IsValid` checks are redundant.

Before (ASP.NET Framework Web API):

```csharp
[HttpPost]
public IHttpActionResult Create(ProductModel model)
{
    if (!ModelState.IsValid)
    {
        return BadRequest(ModelState);
    }
    // ... create logic
}
```

After (ASP.NET Core with `[ApiController]`):

```csharp
[HttpPost]
public IActionResult Create(ProductModel model)
{
    // ModelState.IsValid check is automatic — invalid requests never reach here
    // ... create logic
}
```

The automatic response returns `ValidationProblemDetails` (RFC 7807) instead of the legacy `ModelState` dictionary format. If existing API clients depend on the old error shape, customize the response factory:

```csharp
builder.Services.AddControllers()
    .ConfigureApiBehaviorOptions(options =>
    {
        options.InvalidModelStateResponseFactory = context =>
        {
            var problems = new ValidationProblemDetails(context.ModelState);
            return new BadRequestObjectResult(problems);
        };
    });
```

To disable automatic validation entirely for a specific controller (rare), remove the `[ApiController]` attribute or configure `SuppressModelStateInvalidFilter`:

```csharp
builder.Services.AddControllers()
    .ConfigureApiBehaviorOptions(options =>
    {
        options.SuppressModelStateInvalidFilter = true;
    });
```

### Step 4: Migrate Client-Side Validation Scripts

ASP.NET Core uses the same `jquery.validate.unobtrusive` library for client-side validation, but script loading setup changed.

**Add the validation partial.** Create or update `Views/Shared/_ValidationScriptsPartial.cshtml`:

```cshtml
<script src="~/lib/jquery-validation/dist/jquery.validate.min.js"></script>
<script src="~/lib/jquery-validation-unobtrusive/jquery.validate.unobtrusive.min.js"></script>
```

**Include the partial in views that need client-side validation.** Add at the bottom of each form view or in a `Scripts` section:

```cshtml
@section Scripts {
    <partial name="_ValidationScriptsPartial" />
}
```

The `_Layout.cshtml` must render this section:

```cshtml
@await RenderSectionAsync("Scripts", required: false)
```

**Install client libraries.** Use LibMan (the ASP.NET Core default) instead of NuGet or Bower for client-side libraries:

```
libman install jquery-validation -p cdnjs -d wwwroot/lib/jquery-validation
libman install jquery-validation-unobtrusive -p cdnjs -d wwwroot/lib/jquery-validation-unobtrusive
```

Or add entries to `libman.json` if it already exists.

**Custom client-side validation adapters** that used `$.validator.unobtrusive.adapters.add()` still work, but the registration call must execute after the unobtrusive script loads. Place custom adapter scripts after the `_ValidationScriptsPartial` include.

### Step 5: Migrate Remote Validation

The `[Remote]` attribute exists in ASP.NET Core under `Microsoft.AspNetCore.Mvc` but requires different configuration.

Before (ASP.NET Framework):

```csharp
[Remote("IsEmailAvailable", "Users")]
public string Email { get; set; }
```

After (ASP.NET Core):

```csharp
[Remote(action: "IsEmailAvailable", controller: "Users")]
public string Email { get; set; }
```

The attribute syntax is the same, but ensure the validation endpoint:

1. Returns `JsonResult` — return `Json(true)` for valid, `Json("Error message")` for invalid.
2. Accepts `GET` requests (the default for remote validation AJAX calls).
3. Is accessible without authentication if the form is on a public page.

Example validation action:

```csharp
[AcceptVerbs("GET", "POST")]
public IActionResult IsEmailAvailable(string email)
{
    if (_userService.EmailExists(email))
    {
        return Json($"Email {email} is already in use.");
    }
    return Json(true);
}
```

Remote validation depends on `jquery.validate.unobtrusive` — ensure Step 4 is complete.

### Step 6: Migrate FluentValidation Integration

If the project uses FluentValidation, the registration mechanism changed.

Before (ASP.NET Framework with `FluentValidation.Mvc`):

```csharp
// Global.asax.cs
FluentValidationModelValidatorProvider.Configure();
```

After (ASP.NET Core with `FluentValidation.AspNetCore`):

```csharp
// Program.cs
builder.Services.AddControllersWithViews()
    .AddFluentValidation(fv => fv.RegisterValidatorsFromAssemblyContaining<ProductValidator>());
```

**Package change**: Replace `FluentValidation.Mvc` or `FluentValidation.WebApi` with `FluentValidation.AspNetCore` in the project file.

> **Note:** `AddFluentValidation()` on `IMvcBuilder` was deprecated in FluentValidation 11+. For newer versions, use manual registration:
>
> ```csharp
> builder.Services.AddValidatorsFromAssemblyContaining<ProductValidator>();
> builder.Services.AddFluentValidationAutoValidation();
> builder.Services.AddFluentValidationClientsideAdapters(); // optional: client-side support
> ```

Individual `AbstractValidator<T>` implementations require no changes — the validator classes themselves are framework-agnostic.

### Step 7: Verify Validation Behavior

After migration, verify:

1. **Build succeeds** with no validation-related compilation errors.
2. **Server-side validation** rejects invalid input and returns appropriate error messages.
3. **Client-side validation** (if used) shows errors before form submission.
4. **API validation** (if applicable) returns the expected error response format.
5. **Remote validation** endpoints respond correctly to AJAX calls.

## Troubleshooting

**`ValidationContext.GetService` returns null.** The service is not registered in DI. Register it in `Program.cs` before it can be resolved during validation.

**Client-side validation not firing.** Ensure `jquery`, `jquery.validate`, and `jquery.validate.unobtrusive` load in that order, and that `_ValidationScriptsPartial` is included in the view's `Scripts` section.

**API returns `ValidationProblemDetails` instead of the expected error format.** The `[ApiController]` attribute enables automatic model validation with the RFC 7807 response shape. Customize via `InvalidModelStateResponseFactory` or suppress with `SuppressModelStateInvalidFilter` (see Step 3).

**FluentValidation validators not executing.** Confirm the `FluentValidation.AspNetCore` package is installed and validators are registered via `AddValidatorsFromAssemblyContaining<T>()` or `RegisterValidatorsFromAssemblyContaining<T>()`.

## Success Criteria

- Custom `ValidationAttribute` classes use `ValidationContext.GetService` instead of `DependencyResolver`
- API controllers leverage `[ApiController]` automatic validation or explicitly opt out
- Client-side validation scripts load via `_ValidationScriptsPartial` and LibMan
- `[Remote]` validation endpoints return `JsonResult` and accept GET requests
- FluentValidation uses `FluentValidation.AspNetCore` package with correct registration
- No references to `DependencyResolver`, `FluentValidation.Mvc`, or `FluentValidation.WebApi` remain
- Project builds without errors
