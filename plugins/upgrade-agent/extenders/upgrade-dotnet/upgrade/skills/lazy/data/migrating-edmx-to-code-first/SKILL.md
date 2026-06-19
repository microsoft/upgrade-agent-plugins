---
name: migrating-edmx-to-code-first
description: >
  Migrates Entity Framework 6 EDMX-based models (Database-First/Model-First) to EF Core Code-First.
  Use when upgrading projects containing .edmx files, .Context.tt templates, EntityClient connection
  strings, or ObjectContext references. Triggers for "migrate EDMX", "convert EDMX to code first",
  "EF6 to EF Core", "remove EDMX", "database first to code first", and "scaffold DbContext". Also
  relevant when encountering EntitySQL, EntityObject, or ObjectSet patterns during .NET modernization.
metadata:
  traits: .NET|CSharp|VisualBasic|DotNetCore
  discovery: lazy
---

# EDMX to Code-First Migration

## Overview

Migrate Entity Framework EDMX files to EF Core Code-First. EDMX is not supported in EF Core, so the migration scaffolds a code-based model from the existing database and replaces all EDMX-dependent patterns.

> **Scope:** This skill targets EDMX-based (Database-First/Model-First) projects. If the project already uses EF6 Code-First (no `.edmx` files), use the `migrating-ef6-code-first-to-ef-core` skill instead. For DbContext registration and DI setup during ASP.NET Core migration, also apply the `migrating-ef-dbcontext` skill — it is complementary to this one.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect and assess
- [ ] Step 2: Install packages
- [ ] Step 3: Extract connection string
- [ ] Step 4: Scaffold from database
- [ ] Step 5: Register DbContext
- [ ] Step 6: Preserve customizations
- [ ] Step 7: Handle breaking changes
- [ ] Step 8: Cleanup
- [ ] Step 9: Validate
```

### Step 1: Detect and Assess

1. Search for `.edmx` files in the project
2. Note the DbContext name from `.Context.tt` or `.Designer.cs`
3. Find EntityClient connection strings in `web.config`/`app.config`
4. Check for partial class customizations (`.cs` files matching entity names)
5. Confirm with the user before proceeding: if the project targets .NET Framework, advise upgrading to .NET 8 or later and updating EntityFramework to 6.5.1 first. Explain that the EF Core model will be scaffolded from the database using the extracted connection string, and confirm whether to migrate to EF Core or stay with EF6

### Step 2: Install Packages

Install EF Core packages matching the target framework. Use matching major versions because EF Core packages are tied to specific .NET runtime versions.

```xml
<!-- Choose provider based on the project's database: SqlServer, Sqlite, Npgsql.EntityFrameworkCore.PostgreSQL, Pomelo.EntityFrameworkCore.MySql -->
<PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" />
<PackageReference Include="Microsoft.EntityFrameworkCore.Design" />
<PackageReference Include="Microsoft.EntityFrameworkCore.Tools" />
```

Use the EF Core major version that matches the project's target framework (e.g., EF Core 8.x for .NET 8, EF Core 10.x for .NET 10). Use the **managing-package-references** skill to add these packages — it handles version determination, CPM detection, and NuGet feed lookup.

### Step 3: Extract Connection String

EntityClient connection strings embed the real ADO.NET string. Extract it and place in `appsettings.json`:

```xml
<!-- Before: EntityClient format in web.config -->
provider connection string=&quot;Data Source=...;Initial Catalog=...&quot;
```

Extract ADO.NET connection string and add to `appsettings.json`:

```json
{"ConnectionStrings": {"MyEntities": "Data Source=...;Initial Catalog=..."}}
```

> **Important:** Never store passwords or secrets in source code or config files. Use Secret Manager, environment variables, or Azure Key Vault for production secrets.

### Step 4: Scaffold from Database

The scaffold command requires a live database connection. Provide the user with the command to run — do not execute it directly, as it requires database access and the connection string may contain credentials.

```powershell
# User must run this command — it connects to the database to reverse-engineer the model
dotnet ef dbcontext scaffold "<ADO.NET-connection-string-from-Step-3>" Microsoft.EntityFrameworkCore.SqlServer --output-dir Models --context MyDbContext
```

Replace `<ADO.NET-connection-string-from-Step-3>` with the connection string extracted in Step 3. Replace the provider name if the project uses a different database.

Useful options: `--table` (specific tables only), `--schema` (specific schema), `--data-annotations` (use attributes instead of fluent API), `--force` (overwrite existing files), `--no-pluralize` (keep table names as-is)

### Step 5: Register DbContext

Use the `migrating-ef-dbcontext` skill to register the scaffolded `DbContext` in dependency injection, migrate connection strings to `appsettings.json`, replace direct instantiations with constructor injection, and migrate database initializers. That skill handles both EF6 and EF Core registration patterns.

### Step 6: Preserve Customizations

**Merge entity classes:** Remove the newly scaffolded entity classes and update the scaffolded `OnModelCreating` code to reference the existing old entity classes instead. Merge any scaffolded configuration (column mappings, relationships) into the old entities or their partial class files. This preserves all existing customizations, partial class extensions, and business logic.

**Migrate EntitySQL to LINQ:** EntitySQL is not supported in EF Core.
- Find: `ObjectQuery<T>`, `EntityCommand`, `EntityConnection`, `.eSQL` files
- Replace with LINQ or `FromSql()`
```csharp
// Before: context.CreateQuery<Customer>(esqlString, params)
// After: context.Customers.Where(c => c.City == "London")

