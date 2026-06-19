---
name: migrating-powershell-sdk
description: >
  Migrates the legacy System.Management.Automation (PowerShell SDK) references from obsolete
  .NET Framework (Windows PowerShell 5.1) to modern .NET (PowerShell 7+). Replaces Windows
  PowerShell Reference Assemblies or GAC references with the cross-platform
  System.Management.Automation NuGet package. Use ONLY when the legacy Windows PowerShell SDK
  has been flagged as obsolete or deprecated and must be replaced — not for version-bump
  scenarios where existing PowerShell packages are still supported. Triggers for "migrate
  PowerShell SDK", "upgrade cmdlet project", "PowerShellStandard.Library", project files
  (.csproj, .vbproj, .fsproj) with PowerShell references, and .psd1 module manifests.
metadata:
  discovery: lazy
  traits: .NET|CSharp|VisualBasic|DotNetCore
---

# System.Management.Automation Migration

## Overview

Migrate PowerShell cmdlet projects from .NET Framework (Windows PowerShell 5.1) to modern .NET (.NET 6+). The core change is replacing the Windows PowerShell reference assembly with the cross-platform `System.Management.Automation` NuGet package. Most code remains unchanged because the SDK types (`PSCmdlet`, `Cmdlet`, `PSObject`, attributes) are identical across both packages.

## Package Reference Changes

### Old References (Remove)

```xml
<!-- GAC/file reference -->
<Reference Include="System.Management.Automation" />

<!-- Windows PowerShell ref assemblies NuGet -->
<PackageReference Include="Microsoft.PowerShell.5.ReferenceAssemblies" Version="1.1.0" />
```

### New Reference (Add)

```xml
<!-- Cross-platform NuGet package; use version matching target framework -->
<PackageReference Include="System.Management.Automation" Version="{version-for-target-framework}" />

<!-- OR for dual-targeting Windows PowerShell 5.1 + PowerShell 7 -->
<PackageReference Include="PowerShellStandard.Library" Version="{stable-version}" />
```

### Choosing the Right Package

| Package | When to Use |
|---------|-------------|
| `System.Management.Automation` | Targeting a specific PowerShell 7.x version. Provides full API surface. |
| `PowerShellStandard.Library` | Must support both Windows PowerShell 5.1 and PowerShell 7+ from a single binary. Targets `netstandard2.0`. |

Use tools or [PowerShell releases](https://github.com/PowerShell/PowerShell/releases) to find the latest stable package version for the target framework.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect PowerShell SDK usage
- [ ] Step 2: Determine target framework and package version
- [ ] Step 3: Update project file references
- [ ] Step 4: Handle API differences
- [ ] Step 5: Update module manifest
- [ ] Step 6: Build and verify
```

### Step 1: Detect PowerShell SDK Usage

Scan the project for:
- `using System.Management.Automation;` statements
- Types inheriting from `Cmdlet` or `PSCmdlet`
- `[Cmdlet(...)]` attributes
- Reference type: GAC reference, `Microsoft.PowerShell.5.ReferenceAssemblies` NuGet, or direct file reference

If the project already uses the cross-platform NuGet package, no migration is needed.

### Step 2: Determine Target Framework and Package Version

1. Check if the user specified a target framework (e.g., "migrate to net10.0")
2. Otherwise, read `<TargetFramework>` or `<TargetFrameworks>` from the project file or `Directory.Build.props`
3. Look up the best `System.Management.Automation` package version for that framework
4. If the project must support both Windows PowerShell 5.1 and PowerShell 7+, choose `PowerShellStandard.Library` instead — it targets `netstandard2.0` so a single binary works in both hosts

### Step 3: Update Project File References

Remove old references and add the new package reference (see "Package Reference Changes" above).

### Step 4: Handle API Differences

Most SDK types are identical, but these APIs changed:

| Windows PowerShell | PowerShell 7+ | Action |
|-------------------|---------------|--------|
| `PSSnapIn` classes | Not supported | Convert to module manifests (`.psd1`). Snap-ins were deprecated because modules provide better isolation and discoverability. |
| `PSHost.NotifyBeginApplication` | May not be implemented | Guard with try/catch or remove the call |
| WinRM remoting APIs | Limited on non-Windows | Use SSH remoting for cross-platform scenarios |

### Step 5: Update Module Manifest (If Applicable)

If the project produces a PowerShell module, update the `.psd1`:

```powershell
@{
    PowerShellVersion     = '7.0'
    CompatiblePSEditions  = @('Core')
    ProcessorArchitecture = 'None'
}
```

### Step 6: Build and Verify

1. Build the module:
   ```
   dotnet build
   ```
2. Import and check cmdlet registration:
   ```powershell
   Import-Module ./bin/Debug/{target-framework}/MyModule.dll
   Get-Command -Module MyModule
   ```
3. Run cmdlet smoke tests to verify parameter binding and pipeline operations

## Troubleshooting

### Cmdlets Not Found After Import

Ensure the assembly contains `[Cmdlet]` attributes and the namespace is correctly exported in the module manifest.

### Type Conflicts with Other Modules

Another loaded module may bundle a different `System.Management.Automation` version. Use assembly load contexts or module isolation boundaries to resolve.

### Missing APIs at Runtime

Some Windows PowerShell APIs have no PowerShell 7 equivalent. Check the [PowerShell 7 SDK docs](https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/choosing-the-right-nuget-package) for alternatives.

### Snap-in Code

PowerShell 7 does not support snap-ins. Remove `PSSnapIn`-derived classes and replace with:
- Module manifests (`.psd1`) for metadata
- `RequiredModules` in the manifest for dependency management
