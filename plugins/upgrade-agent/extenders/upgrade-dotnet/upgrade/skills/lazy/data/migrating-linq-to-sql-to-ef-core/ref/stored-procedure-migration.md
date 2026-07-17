# Stored Procedure Migration

## LINQ to SQL Pattern

Stored procedures appear as methods on the DataContext decorated with `[Function]`:
```csharp
[Function(Name = "dbo.GetOrdersByCustomer")]
public ISingleResult<Order> GetOrdersByCustomer(
    [Parameter(Name = "CustomerId")] int customerId)
{
    IExecuteResult result = ExecuteMethodCall(this, ((MethodInfo)(MethodInfo.GetCurrentMethod())), customerId);
    return (ISingleResult<Order>)result.ReturnValue;
}
```

## EF Core Patterns

EF Core has no attribute-based SP mapping. Convert each SP based on its return type:

### SPs Returning Entity Types
```csharp
// LINQ to SQL
var orders = context.GetOrdersByCustomer(42);

// EF Core
var orders = context.Orders
    .FromSqlRaw("EXEC dbo.GetOrdersByCustomer @p0", customerId)
    .ToList();
```

### SPs With No Return Value
```csharp
// LINQ to SQL
context.ArchiveOldOrders(cutoffDate);

// EF Core
context.Database.ExecuteSqlRaw("EXEC dbo.ArchiveOldOrders @p0", cutoffDate);
```

### SPs Returning Non-Entity Types (EF Core 8+)
```csharp
// Define a keyless result type
[Keyless]
public class OrderSummary
{
    public int CustomerId { get; set; }
    public decimal TotalAmount { get; set; }
}

// EF Core 8+
var summaries = context.Database
    .SqlQueryRaw<OrderSummary>("EXEC dbo.GetOrderSummaries @p0", year)
    .ToList();
```

### Output Parameters
```csharp
// LINQ to SQL used ref/out parameters
[Function(Name = "dbo.GetOrderCount")]
public int GetOrderCount([Parameter(Name = "CustomerId")] int customerId, ref int totalCount) { ... }

// EF Core: use SqlParameter
var countParam = new SqlParameter("@TotalCount", SqlDbType.Int) { Direction = ParameterDirection.Output };
context.Database.ExecuteSqlRaw("EXEC dbo.GetOrderCount @CustomerId, @TotalCount OUTPUT",
    new SqlParameter("@CustomerId", customerId), countParam);
var totalCount = (int)countParam.Value;
```

## IMultipleResults — BLOCKER

LINQ to SQL supports SPs returning multiple result sets via `IMultipleResults`. **EF Core has no built-in support.**

```csharp
// LINQ to SQL — works
[Function(Name = "dbo.GetOrderDetails")]
[ResultType(typeof(Order))]
[ResultType(typeof(OrderItem))]
public IMultipleResults GetOrderDetails(int orderId) { ... }

// No EF Core equivalent
```

**Options (choose one):**
1. **Split the SP** into separate SPs, one per result set (recommended if you control the database)
2. **Use raw ADO.NET** with `SqlDataReader.NextResult()` — drops out of EF Core:
```csharp
using var command = context.Database.GetDbConnection().CreateCommand();
command.CommandText = "EXEC dbo.GetOrderDetails @OrderId";
command.Parameters.Add(new SqlParameter("@OrderId", orderId));
await context.Database.OpenConnectionAsync();
using var reader = await command.ExecuteReaderAsync();
// Read first result set
while (await reader.ReadAsync()) { /* map Order */ }
await reader.NextResultAsync();
// Read second result set
while (await reader.ReadAsync()) { /* map OrderItem */ }
```
3. **Redesign** to use separate queries

**Flag this in assessment** — it requires architectural decisions.

## User-Defined Functions (UDFs)

LINQ to SQL maps table-valued functions via `[Function(IsComposable=true)]`. EF Core uses `HasDbFunction()`:

```csharp
// In DbContext.OnModelCreating:
modelBuilder.HasDbFunction(typeof(MyDbContext).GetMethod(nameof(GetOrdersForYear)))
    .HasName("dbo.fn_GetOrdersForYear");

// Declare as method on DbContext:
public IQueryable<Order> GetOrdersForYear(int year) => FromExpression(() => GetOrdersForYear(year));
```
