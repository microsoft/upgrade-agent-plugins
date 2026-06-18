# C# 9.0 Language Features

## Contents
- [Top-level statements](#top-level-statements--recommend)
- [Records](#records--recommend)
- [Init-only setters](#init-only-setters--recommend)
- [Target-typed new expressions](#target-typed-new-expressions--always-apply)
- [Pattern matching enhancements](#pattern-matching-enhancements--always-apply)
- [Static anonymous functions](#static-anonymous-functions--always-apply)
- [Covariant returns](#covariant-returns--recommend)
- [Lambda discard parameters](#lambda-discard-parameters--always-apply)
- [Module initializers](#module-initializers--opt-in)
- [Function pointers](#function-pointers--opt-in)
- [Source generators](#source-generators--opt-in)

.NET 5. Major theme: removing ceremony, separating data from algorithms, more pattern matching.

---

## Top-level statements 🟡 RECOMMEND
Eliminate the `Program` class and `Main` method boilerplate for the application entry point.

```csharp
// BEFORE
namespace MyApp
{
    class Program
    {
        static async Task Main(string[] args)
        {
            var host = CreateHostBuilder(args).Build();
            await host.RunAsync();
        }
    }
}

// AFTER
var host = CreateHostBuilder(args).Build();
await host.RunAsync();
```

**When NOT to apply:**
- In libraries (only one project per solution can have top-level statements).
- When the `Program` class has additional static methods or configuration that would become
  awkward as top-level code.
- When the team has established conventions around `Program.cs` structure.

**Why RECOMMEND, not ALWAYS:** Some teams and analyzers prefer explicit `Program` class.
ASP.NET minimal hosting uses top-level statements by default, so this is the direction .NET is heading.

---

## Records 🟡 RECOMMEND
Convert data-carrier classes to `record` types for built-in value equality, `ToString`,
deconstruction, and `with` expression support.

```csharp
// BEFORE
public class PersonDto
{
    public string Name { get; set; }
    public int Age { get; set; }

    public override bool Equals(object obj) => obj is PersonDto other
        && Name == other.Name && Age == other.Age;
    public override int GetHashCode() => HashCode.Combine(Name, Age);
    public override string ToString() => $"PersonDto {{ Name = {Name}, Age = {Age} }}";
}

// AFTER
public record PersonDto(string Name, int Age);
```

**Strong candidates for conversion:**
- DTOs, view models, API request/response types
- Classes that override `Equals`/`GetHashCode` for value semantics
- Immutable data types

**When NOT to apply:**
- Classes with significant mutable state or side-effectful methods
- Entity Framework entity classes (EF identity semantics conflict with value equality)
- Classes deep in an inheritance hierarchy (records have their own inheritance rules)
- Classes where reference equality is intentional

---

## Init-only setters 🟡 RECOMMEND
Replace settable properties on otherwise-immutable types with `init` accessors.

```csharp
// BEFORE
public class Config
{
    public string ConnectionString { get; set; }  // set after construction, then never again
    public int Timeout { get; set; }
}

// AFTER
public class Config
{
    public string ConnectionString { get; init; }
    public int Timeout { get; init; }
}
// Still supports: new Config { ConnectionString = "...", Timeout = 30 }
// But prevents: config.ConnectionString = "other"; // after construction
```

**When NOT to apply:**
- Properties that genuinely need to be mutable after construction.
- Properties set by frameworks via reflection (some DI containers, ORMs — check compatibility).

---

## Target-typed `new` expressions 🟢 ALWAYS-APPLY
Remove redundant type name when it's obvious from the declaration.

```csharp
// BEFORE
Dictionary<string, List<int>> map = new Dictionary<string, List<int>>();
private readonly ILogger _logger = new Logger();

// AFTER
Dictionary<string, List<int>> map = new();
private readonly ILogger _logger = new Logger(); // Keep: target type is interface, can't use new()

// Works for field declarations, local variables, return statements, arguments:
List<string> items = new();
Point origin = new(0, 0);
```

**When NOT to apply:**
- When the target type is an interface or abstract class (can't `new()` those).
- When the type provides important documentation value: `object result = new MySpecificType()`
  is clearer than `object result = new()`.
- In `var` declarations (`var` already infers — `var x = new()` is illegal).

---

## Pattern matching enhancements 🟢 ALWAYS-APPLY
C# 9 adds relational, logical combinator, and type patterns.

### Relational patterns
```csharp
// BEFORE
if (temperature >= 0 && temperature <= 100) { ... }

// AFTER (in switch expressions or is-expressions)
temperature switch
{
    < 0 => "freezing",
    >= 0 and <= 32 => "cold",
    > 32 and <= 100 => "warm",
    > 100 => "hot",
};
```

### Logical patterns: `and`, `or`, `not`
```csharp
// BEFORE
if (obj != null) { ... }
if (s == null || s == "") { ... }

// AFTER
if (obj is not null) { ... }
if (s is null or "") { ... }
```

**`is not null` vs `!= null`:** Prefer `is not null` because it uses pattern matching and
doesn't invoke any overloaded `==` / `!=` operators. This is both safer and clearer.
Apply this transformation universally.

### Type patterns (without variable)
```csharp
// BEFORE
if (obj is string) { ... }  // C# 7 already allowed: if (obj is string s)

// AFTER (when you don't need the variable)
case string: // instead of: case string _:
```

---

## Static anonymous functions 🟢 ALWAYS-APPLY
Add `static` to lambdas and anonymous methods that don't capture enclosing state.

```csharp
// BEFORE
var filtered = items.Where(x => x > 5);  // no capture — can be static

// AFTER
var filtered = items.Where(static x => x > 5);
```

**When to apply:** When the lambda does not reference `this`, local variables, or parameters
from the enclosing scope. The `static` modifier prevents accidental capture.

**Caveat:** While technically correct, adding `static` to every non-capturing lambda can be
noisy. Apply judiciously — focus on performance-sensitive paths, hot loops, or when capturing
is a known concern. Some teams consider this too verbose for simple LINQ.

---

## Covariant returns 🟡 RECOMMEND
Override methods can return a more derived type than the base class signature.

```csharp
// BEFORE
public override Animal Clone() => new Cat(...);
// Callers needed to cast: var cat = (Cat)myCat.Clone();

// AFTER
public override Cat Clone() => new Cat(...);
```

---

## Lambda discard parameters 🟢 ALWAYS-APPLY
Use `_` for unused lambda parameters.

```csharp
// BEFORE
button.Click += (sender, e) => DoSomething();

// AFTER
button.Click += (_, _) => DoSomething();
```

---

## Module initializers 🔴 OPT-IN
`[ModuleInitializer]` runs code before anything else in the assembly. Specialized use case.

---

## Function pointers 🔴 OPT-IN
Low-level interop feature (`delegate*`). Only for high-performance native interop.

---

## Source generators 🔴 OPT-IN
Not a language syntax feature per se, but enables code generation at compile time. Relevant
when modernizing to use source-generated JSON serialization, logging, etc.
