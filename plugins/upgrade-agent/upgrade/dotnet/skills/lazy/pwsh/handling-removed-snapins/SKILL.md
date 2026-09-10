---
name: handling-removed-snapins
description: >
  Handle PowerShell snap-ins (Add-PSSnapin / Get-PSSnapin / Remove-PSSnapin) that
  do not exist in PowerShell 7.x. Provides the decision tree between module
  replacement, implicit remoting into a Windows PowerShell endpoint, and the
  Windows PowerShell compatibility layer. Use during the
  powershell-5.1-to-7-upgrade scenario for the PSSnapin blocker bucket. For the
  Exchange snap-in specifically, see migrating-exchange-management-shell.
metadata:
  discovery: lazy
  traits: PowerShell
---

# Handling Removed PSSnapins (PowerShell 7.x)

PowerShell **snap-ins do not exist** in PowerShell 7 — there is no
`Add-PSSnapin`. A snap-in is a binary DLL loaded into the Windows PowerShell 5.1
(.NET Framework) runtime; it cannot load into the PS7 (.NET) runtime. This is an
**architectural** change per snap-in, not a rewrite of syntax.

## Decision tree

For each `Add-PSSnapin X`:

0. **Is there a mapping for X?**
   If the finding's rule id is specific to the snap-in rather than the generic
   `snapin`, the answer is already known — an organisation contributed it (see
   *Organisation knowledge* in `scanning-powershell-compatibility`). Use the
   named module, or the named alternative when the map records that no module
   exists. Do not re-derive it; the person who wrote that row knows the estate
   better than `Get-Module -ListAvailable` does, and a probe on the migrating
   machine only proves what is installed *here*.

   A generic `snapin` finding means no mapping was contributed. Continue below,
   and say so — an unmapped in-house snap-in is a question for the user, not
   something to guess at.

1. **Is there a module replacement?**
   Many snap-ins were superseded by modules that DO load in PS7. Check
   `Get-Module -ListAvailable`. If so, replace:
   ```powershell
   Add-PSSnapin SomeSnapin   →   Import-Module SomeModule
   ```

2. **Is the snap-in Windows PowerShell-only with no PS7 module?**
   Use one of, best first:
   - **Implicit remoting** into a Windows PowerShell / product endpoint:
     ```powershell
     $s = New-PSSession -ComputerName Host -ConfigurationName SomeEndpoint
     Import-PSSession -Session $s -Module SomeModule
     ```
     This is the robust path for product shells (Exchange, etc.).
   - **Windows PowerShell compatibility layer — last resort:**
     ```powershell
     Import-Module SomeModule -UseWindowsPowerShell
     ```
     It proxies into a hidden `powershell.exe` (5.1) child process, so the
     script still requires Windows PowerShell locally and is still
     Windows-only. Record it as **deferred**, not remediated. Serialized
     objects lose live methods.

3. **No replacement and no endpoint?**
   The functionality must be re-implemented (e.g. call the product's REST/API
   directly) or the script stays on Windows PowerShell 5.1. Flag it explicitly.

## Record what you learn

When you resolve an unmapped snap-in — by asking the user, or by finding the
replacement module — that answer is worth more than the one fix it unblocks.
Offer to record it as a row in a `## Snapin Module Map` contribution skill under
`.github/skills/`, so every later scan of this estate names the replacement
instead of reporting a bare blocker. See *Organisation knowledge* in
`scanning-powershell-compatibility` for the format.

## Object fidelity caveat

Both the compat layer and implicit remoting return **deserialized** objects
(`Deserialized.*` types) — properties survive, **methods do not**. Rewrite code
that calls methods on returned objects to use cmdlets/parameters instead.

## Exchange

The Exchange management snap-in (`Microsoft.Exchange.Management.PowerShell.*`) is
the most common case and has its own path — see
`migrating-exchange-management-shell`.

## Validation

- Rung 2 confirms no `Add-PSSnapin` remains.
- Rung 3 (`Get-Command`) confirms the cmdlets resolve via the chosen path.
- Rung 4c: product cmdlets that mutate state need a live endpoint —
  prove the command surface matches, else `manual-signoff`.
