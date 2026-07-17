## Contents
- Use the heading outline to navigate sections quickly.
## New Project Setup

### Framework Requirements

**Minimum Versions:**

- .NET 8+ (required for MVVM features)
- .NET 9+ (recommended for DarkMode support)
- .NET 10+ (latest features)

### Project Configuration

**Basic project file (.csproj):**
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net10.0-windows</TargetFramework>
    <UseWindowsForms>true</UseWindowsForms>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
```

**Windows API Projection (for Windows-specific features):**

Only use for Windows-specific projects (NOT class libraries or analyzers):

```xml
<!-- .NET 9 -->
<TargetFramework>net9.0-windows10.0.22000.0</TargetFramework>

<!-- .NET 10 -->
<TargetFramework>net10.0-windows10.0.22000.0</TargetFramework>
```

**NuGet Package References:**

Use well-known, stable packages with latest STABLE major version:
```xml
<PackageReference Include="PackageName" Version="[2.*,)" />
```

### Application Startup Configuration

**C# Program.cs:**

```csharp
using System;
using System.Windows.Forms;

namespace MyApp;

static class Program
{
    [STAThread]
    static void Main()
    {
        ApplicationConfiguration.Initialize();
        
        // .NET 9+ - Enable DarkMode support
        Application.SetColorMode(SystemColorMode.System);
        
        // DPI awareness
        Application.SetHighDpiMode(HighDpiMode.SystemAware);
        
        Application.Run(new MainForm());
    }
}
```

**Visual Basic ApplicationEvents.vb:**

VB uses the Application Framework (no Program.vb):

```vb
Namespace My
    Partial Friend Class MyApplication
        Private Sub MyApplication_ApplyApplicationDefaults(sender As Object, e As ApplyApplicationDefaultsEventArgs) Handles Me.ApplyApplicationDefaults
            ' .NET 9+ - Enable DarkMode support
            e.ColorMode = SystemColorMode.System
            
            ' Default font
            e.Font = New Font("Segoe UI", 9.0F)
            
            ' DPI awareness
            e.HighDpiMode = HighDpiMode.SystemAware
        End Sub
    End Class
End Namespace
```

### Configuration Best Practices

**Do NOT use:**

- ❌ app.config files for DPI settings
- ❌ manifest files for DPI configuration
- ❌ Legacy configuration approaches

**Do use:**

- ✅ `Application.SetHighDpiMode()` at startup
- ✅ `Application.SetColorMode()` for DarkMode (.NET 9+)
- ✅ Code-based configuration

## Two Code Contexts

WinForms has fundamentally different contexts with different rules:

### Designer Code Context

**Files:** `*.Designer.cs`, `*.Designer.vb`
**Method:** `InitializeComponent`
**Language Level:** C# 2.0 features only (.NET 10 and below), C# features up to partial methods (.NET 11+)
**Purpose:** Serialization format for Designer

**Critical Rules:**

- This is a SERIALIZATION FORMAT, not regular code
- Designer is a PARSER tool, not a compiler
- Code represents declarative UI structure
- Must follow strict patterns for Designer compatibility

See the **managing-winforms-designer-code** skill for complete Designer rules.

### Regular Code Context

**Files:** `*.cs`, `*.vb` (except Designer files)
**Methods:** Event handlers, business logic, custom methods
**Language Level:** Modern C# 11-14, VB 16+
**Purpose:** Application logic and behavior

**Use ALL modern language features:**

- Nullable reference types
- Pattern matching
- Switch expressions
- Record types
- Global usings
- File-scoped namespaces
- Target-typed new
- And more

## Modern C# Conventions

Apply ONLY to regular code files, NEVER in Designer files.

### Type Usage

```csharp
// ✅ Use primitive type names
int count;
string name;
bool isValid;

// ❌ Don't use CLR type names
Int32 count;
String name;
Boolean isValid;
```

### Object Instantiation

```csharp
// ✅ Target-typed new
Button button = new();
List<string> items = [];

// ❌ Verbose
Button button = new Button();
List<string> items = new List<string>();
```

### var Usage

```csharp
// ✅ Use var for obvious or very long types
var items = new List<string>();
var lookup = GetComplexDictionaryType();

// ❌ Don't use var for primitives
int count = 10;        // Not: var count = 10;
string name = "John";  // Not: var name = "John";
```

### Nullable Event Handlers

```csharp
// ✅ Modern pattern
private void Button_Click(object? sender, EventArgs e)
{
    // sender can be null
}
```

### Argument Validation

```csharp
// ✅ .NET 8+ throw helpers
public void Process(Control control)
{
    ArgumentNullException.ThrowIfNull(control);
    // Process control
}

// ❌ Old pattern
public void Process(Control control)
{
    if (control == null)
        throw new ArgumentNullException(nameof(control));
}
```

### Property Patterns (CRITICAL)

**Understand memory implications:**

```csharp
// ❌ MEMORY LEAK - Creates new instance on EVERY access!
public List<string> Items => new List<string>();

// ✅ Cached - Created once at construction
public List<string> Items { get; } = new();

// ✅ Lazy initialization - Computed once when needed
private List<string>? _items;
public List<string> Items => _items ??= new List<string>();
```

**NEVER refactor between these patterns without understanding the semantic differences!**

### Raw String Literals

```csharp
string sql = 
    """
    SELECT *
    FROM Users
    WHERE Active = 1
    """;
