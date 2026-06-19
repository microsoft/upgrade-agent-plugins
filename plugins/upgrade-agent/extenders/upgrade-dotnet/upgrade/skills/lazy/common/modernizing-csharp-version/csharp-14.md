# C# 14.0 Language Features

## Contents
- [Extension members](#extension-members-methods-properties-operators--recommend)
- [field keyword in properties](#field-keyword-in-properties--always-apply)
- [Null-conditional assignment](#null-conditional-assignment--always-apply)
- [Partial events and constructors](#partial-events-and-constructors--recommend)
- [User-defined compound assignment operators](#user-defined-compound-assignment-operators--recommend)
- [First-class Span types](#first-class-span-types--always-apply)
- [Simple lambda parameters with modifiers](#simple-lambda-parameters-with-modifiers--always-apply)
- [Unbound generic types in nameof](#unbound-generic-types-in-nameof--always-apply)
- [Ignored directives](#ignored-directives---opt-in)
- [Optional/named arguments in Expression trees](#optionalnamed-arguments-in-expression-trees--always-apply)
- [Breaking changes when upgrading to C# 14 / .NET 10 SDK](#breaking-changes-when-upgrading-to-c-14--net-10-sdk)

.NET 10. Theme: extensions overhaul, field keyword, null-conditional assignment.

**Note:** C# 14 ships with .NET 10 and Visual Studio 2026 v18.0. Some features may still be
in preview. Verify availability before applying.

---

## Extension members (methods, properties, operators) 🟡 RECOMMEND
The new `extension` block syntax replaces static-class-based extension methods with a richer
model that supports properties, operators, and static members.

```csharp
// BEFORE (classic extension methods)
public static class StringExtensions
{
    public static bool IsNullOrEmpty(this string? s) => string.IsNullOrEmpty(s);
    public static string Truncate(this string s, int maxLength) =>
        s.Length > maxLength ? s[..maxLength] : s;
}

// AFTER (C# 14 extension blocks)
public implicit extension StringExtensions for string
{
    public bool IsNullOrEmpty => string.IsNullOrEmpty(this);  // extension PROPERTY
    public string Truncate(int maxLength) =>
        this.Length > maxLength ? this[..maxLength] : this;
}
```

### Extension operators
```csharp
// BEFORE — not possible, had to use named methods
public static class DateTimeExtensions
{
    public static DateTime AddBusinessDays(this DateTime date, int days) { ... }
}

// AFTER — extension operator
public implicit extension DateTimeOperators for DateTime
{
    public static DateTime operator +(DateTime date, BusinessDays days) { ... }
}
```

**When to apply:**
- When modernizing existing extension method classes to take advantage of extension properties.
- When extension properties would simplify the API (e.g., computed values that read as properties).
- When extension operators would make domain-specific code more natural.

**When NOT to apply:**
- If all extensions in the class are methods and the static class pattern works fine.
- If the codebase needs to support consumers on older C# versions.
- Early adoption risk: this is a major language change. Wait for ecosystem stabilization
  before converting large extension libraries.

---

## `field` keyword in properties 🟢 ALWAYS-APPLY
Access the auto-generated backing field directly, eliminating the need to declare it manually
when you only need custom logic in one accessor.

```csharp
// BEFORE
private string _name = "";
public string Name
{
    get => _name;
    set
    {
        ArgumentException.ThrowIfNullOrEmpty(value);
        _name = value;
    }
}

// AFTER
public string Name
{
    get;
    set
    {
        ArgumentException.ThrowIfNullOrEmpty(value);
        field = value;
    }
}
```

**Pattern to find:** Properties with an explicit backing field where:
- The getter just returns the field (`get => _field;`)
- Or the setter just assigns to the field with some validation

**When NOT to apply:**
- When the backing field is referenced elsewhere in the class (not just through the property).
- When there's already a `field` variable in scope (name collision — the keyword takes
  precedence, which could silently change behavior).
- When both getter and setter have complex custom logic that references the field by name.

---

## Null-conditional assignment 🟢 ALWAYS-APPLY
Assign through a null-conditional chain.

```csharp
// BEFORE
if (customer?.Address != null)
{
    customer.Address.IsVerified = true;
}
// or
if (customer?.Address is { } addr)
{
    addr.IsVerified = true;
}

// AFTER
customer?.Address.IsVerified = true;

// Also works with indexers
customers?[0].IsActive = false;
```

**Pattern to find:** Null checks followed by assignment to a member of the checked object.

**When NOT to apply:** When the null check has additional logic in the else branch, or when
the assignment is part of a larger conditional block.

---

## Partial events and constructors 🟡 RECOMMEND
Like partial methods and partial properties, events and constructors can now be partial.

```csharp
// Declaration
public partial class ObservableList<T>
{
    public partial event EventHandler<T>? ItemAdded;
    public partial ObservableList();
}

// Implementation
public partial class ObservableList<T>
{
    private readonly List<T> _items = [];

    public partial ObservableList() => _items = [];

    public partial event EventHandler<T>? ItemAdded
    {
        add { ... }
        remove { ... }
    }
}
```

**When to apply:** Source generator scenarios. Don't split events/constructors manually without
a generator driving the pattern.

---

## User-defined compound assignment operators 🟡 RECOMMEND
Custom types can define `+=`, `-=`, etc. that modify the target in-place.

```csharp
// BEFORE — += allocates a new Matrix
public static Matrix operator +(Matrix a, Matrix b) => new Matrix(...);
// a += b creates a new Matrix and assigns it to a

// AFTER — in-place modification
public void operator +=(Matrix other)
{
    // modify this matrix in place
    for (int i = 0; i < Data.Length; i++)
        Data[i] += other.Data[i];
}
```

**When to apply:** Performance-critical numeric or container types where in-place modification
avoids allocation. Mathematical types (Vector, Matrix), buffer types.

**When NOT to apply:** Immutable types (where allocation on += is intentional).

---

## First-class `Span` types 🟢 ALWAYS-APPLY
Improved type inference and overload resolution for `Span<T>` and `ReadOnlySpan<T>`. Some
explicit casts or `.AsSpan()` calls may be removable.

```csharp
// BEFORE
ReadOnlySpan<char> span = text.AsSpan();
if (DoSomething(span)) { ... }

// AFTER (compiler may now infer conversions automatically)
if (DoSomething(text)) { ... } // implicit conversion to ReadOnlySpan<char>
```

**Check:** Remove unnecessary `.AsSpan()` calls and see if the code still compiles.

---

## Simple lambda parameters with modifiers 🟢 ALWAYS-APPLY
Lambda parameters can have `ref`, `in`, `out`, `scoped` modifiers without requiring explicit types.

```csharp
// BEFORE — had to specify types to use ref
Span<int> span = ...;
span.Sort((ref int a, ref int b) => a.CompareTo(b));

// AFTER
span.Sort((ref a, ref b) => a.CompareTo(b));
```

---

## Unbound generic types in `nameof` 🟢 ALWAYS-APPLY
```csharp
// BEFORE
string name = nameof(List<int>); // had to provide a type argument even though it's ignored

// AFTER
string name = nameof(List<>); // open generic, cleaner
```

---

## Ignored directives (`#:`) 🔴 OPT-IN
Used by `dotnet run app.cs` tooling. Not relevant for typical project-based code.

---

## Optional/named arguments in Expression trees 🟢 ALWAYS-APPLY
Workarounds for Expression tree limitations around optional and named parameters may be removable.

---

## Breaking changes when upgrading to C# 14 / .NET 10 SDK

These are compiler breaking changes in the .NET 9.0.100 → .NET 10.0.100 SDK range.
Review and fix any affected code **before** applying modernizations.

### `field` keyword in property accessors
**Severity:** Warning CS9258 / Error CS9272
**Introduced:** VS 2022 v17.12 / v17.14

The identifier `field` inside a property accessor now refers to a synthesized backing field.
This is a **silent behavior change** if you have a class member or local variable named `field`.

```csharp
// BREAKS — silent behavior change:
class MyClass
{
    private int field = 0;
    public object Property
    {
        get => field; // WARNING CS9258: now refers to synthesized backing field, not the member
    }
}

// FIX: use 'this.field' or '@field' to refer to the existing member
get => this.field;  // OK — explicitly references the class member
get => @field;      // OK — escaped identifier

// ERROR CS9272: declaring a local named 'field' in a property accessor
public object Property
{
    get { int field = 0; return @field; } // Must use @field
}
```

**Detection:** `grep -rn 'field' --include="*.cs"` and check for names inside property accessors.

### `extension` is now a contextual keyword
**Severity:** Compile error
**Introduced:** VS 2022 v17.14 / VS 2026 v18.0

The identifier `extension` is now reserved as a contextual keyword. Types, aliases, and type
parameters cannot be named `extension`.

```csharp
// BREAKS:
class extension { }              // error
using extension = SomeType;      // error
class C<extension> { }           // error

// FIX: use @extension
class @extension { }             // OK
```

### `partial` cannot be a return type
**Severity:** Compile error
**Introduced:** VS 2022 v17.14

Due to partial events/constructors, `partial` in more positions is treated as a modifier.

```csharp
// BREAKS:
partial F() => new partial();    // error

// FIX: escape the type name
@partial F() => new partial();   // OK
```

### `scoped` in lambda parameter list is always a modifier
**Severity:** Compile error
**Introduced:** VS 2022 v17.13

`scoped` is always treated as a modifier in lambda parameters, even if a type named `scoped` exists.

```csharp
// BREAKS:
var v = (scoped scoped s) => { };   // error — both treated as modifiers

// FIX: escape the type name
var v = (scoped @scoped s) => { };  // OK
```

### Span/ReadOnlySpan overloads applicable in more scenarios
**Severity:** Compile error / behavioral change
**Introduced:** VS 2022 v17.13

C# 14's implicit span conversions change overload resolution. `Span<T>` and `ReadOnlySpan<T>`
overloads are now applicable in more scenarios, which can cause ambiguities or select different
overloads.

```csharp
// May become ambiguous:
Assert.Equal([2], x);              // ambiguous between T[] and ReadOnlySpan<T>
Assert.Equal([2], x.AsSpan());     // fix: be explicit

// Behavioral change — Reverse now resolves to in-place Span version:
int[] x = new[] { 1, 2, 3 };
var y = x.Reverse();               // was Enumerable.Reverse, now MemoryExtensions.Reverse
var y = Enumerable.Reverse(x);     // fix: call explicitly
```

### Partial interface properties/events are now implicitly virtual and public
**Severity:** Behavioral change
**Introduced:** VS 2026 v18.0

Partial interface properties and events are now implicitly `virtual` and `public`,
matching non-partial equivalents.

```csharp
// Behavior change — P is now implicitly virtual:
partial interface I
{
    public partial int P { get; }
    public partial int P => 1; // implicitly virtual now — derived can override
}

// FIX (to preserve old behavior): explicitly mark sealed
partial interface I
{
    public sealed partial int P { get; }
    public sealed partial int P => 1;
}
```

### Other breaking changes (lower impact)
- **Diagnostics for pattern-based disposal in foreach**: Obsolete `DisposeAsync` methods now
  produce warnings in `await foreach`.
- **Enumerator disposal state**: `MoveNext()` on a disposed enumerator now properly returns
  `false` without executing more user code.
- **Redundant pattern warnings**: `is not null or 42` now warns that `42` is redundant (likely
  meant `is not (null or 42)`).
- **`UnscopedRefAttribute` with old ref safety rules**: No longer takes effect in C# 10 or earlier.
- **`EmbeddedAttribute` validation**: Must be `internal sealed class` inheriting `Attribute`.
- **`record`/`record struct` pointer members**: Properly disallowed even with custom `Equals`.
- **Missing `ParamCollectionAttribute`**: Reported in `.netmodule` compilations for lambdas/local
  functions with `params` collection parameters.
