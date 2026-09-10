---
name: migrating-mvc-bundling
description: >
  Migrates ASP.NET MVC bundling and minification from System.Web.Optimization to direct
  script/link tags in ASP.NET Core Razor views. Use when upgrading .NET Framework MVC apps that
  use BundleTable.Bundles, BundleConfig.cs, ScriptBundle, StyleBundle, @Scripts.Render, or
  @Styles.Render. Triggers for bundling migration, removing System.Web.Optimization, converting
  bundle references to static file references, or modernizing script/style includes in .cshtml
  files.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Bundling and Minification Migration

Converts .NET Framework MVC bundling (`System.Web.Optimization`) to direct `<script>`/`<link>` tags pointing at static files under `wwwroot/`. ASP.NET Core serves static files from `wwwroot/` instead of using a bundling pipeline, so every bundle reference must be replaced with explicit file references.

## Workflow

```
Progress:
- [ ] Step 1: Inventory bundle registrations
- [ ] Step 2: Replace bundle references in Razor files
- [ ] Step 3: Remove BundleConfig and related code
- [ ] Step 4: Remove System.Web.Optimization usings
- [ ] Step 5: Verify build
```

### Step 1: Inventory bundle registrations

Search for `BundleTable.Bundles` across the project. The registration is typically in a file named `BundleConfig.cs` but may be elsewhere. Record every bundle name and its included file paths — these are needed to expand references in Step 2.

Example registration to look for:
```csharp
bundles.Add(new ScriptBundle("~/bundles/jquery").Include(
    "~/Scripts/jquery-{version}.js"));
bundles.Add(new StyleBundle("~/Content/css").Include(
    "~/Content/site.css"));
```

### Step 2: Replace bundle references in Razor files

Search all `.cshtml` files for `@Scripts.Render` and `@Styles.Render` calls. Replace each call with the corresponding direct tags, using the file paths recorded in Step 1. Convert paths to be relative to `wwwroot/` because ASP.NET Core's static file middleware serves from that directory.

**Before:**
```cshtml
@section Scripts {
    @Scripts.Render("~/bundles/jqueryval")
}
```

**After:**
```cshtml
@section Scripts {
    <script src="~/scripts/jquery.min.js"></script>
    <script src="~/scripts/jquery.validate.min.js"></script>
}
```

For style bundles, use `<link rel="stylesheet" href="~/css/site.css" />` instead of `@Styles.Render`.

### Step 3: Remove BundleConfig and related code

Remove the bundle registration code found in Step 1. If the class (commonly `BundleConfig`) contains only bundling code, delete the entire file. Clean up all references to the removed class — check `Global.asax.cs`, `Startup.cs`, and any other files that call the registration method.

### Step 4: Remove System.Web.Optimization usings

Search all `.cs` files for `using System.Web.Optimization` and remove those statements. This ensures no stale namespace references remain.

### Step 5: Verify build

Build the project to confirm no compilation errors from removed references. Check for any remaining references to `System.Web.Optimization` or `BundleTable`.

## Success Criteria

- No `@Scripts.Render` or `@Styles.Render` calls remain in `.cshtml` files
- All script/style paths are relative to `wwwroot/`
- No `System.Web.Optimization` references remain in any `.cs` file
- Bundle registration code and its call sites are removed
- Project builds without errors
