---
name: fixing-windows-only-modules
description: >
  Handle Windows PowerShell-only modules (ActiveDirectory, ServerManager,
  Hyper-V, FailoverClusters, BitLocker, NetSecurity, Dism, Storage,
  ScheduledTasks, WebAdministration) that are not natively available in
  PowerShell 7.x, using Import-Module -UseWindowsPowerShell (the WinPS
  compatibility layer) or implicit remoting. Use during the
  powershell-5.1-to-7-upgrade scenario for the Windows-only-module bucket.
metadata:
  discovery: lazy
  traits: PowerShell
---

# Fixing Windows-Only Modules (PowerShell 7.x)

Several in-box Windows modules ship only with Windows PowerShell 5.1 (they target
.NET Framework) and are not loaded natively by PowerShell 7. These are
**Manual**-severity: they usually keep working through a shim, but you must
choose and verify the shim per module.

Common ones: `ActiveDirectory`, `ServerManager`, `Hyper-V`, `FailoverClusters`,
`BitLocker`, `NetSecurity`, `Dism`, `Storage`, `ScheduledTasks`,
`WebAdministration`.

## Options (in order of preference)

1. **Native import — the only option that actually completes the upgrade.**
   Many of these are CDXML/CIM-based and DO load in PS7 on a Windows box with the
   RSAT/feature installed. Try a plain import first:
   ```powershell
   Import-Module ActiveDirectory   # works on PS7 with RSAT-AD-PowerShell installed
   ```

2. **A module built for PS7.** Some Windows PowerShell modules have a supported
   successor that targets PS7 directly — `WebAdministration` (IIS) →
   `IISAdministration` is the common one. Prefer the successor over any shim.

3. **Implicit remoting** to a server that has the module:
   ```powershell
   $s = New-PSSession -ComputerName Host
   Invoke-Command $s { Import-Module FailoverClusters }
   Import-PSSession $s -Module FailoverClusters -AllowClobber
   ```
   The dependency moves to a managed remote endpoint rather than to a local 5.1
   install, which is why it ranks above the compatibility layer.

4. **Windows PowerShell compatibility layer — last resort only.**
   ```powershell
   Import-Module Hyper-V -UseWindowsPowerShell
   ```
   This starts a hidden **Windows PowerShell 5.1 child process**
   (`powershell.exe`) and proxies the module's commands into it. The module is
   not ported and the 5.1 requirement is not removed — it is hidden. Use it only
   when 1-3 are genuinely unavailable, and record the result as **deferred**,
   never as remediated. Returned objects are deserialized: properties survive,
   methods do not, so audit every downstream `.Method()` call.

## Notes

- The compatibility layer only exists **on Windows** — none of this makes the
  script cross-platform. Record the target as Windows-bound.
- Installing the proper RSAT/optional feature and importing natively is worth
  real effort: it is the difference between a completed migration and a script
  that still needs Windows PowerShell 5.1 on every machine that runs it.
- If most of the estate can only be landed on option 4, report that as the
  finding. "Blockers cleared via the compatibility layer" is not a successful
  upgrade.

## Validation

- Rung 3 (`Get-Command <cmd> -ErrorAction Stop`) is the key gate here — record
  whether each command resolves **natively** or **only via -UseWindowsPowerShell**.
- Rung 4: read-only queries → 4b diff; state-changing cmdlets (AD writes, cluster
  failover, Hyper-V start/stop) → `manual-signoff` unless run in a sandbox.
