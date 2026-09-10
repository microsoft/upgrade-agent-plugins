---
name: migrating-exchange-management-shell
description: >
  Migrate scripts that load the Exchange management snap-in
  (Microsoft.Exchange.Management.PowerShell.SnapIn / .E2010) off Windows
  PowerShell 5.1 to PowerShell 7.x, using implicit remoting
  (New-PSSession -ConfigurationName Microsoft.Exchange) for on-prem Exchange or
  the Exchange Online (EXO) REST-based module for Exchange Online. Use during the
  powershell-5.1-to-7-upgrade scenario for the Exchange snap-in bucket.
metadata:
  discovery: lazy
  traits: PowerShell
---

# Migrating the Exchange Management Shell (5.1 → 7.x)

The Exchange snap-in (`Microsoft.Exchange.Management.PowerShell.SnapIn`,
`.E2010`, `.Admin`) is a binary snap-in that **cannot load in PowerShell 7**.
This is the single most common — and hardest — blocker in Exchange-heavy repos.
The fix is to stop loading a snap-in and instead **connect to an Exchange
endpoint**, which works from any PowerShell edition.

## On-premises Exchange → implicit remoting

```powershell
# 5.1 (remove this)
Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn

# 7.x — connect to the Exchange remoting endpoint instead
$session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "http://<exchange-server>/PowerShell/" -Authentication Kerberos   # or Negotiate
Import-PSSession $session -DisableNameChecking -AllowClobber

# ... run Exchange cmdlets exactly as before ...

Remove-PSSession $session
```

The imported cmdlets keep the same names and parameters, so most script bodies
are unchanged. Objects come back **deserialized** — properties survive, methods
do not; rewrite any `$mbx.SomeMethod()` calls to use cmdlets.

## Exchange Online → EXO REST module

For Exchange Online, do not use WinRM remoting; use the REST-based module (works
natively on PS7):

```powershell
Install-Module ExchangeOnlineManagement    # once
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
# ... Exchange Online cmdlets ...
Disconnect-ExchangeOnline -Confirm:$false
```

Prefer the `-REST`-backed cmdlets (`Get-EXOMailbox`, `Get-EXORecipient`, …) where
available — they are faster and paginate better than the classic aliases.

## Migration steps per script

1. Delete the `Add-PSSnapin Microsoft.Exchange...` line(s).
2. Insert the correct connect block (on-prem remoting vs EXO) near the top.
3. Add the matching disconnect/cleanup at the end (and in a `finally`).
4. Parameterize the endpoint/credentials — do not hardcode servers or secrets.
5. Replace method calls on returned objects with cmdlet equivalents.

## Validation (Rung 4c — the honest limit)

Full behavioral parity needs a **live Exchange/EXO environment**, which this
agent does not own. Do:
- Rung 1/2: parse + PSScriptAnalyzer clean (no snap-in remains).
- Prove the **command surface** matches after connecting:
  ```powershell
  Get-Command Get-Mailbox | Select-Object -ExpandProperty Parameters
  ```
  Diff against the 5.1 parameter set.
- Use `-WhatIf` in a staging org for mutating cmdlets where supported.
- Otherwise record `needs-live-env` / `manual-signoff`. Do **not** claim runtime
  validation that requires infrastructure you cannot reach.
