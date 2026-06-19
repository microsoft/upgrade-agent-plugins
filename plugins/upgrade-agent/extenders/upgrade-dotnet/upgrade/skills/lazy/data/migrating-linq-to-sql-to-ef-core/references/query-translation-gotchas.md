# Query Translation Gotchas

## Client-Side Evaluation (Critical)

**The #1 source of runtime breaks after migration.**

LINQ to SQL silently evaluates untranslatable expressions on the client. EF Core (since 3.0) **throws `InvalidOperationException`** if it can't translate a query expression to SQL (except in the final `Select` projection).

**Pattern to find:** Method calls, string operations, or custom functions in `Where`, `OrderBy`, `GroupBy`, or `Join` clauses.

**Fix:** Add `.AsEnumerable()` or `.ToList()` before the untranslatable operation:
```csharp
// Fails in EF Core — MyCustomMethod can't be translated to SQL
var results = context.Orders.Where(o => MyCustomMethod(o.Name)).ToList();

// Fix: pull data first, then filter in memory
var results = context.Orders.AsEnumerable().Where(o => MyCustomMethod(o.Name)).ToList();
```

**Warning:** This may pull more data from the database than intended. Review each case for performance.

## GroupBy Translation

EF Core has strict GroupBy translation. This pattern works in LINQ to SQL but fails in EF Core:
```csharp
// Fails: materializing group items requires client evaluation
var groups = context.Orders
    .GroupBy(o => o.Category)
    .Select(g => new { g.Key, Items = g.ToList() })
    .ToList();

// Fix: use two queries or aggregate functions only
var groups = context.Orders
    .GroupBy(o => o.Category)
    .Select(g => new { g.Key, Count = g.Count(), Total = g.Sum(o => o.Amount) })
    .ToList();
```

## Take/Skip Without OrderBy

LINQ to SQL tolerated `Take()`/`Skip()` without `OrderBy()`. EF Core requires an explicit `OrderBy` before pagination:
```csharp
// Fails in EF Core
var page = context.Orders.Skip(10).Take(5).ToList();

// Fix: add OrderBy
var page = context.Orders.OrderBy(o => o.Id).Skip(10).Take(5).ToList();
```

## String Comparison Behavior

LINQ to SQL uses database collation by default. EF Core may generate different comparison semantics depending on the provider.

Watch for case-sensitivity differences in:
- `String.Contains()` — LINQ to SQL uses `LIKE '%value%'`; EF Core generates similar SQL but collation may differ
- `String.StartsWith()` / `String.EndsWith()` — same issue
- `String.Equals()` with `StringComparison` parameter — EF Core may not translate all overloads

**Fix:** Use `EF.Functions.Like()` for explicit LIKE behavior, or configure database collation.

## Null Semantics

LINQ to SQL and EF Core handle null comparisons differently in generated SQL:
- LINQ to SQL sometimes generated `= NULL` (incorrect SQL)
- EF Core correctly generates `IS NULL`

This usually means EF Core is **more correct**, but queries relying on the old behavior may return different results.

## Let Clauses and Complex Subqueries

Complex LINQ queries with `let` clauses that worked in LINQ to SQL may not translate in EF Core:
```csharp
// May fail in EF Core
var results = from o in context.Orders
              let discount = CalculateDiscount(o.Total)
              where discount > 10
              select new { o, discount };
```

**Fix:** Refactor to inline expressions or split into multiple queries.

## Type Conversions in Queries

LINQ to SQL silently handled many type conversions. EF Core is stricter:
- `(int)someDecimal` in a query expression may not translate
- Enum-to-int conversions may behave differently
- DateTime format operations may not translate

**Fix:** Perform type conversions after materializing results.

## CompiledQuery

LINQ to SQL's `CompiledQuery.Compile()` has no equivalent — remove it. EF Core handles query compilation automatically via its internal query cache.

```csharp
// Remove this pattern entirely
static readonly Func<MyDataContext, int, Order> GetOrder =
    CompiledQuery.Compile((MyDataContext ctx, int id) => ctx.Orders.Single(o => o.Id == id));

// EF Core: just write the query normally
var order = context.Orders.Single(o => o.Id == id);
```
