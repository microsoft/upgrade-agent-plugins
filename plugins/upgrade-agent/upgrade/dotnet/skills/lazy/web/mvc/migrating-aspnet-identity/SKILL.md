---
name: migrating-aspnet-identity
description: >
  Migrates ASP.NET MVC Identity to ASP.NET Core Identity, updating IdentityDbContext, UserManager,
  SignInManager, authentication middleware, and OWIN cleanup. Use when upgrading ASP.NET MVC
  projects that use Identity authentication, migrating Identity-based login systems, or converting
  OWIN-based auth to ASP.NET Core middleware. Triggers for Identity migration, auth upgrade,
  UserManager refactor, IdentityDbContext conversion, and OWIN removal.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# ASP.NET Identity to ASP.NET Core Identity Migration

## Overview

Migrates ASP.NET MVC Identity to ASP.NET Core Identity: DbContext conversion, service registration, namespace updates, API changes, and OWIN cleanup.

## Prerequisite

Verify the project uses ASP.NET Identity (e.g., references `Microsoft.AspNet.Identity` or `IdentityDbContext`). If not, skip and inform the user there is nothing to do.

## Workflow

```
Migration Progress:
- [ ] Step 1: Install required packages
- [ ] Step 2: Update IdentityDbContext
- [ ] Step 3: Register DbContext and Identity in Program.cs
- [ ] Step 4: Add Identity middleware
- [ ] Step 5: Update Identity API usage
- [ ] Step 6: Update AccountController
- [ ] Step 7: Clean up OWIN identity code
```

### Step 1: Install Required Packages

Ensure these NuGet packages are installed in the project (version major should match project's target framework):
- `Microsoft.AspNetCore.Identity.EntityFrameworkCore`
- `Microsoft.EntityFrameworkCore.SqlServer`
- `Microsoft.AspNetCore.Identity.UI`
- `Microsoft.AspNetCore.Authentication.Cookies` (latest version)

### Step 2: Update IdentityDbContext

Find the DbContext class inheriting `IdentityDbContext` and:
- Determine its connection string name. If undeterminable, ask the user.
- If the connection string name is known, find it in `web.config` or `app.config` and add it to `appsettings.json` under `ConnectionStrings` with the same name (if not already present).
- Replace old identity namespaces (`Microsoft.AspNet.Identity`, `System.Web.Identity`) with `Microsoft.AspNetCore.Identity`.
- Convert the constructor to accept `DbContextOptions` instead of a connection string.

When refactoring DbContext and related models, only change types that differ in ASP.NET Core Identity. Preserve all business logic unrelated to the identity system — removing it would break application behavior that has nothing to do with the migration.

**Before:**
```csharp
public class ApplicationDbContext : IdentityDbContext<ApplicationUser>
{
    public ApplicationDbContext() : base("DefaultConnection")
    {
    }
}
```

**After:**
```csharp
public class ApplicationDbContext : IdentityDbContext<ApplicationUser>
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }
    
    // ... other DbSets and configuration
}
```

### Step 3: Register DbContext and Identity in Program.cs

Register the DbContext in the `Program.cs` file using connection string name you discovered earlier and correct model class names:

```csharp
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("ConnectionStringName")));

builder.Services.AddIdentity<ApplicationUser, IdentityRole>()
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddDefaultTokenProviders();
```

Add necessary `using` statements (e.g., `using Microsoft.Extensions.Configuration;`) as needed.

### Step 4: Add Identity Middleware

Ensure `Program.cs` contains the Identity middleware in the correct order:

```csharp
app.UseAuthentication();
app.UseAuthorization();
```

### Step 5: Update Identity API Usage

Update identity API calls across all `.cs` and `.cshtml` files:
- Replace old identity namespaces (`Microsoft.AspNet.Identity`, `System.Web.Identity`) with `Microsoft.AspNetCore.Identity`.
- Replace `User.Identity.GetUserId()` with `UserManager.GetUserId(User)`.
- Replace `Html.BeginForm("Login", "Account", FormMethod.Post)` with tag helpers: `<form asp-action="Login" asp-controller="Account" method="post">` in Razor views under `Views/Account`.

### Step 6: Update AccountController

Update the `AccountController` constructor to inject `UserManager<ApplicationUser>` and `SignInManager<ApplicationUser>` (use the project's actual `IdentityUser` subclass as the generic parameter).

If the old constructor had legacy identity-related parameters (e.g., `ApplicationUserManager`), replace them with the new types and update all corresponding properties and references.

### Step 7: Clean Up OWIN Identity Code

Remove any OWIN code that registered identity classes. If `Startup.cs` and `Startup.Auth.cs` are empty or have no remaining non-identity configuration, delete them. If other OWIN configuration remains, propose migrating it to ASP.NET Core middleware and call the feature instructions tool for OWIN removal guidance if the user agrees.


