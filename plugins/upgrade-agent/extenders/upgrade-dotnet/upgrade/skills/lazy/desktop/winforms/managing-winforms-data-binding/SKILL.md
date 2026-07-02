---
name: managing-winforms-data-binding
description: >
  Implements WinForms data binding patterns with BindingSource, INotifyPropertyChanged,
  validation, and master-detail scenarios. Use when binding controls using DataBindings.Add,
  setting up BindingSource with DataSource, implementing INotifyPropertyChanged for automatic
  UI updates, creating two-way bindings between controls and data objects, using
  BindingSource.Filter or BindingSource.Sort, implementing master-detail relationships with
  related BindingSources, handling binding validation with ErrorProvider, or troubleshooting
  binding update issues and performance. Also triggers for "BindingSource", "DataBindings.Add",
  "INotifyPropertyChanged WinForms", "two-way binding", "ErrorProvider", "master-detail
  binding", "BindingNavigator", "DataSource binding", and "WinForms data binding".
metadata:
  discovery: lazy
  traits: (.NET|CSharp|VisualBasic|DotNetCore) & WindowsForms
---

# WinForms Data Binding Guide

Data binding in WinForms enables automatic synchronization between UI controls and data sources, eliminating manual property updates and keeping view and data in sync.

## When to Use This Skill

Use this skill when:

- Binding Label, TextBox, Button, ComboBox, or other controls to data objects
- Implementing two-way data binding
- Working with BindingSource components
- Creating master-detail data relationships
- Setting up DataGridView with data sources
- Implementing data validation with ErrorProvider
- Converting between WPF/MAUI ObservableCollection and WinForms BindingList
- Creating .datasource files for Designer support in the PropertyGrid's BindingPicker
- Troubleshooting binding updates or performance issues

## Related Skills

- [WinForms Development](../building-winforms-applications/SKILL.md)
- [WinForms Designer Code](../managing-winforms-designer-code/SKILL.md)
- [WinForms MVVM](../managing-winforms-mvvm/SKILL.md)
- [WinForms Async APIs](../managing-winforms-async-apis/SKILL.md)
- [WinForms Custom Controls and UserControls](../creating-winforms-custom-controls/SKILL.md)


## Detailed Guidance
Read [Detailed guide](references/detailed-guide.md) for comprehensive patterns, examples, and troubleshooting.

## Workflow
1. Confirm the scenario matches the triggers in this skill.
2. Apply the baseline pattern from this file.
3. Read [Detailed guide](references/detailed-guide.md) for advanced or edge-case handling.
4. Validate changes with an actual build and runtime check.
