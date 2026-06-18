---
name: managing-blazor-server-data-access
description: >
  Manages data access and state in Blazor Server applications. Solves critical Blazor Server
  issues: Session NULL in WebSocket circuits, DbContext threading/concurrent operation errors,
  cart/wizard state loss, scoped lifetime issues, Session NullReferenceException. Configures
  IDbContextFactory for long-lived circuits (required for ANY Blazor Server app using EF Core),
  Session/ViewState/Application state alternatives (ProtectedSessionStorage, scoped services,
  database-backed), and DataSource to service injection migration. Covers Web.config to
  appsettings.json. Use when handling data access in Blazor Server, fixing session/DbContext/cart
  errors, resolving build errors for System.Data.Entity namespaces or EntityFramework package
  references, or troubleshooting data access failures in Blazor Server applications.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore

---

# Managing Data Access and State in Blazor Server

Manages data access and state in Blazor Server applications. Covers critical Blazor Server patterns required for long-lived circuits (IDbContextFactory, Session state alternatives, shopping cart persistence).

## Related Skills

**Reference guide for complementary patterns.** The workflow steps below contain explicit instructions on when to invoke each skill.

| Skill | Use For |
|-------|---------|
| **migrating-webforms-to-blazor-server** | Initial WebForms to Blazor migration (project setup, Routes, markup conversion) |
| **managing-blazor-server-authentication** | Authentication setup and patterns in Blazor Server |
| **migrating-ef6-code-first-to-ef-core** | Entity Framework 6 Code-First to EF Core migration → Step 1 |
| **migrating-mvc-configuration** | Web.config to appsettings.json migration → Step 4 |

## Prerequisites

This skill works with any Blazor Server application.

**If migrating from WebForms**, the `migrating-webforms-to-blazor-server` skill handles initial Blazor Server setup.

---

## Workflow

Configure Blazor Server data and state management in order:

```
Configuration Progress:
- [ ] Step 1: Set up data infrastructure (DbContext factory)
- [ ] Step 2: Configure data binding (DataSource to services)
- [ ] Step 3: Configure state management (Session to storage)
- [ ] Step 4: Migrate configuration (Web.config to appsettings.json)
```

---

## Step 1: Set Up Data Infrastructure

### Database Provider Detection

If the Web Forms project uses Entity Framework, check `Web.config` connection strings to determine the database provider. **CRITICAL: Preserve the original database provider** - do NOT default to SQLite unless the original project specifically used it. SQL Server (including LocalDB) is the most common Web Forms database.

**Detect provider from Web.config:**

| Web.config Indicator | Database Provider | EF Core Package to Install |
|---------------------|-------------------|----------------------------|
| `providerName="System.Data.SqlClient"` | SQL Server | `Microsoft.EntityFrameworkCore.SqlServer` |
| `providerName="System.Data.SQLite"` | SQLite | `Microsoft.EntityFrameworkCore.Sqlite` |
| `providerName="Npgsql"` | PostgreSQL | `Npgsql.EntityFrameworkCore.PostgreSQL` |
| `providerName="MySql.Data.MySqlClient"` | MySQL | `Pomelo.EntityFrameworkCore.MySql` |

**Add the detected provider to your Blazor project:**
```bash
# Example for SQL Server (most common)
dotnet add package Microsoft.EntityFrameworkCore.SqlServer
dotnet add package Microsoft.EntityFrameworkCore.Tools
```

> **Note:** If you previously completed `migrating-webforms-to-blazor-server` Step 1, the provider packages are already installed - skip to the next section.

### Entity Framework Migration

**Identify your data access pattern and execute the appropriate skill:**

| Original Pattern | Skill to Execute | Returns Here? |
|-----------------|------------------|---------------|
| **EF6 Code-First** (no .edmx files) | `migrating-ef6-code-first-to-ef-core` | ✅ Yes |
| **EDMX** (Database-First/Model-First) | `migrating-edmx-to-code-first` | ✅ Yes |
| **LINQ to SQL** (System.Data.Linq) | `migrating-linq-to-sql-to-ef-core` | ✅ Yes |

**All EF Core migration skills** handle:
- Package swaps (legacy → Microsoft.EntityFrameworkCore)
- Namespace updates
- DbContext constructor changes (connection string → `DbContextOptions`)
- Entity configuration conversion
- API changes and migrations history

⚠️ **Critical:** Those skills use `AddDbContext` (scoped lifetime), which **does NOT work** in Blazor Server long-lived circuits. After completing any EF migration skill, **you must** apply the Blazor-specific configuration below.

### Configure DbContext for Blazor Server

⚠️ **CRITICAL: Replace** the `AddDbContext` registration from the EF migration skill with `AddDbContextFactory`:

