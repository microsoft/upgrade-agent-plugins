---
name: azure-functions-upgrade
description: >
  Upgrade Azure Functions project from in-process model to isolated worker model.
  Use when user wants to migrate Azure Functions from in-proc to isolated, upgrade Functions hosting model,
  or modernize Azure Functions projects.
requires-extension: upgrade-dotnet
metadata:
  discovery: scenario
  importance: medium
  traits: .NET|CSharp|VisualBasic|DotNetCore
  scenarioTraitsSet: [.NET]
---

# Azure Functions Upgrade Scenario

This scenario uses the **dotnet-version-upgrade** scenario workflow. The only difference is intent detection — this skill matches Azure Functions upgrade requests specifically.

Follow the `dotnet-version-upgrade` scenario skill for all stages (assessment, planning, execution).