```

**Rules:**

- Opening `"""` MUST be on its own line
- Closing `"""` MUST be on its own line
- Vertical position defines whitespace trimming

### XML Documentation

**Always include for:**

- `public` scope
- `internal` scope
- `protected` scope
- `private protected` scope
- `protected internal` scope
- Interface implementations

**Format:**

```csharp
/// <summary>
///  Brief description of the method.
/// </summary>
/// <param name="value">Parameter description.</param>
/// <returns>Return value description.</returns>
/// <remarks>
///  <para>
///   First paragraph of detailed information.
///  </para>
///  <para>
///   Second paragraph of additional details.
///  </para>
/// </remarks>
public int Process(int value)
{
    return value * 2;
}
```

**Guidelines:**

- Use 1-space indentation
- Use `<para>` tags for multiple paragraphs
- Use `<inheritdoc/>` where applicable
- Include `<exception>` for documented exceptions

## File Structure

### Form/UserControl Organization

**FormName.cs** - Application logic and behavior
**FormName.Designer.cs** - Designer-generated infrastructure

### C# Conventions

```csharp
// File-scoped namespace (C# 10+)
namespace MyApp.Forms;

// Global usings assumed
// using System;
// using System.Windows.Forms;
// using System.Drawing;

public partial class MainForm : Form
{
    public MainForm()
    {
        InitializeComponent();
    }
    
    // Event handlers with nullable sender
    private void Button_Click(object? sender, EventArgs e)
    {
        // Handle click
    }
}
```

### Visual Basic Conventions

```vb
' Use App Framework (no Program.vb)
' Use Friend WithEvents for backing fields
' Prefer Handles clause over AddHandler

Public Class MainForm
    ' Use Handles clause for event handlers
    Private Sub Button_Click(sender As Object, e As EventArgs) Handles btnOK.Click
        ' Handle click
    End Sub
End Class
```

---

# 🎨 OPT-IN ENHANCEMENT FEATURES

> ⚠️ **OPT-IN enhancements only** — apply when:
> - User explicitly requests the feature (e.g., "add dark mode", "modernize async patterns")
> - Invoked by the **winforms-feature-adoption** scenario
> - **DO NOT** apply these during general upgrades or correctness fixes
>
> **See focused guides:** `dark-mode.md`, `async-apis.md`

---

## Best Practices Summary

### DO

✅ Use .NET 8+ for modern WinForms features
✅ Enable DarkMode with `SystemColorMode.System` (.NET 9+)
✅ Use modern C# features in regular code
✅ Follow Designer rules strictly in `.Designer.cs` files
✅ Wrap async event handlers in try/catch
✅ Use `SystemColors` for theme compatibility
✅ Document public APIs with XML comments
✅ Use target-typed new expressions
✅ Enable nullable reference types
✅ Set up proper exception handling

### DON'T

❌ Mix Designer rules with modern C# in InitializeComponent
❌ Use app.config or manifest files for configuration
❌ Forget try/catch in async event handlers
❌ Use absolute colors without DarkMode handling
❌ Create new instances in property getters
❌ Ignore memory implications of property patterns
❌ Use lambdas or modern operators in Designer code
❌ Skip XML documentation on public APIs

## Project Structure Example

```plaintext
MySolution/
├── MyApp.WinForms/          # Main WinForms project
│   ├── Forms/
│   │   ├── MainForm.cs
│   │   └── MainForm.Designer.cs
│   ├── Controls/            # Custom UserControls
│   ├── Properties/
│   │   └── DataSources/     # .datasource files for binding
│   └── Program.cs
├── MyApp.ViewModels/        # ViewModels (if using MVVM)
├── MyApp.Models/            # Domain models
└── MyApp.Services/          # Business logic
```

## Migration Checklist

When modernizing legacy WinForms applications:

1. ✅ Update to .NET 8+ (preferably .NET 9 or 10)
2. ✅ Enable nullable reference types
3. ✅ Convert to file-scoped namespaces
4. ✅ Add DarkMode support (.NET 9+)
5. ✅ Update to modern async patterns
6. ✅ Add application-level exception handling
7. ✅ Review and update Designer files (maintain compatibility)
8. ✅ Add XML documentation
9. ✅ Update NuGet packages to latest stable
10. ✅ Test on high DPI displays

## Quick Reference

### Critical Hierarchy

```plaintext
Designer Compatibility > Code Quality > DRY > Token Efficiency > Length
```

### Two Contexts Rule

| Context | Files | Language | Rules |
|---------|-------|----------|-------|
| Designer | *.Designer.cs | C# 2.0 (≤.NET 10), Modern (.NET 11+) | Serialization format |
| Regular | *.cs | Modern C# | All features allowed |

### Common Gotchas

1. **Property pattern memory leaks** - `=> new()` creates instances on every access
2. **Async event handlers** - Must wrap await in try/catch
3. **DarkMode colors** - Only SystemColors adapt automatically
4. **Designer compatibility** - Never use modern C# in InitializeComponent
5. **Fullscreen state** - Initialize variables before first fullscreen call

## Next Steps

For detailed information on specific topics, refer to these specialized skills:

- **Designer Code Rules** → managing-winforms-designer-code
- **Data Binding** → managing-winforms-data-binding
- **MVVM Pattern** → managing-winforms-mvvm
- **Custom Rendering** → managing-winforms-rendering
- **Layout Strategies** → managing-winforms-high-dpi-layout
