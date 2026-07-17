# Dark Mode Support for WinForms (.NET 9+)

**Prerequisite:** Application must target .NET 9.0 or higher.

> 📖 **For general WinForms patterns**, see the [main detailed guide](detailed-guide.md).

## Quick Start

### Step 1: Enable Dark Mode Application-Wide

Add to your **Program.cs** (or **ApplicationEvents.vb** for VB):

**C#:**
```csharp
[STAThread]
static void Main()
{
    ApplicationConfiguration.Initialize();
    
    // Add this line - must be before Application.Run()
    Application.SetColorMode(SystemColorMode.System);
    
    Application.SetHighDpiMode(HighDpiMode.SystemAware);
    Application.Run(new MainForm());
}
```

**VB:**
```vb
' In ApplicationEvents.vb
Private Sub MyApplication_ApplyApplicationDefaults(sender As Object, e As ApplyApplicationDefaultsEventArgs) Handles Me.ApplyApplicationDefaults
    ' Add this line
    e.ColorMode = SystemColorMode.System
    
    e.HighDpiMode = HighDpiMode.SystemAware
End Sub
```

### Step 2: Query Dark Mode Status at Runtime

```csharp
bool isDarkMode = Application.IsDarkModeEnabled;
```

### Step 3: Adapt Form Colors

#### Use SystemColors (Automatic)

```csharp
// ✅ These automatically adapt to light/dark mode
this.BackColor = SystemColors.Window;
this.ForeColor = SystemColors.WindowText;
label.BackColor = SystemColors.Control;
```

#### Use Custom Colors (Manual Handling Required)

```csharp
// ⚠️ Custom colors need explicit light/dark variants
Color accentColor = Application.IsDarkModeEnabled 
    ? Color.FromArgb(0, 120, 215)  // Dark mode accent
    : Color.Blue;                   // Light mode accent

Color backgroundColor = Application.IsDarkModeEnabled
    ? Color.FromArgb(0x2D, 0x2D, 0x30)  // Dark mode background
    : Color.FromArgb(0xF0, 0xF0, 0xF0); // Light mode background
```

## Important Considerations

### SystemColors Behavior in Dark Mode

**Critical:** In dark mode, `SystemColors` are remapped to complementary values. The **name no longer matches apparent brightness**:

- `SystemColors.ControlDark` is **very bright** in classic mode and **correspondingly dark** in dark mode
- `SystemColors.ControlLightLight` follows the same pattern (reversed)

**Implication:** If you use `SystemColors`, accept that the name describes its *classic-mode* role, not its color.

### When to Use Each Approach

| Scenario | Recommendation |
|----------|---------------|
| Standard form/control backgrounds | Use `SystemColors` - automatic adaptation |
| Standard text colors | Use `SystemColors` - automatic adaptation |
| Brand colors, logos, accents | Define custom light/dark pairs |
| Charts, graphs, data visualization | Define custom palettes per mode |

### Custom Drawing

If your form has custom drawing code (OnPaint overrides):

```csharp
protected override void OnPaint(PaintEventArgs e)
{
    base.OnPaint(e);
    
    bool isDarkMode = Application.IsDarkModeEnabled;
    
    Color lineColor = isDarkMode 
        ? Color.LightGray  // Visible on dark background
        : Color.DarkGray;  // Visible on light background
    
    using (Pen pen = new(lineColor))
    {
        e.Graphics.DrawLine(pen, 0, 0, Width, Height);
    }
}
```

## Validation Checklist

After enabling dark mode:

- [ ] `Application.SetColorMode(SystemColorMode.System)` called in Program.cs/ApplicationEvents.vb
- [ ] Application starts without errors
- [ ] Forms display correctly in **light mode** (switch OS theme to light)
- [ ] Forms display correctly in **dark mode** (switch OS theme to dark)
- [ ] Custom colors have light/dark variants defined
- [ ] SystemColors used for standard UI elements (not hardcoded colors)
- [ ] Designer can still open and edit forms (dark mode logic in regular code files, not InitializeComponent)

## Troubleshooting

**Problem:** Colors don't change when switching OS theme  
**Solution:** Ensure `Application.SetColorMode()` is called **before** `Application.Run()` or `e.ColorMode` is set in `ApplyApplicationDefaults`

**Problem:** Custom colors look wrong in dark mode  
**Solution:** Define explicit light/dark pairs using `Application.IsDarkModeEnabled` check

**Problem:** Third-party controls don't support dark mode  
**Solution:** Document limitation; consider using `SystemColors` where possible or contacting vendor for dark mode support

## Additional Resources

- See [managing-winforms-rendering](../../managing-winforms-rendering/ref/detailed-guide.md) for custom drawing patterns
- See [main detailed guide](detailed-guide.md) for comprehensive WinForms development guidance
