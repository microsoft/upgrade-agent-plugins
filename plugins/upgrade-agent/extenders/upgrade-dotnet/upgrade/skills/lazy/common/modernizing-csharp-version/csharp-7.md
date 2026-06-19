# C# 7.0 – 7.3 Language Features

## Contents
- [C# 7.0](#c-70)
- [C# 7.1](#c-71)
- [C# 7.2](#c-72)
- [C# 7.3](#c-73)

Covers features from C# 7.0 (VS 2017), 7.1, 7.2, and 7.3.
These are the baseline "modern C#" features. Most codebases targeting .NET Framework 4.7+ or
.NET Core 2.x already use many of these — this reference helps catch ones that were missed.

---

## C# 7.0

### Out variables 🟢 ALWAYS-APPLY
Declare out variables inline instead of pre-declaring them.

**Pattern to find:** Variable declared on a prior line solely to be used as an `out` argument.
```csharp
// BEFORE
int result;
if (int.TryParse(input, out result)) { ... }

// AFTER
if (int.TryParse(input, out var result)) { ... }
```
Also works with explicit types: `out int result`. Prefer `var` when the type is obvious from context.

**When NOT to apply:** If the variable is used in both branches (success and failure paths) and
was intentionally declared in the outer scope for that reason.

---

### Pattern matching (type patterns and const patterns) 🟢 ALWAYS-APPLY
Replace `is` + cast and `as` + null-check with pattern matching.

**Pattern to find:**
```csharp
// BEFORE: is + cast
if (obj is MyType)
{
    var typed = (MyType)obj;
    typed.DoSomething();
}

// AFTER
if (obj is MyType typed)
{
    typed.DoSomething();
}

// BEFORE: as + null check
var typed = obj as MyType;
if (typed != null) { ... }

// AFTER
if (obj is MyType typed) { ... }
```

**When NOT to apply:** If the `as` result is intentionally stored and used across multiple
conditional branches, the `as` pattern may be more readable.

---

### Tuples and deconstruction 🟡 RECOMMEND
Replace custom "pair" / "result" classes or out-parameter groups with tuples.

**Pattern to find:** Methods returning custom types that exist solely to carry 2–3 values,
or methods with multiple `out` parameters.
```csharp
// BEFORE
public ResultPair GetMinMax(int[] values) { ... }

// AFTER
public (int Min, int Max) GetMinMax(int[] values) { ... }

// Deconstruction
var (min, max) = GetMinMax(values);
```

**When NOT to apply:**
- If the return type is part of a public API and callers depend on the class name/shape.
- If the "pair" class has methods or validation logic beyond simple data carrying.

---

### Local functions 🟡 RECOMMEND
Replace private helper methods only called from one place with local functions. Also replace
lambdas that don't capture variables and are used for readability.

```csharp
// BEFORE
public void Process(IEnumerable<Item> items)
{
    foreach (var item in items)
        ValidateItem(item);
}
private void ValidateItem(Item item) { /* only called from Process */ }

// AFTER
public void Process(IEnumerable<Item> items)
{
    foreach (var item in items)
        ValidateItem(item);

    void ValidateItem(Item item) { ... }
}
```

**When NOT to apply:** If the helper is tested independently, or called from multiple methods.

---

### Digit separators and binary literals 🟢 ALWAYS-APPLY
Add separators to large numeric literals for readability.

```csharp
// BEFORE
int million = 1000000;
long mask = 0xFF00FF00;

// AFTER
int million = 1_000_000;
long mask = 0xFF_00_FF_00;
// Binary: int flags = 0b1010_0101;
```

---

### Throw expressions 🟢 ALWAYS-APPLY
Use throw in expression contexts (null-coalescing, ternary, expression-bodied members).

```csharp
// BEFORE
public string Name
{
    get { return _name; }
    set
    {
        if (value == null) throw new ArgumentNullException(nameof(value));
        _name = value;
    }
}

// AFTER
private string _name;
public string Name
{
    get => _name;
    set => _name = value ?? throw new ArgumentNullException(nameof(value));
}
```

---

### Expression-bodied members (expanded) 🟢 ALWAYS-APPLY
C# 7.0 expanded expression bodies to constructors, destructors, property accessors, and indexers.

```csharp
// Apply when the body is a single expression/statement
public class Person
{
    private string _name;
    public Person(string name) => _name = name;
    ~Person() => Console.WriteLine("Finalized");
    public string Name
    {
        get => _name;
        set => _name = value ?? throw new ArgumentNullException(nameof(value));
    }
}
```

**When NOT to apply:** If the body has side effects that benefit from being visually prominent
in a full block, or if the expression would exceed ~100 characters.

---

### Ref returns and locals 🔴 OPT-IN
Allow returning references to internal storage. Performance-sensitive, low-level feature.

---

## C# 7.1

### Default literal expressions 🟢 ALWAYS-APPLY
Use `default` without the type when it can be inferred.

```csharp
// BEFORE
int x = default(int);
CancellationToken ct = default(CancellationToken);
void M(string s = default(string)) { }

// AFTER
int x = default;
CancellationToken ct = default;
void M(string s = default) { }
```

---

### Async Main 🟢 ALWAYS-APPLY
If `Main` calls `.GetAwaiter().GetResult()` or `.Result`, convert to `async Task Main`.

```csharp
// BEFORE
static void Main(string[] args) { RunAsync().GetAwaiter().GetResult(); }

// AFTER
static async Task Main(string[] args) { await RunAsync(); }
```

---

### Inferred tuple element names 🟢 ALWAYS-APPLY
Remove redundant tuple element names when they match the source variable.

```csharp
// BEFORE
var t = (name: name, age: age);

// AFTER
var t = (name, age); // names inferred as .name and .age
```

---

## C# 7.2

### `in` parameters 🟡 RECOMMEND
Use `in` for large readonly struct parameters to avoid copying.

```csharp
// BEFORE
public double CalculateDistance(Vector3 a, Vector3 b) { ... }

// AFTER
public double CalculateDistance(in Vector3 a, in Vector3 b) { ... }
```

**When NOT to apply:** For small structs (≤16 bytes), `in` adds indirection overhead.
Don't apply to primitive types or small structs. Best for large custom value types.

---

### `private protected` access modifier 🟡 RECOMMEND
Use when you need "derived classes in the same assembly only."

---

### `Span<T>` and ref-like types 🔴 OPT-IN
Performance feature for stack-allocated memory. Only apply when actively optimizing hot paths.

---

## C# 7.3

### Tuple `==` and `!=` 🟢 ALWAYS-APPLY
Replace manual element-wise tuple comparison with operators.

```csharp
// BEFORE
if (point.Item1 == other.Item1 && point.Item2 == other.Item2) { ... }

// AFTER (if using tuples)
if (point == other) { ... }
```

---

### `stackalloc` initializers 🔴 OPT-IN
Performance-only. `Span<int> x = stackalloc[] { 1, 2, 3 };`

---

### Attributes on auto-property backing fields 🟢 ALWAYS-APPLY
Use `[field: ...]` syntax to apply attributes to the backing field.

```csharp
// BEFORE: Had to write manual property with backing field for serialization attributes
// AFTER
[field: NonSerialized]
public string Name { get; set; }
```

---

### Expression variables in more locations 🟢 ALWAYS-APPLY
Out variables and pattern variables now work in field initializers, constructor initializers,
and LINQ query clauses.

---

### Improved overload resolution 🟢 ALWAYS-APPLY
No code changes needed — the compiler resolves more overloads correctly.
Existing workaround casts for overload ambiguity may be removable.
