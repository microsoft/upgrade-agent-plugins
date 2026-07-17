## Contents
- Use the heading outline to navigate sections quickly.
## Overview

WinForms provides two rendering APIs:

**GDI+ (Graphics class):**

- Modern, object-oriented API
- Supports anti-aliasing and alpha blending
- Rotations, transformations, and gradients
- Use for: Custom graphics, effects, transformed rendering

**GDI (TextRenderer class):**

- Legacy API, performance-optimized for text
- Matches system text rendering exactly
- Use for: Large amounts of text, UI consistency

## Critical Setup for Custom Controls

**ALWAYS configure these settings for controls with custom OnPaint:**

```csharp
public class CustomControl : Control
{
    public CustomControl()
    {
        // CRITICAL: Prevent flicker
        DoubleBuffered = true;
        
        // CRITICAL: Prevent paint artifacts during resize
        SetStyle(ControlStyles.ResizeRedraw, true);
    }
}
```

**Why ResizeRedraw is critical:**

- Without it: Old paint content remains during resize, causing visual artifacts/smearing
- With it: Control repaints completely on every resize
- Small performance cost, but essential for visual correctness

## Resource Management

### Disposable GDI+ Objects

**MUST dispose:** `Graphics` (only when _you_ create it), `Pen`, `Brush`, `Font`, `Image`, `Region`, `GraphicsPath`, `StringFormat`

**Graphics Disposal Rules:**

```csharp
// ✅ DISPOSE - You created it
using Graphics g = pictureBox.CreateGraphics();
using Graphics g2 = Graphics.FromImage(bitmap);
using Graphics g3 = Graphics.FromHwnd(handle);

// ❌ DO NOT DISPOSE - Framework owns it
protected override void OnPaint(PaintEventArgs e)
{
    e.Graphics.DrawRectangle(Pens.Blue, 10, 10, 80, 80);
    // DO NOT dispose e.Graphics!
}
```

**Rule:** If you create it (CreateGraphics, FromImage, FromHwnd), dispose it. If framework provides it (PaintEventArgs.Graphics), don't dispose it.

### System Resources (NEVER Dispose)

**NEVER dispose:** `SystemBrushes.*`, `SystemPens.*`, `SystemColors.*`

These are shared, framework-managed resources. Disposing them breaks other parts of your application!

```csharp
// ✅ SAFE - Use without disposal
Brush brush = SystemBrushes.Control;
Pen pen = SystemPens.ControlText;
Color color = SystemColors.Window;

// ❌ WRONG - NEVER do this!
SystemBrushes.Control.Dispose();  // Breaks entire application!
```

### Caching Pattern for Performance

Cache frequently-used objects as fields instead of creating in OnPaint:

```csharp
public class CustomControl : Control
{
    // Cache as fields
    private readonly Pen _borderPen = new(Color.Blue, 2f);
    private readonly Font _titleFont = new("Segoe UI", 14f, FontStyle.Bold);
    private readonly SolidBrush _textBrush = new(Color.Black);

    protected override void OnPaint(PaintEventArgs e)
    {
        // Reuse cached objects - no allocations in paint!
        e.Graphics.DrawRectangle(_borderPen, ClientRectangle);
        e.Graphics.DrawString("Title", _titleFont, _textBrush, 10, 10);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            // Dispose cached objects
            _borderPen.Dispose();
            _titleFont.Dispose();
            _textBrush.Dispose();
        }
        base.Dispose(disposing);
    }
}
```

**Performance impact:** Creating objects in OnPaint can cause 100+ allocations per second during scrolling or animation!

## Double Buffering

Prevents flicker during painting by rendering to offscreen buffer first.

### Simple Approach (Recommended)

```csharp
public class CustomControl : Control
{
    public CustomControl()
    {
        DoubleBuffered = true;  // That's it!
    }
}
```

### Advanced Approach (More Control)

