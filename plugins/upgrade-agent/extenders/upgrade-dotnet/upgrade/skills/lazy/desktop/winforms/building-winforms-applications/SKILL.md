---
name: building-winforms-applications
description: >
  Structures WinForms applications with Designer-compatible patterns, proper code organization,
  and build/runtime compatibility. Use when creating or maintaining WinForms projects, working
  with Form or UserControl classes, organizing InitializeComponent vs application logic,
  implementing Application.Run patterns, handling Program.cs and ApplicationConfiguration,
  managing Application.SetHighDpiMode, working with .resx resource files, or troubleshooting
  Designer serialization issues. Also triggers for "WinForms project structure", "Form class
  organization", "Designer compatibility", "Application.Run", "Program.cs setup", and
  "WinForms best practices". Enhancement features (dark mode, async APIs, MVVM) are in
  separate skills for opt-in adoption only.
metadata:
  discovery: lazy
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & WindowsForms
---

# WinForms Development Guide

Modern .NET WinForms development for Designer-compatible applications with proper separation of concerns between Designer-generated code and application logic.

## When to Use This Skill

Use this skill when:

- Creating new or maintaining existing WinForms projects or WinForms control libraries
- Developing Forms or UserControls to be compatible with the WinForms Designer
- Modernizing legacy WinForms applications or even legacy VB6 applications
- Setting up solution structures and configuration with enough evidence for using the WinForms projects as the UI stack.

## Related Skills

For specialized topics, see:

- [WinForms Designer Code](../managing-winforms-designer-code/SKILL.md)
- [WinForms Data Binding](../managing-winforms-data-binding/SKILL.md)
- [WinForms MVVM](../managing-winforms-mvvm/SKILL.md)
- [WinForms Rendering](../managing-winforms-rendering/SKILL.md)
- [WinForms High-DPI Fluent Layout](../managing-winforms-high-dpi-layout/SKILL.md)


## Detailed Guidance
Read [Detailed guide](references/detailed-guide.md) for comprehensive patterns, examples, and troubleshooting.

**For opt-in enhancement features** (dark mode, async APIs), see focused guides in [references/enhancements/](references/enhancements/) - these are only applied when explicitly requested or invoked by the winforms-feature-adoption scenario.

## Workflow
1. Confirm the scenario matches the triggers in this skill.
2. Apply the baseline pattern from this file.
3. Read [Detailed guide](references/detailed-guide.md) for advanced or edge-case handling.
4. Validate changes with an actual build and runtime check.
