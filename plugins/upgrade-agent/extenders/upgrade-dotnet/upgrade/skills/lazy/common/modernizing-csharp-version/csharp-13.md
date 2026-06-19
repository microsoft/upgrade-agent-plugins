# C# 13.0 Language Features

## Contents
- [params collections](#params-collections--always-apply)
- [New Lock type and semantics](#new-lock-type-and-semantics--recommend)
- [params Span overloads combined with collection expressions](#params-span-overloads-combined-with-collection-expressions)
- [Partial properties](#partial-properties--recommend)
- [ref struct interface implementation](#ref-struct-interface-implementation--opt-in)
- [ref/unsafe in iterators and async](#refunsafe-in-iterators-and-async--opt-in)
- [Overload resolution priority](#overload-resolution-priority--opt-in)
- [\e escape sequence](#e-escape-sequence--always-apply)
- [Implicit indexer access in object initializers](#implicit-indexer-access-in-object-initializers--always-apply)
- [Method group natural type improvements](#method-group-natural-type-improvements--always-apply)
- [Better conversion from collection expression element](#better-conversion-from-collection-expression-element--always-apply)

.NET 9. Incremental improvements: params collections, Lock object, partial properties.

---

## `params` collections 🟢 ALWAYS-APPLY
`params` now works with `Span<T>`, `ReadOnlySpan<T>`, `IEnumerable<T>`, `List<T>`, and other
collection types — not just arrays.

```csharp
// BEFORE — params only worked with arrays
public void Log(params string[] messages) { ... }
// Caller: Log("a", "b", "c"); // allocates a string[]

// AFTER — use Span to avoid allocation
public void Log(params ReadOnlySpan<string> messages) { ... }
// Caller: Log("a", "b", "c"); // stack-allocated, no array allocation
```

**When to apply:**
- Methods with `params T[]` that are called frequently in hot paths → change to `params ReadOnlySpan<T>`.
- Methods with `params T[]` where the array is only iterated → can change to `params IEnumerable<T>`
  or `params ReadOnlySpan<T>`.

**When NOT to apply:**
- If callers store the params array beyond the method call.
- If the method is part of a public API and changing `T[]` to `Span<T>` would be a breaking change
  for existing compiled callers.

---

## New `Lock` type and semantics 🟡 RECOMMEND
Replace `lock(object)` with `lock(Lock)` for better performance.

```csharp
// BEFORE
private readonly object _syncRoot = new();
lock (_syncRoot) { ... }

// AFTER
private readonly Lock _syncRoot = new();
lock (_syncRoot) { ... }
// Uses Lock.EnterScope() — more efficient than Monitor.Enter/Exit
```

**When to apply:** Any `private readonly object` field used solely as a lock target.

**When NOT to apply:**
- If the lock object is exposed to external callers (public or protected).
- If `Monitor.Wait`/`Pulse` is used (the new Lock type uses a different mechanism).
- If `lock()` is on `this` or a `Type` object (these are anti-patterns regardless).

---

## `params` Span overloads combined with collection expressions

```csharp
// These all work seamlessly in C# 13:
Log("single message");
Log("message 1", "message 2");
Log(..existingMessages);
// No array allocations in any case
```

---

## Partial properties 🟡 RECOMMEND
Split a property into declaration and implementation parts, analogous to partial methods.

```csharp
// Declaration (typically in generated code)
public partial class MyViewModel
{
    public partial string Name { get; set; }
}

// Implementation
public partial class MyViewModel
{
    private string _name = "";
    public partial string Name
    {
        get => _name;
        set
        {
            _name = value;
            OnPropertyChanged();
        }
    }
}
```

**When to apply:** Primarily for source generator scenarios (MVVM frameworks, serialization).
Don't introduce partial properties in hand-written code without a generator driving it.

---

## `ref struct` interface implementation 🔴 OPT-IN
`ref struct` types can now implement interfaces using the `allows ref struct` constraint.

```csharp
public interface IBufferWriter<T> where T : allows ref struct { ... }

public ref struct StackBuffer : IBufferWriter<byte>
{
    // ...
}
```

**When to apply:** Only for high-performance library code that needs ref struct types in
generic contexts. Not for typical application code.

---

## `ref`/`unsafe` in iterators and async 🔴 OPT-IN
Ref locals and unsafe blocks can be used in iterator and async methods between suspension points.

**When to apply:** Only when removing workaround patterns that extracted ref-using code into
separate methods to avoid the previous compiler restriction.

---

## Overload resolution priority 🔴 OPT-IN
`[OverloadResolutionPriority(n)]` lets library authors control which overload is preferred.
Only for library API design.

---

## `\e` escape sequence 🟢 ALWAYS-APPLY
Use `\e` instead of `\x1B` or `\u001B` for the ESC character (ANSI terminal codes).

```csharp
// BEFORE
string reset = "\x1B[0m";
string red = "\u001B[31m";

// AFTER
string reset = "\e[0m";
string red = "\e[31m";
```

**Pattern to find:** `\x1B`, `\x1b`, `\u001B`, `\u001b` in string literals.

---

## Implicit indexer access in object initializers 🟢 ALWAYS-APPLY
Use `^` (from-end) indexer in object initializers.

```csharp
// BEFORE
var buffer = new Buffer();
buffer[buffer.Length - 1] = value;

// AFTER
var buffer = new Buffer { [^1] = value };
```

---

## Method group natural type improvements 🟢 ALWAYS-APPLY
Compiler is better at inferring delegate types from method groups. Some explicit delegate
casts or type annotations that were needed before may now be removable.

---

## Better conversion from collection expression element 🟢 ALWAYS-APPLY
Overload resolution is improved when using collection expressions. If you had workaround casts
inside collection expressions, they may be removable now.