```csharp
public class CustomControl : Control
{
    public CustomControl()
    {
        SetStyle(ControlStyles.OptimizedDoubleBuffer 
               | ControlStyles.AllPaintingInWmPaint 
               | ControlStyles.UserPaint, true);
    }
}
```

### Manual Double Buffering (Complex Scenarios)

```csharp
public class CustomControl : Control
{
    private BufferedGraphicsContext? _context;
    private BufferedGraphics? _buffer;

    protected override void OnPaint(PaintEventArgs e)
    {
        _context ??= BufferedGraphicsManager.Current;
        _buffer ??= _context.Allocate(e.Graphics, ClientRectangle);
        
        Graphics g = _buffer.Graphics;
        g.Clear(BackColor);
        
        // Draw to buffer
        DrawContent(g);
        
        // Render buffer to screen
        _buffer.Render(e.Graphics);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _buffer?.Dispose();
            _context?.Dispose();
        }
        base.Dispose(disposing);
    }
}
```

**CRITICAL:** Never call `Invalidate()` from within `OnPaint` - causes infinite loop and stack overflow!

## Pen Width and Drawing Boundaries

**Fundamental concept:** Pen width draws AROUND the specified coordinates, not confined to them.

```csharp
// 1-pixel pen: draws exactly on coordinates
// 3-pixel pen: 1px left + 1px on coordinate + 1px right = centered

private void DrawBorderedRectangle(Graphics g, Rectangle bounds, float penWidth)
{
    using Pen pen = new(Color.Black, penWidth);
    float halfPen = penWidth / 2f;
    
    // Inset by half pen width to keep stroke inside bounds
    RectangleF drawRect = new(
        bounds.X + halfPen, 
        bounds.Y + halfPen,
        bounds.Width - penWidth, 
        bounds.Height - penWidth);
    
    g.DrawRectangle(pen, drawRect.X, drawRect.Y, drawRect.Width, drawRect.Height);
}
```

### Pixel-Perfect vs Anti-Aliased

```csharp
// Crisp 1-pixel lines (no anti-aliasing)
e.Graphics.SmoothingMode = SmoothingMode.None;
e.Graphics.DrawLine(pen, 10, 10, 100, 10);  // Integer coordinates

// Smooth anti-aliased lines
e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
e.Graphics.DrawLine(pen, 10.5f, 10.5f, 100.5f, 10.5f);  // Half-pixel offsets
```

**Tip:** Use half-pixel offsets (10.5f) with anti-aliasing for centered, smooth lines.

## Quality Modes

Set quality modes at the START of OnPaint for consistent rendering:

### SmoothingMode (Shapes/Lines)

```csharp
e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;     // Smooth curves/diagonals
e.Graphics.SmoothingMode = SmoothingMode.None;          // Crisp pixel-perfect
e.Graphics.SmoothingMode = SmoothingMode.HighQuality;   // Best quality (slower)
```

**Use:**

- `AntiAlias` - Curves, diagonals, circles
- `None` - Grids, pixel art, horizontal/vertical lines

### TextRenderingHint (Text Quality)

```csharp
e.Graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;  // Small text (< 12pt)
e.Graphics.TextRenderingHint = TextRenderingHint.AntiAlias;         // Large text (> 20pt)
e.Graphics.TextRenderingHint = TextRenderingHint.SystemDefault;     // Match system
```

**Guidelines:**

- Small text (8-12pt): ClearTypeGridFit for readability
- Large text (20pt+): AntiAlias for smooth appearance
- UI text: SystemDefault to match system settings

### InterpolationMode (Image Scaling)

```csharp
g.InterpolationMode = InterpolationMode.HighQualityBicubic;  // Downscaling photos
g.InterpolationMode = InterpolationMode.Bilinear;            // General scaling
g.InterpolationMode = InterpolationMode.NearestNeighbor;     // Pixel art (no blur)
```

### CompositingMode/Quality

