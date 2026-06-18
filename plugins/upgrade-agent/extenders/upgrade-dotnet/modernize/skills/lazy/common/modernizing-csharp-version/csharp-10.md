# C# 10.0 Language Features

## Contents
- [File-scoped namespaces](#file-scoped-namespaces--always-apply)
- [Global using directives](#global-using-directives--recommend)
- [Record structs](#record-structs--recommend)
- [Extended property patterns](#extended-property-patterns--always-apply)
- [Constant interpolated strings](#constant-interpolated-strings--always-apply)
- [Lambda improvements](#lambda-improvements--always-apply)
- [with expression on structs and anonymous types](#with-expression-on-structs-and-anonymous-types--always-apply)
- [Improved definite assignment](#improved-definite-assignment--always-apply)
- [Parameterless struct constructors](#parameterless-struct-constructors--recommend)
- [CallerArgumentExpression](#callerargumentexpression--recommend)
- [Interpolated string handlers](#interpolated-string-handlers--opt-in)
- [File-scoped namespace + global usings combined effect](#file-scoped-namespace--global-usings-combined-effect)

.NET 6. Theme: reducing ceremony, global usings, file-scoped namespaces.

---

## File-scoped namespaces 🟢 ALWAYS-APPLY
Eliminate one level of indentation across the entire file.

```csharp
// BEFORE
namespace MyApp.Services
{
    public class UserService
    {
        // ...
    }
}

// AFTER
namespace MyApp.Services;

public class UserService
{
    // ...
}
```

**Apply universally** to files containing a single namespace declaration (which is ~99% of files).

**When NOT to apply:** Files that declare types in multiple namespaces (rare, but exists in
generated code or test files).

---

## Global using directives 🟡 RECOMMEND
Move frequently-repeated `using` statements to a single file (typically `GlobalUsings.cs` or
auto-generated via `<ImplicitUsings>enable</ImplicitUsings>` in csproj).

```csharp
// GlobalUsings.cs
global using System;
global using System.Collections.Generic;
global using System.Linq;
global using System.Threading.Tasks;
global using Microsoft.Extensions.Logging;
```

**Approach:**
1. Scan all `.cs` files for `using` directives.
2. Identify directives that appear in >50% of files.
3. Move those to a `GlobalUsings.cs` file.
4. Remove them from individual files.

**When NOT to apply:**
- If `<ImplicitUsings>` is already enabled in the csproj (the SDK already provides common usings).
- If the team prefers explicit usings per file for clarity.

**Note:** When `<ImplicitUsings>enable</ImplicitUsings>` is set (default for .NET 6+ projects),
the SDK automatically provides globals for `System`, `System.Collections.Generic`, `System.IO`,
`System.Linq`, `System.Net.Http`, `System.Threading`, `System.Threading.Tasks`. Check before
adding a manual `GlobalUsings.cs`.

---

## Record structs 🟡 RECOMMEND
Value-type records. Ideal for small, immutable value types.

```csharp
// BEFORE
public struct Point : IEquatable<Point>
{
    public int X { get; }
    public int Y { get; }
    public Point(int x, int y) { X = x; Y = y; }
    public bool Equals(Point other) => X == other.X && Y == other.Y;
    public override bool Equals(object obj) => obj is Point p && Equals(p);
    public override int GetHashCode() => HashCode.Combine(X, Y);
}

// AFTER
public readonly record struct Point(int X, int Y);
```

**Strong candidates:** Small value types that override `Equals`/`GetHashCode`, coordinate types,
ID wrappers, measurement types.

**When NOT to apply:** Structs with mutable fields/properties that are mutated in-place.

---

## Extended property patterns 🟢 ALWAYS-APPLY
Access nested properties in patterns without nesting braces.

```csharp
// BEFORE (C# 8)
if (order is { Customer: { Address: { Country: "US" } } }) { ... }

// AFTER (C# 10)
if (order is { Customer.Address.Country: "US" }) { ... }
```

---

## Constant interpolated strings 🟢 ALWAYS-APPLY
Interpolated strings composed of constants are now `const`-eligible.

```csharp
// BEFORE
const string prefix = "api";
const string version = "v2";
const string endpoint = prefix + "/" + version; // string concat required

// AFTER
const string prefix = "api";
const string version = "v2";
const string endpoint = $"{prefix}/{version}"; // now valid as const
```

---

## Lambda improvements 🟢 ALWAYS-APPLY
Lambdas can have natural types, explicit return types, and attributes.

```csharp
// Natural type — enables assigning to var
var parse = (string s) => int.Parse(s); // inferred as Func<string, int>

// Explicit return type
var choose = object (bool b) => b ? 1 : "text";

// Attributes on lambdas
var validate = [MyAttribute] (string s) => s.Length > 0;
```

**Typical transformation:** When a lambda is assigned to a `Func<>` / `Action<>` local, you
can often change to `var` if the parameter types are specified in the lambda.

---

## `with` expression on structs and anonymous types 🟢 ALWAYS-APPLY
The `with` expression now works on all structs and anonymous types, not just records.

```csharp
var point = new Point(1, 2);
var moved = point with { X = 10 }; // works on any struct in C# 10
```

---

## Improved definite assignment 🟢 ALWAYS-APPLY
The compiler is smarter about null-state analysis. Some workaround casts or suppressions may
be removable.

```csharp
// BEFORE — compiler false positive, needed workaround
if (dict?.TryGetValue(key, out var value) == true)
{
    // Before C# 10: compiler wasn't sure `value` was assigned
    Console.WriteLine(value!); // null-forgiving operator as workaround
}

// AFTER — compiler correctly understands value is assigned
if (dict?.TryGetValue(key, out var value) == true)
{
    Console.WriteLine(value); // no ! needed
}
```

**Look for:** Unnecessary `!` (null-forgiving) operators or explicit casts that were added
to suppress false compiler warnings in older versions.

---

## Parameterless struct constructors 🟡 RECOMMEND
Structs can now have explicit parameterless constructors and field initializers.

```csharp
// BEFORE — had to use factory method
public struct Options
{
    public int Timeout;
    public static Options Default => new Options { Timeout = 30 };
}

// AFTER
public struct Options
{
    public int Timeout = 30; // field initializer
    public Options() { }     // parameterless constructor
}
```

**Caveat:** `default(Options)` still zero-initializes (bypasses constructor). Only `new Options()`
calls the constructor. This can be confusing — apply only when the team understands the distinction.

---

## CallerArgumentExpression 🟡 RECOMMEND
Capture the text of an argument expression for better error messages.

```csharp
public static void ThrowIfNull(
    object? argument,
    [CallerArgumentExpression(nameof(argument))] string? paramName = null)
{
    if (argument is null) throw new ArgumentNullException(paramName);
}

// Usage: ThrowIfNull(config.Connection);
// Exception message includes "config.Connection" automatically
```

**When to apply:** When modernizing validation/guard methods. .NET 6+ provides
`ArgumentNullException.ThrowIfNull()` which uses this internally.

---

## Interpolated string handlers 🔴 OPT-IN
Advanced performance feature for custom string formatting. Only relevant when building
logging frameworks, string builders, or other formatting infrastructure.

---

## File-scoped namespace + global usings combined effect

When applying both file-scoped namespaces and global usings, the typical file shrinks
significantly:

```csharp
// BEFORE (C# 9 and earlier)
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace MyApp.Services
{
    public class OrderService
    {
        // 1 level of indentation for everything
    }
}

// AFTER (C# 10)
namespace MyApp.Services;

public class OrderService
{
    // 0 wasted indentation levels, usings handled globally
}
```

This compound effect is one of the biggest visual modernizations in C# history.
