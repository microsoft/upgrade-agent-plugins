---
name: migrating-webforms-to-blazor-server
description: >
  Migrates ASP.NET Web Forms applications to Blazor Server using Blazor patterns. Handles
  complete migration: Blazor project setup (side-by-side or in-place), Routes component
  configuration, App.razor InteractiveServer render modes, static asset migration
  (Content/Scripts/Images to wwwroot), markup conversion (.aspx/.ascx/.master to .razor), control
  translation (asp: prefix removal to native HTML/Blazor components), Web Forms expression block
  conversion to Razor syntax, lifecycle mapping (Page_Load to OnInitializedAsync), and Master
  pages to Layouts. Use when migrating Web Forms to Blazor Server, converting .aspx pages with
  CSS/JavaScript compatibility, or fixing build errors for System.Web.UI types (Page, Control),
  ViewState, Response.Redirect, Server.MapPath, asp: controls, or Web Forms namespaces.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Web Forms to Blazor Server Migration

Migrate ASP.NET Web Forms applications to Blazor Server using Blazor patterns. This skill provides complete migration guidance including project setup, configuration, and page conversion.
## Overview

This skill covers end-to-end migration of Web Forms pages to Blazor components — replacing `asp:` server controls with HTML elements and Blazor directives, migrating code-behind lifecycles to component lifecycles, and converting master pages to layouts.

## Related Skills

**Reference guide for conditional/alternative approaches.** These skills address specific migration scenarios you may encounter based on your project's data access patterns, authentication system, and technology stack. The workflow steps below contain explicit instructions on when to invoke each skill.

| Skill | Use For |
|-------|---------|
| **managing-blazor-server-authentication** | Authentication setup, cookie auth in circuits, HttpContext NULL errors |
| **managing-blazor-server-data-access** | Data access, Session state in circuits, DbContext factory pattern, shopping cart persistence (referenced in Step 5 for data layer migration) |
| **migrating-mvc-static-files** | Static file migration from Content/Scripts to wwwroot (executed in Step 2) |

---

## Workflow

Complete migration tasks in order. Reference the child documents for detailed transformation patterns and control mappings.

```
Migration Progress:
- [ ] Step 1: Prepare Blazor project
- [ ] Step 2: Migrate static assets to wwwroot
- [ ] Step 3: Configure _Imports.razor
- [ ] Step 4: Configure App.razor render mode
- [ ] Step 5: Copy/rename files
- [ ] Step 6: Transform markup to Blazor
- [ ] Step 7: Transform code-behind
- [ ] Step 8: Build and validate
```

---

## Step 1: Prepare Blazor Project

Inspect the workspace and user intent to determine the migration approach automatically:

**Check for explicit user instruction:**
- If user explicitly requested creating a new Blazor project → use **side-by-side migration**
- If user explicitly requested converting the project in place → use **in-place migration**
- If user requested moving/migrating specific pages without mentioning a new project → check workspace context (next)

**If user intent is unclear, check workspace:**
1. Search the solution for existing Blazor projects (projects with `<Project Sdk="Microsoft.NET.Sdk.Web">` and Blazor framework references)
2. If no Blazor project exists in the solution → use **side-by-side migration** (create new project)
3. If a Blazor project already exists → use **in-place migration** (migrate into existing project)

**Apply the determined approach:**

**For side-by-side migration:**
```bash
dotnet new blazor -n MyBlazorApp --interactivity Server
```

**For in-place migration:**
1. Identify the target project (existing Blazor project, or the WebForms project being converted)
2. If converting a WebForms project, ensure it is SDK-style and targets .NET 6+ first (use the SDK-style conversion skill if needed)
3. Add the Blazor framework reference to the project file:
   ```xml
   <ItemGroup>
     <FrameworkReference Include="Microsoft.AspNetCore.App" />
   </ItemGroup>
   ```
4. Create or update `Program.cs` with standard Blazor Server hosting setup if not already present
5. Add `App.razor`, `_Imports.razor`, and a layout file if they don't exist

### Database Provider Detection (If Using Entity Framework)

If the Web Forms project has a `Models/` directory or uses Entity Framework, check the `Web.config` connection strings to determine the database provider:

| Web.config Indicator | Database Provider | EF Core Package to Install |
|---------------------|-------------------|---------------------------|
| `providerName="System.Data.SqlClient"` | SQL Server | `Microsoft.EntityFrameworkCore.SqlServer` |
| `providerName="System.Data.SQLite"` | SQLite | `Microsoft.EntityFrameworkCore.Sqlite` |
| `providerName="Npgsql"` | PostgreSQL | `Npgsql.EntityFrameworkCore.PostgreSQL` |
| `providerName="MySql.Data.MySqlClient"` | MySQL | `Pomelo.EntityFrameworkCore.MySql` |

