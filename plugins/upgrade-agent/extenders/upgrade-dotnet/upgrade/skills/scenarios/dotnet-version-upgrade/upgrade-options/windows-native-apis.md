# Windows Native APIs

**Category**: Compatibility

**Applicable when**:
- Windows-specific API usage detected, such as:
  - P/Invoke / `DllImport` calls to Windows DLLs
  - `Microsoft.Win32` namespace usage
  - `System.Drawing` (GDI+) usage
  - `System.Windows.Forms` usage
  - `System.Runtime.InteropServices` with Windows-specific structs
  - Windows-only NuGet packages
  - Registry access (`RegistryKey`, `Registry`)

**Not applicable when**:
- No Windows-specific API usage detected
- Solution already targets Windows explicitly (`<TargetFramework>net8.0-windows</TargetFramework>`)

**Default logic**:
- Recommend **Windows Compatibility Pack** if:
  - Multiple Windows API usages spread across codebase (impractical to fix immediately), OR
  - Team has no immediate cross-platform requirement
- Recommend **No Compatibility Pack** if:
  - 1-2 isolated usages with clear cross-platform alternatives, OR
  - Team explicitly requires Linux/container deployment from day one

**Options**:
- **Windows Compatibility Pack** *(default when applicable)* — adds
  `Microsoft.Windows.Compatibility` package. Enables Windows APIs in .NET Core.
  App remains Windows-only until APIs are replaced. Defers cross-platform work.
- **No Compatibility Pack** — Windows API build errors surface immediately.
  Must be replaced with cross-platform alternatives. Enables Linux/container
  compatibility from the start.

**Stored as**: `Upgrade Options > Compatibility > Windows Native APIs`

**Affects**: Package additions in scaffold tasks, cross-platform eligibility of solution.
