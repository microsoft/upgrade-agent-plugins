---
name: migrating-mvc-razor-views
description: >
  Migrates ASP.NET MVC Razor views to ASP.NET Core by converting HtmlHelpers to TagHelpers,
  child actions to ViewComponents, porting custom view-location precedence, and updating layout
  infrastructure. Use when upgrading MVC apps that use Html.ActionLink, Html.BeginForm,
  Html.TextBoxFor, Html.DropDownListFor, Html.ValidationMessageFor, Html.ValidationSummary,
  Html.Action, Html.RenderAction, ChildActionOnly, @helper, HtmlString, custom HtmlHelper
  extensions, or a custom RazorViewEngine / VirtualPathProviderViewEngine registered through
  ViewEngines.Engines. Also triggers for TagHelper conversion, ViewComponent migration,
  _ViewImports setup, view discovery changes, ViewLocationFormats, PartialViewLocationFormats,
  MasterLocationFormats, AreaViewLocationFormats, RazorViewEngineOptions, IViewLocationExpander,
  ViewBag/ViewData/TempData migration, display templates, and editor templates in MVC-to-Core
  upgrades.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Razor Views Migration

## Overview

Migrate ASP.NET MVC Razor views to ASP.NET Core. Razor syntax is mostly compatible, but the helper ecosystem changed significantly: HtmlHelpers are replaced by TagHelpers, child actions are replaced by ViewComponents, and layout infrastructure requires a `_ViewImports.cshtml` file. For bundle-specific migration (`@Scripts.Render`, `@Styles.Render`, `BundleConfig.cs`), see the `migrating-mvc-bundling` skill.

## Workflow

```
Migration Progress:
- [ ] Step 1: Set up _ViewImports.cshtml
- [ ] Step 2: Port custom view-location precedence
- [ ] Step 3: Convert HtmlHelpers to TagHelpers
- [ ] Step 4: Convert child actions to ViewComponents
- [ ] Step 5: Update partial view references
- [ ] Step 6: Migrate custom HtmlHelper extensions
- [ ] Step 7: Update view data passing patterns
- [ ] Step 8: Clean up removed APIs
- [ ] Step 9: Verify build
```

### Step 1: Set Up _ViewImports.cshtml

Create `Views/_ViewImports.cshtml` if it does not exist. This file replaces per-view `@using` statements and activates TagHelpers globally:

```cshtml
@using MyApp
@using MyApp.Models
@addTagHelper *, Microsoft.AspNetCore.Mvc.TagHelpers
```

Replace `MyApp` with the actual project namespace. The `@addTagHelper` directive is required for all built-in TagHelpers to work. Without it, TagHelper syntax renders as plain HTML attributes.

Verify that `_ViewStart.cshtml` still references the correct layout path. The default `_Layout.cshtml` path is compatible between MVC and Core.

### Step 2: Port Custom View-Location Precedence

Both frameworks probe an ordered list of path formats and render the **first file that exists**, so that order is behavior. An app that replaced the default view engine — usually to put an override folder ahead of `Views/` — loses every override if the order is not carried across, and loses it silently, because the fallback view still renders.

Search the Framework project for these signals in startup, `*ViewEngine.cs`, controllers, and their base classes or view-returning helpers:

