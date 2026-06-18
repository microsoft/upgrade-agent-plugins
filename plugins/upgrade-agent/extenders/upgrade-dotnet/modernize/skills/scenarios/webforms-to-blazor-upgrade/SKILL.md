---
name: webforms-to-blazor-upgrade
description: >
  Upgrade ASP.NET Web Forms projects to modern .NET.
  Use when the user wants to upgrade, migrate, modernize, port, convert, or move
  Web Forms / WebForms / .aspx pages to any modern .NET.
  framework.
metadata:
  discovery: scenario
  importance: high
  traits: (.NET|CSharp|VisualBasic) & DotNetFramework & WebForms
  scenarioTraitsSet: [.NET, DotNetFramework, WebForms]
---
 
# Web Forms to Blazor Upgrade Scenario

This scenario uses the **dotnet-version-upgrade** scenario workflow. The only differences are intent detection and target technology selection — this skill matches Web Forms upgrade requests specifically and always targets **Blazor (Blazor Server)** as the modernization destination.

## Target Technology — Default Lock with Opt-Out

When Web Forms (`.aspx`, `.ascx`, `.master`, `.asmx`, `System.Web.UI`, `<%@ Page %>` directives, server controls, `Global.asax`, WebForm project type GUID `{349C5851-65DF-11DA-9384-00065B846F21}`) is detected, the **default and strongly recommended** upgrade target is **Blazor Server**. Blazor Server is the only target with full, validated support in this scenario.

### When the user explicitly insists on a non-Blazor target

If — and only if — the user explicitly asks to target Razor Pages, ASP.NET Core MVC, Minimal APIs, Web API, or another non-Blazor framework, **honor their choice** rather than refusing. Before proceeding, deliver a clear warning **once** and get acknowledgment:

> ⚠️ **Unsupported target warning**
> This scenario is designed and validated for migrating Web Forms projects to **Blazor Server**. You've asked to target **{user's choice}** instead.
>
> - There is **no first-class support** in this scenario for {user's choice}.
> - Expect **reduced guidance, more manual decisions**, and a higher chance of incomplete or incorrect transformations.
> - Assessment and high-level planning will still work, but execution will rely on general .NET knowledge rather than scenario-specific patterns.
>
> Do you want to proceed with **{user's choice}** anyway, or switch to the recommended **Blazor Server** target?

## Workflow

Follow the `dotnet-version-upgrade` scenario skill for all stages (assessment, planning, execution).