**Add the detected provider to your Blazor project:**
```bash
# Example for SQL Server
dotnet add package Microsoft.EntityFrameworkCore.SqlServer
dotnet add package Microsoft.EntityFrameworkCore.Tools
```

**Important:** Use the **same database provider** as the original Web Forms project. Do not change providers (e.g., SQL Server → SQLite) unless explicitly required, as this can cause data type compatibility issues.

---

## Step 2: Migrate Static Assets to wwwroot

**Execute the `migrating-mvc-static-files` skill** to migrate Content/Scripts/Images to wwwroot. Complete all steps in that skill, then return here for Blazor-specific additions. That skill handles:
- Content/Scripts/Images folders to wwwroot/css/js/images migration
- wwwroot directory structure creation
- UseStaticFiles middleware configuration
- Path reference updates in views and code
- VirtualPathProvider to IFileProvider replacement
- Files outside wwwroot configuration

**After completing the static file migration skill, apply these Blazor-specific additions:**

1. **Add CSS/JS references to `App.razor` preserving bundle order**:

   CSS order matters for cascade rules. Check `App_Start/BundleConfig.cs` for the StyleBundle's `.Include()` calls and add `<link>` tags in `App.razor` **in the same order**. Verify all referenced CSS files exist in `wwwroot/css/`.

   ```razor
   <!DOCTYPE html>
   <html>
   <head>
       <!-- Original site stylesheets - preserve BundleConfig.cs order -->
       <link rel="stylesheet" href="css/bootstrap.min.css" />
       <link rel="stylesheet" href="css/Site.css" />
   </head>
   <body>
       <!-- Original site scripts -->
       <script src="js/jquery-3.7.1.min.js"></script>
       <script src="js/bootstrap.bundle.min.js"></script>
       <script src="js/Site.js"></script>
   </body>
   </html>
   ```

> ⚠️ **WARNING:** The `bootstrap` NuGet package does not expose files through `_content/bootstrap/` in Blazor Server. Copy Bootstrap files from the original `Content/` folder to `wwwroot/css/` to preserve the exact version and avoid class name changes required by version upgrades.

**Search for additional static asset folders** beyond Content/Scripts/Images (e.g., `Pics`, `Files`, `Uploads`, `Documents`). Check for image/document file types and hardcoded paths in service classes, then migrate any found folders to `wwwroot/` preserving their names.

---

## Step 3: Configure `_Imports.razor`

```razor
@using Microsoft.AspNetCore.Components
@using Microsoft.AspNetCore.Components.Web
@using static Microsoft.AspNetCore.Components.Web.RenderMode
```

> **Note:** The `@using static` import lets you write `InteractiveServer` as shorthand in `App.razor`. Do **not** add `@rendermode InteractiveServer` as a line in `_Imports.razor` — `@rendermode` is a directive attribute that belongs on component instances, not a standalone directive.

---

## Step 4: Configure Render Mode in `App.razor`

The `dotnet new blazor --interactivity Server` template generates `App.razor` with render mode already set. Verify it contains:

```razor
<HeadOutlet @rendermode="InteractiveServer" />
...
<Routes @rendermode="InteractiveServer" />
```

