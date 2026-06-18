# C# 8.0 Language Features

## Contents
- [Nullable reference types (NRT)](#nullable-reference-types-nrt--opt-in)
- [Switch expressions](#switch-expressions--always-apply)
- [Recursive / property patterns](#recursive--property-patterns--always-apply)
- [Using declarations](#using-declarations--always-apply)
- [Async streams](#async-streams-iasyncenumerablet--recommend)
- [Ranges and indexes](#ranges-and-indexes--always-apply)
- [Null-coalescing assignment](#null-coalescing-assignment--always-apply)
- [Static local functions](#static-local-functions--always-apply)
- [Default interface members](#default-interface-members--opt-in)
- [Readonly members on structs](#readonly-members-on-structs--recommend)
- [Disposable ref structs](#disposable-ref-structs--opt-in)
- [Verbatim interpolated string order](#verbatim-interpolated-string-order--always-apply)

.NET Core 3.x / .NET Standard 2.1. First version that specifically targets .NET Core — several
features require CLR or library support not available in .NET Framework.

---

## Nullable reference types (NRT) 🔴 OPT-IN
Enables the compiler to track nullability of reference types and warn on potential null
dereferences. Activated via `<Nullable>enable</Nullable>` in csproj or `#nullable enable` per file.

**Why OPT-IN:** Enabling NRT on an existing codebase typically produces hundreds of warnings.
It's a project-wide commitment that requires annotating APIs, adding null checks, and updating
signatures. It should be treated as its own dedicated migration, not a drive-by change.

**If the user explicitly asks for NRT:**
1. Add `<Nullable>enable</Nullable>` to the csproj.
2. Start with leaf projects (those with no dependents).
3. Annotate public API signatures first (`string?` for nullable, `string` for non-null).
4. Add `!` (null-forgiving) sparingly — each one is a potential runtime NRE.
5. Use `#nullable disable` to suppress sections that need more work.

---

## Switch expressions 🟢 ALWAYS-APPLY
Convert `switch` statements that assign to a single variable or return a value.

```csharp
// BEFORE
string GetColor(Status s)
{
    switch (s)
    {
        case Status.Active: return "green";
        case Status.Inactive: return "gray";
        case Status.Error: return "red";
        default: throw new ArgumentOutOfRangeException(nameof(s));
    }
}

// AFTER
string GetColor(Status s) => s switch
{
    Status.Active => "green",
    Status.Inactive => "gray",
    Status.Error => "red",
    _ => throw new ArgumentOutOfRangeException(nameof(s)),
};
```

**When NOT to apply:**
- Switch with side effects in case bodies (logging, mutations, multiple statements).
- Switch that doesn't consistently return/assign a single value.

---

## Recursive / property patterns 🟢 ALWAYS-APPLY
Pattern match into nested properties and combine with type patterns.

```csharp
// BEFORE
if (person != null && person.Address != null && person.Address.City == "Seattle") { ... }

// AFTER
if (person is { Address: { City: "Seattle" } }) { ... }
// Or with C# 10 extended property patterns: person is { Address.City: "Seattle" }
```

---

## Using declarations 🟢 ALWAYS-APPLY
Replace `using` blocks with `using` declarations when the scope naturally matches the enclosing block.

```csharp
// BEFORE
using (var stream = File.OpenRead(path))
{
    // ... entire method body
}

// AFTER
using var stream = File.OpenRead(path);
// ... rest of method — disposed at end of enclosing scope
```

**When NOT to apply:**
- When you need the `using` scope to end *before* the method ends (e.g., releasing a file lock
  before doing subsequent work in the same method).
- When the limited scope is semantically important and `using` declaration would extend lifetime.

---

## Async streams (`IAsyncEnumerable<T>`) 🟡 RECOMMEND
Convert synchronous `IEnumerable<T>`-returning methods that perform async work internally
(calling `.Result` or `.GetAwaiter().GetResult()`) to `async IAsyncEnumerable<T>`.

```csharp
// BEFORE
public IEnumerable<Item> GetItems()
{
    foreach (var id in ids)
        yield return FetchItemAsync(id).GetAwaiter().GetResult();
}

// AFTER
public async IAsyncEnumerable<Item> GetItemsAsync()
{
    foreach (var id in ids)
        yield return await FetchItemAsync(id);
}
// Consumer: await foreach (var item in GetItemsAsync()) { ... }
```

**When NOT to apply:** If the current synchronous implementation is intentional and callers don't
support `await foreach`. Changing the return type is a breaking API change.

---

## Ranges and indexes 🟢 ALWAYS-APPLY
Replace `Substring`, `Skip`/`Take`, and manual index math with range/index syntax.

```csharp
// BEFORE
var last = array[array.Length - 1];
var sub = text.Substring(1, text.Length - 2);
var firstThree = list.Take(3).ToArray();

// AFTER
var last = array[^1];
var sub = text[1..^1];
var firstThree = list.Take(3).ToArray(); // Range doesn't directly apply to IEnumerable
```

**Note:** Range syntax works on arrays, `string`, `Span<T>`, and types that implement
`Index`/`Range` support. It does NOT work on `List<T>` in .NET Core 3 (added in .NET 8 via
`CollectionsMarshal`). Don't apply blindly to `List<T>`.

---

## Null-coalescing assignment (`??=`) 🟢 ALWAYS-APPLY
```csharp
// BEFORE
if (list == null) list = new List<string>();
// or
list = list ?? new List<string>();

// AFTER
list ??= new List<string>();
```

---

## Static local functions 🟢 ALWAYS-APPLY
Add `static` to local functions that don't capture any enclosing variables. Prevents accidental
closure capture and signals intent.

```csharp
void Process(int[] data)
{
    var result = Transform(data);

    static int[] Transform(int[] input) => input.Select(x => x * 2).ToArray();
    // ^ static is valid because Transform doesn't capture any locals from Process
}
```

**How to detect:** If a local function doesn't reference any variables, parameters, or `this`
from the enclosing method, it can be `static`.

---

## Default interface members 🔴 OPT-IN
Allows adding methods with default implementations to interfaces. Powerful for API evolution
but changes the semantics of interface contracts. Only apply when the user is designing or
evolving an interface-heavy architecture.

---

## Readonly members on structs 🟡 RECOMMEND
Mark struct methods and properties as `readonly` when they don't mutate state. Enables compiler
optimizations and signals intent.

```csharp
public struct Point
{
    public int X { get; }
    public int Y { get; }
    public readonly double Distance => Math.Sqrt(X * X + Y * Y);
    public readonly override string ToString() => $"({X}, {Y})";
}
```

---

## Disposable ref structs 🔴 OPT-IN
Ref structs can implement a `Dispose()` pattern without implementing `IDisposable`.
Low-level performance feature.

---

## Verbatim interpolated string order 🟢 ALWAYS-APPLY
Both `$@"..."` and `@$"..."` are now valid. No transformation needed, but if linting flags one
form, both are acceptable in C# 8+.
