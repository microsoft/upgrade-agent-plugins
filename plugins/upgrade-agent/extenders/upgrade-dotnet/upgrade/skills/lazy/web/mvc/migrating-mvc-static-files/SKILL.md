---
name: migrating-mvc-static-files
description: >
  Migrates ASP.NET MVC static file serving and virtual path providers to ASP.NET Core conventions.
  Moves Content/, Scripts/, and App_Data/ folders into wwwroot/, configures UseStaticFiles middleware,
  and replaces VirtualPathProvider with IFileProvider and EmbeddedFileProvider. Use when upgrading MVC
  apps that serve CSS from ~/Content/, JS from ~/Scripts/, use VirtualPathProvider, serve embedded
  resources, or store files in App_Data. Also triggers for "configure static files in Core", "wwwroot
  migration", "embedded resource serving", or "files outside wwwroot".
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET MVC Static Files and Asset Serving Migration

## Overview

ASP.NET Framework serves any file from the project root automatically. ASP.NET Core does not — static files are only served from `wwwroot/` by default, and the `UseStaticFiles` middleware must be explicitly registered. This skill migrates the folder layout, configures the middleware, and replaces `VirtualPathProvider` with `IFileProvider`.

> **Related skill:** `migrating-mvc-bundling` handles bundle reference conversion. Complete bundling migration first so the files referenced by `<script>`/`<link>` tags are already in `wwwroot/`.

## Workflow

Track progress across these steps:

```
Migration Progress:
- [ ] Step 1: Audit existing static file locations
- [ ] Step 2: Create wwwroot structure and move files
- [ ] Step 3: Register static file middleware
- [ ] Step 4: Update path references in views and code
- [ ] Step 5: Migrate VirtualPathProvider to IFileProvider
- [ ] Step 6: Configure files outside wwwroot (if needed)
- [ ] Step 7: Remove legacy folder references
```

### Step 1: Audit Existing Static File Locations

Search the project for static assets and note where they live:

- `Content/` — CSS files, images, fonts
- `Scripts/` — JavaScript files
- `App_Data/` — data files (not served in Core by default)
- Files in the project root or other custom folders
- Embedded resources referenced via `VirtualPathProvider`

Check `Web.config` for any `<staticContent>` MIME type mappings or custom `<handlers>` for static files. These will need equivalent configuration in Core.

### Step 2: Create wwwroot Structure and Move Files

Create the `wwwroot/` folder at the project root and move assets into it following ASP.NET Core conventions:

**Before (ASP.NET MVC):**
```
MyApp/
├── Content/
│   ├── Site.css
│   └── images/
│       └── logo.png
├── Scripts/
│   ├── jquery-3.6.0.min.js
│   └── site.js
├── App_Data/
│   └── data.json
├── fonts/
│   └── custom.woff2
└── Web.config
```

**After (ASP.NET Core):**
```
MyApp/
├── wwwroot/
│   ├── css/
│   │   └── Site.css
│   ├── js/
│   │   ├── jquery-3.6.0.min.js
│   │   └── site.js
│   ├── images/
│   │   └── logo.png
│   ├── fonts/
│   │   └── custom.woff2
│   └── data/
│       └── data.json    (only if public access needed)
├── App_Data/
│   └── data.json        (keep here if private — read via file I/O)
└── Program.cs
```

Key decisions:
- `Content/` → `wwwroot/css/` (rename to match Core convention)
- `Scripts/` → `wwwroot/js/` (rename to match Core convention)
- Images and fonts → `wwwroot/images/`, `wwwroot/fonts/`
- `App_Data/` files that need web access → `wwwroot/data/`; files that should stay private → keep outside `wwwroot/` and access via `IWebHostEnvironment.ContentRootPath`

Ensure the project file includes `wwwroot/` as web root content. SDK-style projects handle this automatically when the folder exists.

### Step 3: Register Static File Middleware

Add `UseStaticFiles()` in `Program.cs`. Order matters — place it before routing middleware:

**Before (ASP.NET MVC — implicit, no code needed):**
```csharp
// Static files served automatically by IIS/ASP.NET pipeline
```

**After (ASP.NET Core):**
```csharp
var app = builder.Build();

app.UseStaticFiles(); // Serves files from wwwroot/

app.UseRouting();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
```

To add custom MIME types (replacing `Web.config` `<staticContent>` entries):

```csharp
var provider = new FileExtensionContentTypeProvider();
provider.Mappings[".webmanifest"] = "application/manifest+json";

app.UseStaticFiles(new StaticFileOptions
{
    ContentTypeProvider = provider
});
```

To configure cache headers for static files:

```csharp
app.UseStaticFiles(new StaticFileOptions
{
    OnPrepareResponse = ctx =>
    {
        ctx.Context.Response.Headers.Append("Cache-Control", "public,max-age=31536000");
    }
});
```

### Step 4: Update Path References in Views and Code

Update all references to the old folder paths in Razor views, CSS files, and C# code.

**Razor views — `~/Content/` and `~/Scripts/` references:**

