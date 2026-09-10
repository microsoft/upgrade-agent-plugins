# Concurrency and Change Tracking

## LINQ to SQL UpdateCheck Model

Each column can be individually configured for optimistic concurrency:

| Value | Behavior | Generated SQL |
|-------|----------|---------------|
| `UpdateCheck.Always` (default) | Include in WHERE clause of UPDATE | `UPDATE ... SET Col1=@new WHERE Col1=@orig AND Col2=@orig` |
| `UpdateCheck.WhenChanged` | Only include if column was modified | `UPDATE ... SET Col1=@new WHERE Col1=@orig` (only changed cols) |
| `UpdateCheck.Never` | Never include in concurrency check | Column excluded from WHERE |

## EF Core Concurrency Model

EF Core uses `[ConcurrencyCheck]` (per-property) or `[Timestamp]`/`IsRowVersion()` (row-version column). There is **no equivalent to `UpdateCheck.WhenChanged`**.

## Migration Decision Tree

### 1. Project uses `rowversion`/`timestamp` column
Straightforward — map to `[Timestamp]`:
```csharp
[Timestamp]
public byte[] RowVersion { get; set; }
```
Or Fluent API: `entity.Property(e => e.RowVersion).IsRowVersion();`

### 2. Project uses `UpdateCheck.Always` on all columns
**Recommended:** Add a `rowversion` column to the database. This is simpler and more performant than marking every property with `[ConcurrencyCheck]`.

```sql
ALTER TABLE Orders ADD RowVersion rowversion NOT NULL;
```

Alternative: Mark relevant columns with `[ConcurrencyCheck]` — but this generates large WHERE clauses.

### 3. Project uses `UpdateCheck.WhenChanged` — NO DIRECT EQUIVALENT
**Recommended:** Add a `rowversion` column (same as above). This provides equivalent protection with better performance.

Other options:
- Mark all potentially-modified columns with `[ConcurrencyCheck]` and handle conflicts in application code
- Custom `SaveChanges` override that builds dynamic SQL (complex, not recommended)

### 4. `UpdateCheck.Never` on specific columns
Those columns simply don't get `[ConcurrencyCheck]`. No action needed for them.

## Conflict Resolution API Mapping

| LINQ to SQL | EF Core |
|------------|---------|
| `ChangeConflictException` | `DbUpdateConcurrencyException` |
| `context.ChangeConflicts` collection | `ex.Entries` collection |
| `conflict.Resolve(RefreshMode.KeepChanges)` | Merge current + database values manually |
| `conflict.Resolve(RefreshMode.OverwriteCurrentValues)` | `entry.Reload()` or `entry.OriginalValues.SetValues(dbValues)` then `SaveChanges()` |
| `conflict.Resolve(RefreshMode.KeepCurrentValues)` | `entry.OriginalValues.SetValues(await entry.GetDatabaseValuesAsync())` then `SaveChanges()` |
| `conflict.MemberConflicts` per-column detail | `entry.GetDatabaseValues()` vs `entry.CurrentValues` vs `entry.OriginalValues` |

## Change Tracking Mechanism

LINQ to SQL uses snapshot-based tracking with `INotifyPropertyChanging` (the `.designer.cs` implements this). EF Core uses snapshot-based tracking by default.

**Action:** Remove `INotifyPropertyChanging` / `INotifyPropertyChanged` implementations and all `OnPropertyChanging` / `OnPropertyChanged` partial methods from entity classes. They are not needed by EF Core.
