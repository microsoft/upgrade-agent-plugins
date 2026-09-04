---
name: migrating-wmi-to-cim
description: >
  Migrate removed WMI cmdlets and type accelerators to CIM in PowerShell 7.x:
  Get-WmiObject → Get-CimInstance, Invoke-WmiMethod → Invoke-CimMethod,
  Remove-WmiObject → Remove-CimInstance, Register-WmiEvent → Register-CimIndicationEvent,
  and [wmi]/[wmiclass]/[wmisearcher] accelerators. Use during the
  powershell-5.1-to-7-upgrade scenario for the WMI blocker bucket.
metadata:
  discovery: lazy
  traits: PowerShell
---

# WMI → CIM Migration (PowerShell 7.x)

All `*-WmiObject`/`*-Wmi*` cmdlets and the `[wmi*]` type accelerators are
**removed** in PowerShell 7. Migrate to the CIM cmdlets (`CimCmdlets` module,
shipped in-box).

## Cmdlet mapping

| Windows PowerShell 5.1 | PowerShell 7.x |
|---|---|
| `Get-WmiObject -Class X` | `Get-CimInstance -ClassName X` |
| `Get-WmiObject -Query "..."` | `Get-CimInstance -Query "..."` |
| `Invoke-WmiMethod` | `Invoke-CimMethod` |
| `Set-WmiInstance` | `Set-CimInstance` / `New-CimInstance` |
| `Remove-WmiObject` | `Remove-CimInstance` |
| `Register-WmiEvent` | `Register-CimIndicationEvent` |
| `[wmi]"path"` | `Get-CimInstance` by key |
| `[wmiclass]"class"` | `Get-CimClass` / `Invoke-CimMethod` |
| `[wmisearcher]"query"` | `Get-CimInstance -Query` |

## Key differences (do not do a blind rename)

1. **`-Class` → `-ClassName`.** The parameter name changed.
2. **Return type differs.** CIM returns `Microsoft.Management.Infrastructure.CimInstance`,
   not `System.Management.ManagementObject`. Downstream property access usually
   works, but:
   - Method invocation changes: `$obj.SomeMethod($a)` (WMI) →
     `Invoke-CimMethod -InputObject $obj -MethodName SomeMethod -Arguments @{ Param = $a }`.
   - `DateTime` and some enums render differently — verify consumers.
3. **Remote access.** `-ComputerName` on WMI used DCOM. CIM defaults to
   **WSMan**; for DCOM-only targets create a session:
   ```powershell
   $opt = New-CimSessionOption -Protocol Dcom
   $s = New-CimSession -ComputerName $c -SessionOption $opt
   Get-CimInstance Win32_Service -CimSession $s
   ```
4. **Filtering.** `-Filter "Name='x'"` works on both; prefer it over
   client-side `Where-Object` for performance.

## Example

```powershell
# 5.1
$svc = Get-WmiObject -Class Win32_Service -Filter "Name='Spooler'"
$svc.StopService()

# 7.x
$svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'"
Invoke-CimMethod -InputObject $svc -MethodName StopService
```

## Validation (Rung 4b)

WMI→CIM is read-mostly and best validated by diffing the **selected properties
actually consumed**, not raw objects:

```powershell
$old = Get-WmiObject Win32_LogicalDisk | Select DeviceID,FreeSpace   # on a 5.1 box
$new = Get-CimInstance Win32_LogicalDisk | Select DeviceID,FreeSpace # on pwsh 7
Compare-Object $old $new -Property DeviceID,FreeSpace
```
Record `read-only-diff-clean` when the consumed properties match.