This enables global server interactivity for all pages. See [ASP.NET Core Blazor render modes](https://learn.microsoft.com/aspnet/core/blazor/components/render-modes) for per-page alternatives.

---

## Step 5: Copy/Move and Rename Files

Based on the migration approach determined in Step 1:

**For side-by-side migration:** Copy files from the WebForms project to the Blazor project and rename them. Place them in the Blazor project respecting Blazor conventions (pages in `/Components/Pages/`, layouts in `/Components/Layout/`, shared components in `/Components/`).

**For in-place migration:** Rename files in place within the same project. They can stay in their current locations initially.

| Original | New Name | Notes |
|----------|----------|-------|
| `MyPage.aspx` | `MyPage.razor` | Page markup |
| `MyPage.aspx.cs` | `MyPage.razor.cs` | Code-behind (keep as partial class) |
| `MyControl.ascx` | `MyControl.razor` | User control markup |
| `MyControl.ascx.cs` | `MyControl.razor.cs` | User control code-behind |
| `Site.Master` | `MainLayout.razor` | Master page → Layout |
| `Site.Master.cs` | `MainLayout.razor.cs` | Layout code-behind |

### Additional Files to Copy

**Models and Business Logic directories:**
If the WebForms project has `Models/`, `BLL/`, `BusinessLogic/`, or `Services/` folders, copy all `.cs` files to the Blazor project preserving directory structure.

> **Data layer migration:** EF6 namespace updates, DbContext configuration, connection strings, and session state migration are handled by **`managing-blazor-server-data-access`**. Execute that skill when:
> - Build errors reference `System.Data.Entity` namespaces
> - User asks about data access, Entity Framework, or database setup  
> - Session state or shopping cart functionality needs migration
> - After markup migration is complete (if deferring data concerns)
---

## Step 6: Transform Markup to Blazor Components

Apply these mechanical transformations to each `.razor` file:

**Control conversions (native HTML/Blazor):**
- `<asp:Label>` → `<label>` or `@value` inline
- `<asp:TextBox>` → `<input @bind="value" />`
- `<asp:Button>` → `<button @onclick="Handler">Text</button>`
- `<asp:DropDownList>` → `<select @bind="value">@foreach...</select>`
- `<asp:GridView>` → `<table>` with `@foreach` rows (or `QuickGrid` for advanced scenarios)
- `<asp:ListView>` / `<asp:Repeater>` → `@foreach` loop with custom markup
- `<asp:RequiredFieldValidator>` etc. → `<EditForm>` with `<DataAnnotationsValidator>` and `<ValidationMessage For="...">`
- `<asp:Login>` → `<form method="post">` → minimal API endpoint (see managing-blazor-server-authentication)
- `<asp:LoginView>` → `<AuthorizeView>` with `<NotAuthorized>` / `<Authorized>` templates
- `<asp:LoginName>` → `@context.User.Identity?.Name` inside `<AuthorizeView>`
- See **[references/control-reference.md](references/control-reference.md)** for complete mapping table

**Directive conversions:**
- `<%@ Page Title="X" ... %>` → `@page "/route"` (derive route from file path)
- `<%@ Master ... %>` → `@inherits LayoutComponentBase`
- `<%@ Control ... %>` → (remove entirely for user controls)
- `<%@ Import Namespace="X" %>` → `@using X`
- Remove directive attributes: `AutoEventWireup`, `CodeBehind`, `Inherits`, `EnableViewState`, `MasterPageFile`

**Expression conversions:**
- `<%: expr %>` → `@(expr)`
- `<%= expr %>` → `@(expr)`
- `<%# Item.Property %>` → `@context.Property` (in templates)
- `<%# Eval("Property") %>` → `@context.Property`
- `<%# Bind("Property") %>` → `@bind-Value="context.Property"`
- `<%-- comment --%>` → `@* comment *@`
- `<% if (x) { %>` → `@if (x) {`
- `<% } %>` → `}`

**URL conversions:**
- `href="~/path"` → `href="/path"`
- `NavigateUrl="~/path"` → `NavigateUrl="/path"`
- `ImageUrl="~/images/x.png"` → `ImageUrl="/images/x.png"`

**Content/Layout conversions:**
- Remove `<asp:Content ContentPlaceHolderID="MainContent">...</asp:Content>` wrappers (keep inner content)
- `<asp:Content ContentPlaceHolderID="HeadContent">` → `<HeadContent>`
- `<asp:ContentPlaceHolder ID="MainContent" />` → `@Body` (in layouts)
- `<form runat="server">` → `<div>` (preserves CSS block formatting context)

Read **[references/markup-transforms.md](references/markup-transforms.md)** for complete transformation tables and examples.

---

## Step 7: Transform Code-Behind (Structural)

For each `.razor.cs` file, apply these structural transformations. Read **[references/code-transforms.md](references/code-transforms.md)** for detailed patterns:

**Lifecycle conversions:**
- `Page_Load` → `OnInitializedAsync` (for first-load initialization)
- `Page_PreRender` → `OnParametersSetAsync` (for pre-render logic)
- Remove `if (!IsPostBack)` guards — `OnInitializedAsync` runs once on first render (no postback concept)

> ⚠️ **Parameter-driven data loading:** If the page loads data based on route parameters 
> or query strings (e.g., category ID, product ID), use `OnParametersSetAsync` instead of 
> `OnInitializedAsync`. Unlike Web Forms postbacks, Blazor reuses component instances when 
> only the route parameter changes — `OnInitializedAsync` won't re-run, but 
> `OnParametersSetAsync` will.

**Event handler signatures:**
- Remove `object sender, EventArgs e` parameters
- Change `protected void` → `private void` (or `async Task`)

**Navigation:**
- `Response.Redirect("~/path")` → `NavigationManager.NavigateTo("/path")`
- Add `@inject NavigationManager NavigationManager` to `.razor` file

**Page title:**
- `Page.Title = "..."` in code-behind → `<PageTitle>...</PageTitle>` in markup

**Data loading:**
- Load data in `OnInitializedAsync` using injected services
- Bind data to component properties and render with `@foreach`
- Inject required services (`@inject ProductService ProductService`)

**State management:**
- `ViewState["key"]` → component field (`private string _value;`)
- `Session["key"]` → scoped DI service pattern

Read **[references/code-transforms.md](references/code-transforms.md)** for detailed patterns.

## Step 8: Build and Validate Migration Quality

Build the project and verify migration completeness:

```bash
dotnet build
```

**After successful build, review migration completeness:**

1. **Check that controls were converted to Blazor:**

   Search `.razor` files to verify Web Forms server controls were replaced:

   - ✅ Files contain native HTML/components like `<input`, `<div`, `<button`, `<select`, `@foreach` loops
   - ⚠️ Any remaining `<asp:` prefixes or `runat="server"` attributes indicate incomplete migration

2. **Verify namespace imports in `_Imports.razor`:**

   ```razor
   @using Microsoft.AspNetCore.Components
   @using Microsoft.AspNetCore.Components.Web
   @using static Microsoft.AspNetCore.Components.Web.RenderMode
   ```

3. **Validate CSS/JavaScript compatibility:**

   If existing CSS or JavaScript depends on Web Forms HTML structure:
   - Run the application and test that styles and scripts still work correctly
   - Blazor renders standard HTML — you may need to adjust CSS selectors or JavaScript event handlers to match the new HTML structure

If migration issues remain after build validation, revisit the transformation references above and re-check lifecycle, data-binding, and control mapping patterns.

---

## Quick Reference

### Common Transformations

**Controls:** Remove `asp:` prefix, `runat="server"`, and replace with native HTML
```html
<!-- Before --> <asp:Label ID="lblName" runat="server" Text="Hello" />
<!-- After  --> <label>Hello</label>

<!-- Before --> <asp:TextBox ID="Name" runat="server" />
<!-- After  --> <input @bind="model.Name" />

<!-- Before --> <asp:Button Text="Submit" OnClick="Submit_Click" runat="server" />
<!-- After  --> <button @onclick="Submit_Click">Submit</button>
```

**Lifecycle:** Convert Page_Load to OnInitializedAsync
```csharp
// Before
protected void Page_Load(object sender, EventArgs e) { }

// After
protected override async Task OnInitializedAsync() { }
```

---

## Reference Documents

For detailed transformation patterns, control mappings, and troubleshooting:

- **[references/markup-transforms.md](references/markup-transforms.md)** — Directive conversion, expression syntax, URL transformations, form wrapper handling
- **[references/code-transforms.md](references/code-transforms.md)** — Lifecycle methods, event handlers, navigation, data binding SelectMethod patterns, query strings, Master Page to Layout migration
- **[references/control-reference.md](references/control-reference.md)** — Complete control translation tables mapping Web Forms controls to native HTML/Blazor equivalents, Ajax Control Toolkit migration, structural components, theming infrastructure


---

## Success Criteria

**Migration scope:**
- [ ] Migration approach determined (side-by-side or in-place)
- [ ] Target Blazor project created and configured
- [ ] All targeted Web Forms files identified

**File transformations:**
- [ ] All migrated files renamed with `.razor` extension
- [ ] All `asp:` prefixes removed from controls
- [ ] All `runat="server"` attributes removed
- [ ] Web Forms expressions converted to Razor syntax
- [ ] `~/` URLs replaced with `/`

**Data binding:**
- [ ] DataSource controls (`SqlDataSource`, `ObjectDataSource`, `EntityDataSource`) replaced with injected services
- [ ] Data loaded in component lifecycle methods (`OnInitializedAsync` / `OnParametersSetAsync`) as appropriate
- [ ] Lists/tables rendered using Blazor markup (`@foreach`, components such as `QuickGrid` when needed)

**Code-behind:**
- [ ] `Page_Load` → `OnInitializedAsync`
- [ ] `Response.Redirect` → `NavigationManager.NavigateTo`
- [ ] Master pages converted to Blazor layouts

**Validation:**
- [ ] Target project builds without errors
- [ ] Application runs and renders migrated pages correctly
- [ ] Interactive features (buttons, forms, navigation) function as expected
- [ ] For side-by-side: original WebForms project still builds and runs (if preservation is required)