```csharp
e.Graphics.CompositingMode = CompositingMode.SourceOver;         // Normal alpha blending
e.Graphics.CompositingMode = CompositingMode.SourceCopy;         // No blending (faster)
e.Graphics.CompositingQuality = CompositingQuality.HighQuality;  // Smooth blending
```

## Text Rendering

### Text Measurement (CRITICAL)

**For precise measurements (especially monospace fonts), use `StringFormat.GenericTypographic`:**

```csharp
// ✅ PRECISE - Reduces padding, critical for layout calculations
using StringFormat format = StringFormat.GenericTypographic;
SizeF size = g.MeasureString(text, font, PointF.Empty, format);

// ⚠️ INACCURATE - Includes extra padding
SizeF size = g.MeasureString(text, font);  // Causes cumulative errors
```

**Use GenericTypographic for:**

- Monospace fonts (Consolas, Courier New, Lucida Console)
- Mixed-style text runs (different fonts/sizes in same line)
- Precise character positioning
- Typography/layout calculations
- Custom text controls

**GDI Alternative (TextRenderer):**

```csharp
Size size = TextRenderer.MeasureText("Text", font);
```

**CRITICAL Rules:**

- Always measure with the SAME Graphics object used for drawing
- Always use the SAME quality settings for measurement and drawing
- Never mix GDI (TextRenderer) and GDI+ (Graphics.DrawString)

### Line Spacing (Non-Linear Growth)

```csharp
private float CalculateLineSpacing(Font font, Graphics g)
{
    float baseHeight = font.GetHeight(g);
    
    if (font.Size > 12f)
    {
        // Flattened growth for larger fonts
        float additionalSpacing = (font.Size - 12f) * 0.7f;
        return baseHeight + additionalSpacing;
    }
    
    return baseHeight * 1.2f;
}
```

### GDI vs GDI+ Selection

**Use GDI (TextRenderer):**

- Large amounts of text (grids, lists, logs)
- UI text that should match system appearance
- Performance-critical text rendering
- Matching TextBox/Label appearance

**Use GDI+ (Graphics.DrawString):**

- Rotated or transformed text
- Custom graphics effects (shadows, outlines, gradients)
- Mixed with other GDI+ primitives (shapes, images)
- Alpha blending and transparency
- Complex typography with Run collections

## Related Skills

- [WinForms Custom Controls and UserControls](../../creating-winforms-custom-controls/SKILL.md)
- [WinForms High-DPI Fluent Layout](../../managing-winforms-high-dpi-layout/SKILL.md)
- [WinForms Designer Code](../../managing-winforms-designer-code/SKILL.md)
- [WinForms Development](../../building-winforms-applications/SKILL.md)
- [WinForms Data Binding](../../managing-winforms-data-binding/SKILL.md)

## Offscreen Rendering

**When to use:**

- Complex compositions
- Rounded corners with transparency
- Avoiding flicker (additional to double buffering)
- Caching expensive renders

```csharp
public class RoundedControl : Control
{
    private Bitmap? _offscreenBuffer;

    protected override void OnPaint(PaintEventArgs e)
    {
        // Resize buffer only when growing (not every paint!)
        if (_offscreenBuffer is null || 
            _offscreenBuffer.Width < Width || 
            _offscreenBuffer.Height < Height)
        {
            _offscreenBuffer?.Dispose();
            _offscreenBuffer = new Bitmap(Width, Height);
        }

        // Render to offscreen buffer
        using (Graphics g = Graphics.FromImage(_offscreenBuffer))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            DrawContent(g);
        }

        // Draw buffer to screen
        e.Graphics.DrawImage(_offscreenBuffer, 0, 0);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _offscreenBuffer?.Dispose();
        }
        base.Dispose(disposing);
    }
}
```

**Performance tip:** Only recreate buffer when size increases, not on every paint.

## DPI and Scaling

