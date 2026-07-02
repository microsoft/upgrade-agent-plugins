---
name: managing-winforms-mvvm
description: >
  Implements MVVM pattern in WinForms applications (.NET 8+) with ViewModels, Commands, and
  DataContext. Use when user explicitly requests MVVM implementation, setting up ViewModel
  with INotifyPropertyChanged or ObservableObject, implementing ICommand or RelayCommand,
  wiring Form.DataContext, binding controls to ViewModel properties, creating Commands for
  button clicks, or separating business logic from UI code. Also triggers for "WinForms MVVM",
  "ViewModel in WinForms", "INotifyPropertyChanged", "DataContext binding", "Command pattern
  WinForms", "ObservableObject", "RelayCommand", and "testable WinForms". Also use when fixing
  existing MVVM code or when guided by winforms-feature-adoption scenario. DO NOT USE FOR:
  automatic application during version upgrades (opt-in only).
metadata:
  discovery: lazy
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & WindowsForms
---

# WinForms MVVM Pattern Guide

MVVM (Model-View-ViewModel) pattern in WinForms (.NET 8+) enables separation of business logic from UI, creating applications that are testable, maintainable, and portable across UI frameworks.

## When to Use This Skill

Use this skill when:

- Working with DataBinding in WinForms .NET 8+
- Implementing MVVM pattern in WinForms in .NET 8+ applications
- Creating ViewModels with MVVM Community Toolkit
- Setting up Command binding for buttons and menus (.NET 8+, `Command` Property)
- Using DataContext property for hierarchical binding (.NET 8+)
- Migrating from traditional event-handler architecture to MVVM
- Writing unit tests for business logic
- Sharing ViewModels between WinForms and WPF/MAUI/Avalonia
- Implementing `ICommand` with `RelayCommand` on ViewModel side
- Working around `ObservableCollection` in WinForms contexts
- Setting up dependency injection with ViewModels
- Creating .datasource files for ViewModel Designer support
- Troubleshooting ViewModel code generation issues

## Related Skills

- [WinForms Development](../building-winforms-applications/SKILL.md)
- [WinForms Data Binding](../managing-winforms-data-binding/SKILL.md)
- [WinForms Designer Code](../managing-winforms-designer-code/SKILL.md)
- [WinForms Async APIs](../managing-winforms-async-apis/SKILL.md)
- [WinForms High-DPI Fluent Layout](../managing-winforms-high-dpi-layout/SKILL.md)


## Detailed Guidance
Read [Detailed guide](references/detailed-guide.md) for comprehensive patterns, examples, and troubleshooting.

## Workflow
1. Confirm the scenario matches the triggers in this skill.
2. Apply the baseline pattern from this file.
3. Read [Detailed guide](references/detailed-guide.md) for advanced or edge-case handling.
4. Validate changes with an actual build and runtime check.
