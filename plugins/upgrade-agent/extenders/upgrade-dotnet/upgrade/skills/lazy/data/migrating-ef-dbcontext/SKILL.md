---
name: migrating-ef-dbcontext
description: >
  Migrates Entity Framework DbContext registration from Global.asax/Startup to ASP.NET Core
  dependency injection in Program.cs. Handles both EF6 (classic Entity Framework) and EF Core
  patterns including connection string migration, DI registration, and database
  initializer/seeding migration. Use when upgrading ASP.NET to ASP.NET Core projects that use
  DbContext, Database.SetInitializer, or connection strings in web.config. Also triggers for
  "migrate DbContext", "register DbContext in DI", "move connection string to appsettings.json",
  or "convert EF6 to EF Core".
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Entity Framework DbContext Registration Migration

## Overview

Migrates DbContext initialization from legacy ASP.NET patterns (Global.asax, Startup.cs) to ASP.NET Core DI in Program.cs. The registration pattern differs between EF6 and EF Core — this skill handles both, including the decision point when a project uses both simultaneously.

## Prerequisites

Verify the project uses Entity Framework before proceeding. Search for `DbContext` subclasses in the codebase and check NuGet references for `EntityFramework` or `Microsoft.EntityFrameworkCore`. If neither is found, skip and inform the user.

### Dual EF Usage Decision

When both `EntityFramework` and `Microsoft.EntityFrameworkCore` packages are present, pause and ask the user which to use for main database logic. Common scenarios:

- **EF Core for Identity only**: User added EF Core for ASP.NET Core Identity but wants EF6 for business data (saves refactoring effort during initial migration)
- **Mid-refactoring**: User plans to fully switch to EF Core but hasn't removed EF6 dependencies yet

Record the user's choice — it determines the registration pattern in Steps 3 and 5.

## Workflow

Track progress through these steps:

```
Migration Progress:
- [ ] Step 1: Find DbContext classes and connection strings
- [ ] Step 2: Update DbContext constructors
- [ ] Step 3: Register DbContext in Program.cs
- [ ] Step 4: Replace direct instantiations with DI
- [ ] Step 5: Migrate database initialization and seeding
```

### Step 1: Find DbContext Classes and Connection Strings

Locate all `DbContext` subclasses — **exclude** `IdentityDbContext` subclasses (handled separately by identity migration). For each, find the connection string name passed to the base constructor.

- **Inline connection string found** → Add it to `appsettings.json` under `ConnectionStrings` with a descriptive key, then reference that key going forward
- **Connection string name found** (e.g., `"name=MyDb"`) → Copy the matching entry from `web.config`/`app.config` to `appsettings.json` under `ConnectionStrings`, preserving the same key

### Step 2: Update DbContext Constructors

Modify constructors to accept caller-provided configuration instead of hardcoded connection string names. This enables DI registration in the next step.

**EF6 — accept connection string parameter:**
```csharp
public class MyDBContext : DbContext
{
    public MyDBContext(string connectionString) : base(connectionString)
    {
    }
}
```

**EF Core — accept DbContextOptions:**
```csharp
public class MyDBContext : DbContext
{
    public MyDBContext(DbContextOptions<MyDBContext> options) : base(options)
    {
    }
}
```

### Step 3: Register DbContext in Program.cs

Registration differs by EF version because EF Core has built-in DI support via `AddDbContext`, while EF6 requires manual scoped registration.

**EF Core:**
```csharp
builder.Services.AddDbContext<MyDBContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("MyConnectionStringName")));
```

**EF6:**
```csharp
builder.Services.AddScoped<MyDBContext>(provider =>
    new MyDBContext("name=MyConnectionStringName"));
```

Add any required `using` statements (e.g., `Microsoft.EntityFrameworkCore` for EF Core).

### Step 4: Replace Direct Instantiations with DI

Find all `new MyDBContext()` calls and refactor to constructor injection. Direct instantiation bypasses the DI-configured connection string and lifetime management.

**Before:**
```csharp
public class MyService
{
    public void DoWork()
    {
        using (var context = new MyDBContext())
        {
            // Use context
        }
    }
}
```

**After:**
```csharp
public class MyService
{
    private readonly MyDBContext _context;

    public MyService(MyDBContext context)
    {
        _context = context;
    }

    public void DoWork()
    {
        // Use _context (lifetime managed by DI container)
    }
}
```

### Step 5: Migrate Database Initialization and Seeding

Search for `Database.SetInitializer` calls and move initialization logic to Program.cs. Register any initializer dependencies in the DI container, including transitive dependencies.

**EF6** — Preserve the original initialization pattern:
```csharp
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    Database.SetInitializer(services.GetRequiredService<MyInitializer>());
}
```

**EF Core** — Replace initializers with migrations. EF Core does not support `Database.SetInitializer`; refactor old initializers (e.g., `CreateDatabaseIfNotExists`, `DropCreateDatabaseIfModelChanges`) into EF Core migrations and seed methods:
```csharp
using (var scope = app.Services.CreateScope())
{
    var myContext = scope.ServiceProvider.GetRequiredService<MyDBContext>();
    myContext.Database.Migrate();
    MyDBContextSeed.Seed(myContext);
}
```

Remove the original `Database.SetInitializer` calls after migration.

## EF6 vs EF Core Quick Reference

| Aspect | EF6 | EF Core |
|--------|-----|---------|
| DI registration | `AddScoped<T>(provider => new T("name=..."))` | `AddDbContext<T>(options => ...)` |
| DB initialization | `Database.SetInitializer(...)` | `context.Database.Migrate()` |
| Connection string | `"name=ConnectionStringName"` format | `Configuration.GetConnectionString(...)` |
| Initializers | `CreateDatabaseIfNotExists`, `DropCreateDatabaseIfModelChanges` | Migrations-based approach |

## Success Criteria

- All DbContext classes have updated constructors (string for EF6, DbContextOptions for EF Core)
- Connection strings migrated from `web.config`/`app.config` to `appsettings.json`
- DbContext registered in Program.cs using the correct pattern for the chosen EF version
- All direct `new DbContext()` instantiations replaced with constructor injection
- Database initialization and seeding migrated to Program.cs
- Old `Database.SetInitializer` calls removed
- All initializer dependencies registered in DI
- Project builds without errors
