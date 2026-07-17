---
name: scaffolding-yarp-proxy-project
description: >
  Scaffolds a new ASP.NET Core project with YARP reverse proxy alongside an existing
  .NET Framework MVC or WebAPI project for incremental side-by-side migration. Use when
  a migration task requires creating a new Core project that proxies to the old Framework
  app, when the side-by-side migration approach is selected, or when scaffold/YARP/proxy
  setup is needed. Also triggers for "create new Core project", "set up YARP proxy",
  "side-by-side project setup".
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# Scaffold ASP.NET Core Project with YARP Proxy

Creates a new ASP.NET Core web project alongside an existing .NET Framework
MVC or WebAPI project. The new project is configured with a YARP reverse proxy
that routes unhandled requests to the old project, enabling incremental
controller-by-controller migration.

## ⛔ REQUIRED: Read This File Completely

This file contains **2 steps** and **10 sub-steps** for manual scaffolding. You MUST read all sections before starting:

| Step | Section | What It Covers |
|------|---------|----------------|
| 1 | Check for Existing Tool | Try `scaffold_yarp_proxy_web_project` tool first |
| 2 | Scaffold Using Script + Templates | Primary path — script + template files |
| 2.1 | Gather Parameters | Paths, TFM, URLs, package versions |
| 2.2 | Run the Script | Script copies templates, adds to solution, links projects |
| 2.3 | If Script Fails | Manual fallback — copy templates, replace placeholders |
| - | Template Files Reference | What each template contains |
| - | Success Criteria | Final checklist |

**Do not stop reading after Step 1.** If the tool is unavailable, you need Steps 2.1–2.10.

## Prerequisites

Before using this skill, you need:
- Path to the **old .NET Framework web project** (.csproj)
- Path to the **solution file** (.sln or .slnx) containing it
- **Target framework** for the new project (e.g., `net10.0`)
- **Project type**: MVC or WebAPI
- **New project name** (default: `{OldProjectName}.Core`)

## Step 1: Check for Existing Tool

First, check if `scaffold_yarp_proxy_web_project` tool is available in your
environment. If it is, use it — it handles everything automatically:

```
scaffold_yarp_proxy_web_project(
  solutionPath="{solution_path}",
  projectPath="{old_project_path}",
  targetFramework="{tfm}",
  targetProjectName="{new_name}",
  projectType="{MVC|WebAPI}"
)
```

If the tool is not available or fails, proceed with Step 2.

## Step 2: Scaffold Using Script + Templates

This skill includes template files and a PowerShell script that handles the mechanical work.
The LLM handles the parts that need judgment (finding the old app URL, resolving package versions).

### 2.1 Gather Parameters

⛔ **All parameters are mandatory.** The new project will not work correctly with the
old project unless every value is accurate. Do not use defaults without verifying them.

Before running the script, determine these values:

| Parameter | How to find it |
|-----------|---------------|
| `OldProjectPath` | Full path to the .NET Framework .csproj |
| `SolutionPath` | Full path to the .sln/.slnx file |
| `TargetFramework` | Upgrade TFM (e.g., `net10.0`) |
| `NewProjectName` | Name for new project (default: `{OldName}.Core`). Must be unique in the solution — check existing project names and folder names |
| `ProjectType` | `MVC` or `WebAPI` — match the old project's type |
| `OldAppUrl` | ⛔ **Must be the actual URL the old app runs on.** Find it in the old project's `Properties/launchSettings.json` (look for `applicationUrl` in the active profile), or in IIS/IIS Express bindings. Do NOT guess — if the proxy points to the wrong URL, all forwarded requests will fail silently. |
| `SystemWebAdaptersVersion` | ⛔ Use `get_supported_package_version` for `Microsoft.AspNetCore.SystemWebAdapters.CoreServices` |
| `YarpVersion` | ⛔ Use `get_supported_package_version` for `Yarp.ReverseProxy` |

**NewProjectName validation:**
- Must not match any existing project name in the solution
- The folder `{parent_of_old_project}/{NewProjectName}` must not already exist
- The script checks both conditions and fails with a clear error if violated
- The new project folder is always created as a **sibling** to the old project's folder

### 2.2 Run the Script

The script copies template files from `tmpl/mvc/` or `tmpl/webapi/`, applies
variable substitutions (`$TargetFramework$`, `$ProjectName$`, `$OldAppUrl$`, etc.),
adds the project to the solution, links the old project via `_MigrateToProjectGuid`,
and verifies the build.

