# C# 15.0 Language Features

## Contents
- [Collection expression arguments](#collection-expression-arguments-with--recommend)
- [Breaking changes when upgrading to C# 15 / .NET 11 SDK](#breaking-changes-when-upgrading-to-c-15--net-11-sdk)

.NET 11. C# 15 is a focused release with collection expression enhancements.

**Note:** C# 15 ships with .NET 11 and Visual Studio 2026 v18.x. Features may still be
in preview. Verify availability before applying.

---

## Collection expression arguments (`with(...)`) 🟡 RECOMMEND
Pass arguments to the underlying collection's constructor or factory method by using a
`with(...)` element as the first element in a collection expression. This enables specifying
capacity, comparers, or other constructor parameters directly within the collection expression.

```csharp
// BEFORE — capacity requires separate construction
var names = new List<string>(capacity: values.Length * 2);
names.AddRange(values);

// AFTER — capacity inline with collection expression
List<string> names = [with(capacity: values.Length * 2), .. values];

// BEFORE — HashSet with comparer
var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Hello", "HELLO", "hello" };

// AFTER — comparer inline with collection expression
HashSet<string> set = [with(StringComparer.OrdinalIgnoreCase), "Hello", "HELLO", "hello"];
```

### More examples
```csharp
// Dictionary with capacity
Dictionary<string, int> dict = [with(capacity: 100), .. existingPairs];

// Frozen collections with comparer
FrozenSet<string> frozenSet = [with(StringComparer.OrdinalIgnoreCase), "A", "B", "C"];
```

**When to apply:**
- When collection expressions already exist but had to be split into construction + population
  because the constructor needed arguments (capacity, comparer, etc.).
- When `new List<T>(capacity)` followed by `AddRange` or manual adds can be expressed as a
  single collection expression.
- When `new HashSet<T>(comparer)` or `new Dictionary<TKey,TValue>(comparer)` initializers
  can be simplified.

**When NOT to apply:**
- If the code doesn't already use collection expressions — don't introduce `with(...)` as
  the first step. Convert to collection expressions first (C# 12 feature), then add `with(...)`
  where constructor arguments are needed.
- If the `with(...)` syntax reduces clarity — simple cases like `new List<string> { "a", "b" }`
  don't need `with(...)` unless capacity/comparer is involved.
- If targeting consumers on C# 14 or earlier — this syntax is only valid in C# 15+.

---

## Breaking changes when upgrading to C# 15 / .NET 11 SDK

These are compiler breaking changes in the .NET 10.0.100 → .NET 11.0.100 SDK range.
Review and fix any affected code **before** applying modernizations.

### `with()` as a collection expression element is treated as collection construction arguments
**Severity:** Compile error (possible)
**Introduced:** VS 2026 v18.4

In C# 15, `with(...)` as the first element in a collection expression is parsed as collection
construction arguments, not as an invocation of a method named `with`.

```csharp
// Code that worked in C# 14 but breaks in C# 15:
object[] items = [with(x, y), z];  // C# 14: call to with() method
                                    // C# 15: error — args not supported for object[]

// Fix: escape the method name
object[] items = [@with(x, y), z]; // Calls the with() method
```

**Detection:** Search for methods named `with` that may be called inside collection expressions.

### Span/ReadOnlySpan collection expression safe-context changed to declaration-block
**Severity:** Compile error
**Introduced:** VS 2026 v18.3

The safe-context of a collection expression of `Span<T>` / `ReadOnlySpan<T>` type is now
`declaration-block` (was `function-member`). Code that assigns a span collection expression
from an inner scope to an outer variable now fails.

```csharp
// BREAKS:
scoped Span<int> items1 = default;
foreach (var x in new[] { 1, 2 })
{
    Span<int> items = [x];
    items1 = items; // ERROR — safe-context is now declaration-block
}

// FIX: use array type instead
foreach (var x in new[] { 1, 2 })
{
    int[] items = [x];
    items1 = items; // OK — array conversion to Span<int>
}
```

### `ref readonly` synthesized delegates require `InAttribute`
**Severity:** Compile error
**Introduced:** VS 2026 v18.3

When the compiler synthesizes a delegate for a `ref readonly` returning method group or lambda,
it now correctly emits `InAttribute` metadata, which requires the type to be available.

```csharp
// May fail with: CS0518: Predefined type 'System.Runtime.InteropServices.InAttribute'
// is not defined or imported
var d = this.MethodWithRefReadonlyReturn;

// FIX: ensure the project references an assembly defining InAttribute
// (standard on .NET Core / .NET 5+; issue mainly on .NET Framework)
```

### Dynamic `&&`/`||` with interface left operand now disallowed
**Severity:** Compile error (previously runtime exception)
**Introduced:** VS 2026 v18.3

Using an interface type as the left operand of `&&` or `||` with a `dynamic` right operand
now produces a compile error instead of a runtime `RuntimeBinderException`.

```csharp
// BREAKS at compile time (previously failed at runtime):
I1 x = new C1();
dynamic y = new C1();
_ = x && y; // CS7083

// FIX: cast to concrete type or dynamic
_ = (C1)x && y;     // OK
_ = (dynamic)x && y; // OK
```

### `nameof(this.)` in attributes disallowed
**Severity:** Compile error
**Introduced:** VS 2026 v18.3 / .NET 10.0.200

Using `this` or `base` inside `nameof` in an attribute was previously unintentionally allowed
and is now disallowed.

```csharp
// BREAKS:
[System.Obsolete(nameof(this.P))] // error
void M() { }

// FIX: remove the qualifier
[System.Obsolete(nameof(P))]      // OK
void M() { }
```

### Parsing of `with` within a switch-expression-arm
**Severity:** Parsing change
**Introduced:** VS 2026 v18.4

Previously, `(X.Y) when` in a switch expression was parsed as a cast expression.
Now it's treated as a constant pattern `(X.Y)` followed by a `when` clause, which is the
intended behavior. Code relying on the old parsing may need parenthesization adjustments.