| Signal | What it means |
|--------|---------------|
| `ViewEngines.Engines.Clear()`, `.Add(...)`, `.Insert(...)` | the engine list was replaced or reordered |
| a type deriving from `RazorViewEngine` or `VirtualPathProviderViewEngine` | custom formats, or an overridden `FindView` / `FindPartialView` / `CreateView` |
| a type implementing `IViewEngine` directly | fully custom resolution, which may go beyond file locations |
| assignment to any `*LocationFormats` property | the precedence list itself |
| `DisplayModeProvider.Instance.Modes`, `DefaultDisplayMode`, `*.Mobile.cshtml`, or other configured suffixed views | request-dependent selection, including stock Mobile mode without a custom engine |
| `View(viewName, masterName)` or `View(viewName, masterName, model)`, including named `masterName:` arguments | explicit master selection, even with the stock engine; follow the [explicit-layout rewrite guidance](ref/view-location-precedence.md#when-the-source-orders-diverge) |

Confirm the bound MVC overload before rewriting: `View(viewName, model)` is not a master-name call. The two-string master overload silently binds to Core's `View(string, object)`, making the layout name the model; the three-argument master overload has no Core equivalent. Do not take the no-signal exit until these call sites have been checked.

**If none of them is present, skip to Step 3 after checking the stock fallbacks.** MVC also searched `~/Views/{1}/{0}.cshtml` for a request inside an area, and Core's default area list does not. Insert `/Views/{1}/{0}.cshtml` immediately before `/Views/Shared/{0}.cshtml`, after the two area-specific entries. Appending it would let a global shared view beat the controller-specific view. Inside the existing Razor options configuration, for an otherwise unchanged Core default list:

```csharp
options.AreaViewLocationFormats.Insert(2, "/Views/{1}/{0}.cshtml");
```

The resulting order is area controller, area shared, non-area controller, global shared. If other configuration has changed the list, reconstruct that order rather than relying on index 2. MVC's `.vbhtml` locations have no Core equivalent at all — Core Razor compiles C# only, so a VB Razor view has to be rewritten as `.cshtml` before any location matters.

One registration also needs no port: a `ViewEngines.Engines.Clear()` whose only purpose was dropping `WebFormViewEngine`, followed by a stock `RazorViewEngine` with no format overrides. The area, `.vbhtml`, display-mode, and explicit-master checks still apply.

Otherwise, copy every `*LocationFormats` array out **verbatim and in order**, and inventory explicit master calls and display modes before flattening the lists. Follow [ref/view-location-precedence.md](ref/view-location-precedence.md) for explicit-layout rewrites, collection mapping, area-list concatenation, display-mode selection, and `IViewLocationExpander` for request-varying precedence.

### Step 3: Convert HtmlHelpers to TagHelpers

Replace `@Html.*` helper calls with TagHelper equivalents. TagHelpers use HTML attributes prefixed with `asp-` instead of C# method calls, making views closer to standard HTML.

#### Links and Navigation

**Before:**
```cshtml
@Html.ActionLink("View Details", "Details", "Products", new { id = item.Id }, new { @class = "btn" })
```

**After:**
```cshtml
<a asp-controller="Products" asp-action="Details" asp-route-id="@item.Id" class="btn">View Details</a>
```

#### Forms

**Before:**
```cshtml
@using (Html.BeginForm("Create", "Products", FormMethod.Post, new { @class = "form" }))
{
    @Html.AntiForgeryToken()
    @Html.LabelFor(m => m.Name)
    @Html.TextBoxFor(m => m.Name, new { @class = "form-control" })
    @Html.ValidationMessageFor(m => m.Name, "", new { @class = "text-danger" })
}
```

**After:**
```cshtml
<form asp-controller="Products" asp-action="Create" method="post" class="form">
    <label asp-for="Name"></label>
    <input asp-for="Name" class="form-control" />
    <span asp-validation-for="Name" class="text-danger"></span>
</form>
```

The `asp-for` TagHelper generates `id`, `name`, `type`, and validation attributes automatically. The antiforgery token is injected automatically by the form TagHelper when `method="post"`.

#### Dropdowns

**Before:**
```cshtml
@Html.DropDownListFor(m => m.CategoryId, Model.Categories, "-- Select --", new { @class = "form-control" })
```

**After:**
```cshtml
<select asp-for="CategoryId" asp-items="Model.Categories" class="form-control">
    <option value="">-- Select --</option>
</select>
```

#### Validation Summary

**Before:**
```cshtml
@Html.ValidationSummary(true, "", new { @class = "text-danger" })
```

**After:**
```cshtml
<div asp-validation-summary="ModelOnly" class="text-danger"></div>
```

Use `All` instead of `ModelOnly` if the original `excludePropertyErrors` parameter was `false`.

### Step 4: Convert Child Actions to ViewComponents

Child actions (`Html.Action` / `Html.RenderAction` with `[ChildActionOnly]`) are removed in ASP.NET Core. Replace them with ViewComponents, which follow a mini-controller pattern.

#### Create the ViewComponent Class

**Before (child action in controller):**
```csharp
[ChildActionOnly]
public ActionResult RecentProducts(int count = 5)
{
    var products = _repository.GetRecent(count);
    return PartialView("_RecentProducts", products);
}
```

**After (ViewComponent class):**
```csharp
public class RecentProductsViewComponent : ViewComponent
{
    private readonly IProductRepository _repository;

    public RecentProductsViewComponent(IProductRepository repository)
    {
        _repository = repository;
    }

    public IViewComponentResult Invoke(int count = 5)
    {
        var products = _repository.GetRecent(count);
        return View(products);
    }
}
```

Place ViewComponent classes in a `ViewComponents/` folder or any folder — they are discovered by convention (suffix `ViewComponent`) or by the `[ViewComponent]` attribute. ViewComponents support constructor dependency injection natively.

#### Move the View

Move the partial view from `Views/<Controller>/_RecentProducts.cshtml` (or `Views/Shared/_RecentProducts.cshtml`) to `Views/Shared/Components/RecentProducts/Default.cshtml`. The view content stays the same.

#### Update the Invocation

**Before:**
```cshtml
@Html.Action("RecentProducts", "Home", new { count = 10 })
```

**After:**
```cshtml
@await Component.InvokeAsync("RecentProducts", new { count = 10 })
```

Alternatively, use the TagHelper syntax after registering the assembly in `_ViewImports.cshtml`:
```cshtml
<vc:recent-products count="10"></vc:recent-products>
```

For the TagHelper syntax, add to `_ViewImports.cshtml`:
```cshtml
@addTagHelper *, MyApp
```

### Step 5: Update Partial View References

Partial views are supported in ASP.NET Core but the invocation syntax changed.

**Before:**
```cshtml
@Html.Partial("_ProductCard", item)
@{ Html.RenderPartial("_Sidebar"); }
```

**After:**
```cshtml
<partial name="_ProductCard" model="item" />
```

The `<partial>` TagHelper is preferred over `@Html.PartialAsync` and `@await Html.PartialAsync`. The synchronous `Html.Partial` is removed in ASP.NET Core because views run asynchronously.

Non-area partials resolve the same way by default: `Views/<Controller>/` then `Views/Shared/`. A partial requested from inside an area does not — MVC also probed `~/Views/{1}/{0}.cshtml` there and Core's default area list does not, which is the gap Step 2 covers. If Step 2 found a custom view engine, partials resolve through the ported `ViewLocationFormats` instead. Display templates (`DisplayTemplates/`) and editor templates (`EditorTemplates/`) follow the same conventions and are compatible.

### Step 6: Migrate Custom HtmlHelper Extensions

Custom `HtmlHelper` extension methods use a different pattern in ASP.NET Core because the return type changed from `HtmlString`/`MvcHtmlString` to `IHtmlContent`.

**Before:**
```csharp
public static MvcHtmlString IconLink(this HtmlHelper html, string text, string icon)
{
    return new MvcHtmlString($"<span class=\"{icon}\"></span> {HttpUtility.HtmlEncode(text)}");
}
```

**After (option A — IHtmlHelper extension):**
```csharp
public static IHtmlContent IconLink(this IHtmlHelper html, string text, string icon)
{
    return new HtmlString($"<span class=\"{icon}\"></span> {HtmlEncoder.Default.Encode(text)}");
}
```

**After (option B — custom TagHelper, preferred for new code):**
```csharp
[HtmlTargetElement("icon-link")]
public class IconLinkTagHelper : TagHelper
{
    public string Text { get; set; }
    public string Icon { get; set; }

    public override void Process(TagHelperContext context, TagHelperOutput output)
    {
        output.TagName = "span";
        output.Content.AppendHtml($"<span class=\"{Icon}\"></span> ");
        output.Content.Append(Text);
    }
}
```

Option A preserves the existing call sites (`@Html.IconLink(...)`). Option B is the ASP.NET Core idiomatic approach and uses `<icon-link text="Click" icon="fa-home"></icon-link>` syntax. Prefer Option A during migration to minimize view changes, then refactor to Option B as a follow-up.

Replace `HttpUtility.HtmlEncode` with `HtmlEncoder.Default.Encode` (from `System.Text.Encodings.Web`). Replace `MvcHtmlString` / `HtmlString` from `System.Web` with `HtmlString` from `Microsoft.AspNetCore.Html` or the `IHtmlContent` interface.

### Step 7: Update View Data Passing Patterns

These patterns are mostly compatible but have behavioral differences:

- **`@model`** — fully compatible, no changes needed.
- **`ViewBag`** — works in ASP.NET Core MVC controllers and views. Not available in Razor Pages.
- **`ViewData`** — works in ASP.NET Core. The `ViewData["Title"]` pattern for page titles is the standard approach.
- **`TempData`** — works in ASP.NET Core but the default backing store changed from session state to cookies (`CookieTempDataProvider`). If the app stores large objects in `TempData`, configure `SessionStateTempDataProvider` in `Program.cs`:

```csharp
builder.Services.AddControllersWithViews()
    .AddSessionStateTempDataProvider();
builder.Services.AddSession();
```

- **`WebViewPage<T>`** — if the project uses a custom base class derived from `WebViewPage<T>`, migrate to a custom `RazorPage<T>` base class or use `_ViewImports.cshtml` with `@inject` directives instead.

### Step 8: Clean Up Removed APIs

Search for and remove these patterns that have no direct equivalent in ASP.NET Core:

| Pattern | Action |
|---------|--------|
| `@helper { }` blocks | Convert to partial views or TagHelpers |
| `Html.Action()` / `Html.RenderAction()` | Converted in Step 4 |
| `ViewEngines.Engines` registration | Converted in Step 2 — remove after the formats reach `RazorViewEngineOptions` |
| `RazorViewEngine` / `VirtualPathProviderViewEngine` subclasses | Delete once their formats or lookup logic are ported (Step 2) |
| `[ChildActionOnly]` | Remove — ViewComponents are not callable as actions by default |
| `MvcHtmlString` | Replace with `IHtmlContent` or `HtmlString` |
| `System.Web.Mvc` usings | Replace with `Microsoft.AspNetCore.Mvc` |
| `System.Web.WebPages` usings | Remove — Razor is built into ASP.NET Core MVC |
| `HttpUtility.HtmlEncode` | Replace with `HtmlEncoder.Default.Encode` |

For bundling cleanup (`@Scripts.Render`, `@Styles.Render`, `BundleConfig.cs`), follow the `migrating-mvc-bundling` skill.

### Step 9: Verify Build

Build the project to confirm no compilation errors. Search for any remaining `System.Web` references in `.cshtml` and `.cs` files. Common post-migration build errors:

- **Missing TagHelper attributes**: Verify `@addTagHelper` directive in `_ViewImports.cshtml`.
- **`Html.Partial` errors**: Replace synchronous `Html.Partial` with `<partial>` TagHelper.
- **`MvcHtmlString` not found**: Replace with `IHtmlContent`.
- **`InvalidOperationException: The view '...' was not found`**: The message lists every location searched. Compare that list against the formats recorded in Step 2 — a missing entry or a lost `Clear()` is the usual cause.

## HtmlHelper to TagHelper Quick Reference

| ASP.NET MVC HtmlHelper | ASP.NET Core TagHelper |
|------------------------|----------------------|
| `@Html.ActionLink("text", "action", "ctrl")` | `<a asp-controller="ctrl" asp-action="action">text</a>` |
| `@Html.BeginForm("action", "ctrl")` | `<form asp-controller="ctrl" asp-action="action">` |
| `@Html.TextBoxFor(m => m.Prop)` | `<input asp-for="Prop" />` |
| `@Html.TextAreaFor(m => m.Prop)` | `<textarea asp-for="Prop"></textarea>` |
| `@Html.CheckBoxFor(m => m.Prop)` | `<input asp-for="Prop" />` |
| `@Html.RadioButtonFor(m => m.Prop, val)` | `<input asp-for="Prop" value="val" />` |
| `@Html.DropDownListFor(m => m.Prop, items)` | `<select asp-for="Prop" asp-items="items"></select>` |
| `@Html.ListBoxFor(m => m.Prop, items)` | `<select asp-for="Prop" asp-items="items" multiple></select>` |
| `@Html.HiddenFor(m => m.Prop)` | `<input asp-for="Prop" type="hidden" />` (or `<input type="hidden" asp-for="Prop" />`) |
| `@Html.LabelFor(m => m.Prop)` | `<label asp-for="Prop"></label>` |
| `@Html.ValidationMessageFor(m => m.Prop)` | `<span asp-validation-for="Prop"></span>` |
| `@Html.ValidationSummary()` | `<div asp-validation-summary="All"></div>` |
| `@Html.Partial("_Name")` | `<partial name="_Name" />` |
| `@Html.Action("Act", "Ctrl")` | `@await Component.InvokeAsync("Act")` |
| `@Html.AntiForgeryToken()` | Automatic with form TagHelper (`method="post"`) |
| `@Url.Action("act", "ctrl")` | `@Url.Action("act", "ctrl")` (compatible) |

## Success Criteria

- `_ViewImports.cshtml` exists with `@addTagHelper` directive
- Custom view-location formats ported to `RazorViewEngineOptions` with their original order preserved, or confirmed that the app registered no custom view engine
- No `ViewEngines.Engines` registration or `RazorViewEngine` / `VirtualPathProviderViewEngine` subclass remains
- All `@Html.ActionLink`, `@Html.BeginForm`, `@Html.TextBoxFor`, and similar calls replaced with TagHelpers
- All `@Html.Action` / `@Html.RenderAction` calls replaced with ViewComponent invocations
- All `@Html.Partial` / `@Html.RenderPartial` calls replaced with `<partial>` TagHelper
- Custom HtmlHelper extensions updated to return `IHtmlContent`
- No `[ChildActionOnly]`, `MvcHtmlString`, `System.Web.Mvc`, or `@helper` blocks remain
- ViewComponent classes created with corresponding views under `Views/Shared/Components/`
- Bundle references migrated per `migrating-mvc-bundling` skill
- Project builds without errors
