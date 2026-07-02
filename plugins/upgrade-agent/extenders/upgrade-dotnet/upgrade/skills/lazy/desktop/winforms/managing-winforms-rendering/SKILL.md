---
name: managing-winforms-rendering
description: >
  Implements custom painting and rendering in WinForms using GDI and GDI+. Use when overriding
  OnPaint or OnPaintBackground, creating owner-drawn controls, working with Graphics objects,
  drawing primitives (DrawLine, DrawRectangle, FillEllipse), measuring or rendering text with
  TextRenderer or Graphics.DrawString, handling Paint events, using BufferedGraphics for
  double-buffering, or managing resource disposal for Pen, Brush, Font, and Graphics objects.
  Also triggers for "custom paint WinForms", "override OnPaint", "Graphics object", "GDI+
  rendering", "DrawString", "TextRenderer", "owner-drawn control", "double buffer", and
  "dispose Graphics resources".
metadata:
  discovery: lazy
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & WindowsForms
---

# WinForms Custom Rendering Guide

Custom rendering in WinForms enables complete control over how controls paint themselves, from simple borders to complex visualizations using GDI+ (modern, object-oriented) and GDI (legacy, performance-optimized).

## When to Use This Skill

Use this skill when:

- Implementing custom OnPaint methods
- Creating custom controls that render their content themselves
- Working with Graphics, Pen, Brush, or Font objects
- Drawing shapes, lines, or custom graphics in a DC painting context
- Rendering and measuring text
- Implementing double buffering to avoid flicker
- Optimizing rendering performance
- Supporting high-DPI displays
- Implementing DarkMode-aware rendering (.NET 9+)
- Troubleshooting paint artifacts or flicker
- Managing GDI+ resource disposal


## Related Skills
- [building-winforms-applications](../building-winforms-applications/SKILL.md)
- [managing-winforms-data-binding](../managing-winforms-data-binding/SKILL.md)
- [managing-winforms-mvvm](../managing-winforms-mvvm/SKILL.md)
- [managing-winforms-high-dpi-layout](../managing-winforms-high-dpi-layout/SKILL.md)
- [creating-winforms-custom-controls](../creating-winforms-custom-controls/SKILL.md)


## Detailed Guidance
Read [Detailed guide](references/detailed-guide.md) for comprehensive patterns, examples, and troubleshooting.

## Workflow
1. Confirm the scenario matches the triggers in this skill.
2. Apply the baseline pattern from this file.
3. Read [Detailed guide](references/detailed-guide.md) for advanced or edge-case handling.
4. Validate changes with an actual build and runtime check.
