# C# 12.0 Language Features

## Contents
- [Collection expressions](#collection-expressions--always-apply)
- [Primary constructors](#primary-constructors--recommend)
- [Alias any type](#alias-any-type--recommend)
- [Inline arrays](#inline-arrays--opt-in)
- [Ref readonly parameters](#ref-readonly-parameters--recommend)
- [Lambda optional parameters and params](#lambda-optional-parameters-and-params--always-apply)
- [Interceptors](#interceptors--opt-in)
- [Nameof accessing instance members](#nameof-accessing-instance-members--always-apply)
- [Combined modernization: DI service class (C# 12)](#combined-modernization-di-service-class-c-12)

.NET 8. Theme: collection expressions, primary constructors, alias any type.

---

## Collection expressions 🟢 ALWAYS-APPLY
Unified syntax for creating arrays, lists, spans, and other collections.

```csharp
// BEFORE
int[] numbers = new int[] { 1, 2, 3 };
List<string> names = new List<string> { "Alice", "Bob" };
Span<int> span = stackalloc int[] { 1, 2, 3 };
ImmutableArray<int> immutable = ImmutableArray.Create(1, 2, 3);

// AFTER
int[] numbers = [1, 2, 3];
List<string> names = ["Alice", "Bob"];
Span<int> span = [1, 2, 3];
ImmutableArray<int> immutable = [1, 2, 3];

// Empty collections
List<int> empty = [];            // replaces new List<int>()
int[] emptyArray = [];           // replaces Array.Empty<int>()
```

### Spread operator (`..`)
```csharp
int[] first = [1, 2, 3];
int[] second = [4, 5, 6];
int[] combined = [..first, ..second];  // replaces first.Concat(second).ToArray()

// Prepend/append
int[] withHeader = [0, ..values];
int[] withTrailer = [..values, 99];
```

**Pattern to find:**
- `new T[] { ... }` → `[...]`
- `new List<T> { ... }` → `[...]`
- `Array.Empty<T>()` → `[]`
- `Enumerable.Empty<T>()` → `[]` (when assigned to a concrete type)
- `.Concat(...).ToArray()` / `.ToList()` → `[..a, ..b]`
- `ImmutableArray.Create(...)` → `[...]`

**When NOT to apply:**
- When the target type is ambiguous (e.g., the variable is typed as `IEnumerable<T>` and the
  compiler can't determine which collection type to create).
- When constructing with a specific capacity or comparer: `new List<int>(capacity: 100)` can't
  be expressed as a collection expression.

---

## Primary constructors 🟡 RECOMMEND
Eliminate constructor + field assignment boilerplate for dependency injection and simple initialization.

```csharp
// BEFORE
public class OrderService
{
    private readonly IOrderRepository _repo;
    private readonly ILogger<OrderService> _logger;

    public OrderService(IOrderRepository repo, ILogger<OrderService> logger)
    {
        _repo = repo;
        _logger = logger;
    }

    public async Task<Order> GetOrder(int id) => await _repo.FindAsync(id);
}

// AFTER
public class OrderService(IOrderRepository repo, ILogger<OrderService> logger)
{
    public async Task<Order> GetOrder(int id) => await repo.FindAsync(id);
}
```

**Important behavior difference:** Primary constructor parameters are NOT fields — they're
captured parameters. If you need a `readonly` field guarantee, assign to a field:
```csharp
public class OrderService(IOrderRepository repo)
{
    private readonly IOrderRepository _repo = repo; // explicitly readonly
    // repo parameter is also still accessible but can be reassigned
}
```

**Strong candidates:**
- DI service classes with constructor injection
- Simple wrapper/adapter classes
- Classes where the constructor just assigns parameters to fields

**When NOT to apply:**
- Classes with complex constructor logic (validation, computed fields, conditional init).
- When the class has multiple constructors.
- When the mutable-parameter semantics would be surprising (the parameter is not `readonly`).
- Large classes (>100 lines) where the constructor parameters feel disconnected from usage.
- When the private backing fields are referenced by name elsewhere (serialization, reflection).

---

## Alias any type 🟡 RECOMMEND
`using` aliases now work for tuples, arrays, generics, and other complex types.

```csharp
// BEFORE — no way to alias these
// Had to type the full thing every time
Dictionary<string, List<(int Id, string Name)>> lookup = ...;

// AFTER
using Lookup = System.Collections.Generic.Dictionary<string,
    System.Collections.Generic.List<(int Id, string Name)>>;

Lookup lookup = ...;
```

Also works for:
```csharp
using Point = (int X, int Y);          // tuple alias
using Numbers = int[];                   // array alias
using Handler = System.Func<string, Task<bool>>;  // delegate alias
```

**When to apply:** Complex generic types that appear repeatedly. Tuple types used as
ad-hoc structures across multiple methods.

---

## Inline arrays 🔴 OPT-IN
`[InlineArray(size)]` attribute for fixed-size stack-allocated buffers. Performance feature
for library authors and runtime internals.

---

## Ref readonly parameters 🟡 RECOMMEND
Stricter than `in` — makes it explicit that the parameter is by-ref and readonly.

```csharp
// Subtly different from 'in': callers can't accidentally pass an rvalue
void Process(ref readonly int value) { ... }
```

**When to apply:** When modernizing library APIs that use `in` parameters and want to be
more explicit about the contract.

---

## Lambda optional parameters and params 🟢 ALWAYS-APPLY
Lambdas can now have default parameter values and `params`.

```csharp
// BEFORE — had to use a full method or overloads
Func<string, int, string> truncate = (s, maxLength) => s.Length > maxLength ? s[..maxLength] : s;

// AFTER
var truncate = (string s, int maxLength = 50) => s.Length > maxLength ? s[..maxLength] : s;
truncate("hello"); // maxLength defaults to 50
```

---

## Interceptors 🔴 OPT-IN
Experimental. Allows source generators to intercept specific method calls. Not for general use.

---

## Nameof accessing instance members 🟢 ALWAYS-APPLY
`nameof` can reference instance members from static contexts (e.g., attributes on static members).

```csharp
// BEFORE — had to use string literal
[JsonPropertyName("items")]
public List<Item> Items { get; set; }

// AFTER (when nameof is useful for refactoring safety)
// This specific example doesn't change, but in validation attributes:
[MaxLength(100, ErrorMessage = nameof(Name) + " is too long")]
public string Name { get; set; }
```

---

## Combined modernization: DI service class (C# 12)

Showing the compound effect of collection expressions + primary constructors + file-scoped
namespace + target-typed new + pattern matching:

```csharp
// BEFORE (C# 7-era style)
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Extensions.Logging;

namespace MyApp.Services
{
    public class NotificationService
    {
        private readonly IEmailSender _emailSender;
        private readonly ISmsSender _smsSender;
        private readonly ILogger<NotificationService> _logger;

        public NotificationService(
            IEmailSender emailSender,
            ISmsSender smsSender,
            ILogger<NotificationService> logger)
        {
            _emailSender = emailSender;
            _smsSender = smsSender;
            _logger = logger;
        }

        public async Task NotifyAsync(User user, string message)
        {
            var channels = new List<string>();
            if (user.Email != null)
                channels.Add("email");
            if (user.Phone != null)
                channels.Add("sms");

            if (channels.Count == 0)
            {
                _logger.LogWarning("No channels for user {Id}", user.Id);
                return;
            }

            foreach (var channel in channels)
            {
                switch (channel)
                {
                    case "email":
                        await _emailSender.SendAsync(user.Email, message);
                        break;
                    case "sms":
                        await _smsSender.SendAsync(user.Phone, message);
                        break;
                }
            }
        }
    }
}

// AFTER (C# 12 fully modernized)
namespace MyApp.Services;

public class NotificationService(
    IEmailSender emailSender,
    ISmsSender smsSender,
    ILogger<NotificationService> logger)
{
    public async Task NotifyAsync(User user, string message)
    {
        List<string> channels = [
            ..user.Email is not null ? ["email"] : [],
            ..user.Phone is not null ? ["sms"] : [],
        ];

        if (channels is [])
        {
            logger.LogWarning("No channels for user {Id}", user.Id);
            return;
        }

        foreach (var channel in channels)
        {
            _ = channel switch
            {
                "email" => emailSender.SendAsync(user.Email!, message),
                "sms" => smsSender.SendAsync(user.Phone!, message),
                _ => Task.CompletedTask,
            };
        }
    }
}
```