```csharp
protected override void OnPaint(PaintEventArgs e)
{
    // Get current DPI
    float dpiX = e.Graphics.DpiX;  // 96 = 100%, 120 = 125%, 144 = 150%
    float scaleFactor = dpiX / 96f;
    
    // Scale pen width
    float scaledPenWidth = 2f * scaleFactor;
    using Pen pen = new(Color.Black, scaledPenWidth);
    
    e.Graphics.DrawRectangle(pen, 10, 10, 100, 100);
}

// Physical size calculation
private float InchesToPixels(float inches, float dpi) 
    => inches * dpi;

// Example: 1 inch at 96 DPI = 96 pixels
// Example: 1 inch at 144 DPI = 144 pixels
```

**IMPORTANT:** Font sizes are already DPI-aware - don't manually scale `Font.Size`!

```csharp
// ❌ WRONG - Font.Size is already DPI-aware!
float scaledSize = font.Size * (dpiX / 96f);

// ✅ CORRECT - Just use font as-is
e.Graphics.DrawString(text, font, brush, point);
```

## Accounting for Dark Mode (.NET 9+)

```csharp
protected override void OnPaint(PaintEventArgs e)
{
    bool isDarkMode = Application.IsDarkModeEnabled;
    
    // SystemColors adapt automatically
    using SolidBrush backBrush = new(SystemColors.Window);
    using SolidBrush textBrush = new(SystemColors.WindowText);
    
    e.Graphics.FillRectangle(backBrush, ClientRectangle);
    e.Graphics.DrawString("Text", Font, textBrush, 10, 10);
    
    // Custom colors require manual handling
    Color accentColor = isDarkMode 
        ? Color.FromArgb(0, 120, 215)   // Dark mode accent
        : Color.Blue;                    // Light mode accent
}
```

**Important Color Note:**

- Color names like `SystemColors.ControlDark` imply unconditional darkness
- In DarkMode, these become complementary (lighter) colors
- Treat `ControlDark` like `ControlLight` in DarkMode contexts

**Only `SystemColors` automatically update for DarkMode. Absolute colors need manual handling.**

## Common Pitfalls

### Memory Leaks

```csharp
// ❌ LEAK - Creating in OnPaint without disposing
protected override void OnPaint(PaintEventArgs e)
{
    Pen pen = new(Color.Black, 2f);  // Never disposed!
    e.Graphics.DrawRectangle(pen, ClientRectangle);
}

// ✅ CORRECT - Using statement
protected override void OnPaint(PaintEventArgs e)
{
    using Pen pen = new(Color.Black, 2f);
    e.Graphics.DrawRectangle(pen, ClientRectangle);
}

// ✅ BETTER - Cache as field
private readonly Pen _borderPen = new(Color.Black, 2f);

protected override void OnPaint(PaintEventArgs e)
{
    e.Graphics.DrawRectangle(_borderPen, ClientRectangle);
}
```

### Performance Issues

```csharp
// ❌ SLOW - Creating in loop (1000 allocations!)
for (int i = 0; i < 1000; i++)
{
    using Pen pen = new(Color.Red, 1f);
    e.Graphics.DrawLine(pen, 0, i, Width, i);
}

// ✅ FAST - Reuse (1 allocation)
using Pen pen = new(Color.Red, 1f);
for (int i = 0; i < 1000; i++)
{
    e.Graphics.DrawLine(pen, 0, i, Width, i);
}
```

### Visual Artifacts

When stroking a rectangle with a thick pen, the stroke is centered on the shape's edge, meaning part of the stroke can spill outside intended bounds.

**Problem:**

```csharp
// ❌ Stroke may extend beyond bounds
using Pen pen = new(Color.Black, 5f);
e.Graphics.DrawRectangle(pen, 0, 0, Width, Height);
```

**Solution 1: Manual inset (most reliable):**

```csharp
// ✅ Reliable - Inset manually by half pen width
using Pen pen = new(Color.Black, 5f);
float half = pen.Width / 2f;

e.Graphics.DrawRectangle(
    pen,
    half,                    // X offset
    half,                    // Y offset
    Width - pen.Width,       // Width (subtract full pen width)
    Height - pen.Width);     // Height (subtract full pen width)
```

