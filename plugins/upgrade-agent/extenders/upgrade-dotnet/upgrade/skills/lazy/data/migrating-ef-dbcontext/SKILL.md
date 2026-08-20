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

### Shared-database check (do this first)

Before changing any registration, determine whether the .NET Framework host stays live
against the same database. Check whether the old project's `*.config` and the new host's
configuration resolve to the same database, and whether the old host is still deployed.

If they share a database, **load `managing-shared-database-schema` now and follow it** —
`get_instructions(kind='skill', query='managing-shared-database-schema')`. This skill
tells you where to register a `DbContext`; it does not tell you who is allowed to change
the schema, and getting that wrong on a live shared database is not recoverable by
rolling back code. In particular, do not enable startup migration and do not create a
second `Migrations/` folder until that skill's ownership decision says you own the schema.

**If you cannot tell, assume the database is shared.** At scaffold time the answer often is
not determinable from the repo. Silence is not a "no": unless you can positively confirm the
old host is retired or runs against its own database, take the shared branch — do not enable
startup migration, and load `managing-shared-database-schema` first. Being wrong that way
costs one skill load; being wrong the other way is not recoverable by rolling back code.

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

**EF6** — Preserve the original initialization pattern.

> **Do not carry a migration-applying initializer across.** If the preserved initializer is
> `MigrateDatabaseToLatestVersion<TContext, TConfiguration>`, re-registering it here runs
> `DbMigrator.Update()` on first context use — a second, uncoordinated schema writer that
> deploys on process start. Where another host still writes this database, register
> `Database.SetInitializer<TContext>(null)` instead and load the shared-database skill first:
> `get_instructions(kind='skill', query='managing-shared-database-schema')`

```csharp
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;

    // Add ONLY if this host is the sole schema owner. If another host still writes this
    // database, leave this commented and use Database.SetInitializer<MyDBContext>(null).
    // Database.SetInitializer(services.GetRequiredService<MyInitializer>());
}
```

**EF Core** — Replace initializers with migrations. EF Core does not support `Database.SetInitializer`; refactor old initializers (e.g., `CreateDatabaseIfNotExists`, `DropCreateDatabaseIfModelChanges`) into EF Core migrations and seed methods.

> **Do not enable startup migration on a shared database.** `Database.Migrate()` at startup is
> safe only when this host is the **sole** schema owner. If a .NET Framework host still runs
> against the same database (a side-by-side migration), this line gives you a second,
> uncoordinated schema writer. Load `managing-shared-database-schema` first and follow its
> ownership decision: `get_instructions(kind='skill', query='managing-shared-database-schema')`
>
> Where another host owns the schema, omit the `Database.Migrate()` call entirely and seed
> only — or leave initialization out of the host and run migrations from the dedicated runner.

```csharp
using (var scope = app.Services.CreateScope())
{
    var myContext = scope.ServiceProvider.GetRequiredService<MyDBContext>();

    // Add ONLY if this host is the sole schema owner. Left commented deliberately: on a
    // shared database this line is a second, uncoordinated schema writer.
    // myContext.Database.Migrate();

    MyDBContextSeed.Seed(myContext);
}
```

Remove the original `Database.SetInitializer` calls after migration.

## EF6 vs EF Core Quick Reference

| Aspect | EF6 | EF Core |
|--------|-----|---------|
| DI registration | `AddScoped<T>(provider => new T("name=..."))` | `AddDbContext<T>(options => ...)` |
| DB initialization | `Database.SetInitializer(...)` | `context.Database.Migrate()` — only from the single designated migration runner; never at startup while another host shares the database |
| Connection string | `"name=ConnectionStringName"` format | `Configuration.GetConnectionString(...)` |
| Initializers | `CreateDatabaseIfNotExists`, `DropCreateDatabaseIfModelChanges` | Migrations-based approach |

## Success Criteria

- All DbContext classes have updated constructors (string for EF6, DbContextOptions for EF Core)
- Connection strings migrated from `web.config`/`app.config` to `appsettings.json`
- DbContext registered in Program.cs using the correct pattern for the chosen EF version
- All direct `new DbContext()` instantiations replaced with constructor injection
- Database initialization and seeding migrated to Program.cs
- Old `Database.SetInitializer` calls removed
- Startup `Database.Migrate()` present **only** where this host is the sole schema owner —
  omitted when another live host shares the database
- All initializer dependencies registered in DI
- Project builds without errors
