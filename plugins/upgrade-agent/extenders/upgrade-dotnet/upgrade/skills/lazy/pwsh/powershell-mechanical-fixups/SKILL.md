---
name: powershell-mechanical-fixups
description: >
  Apply low-risk, deterministic PowerShell 5.1 → 7.x fixes across scripts:
  '-Encoding Byte' → '-AsByteStream', hardcoded 'powershell.exe' → 'pwsh',
  removing 'New-WebServiceProxy', bumping '#Requires -Version 5' / dropping
  '-PSEdition Desktop', pinning explicit '-Encoding' on file writes (the
  default changed to UTF-8 no-BOM in PS7), and rewriting fragile '$x -eq $null'
  to '$null -eq $x'.
  Use during the powershell-5.1-to-7-upgrade scenario's execution stage to clear
  the AutoFix-severity findings before tackling architectural blockers.
metadata:
  discovery: lazy
  traits: PowerShell
---

# PowerShell Mechanical Fix-ups (5.1 → 7.x)

Deterministic rewrites for the **AutoFix**-severity findings from the
`scanning-powershell-compatibility` scan. Apply these first: they are low-risk and
shrink the noise before the architectural blockers.

## Fixes

### 1. `-Encoding Byte` → `-AsByteStream`
`Get-Content`/`Set-Content` dropped the `Byte` encoding value in PS7.

```powershell
# 5.1
Get-Content $path -Encoding Byte
Set-Content $path -Encoding Byte -Value $bytes
# 7.x
Get-Content $path -AsByteStream
Set-Content $path -AsByteStream -Value $bytes
```

If the script also passes `-Raw`, keep it. `-AsByteStream` already returns the
raw byte array.

### 2. Hardcoded `powershell.exe` → `pwsh`
`powershell.exe` always launches Windows PowerShell 5.1. Use `pwsh` to invoke
PowerShell 7. Watch for:
- Nested invocations: `Start-Process powershell.exe`, `& 'powershell.exe'`,
  scheduled-task actions, `Invoke-Command`.
- Do **not** blindly change paths that *intentionally* target 5.1 (rare — call
  it out and confirm).

### 3. Remove `New-WebServiceProxy`
Removed in PS7. Replace with `Invoke-RestMethod`/`Invoke-WebRequest` against the
endpoint, or a generated WCF client. This is not purely mechanical — flag each
call site for the SOAP/REST replacement decision.

### 4. `#Requires` version pin
`#Requires -Version` states a **minimum**, so `#Requires -Version 5.1` does not
block PowerShell 7 — the script still runs. It is stale metadata worth
correcting, not a blocker. `#Requires -PSEdition Desktop` **is** a blocker:
PowerShell 7 is edition Core and refuses to run the script at all.

Once a script is PS7-clean, update the directive. Use `7.0` as the **floor** —
it is the edition gate (any PowerShell 7 is Core/.NET), not a pin to a specific
minor. Only raise the floor above 7.0 if the script actually uses a feature
introduced in a later 7.x:

```powershell
# 5.1
#Requires -Version 5.1
#Requires -PSEdition Desktop
# 7 (Core)
#Requires -Version 7.0
# (drop -PSEdition Desktop; add -PSEdition Core only if truly Core-only)
```
Bump the version **after** the script passes validation, not before. Raising the
floor is what stops the script silently regressing back onto Windows PowerShell.

### 5. Pin `-Encoding` on file writes
The highest-impact silent break in this migration, and the one no parse or
compatibility rule will catch: **the default output encoding changed**. The
script keeps running and the bytes on disk change.

| Write site | Windows PowerShell 5.1 default | PowerShell 7 default | Same bytes for pure ASCII? |
|---|---|---|---|
| `Out-File`, `>`, `>>`, `Tee-Object -FilePath` | **UTF-16LE with BOM** (`FF FE …`) | UTF-8 without BOM | **No** — every byte changes |
| `Set-Content`, `Add-Content` | ANSI (the system code page) | UTF-8 without BOM | Yes — differs only for non-ASCII |
| `Export-Csv` | ASCII (non-ASCII is **lost** as `?`) | UTF-8 without BOM | Yes — 7 stops corrupting non-ASCII |
| `Export-Clixml` | **UTF-16LE with BOM** | UTF-8 without BOM | **No** — every byte changes |
| `Out-File -Encoding UTF8` | UTF-8 **with** BOM | UTF-8 without BOM | No — BOM disappears |

Measured on 5.1 and 7.6 with the literal content `abc`; do not restate this table
from memory, it is counter-intuitive. The redirection operators and `Out-File`
are **not** ANSI in 5.1 — treating them as ANSI is the single most damaging
mistake available here, because it is the highest-volume finding class.

Consequences to look for: a downstream tool that reads the file with the system
code page now sees mojibake for non-ASCII text; a consumer that requires a BOM
(some Windows tooling, Excel opening a CSV) no longer finds one; and a file
compared byte-for-byte in a test now differs.

The fix is to make the encoding explicit rather than to adopt the new default:

```powershell
# implicit — meaning changes between 5.1 and 7
$data | Set-Content $path
$data | Out-File $path -Encoding UTF8       # BOM in 5.1, no BOM in 7

# explicit — same bytes on both
$data | Set-Content $path -Encoding utf8BOM   # or: ansi / utf8NoBOM / unicode
$data | Out-File     $path -Encoding unicode  # reproduces the 5.1 bytes exactly
```

`>` and `>>` take no `-Encoding`; a site that must keep its 5.1 bytes has to be
rewritten as `| Out-File -Encoding unicode`.

Pin whatever the **consumer** needs, not whatever the script used to emit by
accident. `utf8NoBOM` is the right answer for anything Git-tracked or read by
cross-platform tooling; `utf8BOM` for legacy Windows consumers. For an
`Out-File`/redirection site whose consumer is unknown, `unicode` is the
byte-preserving choice — `ansi` is **not**, and never was.
`$PSDefaultParameterValues` can set it once per script, but an explicit
parameter at each call site survives refactoring better.

Note `-Encoding ansi` and `utf8BOM`/`utf8NoBOM` are PS7-only spellings; if a
script must run under **both** editions, use `-Encoding` values that exist in
both (`ascii`, `unicode`, `utf7`, `utf8`, `utf32`, `bigendianunicode`, `oem`)
and accept that `utf8` differs on BOM.

### 6. Fragile `$null` comparison
`$x -eq $null` unrolls arrays and misbehaves. Rewrite with `$null` on the left:

```powershell
if ($x -eq $null)  →  if ($null -eq $x)
if ($x -ne $null)  →  if ($null -ne $x)
```
This is **Advisory**, not a completion gate — offer it as an optional batch. Be
careful not to rewrite matches inside strings/comments.

## Validation

After applying, re-run the `scanning-powershell-compatibility` scan on the touched
files to confirm the AutoFix findings cleared, then climb the scenario's validation
ladder (parse → PSScriptAnalyzer).