**Solution 2: PenAlignment.Inset (inconsistent):**

```csharp
// ✅ Alternative - Try PenAlignment.Inset (works on some closed shapes)
using Pen pen = new(Color.Black, 5f)
{
    Alignment = System.Drawing.Drawing2D.PenAlignment.Inset
};

// Note: Right and bottom edges are "open" in GDI+ - subtract 1
e.Graphics.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
```

**⚠️ Note on PenAlignment.Inset:**

- Can work on closed shapes (rectangles, polygons)
- Effect is inconsistent in GDI+
- For predictable results with thick/dashed/compound pens, prefer manual inset

**Helper Method:**

```csharp
static RectangleF InnerRect(RectangleF bounds, Pen pen)
{
    float w = pen?.Width ?? 1f;
    float half = w / 2f;
    return new RectangleF(
        bounds.X + half,
        bounds.Y + half,
        Math.Max(0, bounds.Width - w),
        Math.Max(0, bounds.Height - w));
}

// Usage:
using Pen pen = new(Color.Black, 5f);
e.Graphics.DrawRectangle(pen, InnerRect(new RectangleF(0, 0, Width, Height), pen));
```

## Best Practices

### DO

✅ Enable double buffering (`DoubleBuffered = true`)
✅ Set `ResizeRedraw` style for custom paint controls
✅ Use `StringFormat.GenericTypographic` for precise text measurement
✅ Dispose GDI+ objects you create (Pen, Brush, Font, Image)
✅ Use `SystemBrushes`/`SystemPens` for theme compatibility
✅ Cache frequently-used objects as fields
✅ Set quality modes at start of `OnPaint`
✅ Account for pen width in boundary calculations
✅ Use `TextRenderer` for large amounts of text
✅ Scale appropriately for DPI awareness
✅ Test in both Light and Dark mode (.NET 9+)

### DON'T

❌ Dispose `Graphics` from `PaintEventArgs`
❌ Dispose `SystemBrushes.*` or `SystemPens.*`
❌ Create GDI+ objects in tight loops
❌ Call `Invalidate()` from within `OnPaint`
❌ Manually scale `Font.Size` for DPI
❌ Assume Light mode colors work in Dark mode
❌ Skip `ResizeRedraw` for custom controls with OnPaint
❌ Use default `MeasureString` for precise typography
❌ Mix GDI and GDI+ for same rendering task

## Pre-Implementation Checklist

Before implementing custom rendering:

| Requirement | Code | Purpose |
|-------------|------|---------|
| Double buffering | `DoubleBuffered = true` | Prevent flicker |
| Resize redraw | `SetStyle(ControlStyles.ResizeRedraw, true)` | Prevent artifacts |
| Text precision | `StringFormat.GenericTypographic` | Accurate measurements |
| Quality modes | Set once at OnPaint start | Consistent rendering |
| Resource caching | Cache Pen/Brush/Font as fields | Performance |

## Performance Checklist

1. ✅ Double buffering enabled?
2. ✅ ResizeRedraw style set?
3. ✅ Objects cached as fields?
4. ✅ Using statements for temporary objects?
5. ✅ Quality settings appropriate (not always HighQuality)?
6. ✅ Offscreen buffers reused (not recreated)?
7. ✅ TextRenderer used for large text amounts?
8. ✅ Invalidation targeted to regions, not entire control?

## Related Skills

For related topics:

- **building-winforms-applications** - Overall WinForms development patterns
- **managing-winforms-high-dpi-layout** - High-DPI fluent layout and control arrangement
- **managing-winforms-designer-code** - Designer compatibility for custom controls

## Summary

Effective custom rendering requires:

- Proper resource management (disposal, caching)
- Understanding of double buffering
- Quality mode selection
- DPI awareness
- Dark mode support (.NET 9+)
- Performance optimization
- Correct pen width handling

Follow these patterns for flicker-free, efficient, theme-aware custom rendering.