// If raw SQL is needed (use interpolated string for automatic parameterization):
context.Customers.FromSql($"SELECT * FROM Customers WHERE City = {city}")
// WARNING: Do not use string concatenation — only FormattableString (interpolated) strings
// are parameterized by EF Core. String concatenation creates SQL injection vulnerabilities.
```

**ObjectContext → DbContext:** EF Core uses DbContext exclusively.
- Replace `ObjectContext` with `DbContext`, `ObjectSet<T>` with `DbSet<T>`
- Remove `EntityObject` base class
- Replace `CreateObjectSet<T>()` with `Set<T>()`
- Replace `DbEntityEntry<T>` with `EntityEntry<T>`
- Replace `Database.Log` with `Microsoft.Extensions.Logging` or `LogTo` in `OnConfiguring`
- Replace `System.Data.Entity` usings with `Microsoft.EntityFrameworkCore`

**Stored procedures:** EDMX function-import mappings do not exist in EF Core.
- For **read** operations: use `FromSql` to map result sets to entities:
  ```csharp
  context.Customers.FromSql($"EXEC GetCustomersByCity {city}");
  ```
- For **CUD** operations: configure stored procedure mapping in `OnModelCreating` (EF Core 7.0+):
  ```csharp
  modelBuilder.Entity<Customer>()
      .InsertUsingStoredProcedure("Customer_Insert", sp => sp.HasParameter(c => c.Name));
  ```
- For unsupported scenarios: use `context.Database.ExecuteSql(...)`.

**Navigation loading:**
```csharp
// Before: order.CustomerReference.Load();
// After: context.Entry(order).Reference(o => o.Customer).Load();
```

**Independent associations:** EF Core does not support independent associations (relationships defined in the EDMX without explicit foreign key properties on the entity). Add FK properties to the entity classes or configure shadow properties in `OnModelCreating`:
```csharp
// Option 1: Add an explicit FK property to the entity
public int CustomerId { get; set; }
public Customer Customer { get; set; }

// Option 2: Use a shadow property (no FK on the entity class)
modelBuilder.Entity<Order>()
    .HasOne(o => o.Customer)
    .WithMany(c => c.Orders)
    .HasForeignKey("CustomerId");
