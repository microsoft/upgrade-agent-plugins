---
name: managing-winforms-high-dpi-layout
description: >
  Implements WinForms high-DPI fluent layouts using TableLayoutPanel, FlowLayoutPanel, and
  DPI-aware design patterns. Use when creating responsive form layouts that must scale across
  different DPI settings, implementing Per Monitor V2 (PerMonitorV2) DPI awareness, working with
  TableLayoutPanel.RowStyles/ColumnStyles, using FlowLayoutPanel for dynamic layouts,
  replacing fixed pixel positioning with container-based layout, troubleshooting DPI scaling
  issues, or structuring nested layout containers. Also triggers for "TableLayoutPanel",
  "FlowLayoutPanel", "high DPI WinForms", "PerMonitorV2", "DPI aware layout", "responsive
  WinForms", "scale UI", "AutoScaleMode", and "DPI scaling".
metadata:
  discovery: lazy
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & WindowsForms
---

# WinForms High-DPI Fluent Layout Guide

Fluent layout strategies for scalable, DPI-aware WinForms form designs using TableLayoutPanel and FlowLayoutPanel. All layout code shown here must follow the **managing-winforms-designer-code** skill rules ─ control configuration belongs in `InitializeComponent` inside the `.Designer.cs` file.

## When to Use This Skill

Use this skill when:

- Designing new or modifying existing forms or UserControls with responsive layouts
- Implementing fluent layout scenarios using `TableLayoutPanel` or `FlowLayoutPanel`
- Ensuring DPI compatibility, specifically for Per Monitor V2 High-DPI modes
- Creating complex nested layouts with proper scaling
- Implementing fullscreen or presentation modes
- Designing modal dialogs with proper layout structure
- Reviewing whether WinForms Forms/UserControls are "designed according to standard", "not designed properly", "badly designed", "layout looks wrong", or similar; pair this with `managing-winforms-designer-code` so Designer serialization rules are checked too.

## Designer Compatibility Note

**CRITICAL:** All control instantiation, property assignment, and layout wiring shown in this skill belongs inside `InitializeComponent` in the `.Designer.cs` file. Do NOT extract control configuration into helper methods like `CreateDetailsPanel()` or `SetupLayout()` ─ this breaks the WinForms Designer. See the **managing-winforms-designer-code** skill for the authoritative rules.

## Related Skills

- [WinForms Designer Code](../managing-winforms-designer-code/SKILL.md)
- [WinForms Development](../building-winforms-applications/SKILL.md)
- [WinForms Custom Controls and UserControls](../creating-winforms-custom-controls/SKILL.md)
- [WinForms Rendering](../managing-winforms-rendering/SKILL.md)
- [WinForms Data Binding](../managing-winforms-data-binding/SKILL.md)


## Detailed Guidance
Read [Detailed guide](ref/detailed-guide.md) for comprehensive patterns, examples, and troubleshooting.

## Workflow
1. Confirm the scenario matches the triggers in this skill.
2. Apply the baseline pattern from this file.
3. Read [Detailed guide](ref/detailed-guide.md) for advanced or edge-case handling.
4. Validate changes with an actual build and runtime check.