```powershell
{skill_path}/scaffold-project.ps1 `
  -OldProjectPath "{OLD_PROJECT_PATH}" `
  -SolutionPath "{SOLUTION_PATH}" `
  -TargetFramework "{TFM}" `
  -NewProjectName "{NEW_PROJECT_NAME}" `
  -ProjectType "{MVC|WebAPI}" `
  -OldAppUrl "{OLD_APP_URL}" `
  -SystemWebAdaptersVersion "{VERSION}" `
  -YarpVersion "{VERSION}"
```

### 2.3 If Script Fails or Is Unavailable

If the script cannot be executed (e.g., PowerShell not available, permissions issue),
do the steps manually. The template files in `tmpl/mvc/` and `tmpl/webapi/`
contain the exact file contents — copy them to the new project folder and replace
the `$placeholder$` variables:

| Placeholder | Replace with |
|-------------|-------------|
| `$TargetFramework$` | Target framework (e.g., `net10.0`) |
| `$SystemWebAdaptersVersion$` | Package version from `get_supported_package_version` |
| `$YarpVersion$` | Package version from `get_supported_package_version` |
| `$ProjectName$` | New project name |
| `$HttpsPort$` | HTTPS port (pick 7100-7999, avoid old project's ports) |
| `$HttpPort$` | HTTP port (pick 5100-5999, avoid old project's ports) |
| `$NewPort$` | IIS Express HTTP port (pick 60000-65000) |
| `$NewSslPort$` | IIS Express SSL port (pick 44300-44399) |
| `$OldAppUrl$` | Old app's URL (e.g., `https://localhost:44319`) |

Then manually:
1. Rename `ProjectName.csproj` to `{NewProjectName}.csproj`
2. Run `dotnet sln "{SOLUTION_PATH}" add "{NEW_PROJECT_PATH}"`
3. Find the new project's GUID in the solution file
4. Add `<_MigrateToProjectGuid>{GUID}</_MigrateToProjectGuid>` to the old project's .csproj
5. Run `dotnet build` to verify

### Template Files Reference

```
tmpl/
  mvc/                         ← For MVC projects
    ProjectName.csproj         ← SDK-style web project with YARP + SystemWebAdapters packages
    Program.cs                 ← AddControllersWithViews + YARP forwarder + UseStaticFiles
    appsettings.json           ← Includes ProxyTo key
    appsettings.Development.json
    Properties/
      launchSettings.json      ← ProxyTo in environmentVariables
  webapi/                      ← For WebAPI projects
    ProjectName.csproj         ← Same packages, no Swashbuckle
    Program.cs                 ← AddControllers + YARP forwarder (no UseStaticFiles)
    appsettings.json
    appsettings.Development.json
    Properties/
      launchSettings.json
```

Key things the templates set up:
- `builder.Services.AddSystemWebAdapters()` — System.Web compatibility shims
- `builder.Services.AddHttpForwarder()` — YARP forwarder registration
- `app.UseSystemWebAdapters()` — middleware for adapter support
- `app.MapForwarder("/{**catch-all}", ...)` — catch-all route at lowest priority, forwards unmatched requests to old app

## Success Criteria

- [ ] New project folder created as sibling to old project folder
- [ ] .csproj has correct TFM and package references (latest versions)
- [ ] Program.cs has YARP forwarder and SystemWebAdapters registration
- [ ] appsettings.json has `ProxyTo` key
- [ ] launchSettings.json has `ProxyTo` pointing to the **verified** old app URL
- [ ] New project added to solution
- [ ] Old project has `_MigrateToProjectGuid` property pointing to new project
- [ ] New project builds with 0 errors

## Troubleshooting

If the scaffolded project doesn't work, tell the user to check:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Proxy returns 502/connection refused | `ProxyTo` URL is wrong or old app isn't running | Verify URL in `launchSettings.json` matches old app's actual URL; start old app first |
| New project won't build | Wrong TFM or package versions | Check `TargetFramework` matches installed SDK; verify package versions are compatible |
| Requests not forwarded | YARP middleware not registered | Check `Program.cs` has `AddHttpForwarder()` and `MapForwarder()` |
| Controllers return 404 | Routes not configured | Ensure `MapDefaultControllerRoute()` (MVC) or `MapControllers()` (WebAPI) is in `Program.cs` |
| `_MigrateToProjectGuid` missing | Script couldn't find GUID in solution | Manually find the project GUID in .sln/.slnx and add the property to old .csproj |