The EF migration skills use `AddDbContext` (scoped lifetime), which is correct for MVC/API but **WILL FAIL** in Blazor Server. You must replace it.

**Before (from EF migration skill - DO NOT USE):**
```csharp
// ❌ WRONG for Blazor Server
builder.Services.AddDbContext<SchoolContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));
```

**After (Blazor Server pattern - REQUIRED):**
```csharp
// ✅ CORRECT for Blazor Server — use IDbContextFactory for long-lived Blazor circuits
builder.Services.AddDbContextFactory<SchoolContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));
    // ↑ Replace with UseNpgsql(), UseMySql(), UseSqlite(), etc. to match original provider
```

**Why `IDbContextFactory`?** Blazor Server circuits are long-lived. A single `DbContext` instance would accumulate stale data and tracking issues. The factory pattern creates short-lived contexts per operation.

**Verification:** After making this change, search Program.cs for `AddDbContext`. If found, you missed the replacement - it MUST be `AddDbContextFactory` for Blazor Server.

### ADO.NET (Non-EF) Data Access

If the WebForms project uses **raw ADO.NET** (SqlCommand, SqlDataReader) without Entity Framework:

**Execute `migrating-to-microsoft-data-sqlclient` skill** to upgrade the provider (System.Data.SqlClient → Microsoft.Data.SqlClient). This works in Blazor Server with standard DI-registered services - no IDbContextFactory needed.

Example service pattern:
```csharp
public class ProductRepository(IConfiguration configuration)
{
    public async Task<List<Product>> GetProductsAsync()
    {
        using var connection = new SqlConnection(configuration.GetConnectionString("DefaultConnection"));
        using var command = new SqlCommand("SELECT * FROM Products", connection);
        await connection.OpenAsync();
        // ... read data
    }
}
```

### Data Access Service Layer

Create services to encapsulate database operations:

```csharp
// ProductService.cs
public class ProductService(IDbContextFactory<SchoolContext> factory)
{
    public async Task<List<Product>> GetProductsAsync()
    {
        using var db = factory.CreateDbContext();
        return await db.Products.ToListAsync();
    }

    public async Task<Product?> GetProductAsync(int id)
    {
        using var db = factory.CreateDbContext();
        return await db.Products.FindAsync(id);
    }
}

// Program.cs
builder.Services.AddScoped<IProductService, ProductService>();
```

### Connection String Migration

Before DbContext can use `GetConnectionString()`, migrate connection strings from Web.config to appsettings.json:

**Web.config:**
```xml
<connectionStrings>
  <add name="DefaultConnection"
       connectionString="Data Source=(LocalDb)\MSSQLLocalDB;Initial Catalog=MyApp;Integrated Security=True"
       providerName="System.Data.SqlClient" />
</connectionStrings>
```

**Create or update appsettings.json:**
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=(LocalDb)\\MSSQLLocalDB;Initial Catalog=MyApp;Integrated Security=True"
  }
}
```

**Key changes:**
- Remove `providerName` attribute (provider specified in code via `UseSqlServer()`, etc.)
- Escape backslashes: `\` → `\\`
- Section name is `ConnectionStrings` (capital C and S)

> **Note:** Complete configuration migration (appSettings, custom sections, secrets, environment files) will be done in Step 4.

---

## Step 2: Migrate DataSource Controls to Services

Web Forms declarative `DataSource` controls (`SqlDataSource`, `ObjectDataSource`, `EntityDataSource`) have no equivalent in Blazor. Replace with dependency-injected services that load data programmatically in component lifecycle methods.

```xml
<!-- Web Forms — declarative data binding -->
<asp:SqlDataSource ID="ProductsDS" runat="server"
    ConnectionString="<%$ ConnectionStrings:DefaultConnection %>"
    SelectCommand="SELECT * FROM Products" />
<asp:GridView DataSourceID="ProductsDS" runat="server" />
```

```razor
@* Blazor — service injection + @foreach table *@
@inject IProductService ProductService

<table>
    <thead><tr><th>Name</th><th>Price</th></tr></thead>
    <tbody>
        @foreach (var p in products)
        {
            <tr>
                <td>@p.Name</td>
                <td>@p.UnitPrice.ToString("C")</td>
            </tr>
        }
    </tbody>
</table>

@code {
    private List<Product> products = [];

    protected override async Task OnInitializedAsync()
    {
        products = await ProductService.GetProductsAsync();
    }
}
```

> **For advanced scenarios** (sorting, filtering, pagination), use **Microsoft.AspNetCore.Components.QuickGrid** (`dotnet add package Microsoft.AspNetCore.Components.QuickGrid`).

### Service Registration Pattern

```csharp
// Program.cs — use the provider that matches the original Web Forms database
builder.Services.AddRazorComponents().AddInteractiveServerComponents();
builder.Services.AddDbContextFactory<ProductContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));
    // ↑ Match the original provider: UseNpgsql(), UseMySql(), UseSqlite(), etc.