Before:
```cshtml
<link href="~/Content/Site.css" rel="stylesheet" />
<script src="~/Scripts/site.js"></script>
<img src="~/Content/images/logo.png" alt="Logo" />
```

After:
```cshtml
<link href="~/css/Site.css" rel="stylesheet" />
<script src="~/js/site.js"></script>
<img src="~/images/logo.png" alt="Logo" />
```

The `~/` prefix continues to work in ASP.NET Core Razor views — it resolves to `wwwroot/`.

**CSS files — relative paths:**

Before:
```css
background-image: url('../Content/images/logo.png');
```

After:
```css
background-image: url('../images/logo.png');
```

**C# code — `Server.MapPath` and `HostingEnvironment.MapPath`:**

Before:
```csharp
var path = Server.MapPath("~/App_Data/data.json");
var path2 = HostingEnvironment.MapPath("~/Content/templates/report.html");
```

After:
```csharp
// Inject IWebHostEnvironment via constructor
var path = Path.Combine(_env.ContentRootPath, "App_Data", "data.json");
var path2 = Path.Combine(_env.WebRootPath, "templates", "report.html");
```

Use `ContentRootPath` for private files outside `wwwroot/` and `WebRootPath` for public files inside `wwwroot/`.

### Step 5: Migrate VirtualPathProvider to IFileProvider

ASP.NET MVC's `VirtualPathProvider` has no direct replacement. ASP.NET Core uses `IFileProvider` for the same purpose.

**Embedded resource serving:**

Before (ASP.NET MVC):
```csharp
// Custom VirtualPathProvider registered in Global.asax
HostingEnvironment.RegisterVirtualPathProvider(new EmbeddedResourceProvider());
```

After (ASP.NET Core):
```csharp
var embeddedProvider = new EmbeddedFileProvider(
    typeof(Program).Assembly,
    "MyApp.EmbeddedAssets");

app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = embeddedProvider,
    RequestPath = "/embedded"
});
```

Mark resources as embedded in the project file:
```xml
<ItemGroup>
  <EmbeddedResource Include="EmbeddedAssets/**/*" />
</ItemGroup>
```

**Custom file system sources:**

Before (ASP.NET MVC):
```csharp
public class DatabaseVirtualPathProvider : VirtualPathProvider
{
    public override bool FileExists(string virtualPath) { /* ... */ }
    public override VirtualFile GetFile(string virtualPath) { /* ... */ }
}
```

After (ASP.NET Core):
```csharp
public class DatabaseFileProvider : IFileProvider
{
    public IFileInfo GetFileInfo(string subpath) { /* ... */ }
    public IDirectoryContents GetDirectoryContents(string subpath) { /* ... */ }
    public IChangeToken Watch(string filter) => NullChangeToken.Singleton;
}
```

Register the custom provider:
```csharp
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new DatabaseFileProvider(connectionString),
    RequestPath = "/dynamic"
});
```

To compose multiple providers (equivalent to chaining `VirtualPathProvider` instances):
```csharp
var compositeProvider = new CompositeFileProvider(
    builder.Environment.WebRootFileProvider,
    new EmbeddedFileProvider(typeof(Program).Assembly),
    new DatabaseFileProvider(connectionString));

app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = compositeProvider
});
```

### Step 6: Configure Files Outside wwwroot

Files outside `wwwroot/` are not served by default. To serve files from additional directories, add a second `UseStaticFiles` call with an explicit `PhysicalFileProvider`:

```csharp
app.UseStaticFiles(); // Default: serves from wwwroot/

app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(
        Path.Combine(builder.Environment.ContentRootPath, "StaticAssets")),
    RequestPath = "/assets"
});
```

Skip this step if all public assets fit under `wwwroot/`. Serving files from outside `wwwroot/` adds complexity — prefer moving files into `wwwroot/` when possible.

### Step 7: Remove Legacy Folder References

Search the codebase for remaining references to the old folder structure and clean them up:

- Remove `Content/`, `Scripts/` folders (now empty after move)
- Remove `VirtualPathProvider` registration from `Global.asax` or startup
- Remove `<staticContent>` entries from `Web.config` (if `Web.config` is being removed)
- Remove `HostingEnvironment.MapPath` and `Server.MapPath` calls
- Remove `HostingEnvironment.RegisterVirtualPathProvider` calls
- Update any build scripts or CI pipelines that reference old paths

## Success Criteria

- `wwwroot/` folder exists with `css/`, `js/`, `images/` subfolders following Core conventions
- `app.UseStaticFiles()` registered in `Program.cs` before routing middleware
- All `~/Content/` and `~/Scripts/` references updated to `~/css/` and `~/js/`
- `Server.MapPath`/`HostingEnvironment.MapPath` replaced with `IWebHostEnvironment` paths
- `VirtualPathProvider` replaced with `IFileProvider`/`EmbeddedFileProvider` (if applicable)
- Custom MIME types from `Web.config` migrated to `FileExtensionContentTypeProvider`
- No remaining references to `Content/`, `Scripts/`, or `VirtualPathProvider`
- Project builds without errors