```

### Step 7: Handle Breaking Changes

**Lazy loading:** EF Core disables lazy loading by default.
- Option 1: Install `Microsoft.EntityFrameworkCore.Proxies`, use `UseLazyLoadingProxies()`
- Option 2 (preferred): Use `.Include()` for eager loading

**Complex types:** In EF Core 7 and earlier, `[ComplexType]` is replaced by owned entities:
```csharp
// Configure in OnModelCreating:
modelBuilder.Entity<Customer>().OwnsOne(c => c.Address);
```
EF Core 8+ reintroduces native complex type support. If targeting .NET 8+, use `ComplexProperty()` instead:
```csharp
modelBuilder.Entity<Customer>().ComplexProperty(c => c.Address);
```

**Many-to-many:** EF Core 5.0+ auto-generates the join table for simple many-to-many relationships. Pre-5.0 needs an explicit join entity. Even on 5.0+, explicit join entity configuration is required when the join table contains payload columns (columns other than the two foreign keys).

**Migrations:** Advise the user to apply all pending EF6 migrations to their database before starting the EF Core migration — this is a manual prerequisite. Once confirmed, delete the Migrations folder and create an empty EF Core `InitialCreate` migration. This avoids schema conflicts between the two migration systems.

**Database initializers:** EF Core does not support automatic migrations or database initializers (`CreateDatabaseIfNotExists`, `DropCreateDatabaseIfModelChanges`, `DropCreateDatabaseAlways`, `MigrateDatabaseToLatestVersion`). Remove all `Database.SetInitializer` calls and use `Database.Migrate()` or `EnsureCreated()` explicitly at startup.

**Configuration classes:**
```csharp
// Change: EntityTypeConfiguration<T> → IEntityTypeConfiguration<T>
// Change: HasDatabaseGeneratedOption → ValueGeneratedOnAdd/Never
```
When using `IEntityTypeConfiguration<T>`, register all configurations in `OnModelCreating` via `modelBuilder.ApplyConfigurationsFromAssembly(typeof(MyDbContext).Assembly)`.

**Data validation:** EF Core does not perform data validation on `SaveChanges()`. If the app relied on EF6's built-in validation (`IValidatableObject` invoked by `SaveChanges`), add an alternative validation strategy — ASP.NET model validation, FluentValidation, or manual checks before `SaveChanges()`.

**Async methods (optional):** Convert `ToList()` → `ToListAsync()`, `SaveChanges()` → `SaveChangesAsync()`. Recommended but not required for the migration to succeed.

### Step 8: Cleanup

Delete these EDMX artifacts:
- `*.edmx`, `*.edmx.diagram`, `*.Designer.cs`, `*.Context.tt`, `*.tt` files
- `<EntityDeploy>` entries from the project file
- Remove `EntityFramework` and any related EF6 packages (e.g., `EntityFramework.SqlServer`, `EntityFramework.SqlServerCompact`) using the project's package management approach

### Step 9: Validate

Compilation alone is not sufficient. Many EF6→EF Core differences only surface at runtime.

**LLM responsibilities (automated):**
1. Build the project and fix any compilation errors
2. Confirm no EDMX artifacts remain in the project (`.edmx`, `.tt`, `<EntityDeploy>`, `EntityFramework` package reference)
3. Run existing unit tests

**User responsibilities (require database access and manual verification):**
4. Verify all CRUD operations work end-to-end against a test database
5. Check navigation property loading — confirm eager loading (`.Include()`) returns expected related data
6. Validate change tracking behavior matches expectations (Added, Modified, Deleted states)
7. Test stored procedure calls and `FromSql`/`ExecuteSql` results
8. Compare query results with the EF6 version for any complex LINQ queries

Present items 4–8 as a checklist for the user — the LLM cannot validate runtime database behavior.

## Breaking Changes Quick Reference
| EF6 | EF Core | Action |
|-----|---------|--------|
| EDMX | Not supported | Scaffold from DB |
| EntitySQL | LINQ/FromSql | Rewrite queries |
| EntityClient connection | Standard ADO.NET | Extract provider string |
| ObjectContext | DbContext | Replace references |
| DbEntityEntry<T> | EntityEntry<T> | Update type references |
| Database.Log | Microsoft.Extensions.Logging / LogTo | Configure logging in DI or OnConfiguring |
| System.Data.Entity | Microsoft.EntityFrameworkCore | Replace usings |
| [ComplexType] | `OwnsOne()` (pre-8) / `ComplexProperty()` (8+) | Configure in OnModelCreating |
| EntityTypeConfiguration<T> | IEntityTypeConfiguration<T> | Update interface |
| HasDatabaseGeneratedOption | ValueGeneratedOnAdd | Replace calls |
| EntityReference.Load() | Entry().Reference().Load() | Update syntax |
| Independent associations (no FK property) | Not supported | Add explicit FK properties or configure shadow properties |
| `DbSet.Add` marks all reachable entities `Added` | Entities with store-generated key set → `Unchanged`; unset → `Added` | Test all Add/Update/Attach scenarios with entity graphs |
| `DbSet.Attach` marks all reachable entities `Unchanged` | Entities with store-generated key set → `Unchanged`; unset → `Added` | Verify Attach behavior in disconnected-entity workflows |
| Table names = pluralized entity class name | Table names = `DbSet<T>` property name; falls back to class name | Verify table mappings or add explicit `.ToTable()` calls |
| Auto-creates DB/schema, checks model compatibility | No automatic initialization | Call `Database.Migrate()` or `EnsureCreated()` explicitly at startup |
| Orphaned dependents preserved | Orphaned dependents **deleted** | Review parent-child removal logic; add `ClientSetNull` if preservation needed |
| Full-graph change detection | Per-entity change detection | Configure notification entities if needed |
| Self-tracking entities supported | Not supported | Switch to explicit change tracking via `DbContext` |
| Connection factories supported | Not supported | Always provide an explicit connection string |
| `ClientSetNull` → `RESTRICT` | `ClientSetNull` → `NO ACTION` | Verify cascade delete behavior; add explicit `OnDelete` configuration |
| `SaveChanges` validates `IValidatableObject` | No built-in validation | Add ASP.NET model validation, FluentValidation, or manual checks |

## Success Criteria

- All `.edmx` files and related artifacts removed
- Code-based model scaffolded and compiling
- Partial class customizations preserved
- EntitySQL converted to LINQ or `FromSql()`
- Connection strings in `appsettings.json`
- (Optional) Lazy loading strategy configured
- Complex types and many-to-many relationships migrated
- (Optional) Async methods used where appropriate
- Project builds, tests pass, queries return correct results
- Adding a new EF Core migration produces one without any operations (model matches database)
- No secrets are stored in plain text