builder.Services.AddScoped<IProductService, ProductService>();
builder.Services.AddScoped<ICategoryService, CategoryService>();
builder.Services.AddScoped<IOrderService, OrderService>();

// ... after builder.Build() ...
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();
```

---

## Step 3: Convert State Management Patterns

> **CRITICAL:** When using `<Routes @rendermode="InteractiveServer" />` (global interactive server mode), `HttpContext.Session` is **NULL** during WebSocket rendering. Session state access inside Blazor components will throw `NullReferenceException` or silently fail.

**Why:** After the initial HTTP request establishes the SignalR circuit, Blazor communicates over WebSocket. There is no HTTP request/response, and therefore no session middleware processing during component interactions.

**Solution:** Replace Session state with one of four patterns based on your requirements:

| Pattern | Use For | Survives Refresh? | Survives Disconnect? |
|---------|---------|-------------------|----------------------|
| **Option A: Minimal API Endpoints** | Form submissions, business operations | ✅ Yes | ✅ Yes (if persisted) |
| **Option B: Scoped Services** | Transient UI state (wizard progress, filters) | ❌ No | ❌ No |
| **Option C: Database-Backed** | Business-critical state (cart, preferences) | ✅ Yes | ✅ Yes |
| **Option D: ProtectedSessionStorage** | Browser tab-specific state | ✅ Yes | ❌ No |

**For detailed implementation examples and decision guidance**, read **[references/session-state-patterns.md](references/session-state-patterns.md)**.

**Quick reference:**
- Shopping carts, user preferences → **Option C** (database-backed)
- Form submissions → **Option A** (minimal API endpoints)
- Wizard progress, temporary filters → **Option B** (scoped services)
- Tab-specific data that survives refresh → **Option D** (ProtectedSessionStorage)

---

## Step 4: Migrate Configuration

Complete configuration migration from Web.config to appsettings.json. This step handles all configuration beyond the connection strings already migrated in Step 1.

**Execute the `migrating-mvc-configuration` skill** to migrate:
- AppSettings → appsettings.json with nested JSON structure
- Additional connection strings (if your app has multiple databases)
- IConfiguration injection patterns
- IOptions<T> strongly-typed configuration
- Environment-specific configuration files (Development, Staging, Production)
- Custom config sections → POCO classes
- Secrets migration to User Secrets / Key Vault
- ConfigurationManager removal and cleanup

Execute that skill to complete configuration migration, then return here.

### Blazor-Specific Syntax Note

Configuration access in Blazor components uses `@inject` directive syntax instead of constructor injection:

```csharp
// Blazor component
@inject IConfiguration Configuration
@inject IOptions<AppSettings> AppSettingsOptions

@code {
    protected override void OnInitialized()
    {
        var apiUrl = Configuration["AppSettings:ApiBaseUrl"];
        var maxPageSize = AppSettingsOptions.Value.MaxPageSize;
    }
}
```

The underlying concepts (IConfiguration, IOptions<T>, registration in Program.cs) are identical to the general skill's guidance.

---

## Reference Documents

For detailed implementation patterns and code examples:

- **[references/session-state-patterns.md](references/session-state-patterns.md)** — Session state migration patterns (scoped services, database-backed, ProtectedSessionStorage, minimal API endpoints)

---

## Common Data Migration Gotchas

### DbContext Lifetime
Blazor Server circuits are long-lived. Always use `IDbContextFactory` and create short-lived `DbContext` instances per operation.

⚠️ **CRITICAL VALIDATION:** After completing EF migration steps, search `Program.cs` for the pattern `AddDbContext<`. If found, you have NOT correctly applied the Blazor Server pattern - it MUST be `AddDbContextFactory<` instead. The referenced EF migration skills use `AddDbContext` (correct for MVC/API), which will cause runtime failures in Blazor Server.

### No Page-Level Transaction Scope
Web Forms `SelectMethod` runs inside a page lifecycle. Blazor doesn't have this. Use explicit transaction scopes in services if needed:
```csharp
using var db = factory.CreateDbContext();
using var transaction = await db.Database.BeginTransactionAsync();
// ... operations
await transaction.CommitAsync();
```

### Async All the Way
Web Forms `SelectMethod` returns `IQueryable` synchronously. Blazor services should be async:
```csharp
// WRONG: return db.Products.ToList();
// RIGHT: return await db.Products.ToListAsync();
```

### No ConfigurationManager
`ConfigurationManager.AppSettings["key"]` doesn't exist. Inject `IConfiguration` or use the Options pattern.

### Static Helpers with HttpContext
Web Forms often has static helper classes that access `HttpContext.Current`. These must be refactored to accept dependencies via constructor injection.