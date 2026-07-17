# DataContext to DbContext Migration

## Lifecycle Difference

| Aspect | LINQ to SQL DataContext | EF Core DbContext |
|--------|------------------------|-------------------|
| Creation | `new MyDataContext(connectionString)` inline | DI-injected with scoped lifetime |
| Lifetime | Short-lived per method call | Scoped per HTTP request (web) or per operation |
| Disposal | Explicit `using` blocks | DI container manages disposal |
| Thread safety | Not thread-safe | Not thread-safe |

**Migration steps:**
1. Register DbContext in DI: `builder.Services.AddDbContext<MyDbContext>(options => options.UseSqlServer(connectionString))`
2. Find all `new MyDataContext(...)` instantiation points
3. Replace with constructor-injected DbContext
4. **Remove `using` blocks** around the injected DbContext — the DI container manages its lifecycle. Keeping `using` causes premature disposal.
5. Refactor static methods or utility classes that create DataContext — these need refactoring to accept DbContext via DI

## API Mapping

| LINQ to SQL | EF Core | Notes |
|------------|---------|-------|
| `Table<T>` property | `DbSet<T>` property | Different query semantics (see query gotchas) |
| `SubmitChanges()` | `SaveChanges()` / `SaveChangesAsync()` | Prefer async variant |
| `SubmitChanges(ConflictMode)` | `SaveChanges()` + catch `DbUpdateConcurrencyException` | No ConflictMode param — handle in catch block |
| `GetChangeSet()` | `ChangeTracker.Entries()` | Different API shape |
| `ChangeConflictException` | `DbUpdateConcurrencyException` | Different resolution API |
| `ExecuteCommand(sql, params)` | `Database.ExecuteSqlRaw(sql, params)` | Similar signature |
| `ExecuteQuery<T>(sql, params)` | `FromSqlRaw(sql, params)` on DbSet, or `Database.SqlQueryRaw<T>(sql, params)` (EF Core 8+) | `SqlQueryRaw` for non-entity types |
| `DataContext.Log = textWriter` | `optionsBuilder.LogTo(Console.WriteLine)` or `ILoggerFactory` | Configure in DI setup, not per-instance |
| `ObjectTrackingEnabled = false` | `AsNoTracking()` per query | Per-query, not per-context |
| `DataContext.CreateDatabase()` | EF Core migrations | Significant workflow change |
| `DataContext.Attach(entity)` | `DbContext.Attach(entity)` | Behavior differs: EF Core sets `Unchanged` state; LINQ to SQL required original values |
| `DataContext.Refresh(RefreshMode, entity)` | `Entry(entity).Reload()` | Only supports database-wins |

## Connection String Handling

LINQ to SQL pattern:
```csharp
var context = new MyDataContext(ConfigurationManager.ConnectionStrings["MyDb"].ConnectionString);
```

EF Core pattern (in `Program.cs` or startup):
```csharp
builder.Services.AddDbContext<MyDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("MyDb")));
```

If the codebase passes connection strings around (e.g., to factory methods), refactor to use the DI-configured DbContext instead.

## Conflict Resolution Differences

LINQ to SQL:
```csharp
try { context.SubmitChanges(ConflictMode.ContinueOnConflict); }
catch (ChangeConflictException)
{
    foreach (var conflict in context.ChangeConflicts)
        conflict.Resolve(RefreshMode.KeepCurrentValues);
    context.SubmitChanges();
}
```

EF Core:
```csharp
try { context.SaveChanges(); }
catch (DbUpdateConcurrencyException ex)
{
    foreach (var entry in ex.Entries)
    {
        var dbValues = await entry.GetDatabaseValuesAsync();
        entry.OriginalValues.SetValues(dbValues);
    }
    context.SaveChanges();
}
```
