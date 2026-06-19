# C# 11.0 Language Features

## Contents
- [Raw string literals](#raw-string-literals--always-apply)
- [List patterns](#list-patterns--always-apply)
- [Required members](#required-members--recommend)
- [Generic math / static abstract interface members](#generic-math--static-abstract-interface-members--opt-in)
- [Generic attributes](#generic-attributes--recommend)
- [UTF-8 string literals](#utf-8-string-literals--recommend)
- [File-local types](#file-local-types--recommend)
- [Newlines in string interpolation expressions](#newlines-in-string-interpolation-expressions--always-apply)
- [Pattern match Span on string constants](#pattern-match-spanchar-on-string-constants--always-apply)
- [Auto-default structs](#auto-default-structs--always-apply)
- [checked user-defined operators](#checked-user-defined-operators--opt-in)
- [Unsigned right-shift operator](#unsigned-right-shift-operator---opt-in)
- [Extended nameof scope](#extended-nameof-scope--always-apply)

.NET 7. Theme: generic math, raw strings, list patterns, required members.

---

## Raw string literals 🟢 ALWAYS-APPLY
Replace escaped strings (especially JSON, XML, regex, SQL) with raw string literals.

```csharp
// BEFORE
string json = "{\n  \"name\": \"Alice\",\n  \"age\": 30\n}";
string regex = "\\d+\\.\\d+";
string sql = "SELECT * FROM \"Users\" WHERE \"Name\" = 'Alice'";

// AFTER
string json = """
    {
      "name": "Alice",
      "age": 30
    }
    """;
string regex = """\\d+\\.\\d+""";  // single-line raw also works
string sql = """SELECT * FROM "Users" WHERE "Name" = 'Alice'""";
```

**With interpolation:** Use `$$` for raw interpolated strings:
```csharp
string json = $$"""
    {
      "name": "{{name}}",
      "age": {{age}}
    }
    """;
```

**Pattern to find:** Any string containing `\"`, `\\`, `\n`, or multi-line verbatim strings
(`@"..."`) with lots of `""` escapes.

**When NOT to apply:** Simple strings with one or two escapes where the raw literal adds more
visual overhead than it removes.

---

## List patterns 🟢 ALWAYS-APPLY
Pattern match on arrays, lists, and other indexable collections.

```csharp
// BEFORE
if (args.Length == 0) { ShowHelp(); }
else if (args.Length == 1 && args[0] == "--version") { ShowVersion(); }
else if (args.Length >= 2 && args[0] == "run") { Run(args[1]); }

// AFTER
switch (args)
{
    case []: ShowHelp(); break;
    case ["--version"]: ShowVersion(); break;
    case ["run", var target, ..]: Run(target); break;
}

// Or as a switch expression:
var result = numbers switch
{
    [] => "empty",
    [var x] => $"single: {x}",
    [var x, var y] => $"pair: {x}, {y}",
    [var first, .., var last] => $"first: {first}, last: {last}",
};
```

**Pattern to find:** Code that checks `.Length` / `.Count` and then indexes specific positions.

---

## Required members 🟡 RECOMMEND
Force callers to initialize specific properties via object initializers.

```csharp
// BEFORE
public class Person
{
    public string Name { get; set; } = null!;  // null-forgiving because "trust me, it's set"
    public string Email { get; set; } = null!;
    public int? Age { get; set; }
}

// AFTER
public class Person
{
    public required string Name { get; set; }
    public required string Email { get; set; }
    public int? Age { get; set; }
}
// Caller must: new Person { Name = "Alice", Email = "a@b.com" }
// Compiler error if Name or Email omitted.
```

**When NOT to apply:**
- Classes constructed by frameworks via reflection (DI, ORMs, serializers) — check that the
  framework supports `required`. System.Text.Json supports it (.NET 7+), EF Core 8+ supports it.
- Classes with parameterized constructors that already enforce initialization.

---

## Generic math / static abstract interface members 🔴 OPT-IN
Allows writing generic numeric algorithms using `INumber<T>`, `IAdditionOperators<T,T,T>`, etc.

```csharp
T Sum<T>(IEnumerable<T> values) where T : INumber<T>
{
    T result = T.Zero;
    foreach (var value in values)
        result += value;
    return result;
}
```

**When to apply:** Only when the user is building numeric libraries or generic math utilities.
Not for typical business logic.

---

## Generic attributes 🟡 RECOMMEND
Attributes can now be generic, avoiding `typeof()` arguments.

```csharp
// BEFORE
[TypeConverter(typeof(StringConverter))]
public string Name { get; set; }

// AFTER (if the attribute is defined as generic)
[TypeConverter<StringConverter>]
public string Name { get; set; }
```

**Note:** This only applies to custom attributes that the codebase defines. BCL attributes are
not retroactively made generic. Apply when modernizing custom attribute definitions.

---

## UTF-8 string literals 🟡 RECOMMEND
Use `u8` suffix for UTF-8 byte sequences, avoiding encoding overhead.

```csharp
// BEFORE
byte[] data = Encoding.UTF8.GetBytes("hello");

// AFTER
ReadOnlySpan<byte> data = "hello"u8;
```

**When to apply:** HTTP headers, protocol constants, performance-sensitive serialization paths.
Not for general string usage.

---

## File-local types 🟡 RECOMMEND
Restrict type visibility to the current file. Ideal for source generators but also useful for
helper types.

```csharp
file class HelperDto { ... } // only visible within this .cs file
```

**When to apply:** Private helper classes that are only used within one file and currently
pollute the namespace. Especially useful for test helper types.

---

## Newlines in string interpolation expressions 🟢 ALWAYS-APPLY
Interpolated strings can now contain newlines in the expression holes.

```csharp
// BEFORE — had to use a temporary variable
var temp = items.Count > 0 ? "some" : "none";
var msg = $"Found {temp} items";

// AFTER
var msg = $"Found {items.Count > 0
    ? "some"
    : "none"} items";
```

---

## Pattern match `Span<char>` on string constants 🟢 ALWAYS-APPLY
```csharp
ReadOnlySpan<char> span = input.AsSpan();
if (span is "hello") { ... }  // no allocation, compared character-by-character
```

**Pattern to find:** Code that calls `span.SequenceEqual("hello".AsSpan())` or
`MemoryExtensions.Equals(span, "hello", ...)`.

---

## Auto-default structs 🟢 ALWAYS-APPLY
Struct constructors auto-initialize fields to `default` even if not explicitly assigned.
This means workaround assignments like `field = default;` in struct constructors are removable.

```csharp
// BEFORE
public struct Pair
{
    public int X;
    public int Y;
    public Pair(int x)
    {
        X = x;
        Y = default; // Required pre-C# 11 to satisfy definite assignment
    }
}

// AFTER
public struct Pair
{
    public int X;
    public int Y;
    public Pair(int x)
    {
        X = x;
        // Y auto-defaults to 0
    }
}
```

---

## `checked` user-defined operators 🔴 OPT-IN
Only for custom numeric types implementing arithmetic operators.

---

## Unsigned right-shift operator (`>>>`) 🔴 OPT-IN
Replaces manual cast-and-shift patterns. Only relevant in bitwise manipulation code.

---

## Extended `nameof` scope 🟢 ALWAYS-APPLY
`nameof` can reference method parameters in attribute contexts.

```csharp
// BEFORE — had to use string literal
[return: NotNullIfNotNull("input")]
public string? Process(string? input) { ... }

// AFTER
[return: NotNullIfNotNull(nameof(input))]
public string? Process(string? input) { ... }
```
