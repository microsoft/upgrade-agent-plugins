---
name: creating-winforms-custom-controls
description: >
  Creates custom controls and UserControls for modern WinForms (.NET 6+). Use when deriving
  from Control, UserControl, Button, TextBox, or other base controls, implementing custom
  rendering with OnPaint overrides, creating composite controls with child control composition,
  adding custom properties with [Browsable], [Category], or [DefaultValue] attributes for
  Designer support, implementing INotifyPropertyChanged for control properties, handling
  Layout/LayoutEngine for custom sizing, creating scrollable controls with AutoScrollMinSize,
  implementing dark mode theming, or building List/Grid/Tree-like controls. Also triggers for
  "custom UserControl", "derive from Control", "owner-drawn control", "Designer properties",
  "[Browsable] attribute", "custom WinForms control", "LayoutEngine", "AutoScroll control",
  and "themed control".
metadata:
  discovery: lazy
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & WindowsForms
---

# When to Use This Skill

Authoring custom controls and UserControls for modern WinForms (.NET 6+, C# 13/14): base-class selection, clip-proof layout/sizing, owner-draw, dark-mode theming, Designer serialization, and List/Grid controls.
Use this skill when asked to create, derive, or modernize a WinForms control, UserControl, owner-drawn control, themed/dark-mode-aware control, scrollable Control-derived control, or a List/Grid-like control, and when wiring up Designer serialization for new control properties.

Use it for designing UserControl to offload complex UI from forms, or when a reusable control is needed across multiple forms/projects. Also use it for modernizing legacy controls to be dark-mode aware and DPI-aware.

## Related Skills

- [WinForms Development](../building-winforms-applications/SKILL.md)
- [WinForms Designer Code](../managing-winforms-designer-code/SKILL.md)
- [WinForms Data Binding](../managing-winforms-data-binding/SKILL.md)
- [WinForms Rendering](../managing-winforms-rendering/SKILL.md)
- [WinForms High-DPI Fluent Layout](../managing-winforms-high-dpi-layout/SKILL.md)

**Tenets:** Assume the project's house style:

- **No `using` statements** ─ globally-imported namespaces only.
- **NRTs enabled** ─ `#nullable enable` / `nullable` mode.
- **Modern C#** ─ pattern matching, `is`/`and`/`or`, switch expressions, collection initializers (`[]`).
- **XML doc comments** ─ for all public members.
- **`var` discipline** ─ use `var` only when the right-hand side is a constructor call or cast that makes the type obvious (e.g., `var cp = new CreateParams()`). Use explicit types for `int`, `bool`, `string`, `float`, `double`, `Color`, `Size`, `Point`, and similar short type names.
- **Expression-bodied members** ─ use them for single-expression getters, simple one-liner methods, and read-only properties. Use block bodies when the logic has side effects or exceeds ~100 characters.
- **Blank line before `return`** ─ improves readability in multi-statement methods.
- **Be brief** ─ the code carries the intent.

## 1. Pick the right base class

Decide *generic reusable control* vs *composite/LOB control* first.

- **Generic, no domain (a slider, badge, gauge, custom button):** derive from `Control`, or the closest specialized base (`ButtonBase`, `ScrollableControl`, `ListControl`, `Panel`, `Label`, —¦). `Control` gives you a blank canvas with full paint/input control. `TextBoxBase` is **not available** ─ it is `internal`; if you need text-box-like behavior, derive from `TextBox` or compose one.
- **Composite / LOB / domain-specific:** derive from `UserControl` and assemble constituent controls (see §5).
- **List- or grid-shaped data:** derive from `DataGridView`, not `Control` from scratch (see §6).

Prefer the most specific base that already solves the hard parts ─ don't reimplement `ButtonBase`'s focus/click mechanics on a raw `Control`.

## 2. Layout & sizing ─ make it clip-proof

A control that looks fine at 100% DPI with the default font but clips at 200% / large fonts is broken. Treat sizing as first-class wherever content needs a *minimum real estate* to render fonts/glyphs/images without clipping.

Implement these as a coherent set:

- **`GetPreferredSize(Size proposedSize)`** ─ return the size genuinely needed for current content, font, padding, and DPI. Measure text with `TextRenderer.MeasureText` (it matches `TextRenderer.DrawText`). Always add `Padding.Size`. This is the single source of truth for "how big do I need to be."
- **`AutoSize`** ─ expose and honor it. When `true`, the layout engine calls `GetPreferredSize`; your job is to return an honest number. Re-raise layout when size-affecting content changes (`PerformLayout()` / `Invalidate()`).
- **`SetBounds(...)`** ─ override when you must clamp or adjust the bounds you're given (e.g. enforce a minimum). Respect the `BoundsSpecified` flags so you don't clobber a dimension the caller didn't set.
- **`Padding`** ─ honor it in painting *and* `GetPreferredSize`. Content draws inside the padded rectangle.

Rule of thumb: an honest `GetPreferredSize` plus honored `AutoSize`/`Padding` survives DPI and font scaling automatically.

A typical `GetPreferredSize` for a text-bearing `Control`-derived control:

```csharp
public override Size GetPreferredSize(Size proposedSize)
{
    Size textSize = TextRenderer.MeasureText(Text, Font);
    Size content = new(
        textSize.Width + Padding.Horizontal,
        textSize.Height + Padding.Vertical);

    return new Size(
        Math.Max(content.Width, MinimumSize.Width),
        Math.Max(content.Height, MinimumSize.Height));
}
```

`OnTextChanged` / `OnFontChanged` overrides should call `PerformLayout()` (and `Invalidate()` if owner-drawn) so a new preferred size is picked up while `AutoSize` is on.

## 3. Owner-draw → always double-buffer

When you take over painting (`OnPaint`, owner-draw cells, custom rendering), enable double buffering to eliminate flicker:

```csharp
SetStyle(
    ControlStyles.UserPaint
        | ControlStyles.AllPaintingInWmPaint
        | ControlStyles.OptimizedDoubleBuffer,
    true);
```

Do all painting in `OnPaint` ─ don't scatter logic into `OnPaintBackground`. Call `Invalidate()` (not `Refresh()`) to request a repaint so it coalesces with other invalidations rather than forcing a synchronous redraw.

## 4. Dark mode & theming

Modern WinForms supports dark mode. Two things bite custom controls:

### 4.1 Win32 scrollbars on a `Control`-derived class are not themed automatically

If you add scrollbars by calling Win32 (`WS_HSCROLL` / `WS_VSCROLL`, `ShowScrollBar`, etc.) on a `Control` subclass, those scrollbars render in the classic (light) theme even in dark mode. To get them themed, override **`CreateParams`** and opt in:

```csharp
protected override CreateParams CreateParams
{
    get
    {
        SetStyle(ControlStyles.ApplyThemingImplicitly, true); // opt-in; false = opt-out
        CreateParams cp = base.CreateParams;
        // add WS_HSCROLL / WS_VSCROLL here as needed
        return cp;
    }
}
```

This **cannot** be done in the constructor: the base constructor reads `CreateParams` *before* your constructor body runs. It must live in the `CreateParams` getter, with the `SetStyle` call placed *before* `base.CreateParams` is read.

### 4.2 `SystemColors` flip in dark mode ─ names become counter-intuitive

In dark mode, `SystemColors` are remapped to roughly complementary values. The **name no longer matches the apparent brightness, and that is intentional**: `ControlLightLight` is very bright in classic mode and correspondingly dark in dark mode. The remap is *not* always a strict mathematical complement ─ some colors are nudged to keep contrast adequate.

Consequences:

- If you use `SystemColors`, accept that the name describes its *classic-mode* role, not its color.
- For **guaranteed contrast in both modes**, don't use `SystemColors` for your control's palette. Define your own colors as explicit `#AARRGGBB` values with **separate defaults for classic and dark mode**.
- Pick the active set at runtime via `Application.IsDarkModeEnabled`, which reflects the *current* mode:

```csharp
Color faceColor = Application.IsDarkModeEnabled
    ? Color.FromArgb(unchecked((int)0xFF2D2D30))
    : Color.FromArgb(unchecked((int)0xFFF0F0F0));
```

## 5. UserControls & composite custom controls

For a `UserControl` (or any control composed of constituent controls):

- **No design-time `Font` definitions.** Don't set `Font` on the UserControl or its children at design time. Design-time fonts pollute the HighDPI `AutoScaleDimensions` code generation, so when the user later re-opens the control in the Designer the generated scaling code is wrong. Adjust font *size* only at **runtime**.
- **Layout in a `TableLayoutPanel`** with `AutoSize` rows/columns. Let the table compute geometry.
- **The control itself exposes `AutoSize`** and an honest **`GetPreferredSize`** big enough to render every child unclipped across all HighDPI and large-font scenarios (§2). The `TableLayoutPanel` with AutoSize cells does most of this for you, but verify the outer control reports it.
- **Very large UserControls** with many containers/controls where a single clip-proof preferred size is impractical: host the content in a scrolling `Panel` (`AutoScroll = true`) rather than forcing an unreasonable minimum size.

## 6. List- / Grid-like controls

When asked for anything list- or grid-shaped, **derive from `DataGridView`** rather than building from scratch.

For image-rich or graphically rich data records, the best outcome is usually to **render the entire data item in one cell** via a custom `DataGridViewCell` ─ symbol fonts, multiple colors, multiple font sizes, multi-line layout, all in a single cell. Skip column headers in that case.

Keep column headers (and therefore per-field columns) only when the context genuinely needs a schema overview or per-column sort/filter. Even then, prefer **custom cell rendering** to get the rich graphical UI; don't fall back to plain text just because headers exist.

Whenever cells vary in height, **compute row height from the tallest cell in the data row** ─ measure each cell's required height and set the row to the max, or the content clips.

## 7. Designer serialization for new properties

Every public property you add must tell the Designer how to serialize it. Pick **exactly one** of these three mechanisms (they conflict if combined):

1. **`[DesignerSerializationVisibility(...)]`** ─ `Hidden` for runtime-only/derived properties the Designer must not write to `InitializeComponent`; `Content` for collections whose items serialize individually.
2. **`[DefaultValue(...)]`** ─ the property serializes only when its value differs from this constant. Use for simple properties with a fixed, compile-time-constant default.
3. **`ResetXxx()` + `ShouldSerializeXxx()` pair** ─ `ShouldSerializeXxx` returns whether the value should be written; `ResetXxx` restores the default. **Use this** for ambient properties, and whenever a default is *not constant* (depends on another property or the theme) ─ `[DefaultValue]` can't express that.

The method pair, for a property whose default depends on the current theme:

```csharp
/// <summary>Gets or sets the color of the control's face.</summary>
public Color FaceColor { get; set; } = DefaultFaceColor;

private static Color DefaultFaceColor
    => Application.IsDarkModeEnabled
        ? Color.FromArgb(unchecked((int)0xFF2D2D30))
        : Color.FromArgb(unchecked((int)0xFFF0F0F0));

// The Designer discovers these by naming convention ─ keep them private.
private bool ShouldSerializeFaceColor()
    => FaceColor != DefaultFaceColor;

private void ResetFaceColor()
    => FaceColor = DefaultFaceColor;
```

Note the convention: the methods are `private`, named exactly `ShouldSerialize<Property>` / `Reset<Property>`, and take no parameters. Don't combine them with `[DefaultValue]` on the same property ─ the two mechanisms conflict.

Don't leave a property with none of these ─ the Designer will either over-serialize or fail to round-trip.

### 7.1 Property-window attributes

Beyond serialization, decorate every new public property so it behaves well in the Properties window and IntelliSense. These are four *distinct* concerns:

- **`[Category("Appearance")]`** ─ the Properties-window group. Reuse standard names (`Appearance`, `Behavior`, `Layout`, `Data`, —¦) so your properties merge with the built-in ones.
- **`[Description("...")]`** ─ help text in the Properties window's description pane. Write it for a control *consumer*.
- **`[Browsable(false)]`** ─ hides the property from the Properties window. Use for runtime-only state. It almost always also needs `[DesignerSerializationVisibility(Hidden)]` ─ hiding from the grid does *not* stop serialization.
- **`[EditorBrowsable(EditorBrowsableState.Never | Advanced)]`** ─ controls IntelliSense visibility, independent of the grid. `Never` hides from completion; `Advanced` shows only when "Hide advanced members" is off.

To fully suppress an inherited property that's meaningless on your control (e.g. shadowing `Text`), combine all three on the `new`/`override` member:

```csharp
[Browsable(false)]
[EditorBrowsable(EditorBrowsableState.Never)]
[DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
public override string Text
{
    get => base.Text;
    set => base.Text = value;
}
```

A normal, visible property reads like this:

```csharp
[Category("Appearance")]
[Description("The color used to paint the control's face.")]
public Color FaceColor { get; set; } = DefaultFaceColor;
```

## 8. Construction order ─ `ISupportInitialize`

During `InitializeComponent`, the Designer sets your properties one at a time in an order *you don't control*. If two properties are interdependent ─ or a setter does expensive work (re-layout, allocation, a Win32 round-trip) ─ the control repeats that work against a half-configured state, and may even throw because property B isn't set yet when property A's setter runs.

Implement **`ISupportInitialize`** to defer it. The Designer emits `BeginInit()` before the property block and `EndInit()` after; do nothing expensive in between:

```csharp
public class GaugeControl : Control, ISupportInitialize
{
    private bool _initializing;

    public void BeginInit()
        => _initializing = true;

    public void EndInit()
    {
        _initializing = false;
        RecalculateLayout(); // the deferred work, done once, fully configured
        Invalidate();
    }

    public int Minimum
    {
        get;
        set
        {
            field = value;

            if (!_initializing)
            {
                RecalculateLayout();
                Invalidate();
            }
        }
    }
}
```

Every interdependent setter checks `_initializing` and skips the expensive path while it's `true`. `EndInit` runs that path exactly once. At runtime (no Designer), code that sets properties directly without calling `BeginInit`/`EndInit` still works ─ `_initializing` is just `false`, so each setter does its work immediately.

## 9. Designer support code (.NET 6+)

Designer functionality in .NET 6+ requires the **WinForms Designer SDK** NuGet package.

- Use the current preview: **`Microsoft.WinForms.Designer.SDK 1.13.0-preview.2.24575.3`**. The latest stable (`1.6.0`) is missing features you'll likely need ─ prefer the preview.
- Without shipping a separate Designer NuGet package, you **can** put the following in the *same .NET assembly as the control*: custom `CodeDomSerializer`s, custom `TypeConverter`s, and custom `DesignerActionList` (smart-tag) actions.
- **Out of scope for this skill:** Designers with a *custom design-time UI*. Those can't live in the control assembly ─ they need a dedicated multi-assembly NuGet package (client side on .NET Framework 4.7.2, server-side process on .NET, and a multi-targeted communication layer). If the user needs that, say so and stop.

## Quick checklist

- Most specific base class (`Control` generic, `UserControl` composite, `DataGridView` list/grid).
- `GetPreferredSize` honest; `AutoSize` + `Padding` honored; survives 200% DPI / large fonts.
- Owner-draw → `OptimizedDoubleBuffer | AllPaintingInWmPaint | UserPaint`; repaint via `Invalidate()`.
- Dark mode: own `#AARRGGBB` palette per mode, switched on `Application.IsDarkModeEnabled`; Win32 scrollbars themed via `CreateParams` + `ApplyThemingImplicitly`.
- UserControl: no design-time fonts, `TableLayoutPanel` with AutoSize cells, scrolling `Panel` if too large.
- Every new property: `[DefaultValue]`, `[DesignerSerializationVisibility]`, or `ShouldSerializeXxx`/`ResetXxx`; plus `[Category]`/`[Description]`.
- Interdependent or expensive property setters → `ISupportInitialize` with a `_initializing` guard.
- Designer SDK preview `1.13.0-preview.2.24575.3` if design-time code is involved.
