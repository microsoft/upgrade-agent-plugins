---
name: replacing-eventlog-with-winevent
description: >
  Replace the removed *-EventLog cmdlets (Get-EventLog, Write-EventLog,
  New-EventLog, Clear-EventLog, Limit-EventLog, Show-EventLog, Remove-EventLog)
  with Get-WinEvent / New-WinEvent or System.Diagnostics.EventLog in PowerShell
  7.x. Use during the powershell-5.1-to-7-upgrade scenario for the EventLog
  blocker bucket.
metadata:
  discovery: lazy
  traits: PowerShell
---

# EventLog → WinEvent Migration (PowerShell 7.x)

The classic `*-EventLog` cmdlets are **removed** in PowerShell 7. Use
`Get-WinEvent`/`New-WinEvent`, or the `System.Diagnostics.EventLog` .NET type
directly. These are Windows-only APIs — the scripts remain Windows-bound.

## Reading events

```powershell
# 5.1
Get-EventLog -LogName Application -Newest 50
Get-EventLog -LogName System -EntryType Error -After (Get-Date).AddDays(-1)

# 7.x — Get-WinEvent uses a FilterHashtable (much faster, server-side filter)
Get-WinEvent -FilterHashtable @{ LogName='Application' } -MaxEvents 50
Get-WinEvent -FilterHashtable @{ LogName='System'; Level=2; StartTime=(Get-Date).AddDays(-1) }
```

Property name changes to expect:
| Get-EventLog | Get-WinEvent |
|---|---|
| `EventID` | `Id` |
| `EntryType` | `LevelDisplayName` / `Level` (1=Critical,2=Error,3=Warning,4=Info) |
| `Source` | `ProviderName` |
| `TimeGenerated` | `TimeCreated` |
| `Message` | `Message` |

### `EntryType` and `Level` are different enums — translate, never pass through

`[System.Diagnostics.EventLogEntryType]` (what `-EntryType` took) and
`Get-WinEvent`'s `Level` do **not** share numbering:

| Meaning | `EventLogEntryType` | `Get-WinEvent` `Level` |
|---|---:|---:|
| Critical | — | 1 |
| Error | **1** | **2** |
| Warning | **2** | **3** |
| Information | **4** | **4** |

Forwarding an `EntryType` value straight into `Level` therefore asks for
*Critical* when the script meant *Error*, and *Error* when it meant *Warning*.
The script still parses, still passes Rung 2, and silently returns the wrong
events — a monitoring script goes blind. Only `Information` survives by
coincidence. Map explicitly:

```powershell
$levelMap = @{
    [System.Diagnostics.EventLogEntryType]::Error       = 2
    [System.Diagnostics.EventLogEntryType]::Warning     = 3
    [System.Diagnostics.EventLogEntryType]::Information = 4
}
```

### `Get-WinEvent` throws where `Get-EventLog` returned empty

A missing provider or a filter that matches nothing is a **terminating-style
error**, not an empty result. `-ErrorAction SilentlyContinue` is not sufficient:
the cmdlet emits several errors per call and one still reaches the host. Use
`try`/`catch` with `-ErrorAction Stop`:

```powershell
try   { $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $n -ErrorAction Stop }
catch { $events = @() }
```

Then iterate with `foreach ($e in $events)`, **not** `$events | ForEach-Object`
— piping `$null` runs the block once with `$_ = $null`, which turns "no events"
into a null-reference error.

## Writing events

`Write-EventLog`/`New-EventLog` are gone. Use the .NET type:

```powershell
# Create a source once (needs admin)
if (-not [System.Diagnostics.EventLog]::SourceExists('MyApp')) {
    [System.Diagnostics.EventLog]::CreateEventSource('MyApp', 'Application')
}
# Write
[System.Diagnostics.EventLog]::WriteEntry('MyApp', 'message', [System.Diagnostics.EventLogEntryType]::Information, 1000)
```

Or `New-WinEvent` when the provider is manifest-based.

## Admin / clear operations

`Clear-EventLog`, `Limit-EventLog`, `Remove-EventLog` have no direct PS7 cmdlet.
Use `System.Diagnostics.EventLog` (`.Clear()`, `MaximumKilobytes`) or
`wevtutil.exe` for advanced cases.

## Validation

- Rung 2 (PSScriptAnalyzer `PSUseCompatibleCommands`) confirms no `*-EventLog`
  remains. It cannot see an `EntryType`→`Level` mistranslation — that is a
  data-correctness bug, not a compatibility one, so a green Rung 2 does **not**
  clear this migration.
- Rung 4: reading is safe to diff (4b) and you should diff it — compare the
  event ids/timestamps returned by the 5.1 and 7.x versions for the same filter,
  not just the row count. Writing/clearing mutates the log — validate in a
  sandbox or mark `manual-signoff`.
