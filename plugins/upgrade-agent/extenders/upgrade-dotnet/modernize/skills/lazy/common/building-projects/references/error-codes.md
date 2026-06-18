# Build Error Codes Reference

## Contents

- [MSBuild Errors (MSB\*)](#msbuild-errors-msb)
- [.NET SDK Errors (NETSDK\*)](#net-sdk-errors-netsdk)
- [C# Compilation Errors (CS\*)](#c-compilation-errors-cs) — out of scope, see note
- [NuGet Errors (NU\*)](#nuget-errors-nu)
- [WPF / XAML Errors](#wpf--xaml-errors)
- [Resource Generation Errors](#resource-generation-errors)

---

## How to Use This File

1. **Identify the error category** from the prefix (MSB, NETSDK, NU, MC, XDG, XLS, RG)
2. **Jump to that section** and find the specific error code
3. **If the code isn't listed**, search the [Microsoft .NET error documentation](https://learn.microsoft.com/en-us/dotnet/core/tools/sdk-errors/) for NETSDK errors or the [MSBuild error reference](https://learn.microsoft.com/en-us/visualstudio/msbuild/errors/msb3086) for MSB errors
4. **If the error is CS\***, the build tool is correct — the problem is in the code, not the build infrastructure
5. **Increase verbosity** on the next build attempt (`-v:detailed` for `dotnet build`, `/v:diag` for `msbuild.exe`) to get more context
6. **Build the failing project in isolation** (not the full solution) to narrow the error surface

---

## MSBuild Errors (MSB\*)

| Error Code | Description | Common Cause | Recovery Action |
|------------|-------------|--------------|-----------------|
| MSB3086 | Task could not find resource generation tool | `dotnet build` using portable ResGen that can't handle image resources in `.resx` | Switch to `msbuild.exe` (full VS MSBuild) |
| MSB3552 | Resource file cannot be found | `.resx` references a file that's missing or has a wrong relative path | Verify the referenced file exists at the expected path; fix the `.resx` `<data>` entry |
| MSB4019 | Imported project was not found | Missing SDK, targets file, or build extension (e.g., `Microsoft.WinFX.targets`) | Install the required SDK/workload, or switch to `msbuild.exe` if it's a VS-only target |
| MSB4236 | SDK could not be resolved | `global.json` pins an SDK version that isn't installed | Install the pinned SDK version or update `global.json` |
| MSB3644 | Reference assemblies for framework not found | Targeting a .NET Framework version without the targeting pack installed | Install the targeting pack, or add `Microsoft.NETFramework.ReferenceAssemblies` NuGet package |
| MSB3270 | Processor architecture mismatch | Mixed `AnyCPU` and `x86`/`x64` references | Align `PlatformTarget` across referencing projects |
| MSB3277 | Found conflicts between different versions of the same assembly | Transitive dependency version conflicts | Add explicit `<PackageReference>` or binding redirects for the conflicting assembly |

## .NET SDK Errors (NETSDK\*)

| Error Code | Description | Common Cause | Recovery Action |
|------------|-------------|--------------|-----------------|
| NETSDK1005 | Assets file doesn't have a target for the specified framework | Project targets a TFM that wasn't restored (e.g., `net472` without reference assemblies) | Run `dotnet restore` explicitly; add `Microsoft.NETFramework.ReferenceAssemblies` if targeting .NET Framework |
| NETSDK1045 | Current .NET SDK does not support targeting the specified framework | SDK too old for the target TFM (e.g., SDK 8.0 trying to build `net10.0`) | Install the required .NET SDK version |
| NETSDK1064 | Package not compatible with target framework | A NuGet package doesn't support the project's TFM | Find a compatible package version or an alternative package |
| NETSDK1071 | PackageReference with explicit version found in project managed by central package management | Version specified in both the project file and `Directory.Packages.props` | Remove the `Version` attribute from the project's `<PackageReference>` |
| NETSDK1141 | Unable to resolve the .NET SDK version as specified in global.json | `global.json` `rollForward` policy is too restrictive | Relax the `rollForward` policy or install the exact SDK version |
| NETSDK1100 | Windows is required to build Windows desktop applications | Attempting to build WPF/WinForms on Linux/macOS | Build on Windows, or remove the Windows desktop SDK reference for cross-platform builds |

## C# Compilation Errors (CS\*)

C# compilation errors (CS0246, CS0234, CS1061, etc.) indicate **code-level issues**,
not build tool or configuration problems. This skill does not cover their resolution —
they are handled by the migration skills and the agent's code editing capabilities.

If a build fails with ONLY CS\* errors and no MSB/NETSDK/NU errors, the build tool
selection is correct — the problem is in the code, not the build infrastructure.

## NuGet Errors (NU\*)

| Error Code | Description | Common Cause | Recovery Action |
|------------|-------------|--------------|-----------------|
| NU1100 | Unable to resolve package | Package doesn't exist in configured sources | Check NuGet source configuration; verify package name spelling |
| NU1101 | Package not found on any source | Package name is wrong or the source requires authentication | Verify package name; check `nuget.config` for source credentials |
| NU1102 | Package version not found | Specific version doesn't exist | Use a valid version; check available versions on nuget.org |
| NU1202 | Package not compatible with target framework | Package doesn't support the project's TFM | Find a newer package version that supports the TFM, or find an alternative |
| NU1301 | Unable to load the service index for a source | NuGet source is unreachable | Check network connectivity; verify the source URL in `nuget.config` |
| NU1605 | Detected package downgrade | A transitive dependency pulls in a higher version than explicitly referenced | Update the explicit `<PackageReference>` to at least the transitive version |

## WPF / XAML Errors

| Error Code | Description | Common Cause | Recovery Action |
|------------|-------------|--------------|-----------------|
| MC1000 | Unknown build error in markup compilation | XAML parser failure, often from missing types or wrong namespaces | Verify XAML namespace declarations; ensure referenced types are available |
| XDG0008 | Unable to find type in XAML | Type referenced in XAML doesn't exist in the target TFM | Update the type reference or add the package containing the type |
| XLS0414 | Type not found in XAML namespace | Similar to XDG0008 — namespace mapping is wrong | Update `xmlns` declarations to point to the correct CLR namespace |

## Resource Generation Errors

| Error Code | Description | Common Cause | Recovery Action |
|------------|-------------|--------------|-----------------|
| MSB3086 | Resource generation task failed | `.resx` contains binary resources (images, icons) and `dotnet build`'s portable ResGen can't process them | Switch to `msbuild.exe`; or convert `.resx` to use `LogicalName` with precompiled resources |
| MSB3552 | Resource file not found | File path in `.resx` is wrong or the file was not included in the project | Fix the path in the `.resx` file; ensure the resource file is included |
| RG0000 | General ResGen failure | System.Drawing types in `.resx` that the .NET SDK ResGen doesn't understand | Switch to `msbuild.exe` which uses the full-framework ResGen |
