# Relationship Migration

## Type Replacements

| LINQ to SQL | EF Core | Notes |
|------------|---------|-------|
| `EntitySet<T>` | `ICollection<T>` or `List<T>` | Initialize in constructor: `= new List<T>()` |
| `EntityRef<T>` | Navigation property (plain reference) | Remove the struct wrapper entirely |
| `EntitySet<T>.Assign()` | Direct collection assignment | No special assignment method needed |
| `EntityRef<T>.Entity` | Direct property access | Remove `.Entity` suffix |
| `EntityRef<T>.HasLoadedOrAssignedValue` | No equivalent needed | EF Core tracks this internally |

## Association Attribute to Fluent API

LINQ to SQL `[Association]` attributes map to EF Core relationship configuration:

```csharp
// LINQ to SQL
[Association(ThisKey = "CustomerId", OtherKey = "Id", Storage = "_Customer", IsForeignKey = true)]
public Customer Customer { get { return _Customer.Entity; } set { _Customer.Entity = value; } }

// EF Core entity (clean POCO)
public int CustomerId { get; set; }
public Customer Customer { get; set; }
```

Fluent API (only needed for non-convention cases):
```csharp
modelBuilder.Entity<Order>()
    .HasOne(o => o.Customer)
    .WithMany(c => c.Orders)
    .HasForeignKey(o => o.CustomerId);
```

EF Core convention infers most relationships automatically from navigation properties and FK naming. Only use Fluent API when:
- FK property name doesn't follow convention (`{NavigationProperty}Id`)
- Cascade delete behavior needs customizing
- The relationship is self-referencing or complex

## Cascade Delete Migration

| LINQ to SQL | EF Core |
|------------|---------|
| `[Association(DeleteOnNull=true)]` | `.OnDelete(DeleteBehavior.Cascade)` (default for required relationships) |
| `[Association(DeleteRule="...")]` | `.OnDelete(DeleteBehavior.Restrict)` / `.SetNull` / `.Cascade` |

## Deferred Loading — HIGH RISK

**LINQ to SQL lazy-loads by default** via `EntitySet<T>` / `EntityRef<T>`. **EF Core does NOT lazy-load by default.**

This means code like this silently breaks:
```csharp
var order = context.Orders.First(o => o.Id == 42);
var customerName = order.Customer.Name; // LINQ to SQL: works (lazy load)
                                         // EF Core: NullReferenceException!
```

### Finding All Affected Code

Search for navigation property access patterns across the codebase:
1. Find all `EntitySet<T>` and `EntityRef<T>` usages — these are the navigation properties
2. For each, search for property access on the loaded entity (e.g., `order.Customer.Name`, `customer.Orders.Count()`)
3. Check if the query that loaded the parent included an `Include()` for that navigation

### Fixing Loading Patterns

**Option 1 (Recommended): Eager loading with Include()**
```csharp
var order = context.Orders
    .Include(o => o.Customer)
    .First(o => o.Id == 42);
// order.Customer is now loaded
```

**Option 2: Explicit loading**
```csharp
var order = context.Orders.First(o => o.Id == 42);
context.Entry(order).Reference(o => o.Customer).Load();
```

**Option 3: Lazy loading proxies** (not recommended — hides performance problems)
```csharp
// In DI setup:
services.AddDbContext<MyDbContext>(options => options.UseLazyLoadingProxies().UseSqlServer(conn));
// Requires: Microsoft.EntityFrameworkCore.Proxies package
// Requires: all navigation properties must be virtual
```

## DataLoadOptions Migration

| LINQ to SQL | EF Core |
|------------|---------|
| `DataLoadOptions.LoadWith<Order>(o => o.Customer)` | `.Include(o => o.Customer)` |
| `DataLoadOptions.LoadWith<Order>(o => o.Items)` | `.Include(o => o.Items)` |
| `DataLoadOptions.AssociateWith<Customer>(c => c.Orders.Where(o => o.IsActive))` | `.Include(c => c.Orders.Where(o => o.IsActive))` (filtered include, EF Core 5+) |
| Set `DataLoadOptions` on DataContext once | Apply `Include()` per query |

**Key difference:** LINQ to SQL's `DataLoadOptions` was set once on the DataContext and applied to all queries. EF Core's `Include()` is per-query. Each query that needs related data must specify its own `Include()` calls.
