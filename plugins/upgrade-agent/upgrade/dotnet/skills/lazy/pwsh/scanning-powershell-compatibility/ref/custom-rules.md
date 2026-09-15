# Custom Rules and Snap-in Maps

Read when extending the catalog, loading contributed compatibility knowledge, or
projecting mappings supplied by the user. The normal scan workflow stays in SKILL.md.

## Contents

- [Extending the catalog](#extending-the-catalog)
- [Organisation knowledge](#organisation-knowledge-contributed-rules-and-snap-in-maps)
- [A mapping given in conversation](#a-mapping-given-in-conversation)
- [Asking for missing mappings](#asking-for-the-mappings-you-are-missing)

## Extending the catalog

The rules live in `rules/PSCompatibilityRules.psd1` relative to the skill root as **data**, loaded with
`Import-PowerShellDataFile`, which parses restricted data-language literals and
never evaluates code. A rule file therefore cannot execute anything — keep it
that way. If a rule needs behaviour, it needs a new `Kind` implemented in the
script, not code smuggled into the data.

There are two ways in, and they are not equivalent:

| | Use when |
|---|---|
| `-AdditionalRulesPath <file>` | You want the shipped rules **plus** your own. Merged on top of the base catalog: a rule whose `Id` matches a shipped one replaces it, anything else is added. This is almost always what you want. |
| `-RulesPath <file>` | You want to replace the catalog outright. You then own a fork that will not pick up new shipped rules. |

Never edit the shipped file inside a customer repo.

A rule is:

```powershell
@{
    Id          = 'contoso-legacy-module'
    Kind        = 'Module'
    Match       = @('Contoso.Legacy.Admin')
    Category    = 'InternalModule'
    Severity    = 'Blocker'
    Remediation = 'Contoso.Legacy.Admin is .NET Framework only. Use Contoso.Admin 3.x.'
    Skill       = 'fixing-windows-only-modules'
}
```

Available `Kind` values, and what each matches:

| Kind | Matches |
|---|---|
| `Command` | A name in command position — cmdlet, function, or alias. Aliases must be listed explicitly (`gwmi` alongside `Get-WmiObject`). |
| `Keyword` | A language keyword, e.g. `workflow`. |
| `Type` | A type literal. `MatchMode = 'Exact'` compares the accelerator (`wmi`); `'Contains'` compares the full name (`System.Windows.Forms`). Also covers the type argument of `New-Object`, in both positional and `-TypeName` form. |
| `StringLiteral` | A substring of a string constant. Context-blind by design: it also matches prose, log messages and test data, so it suits high-recall rules that are triaged manually, not `AutoFix` ones. Prefer `CommandArgument` or `MemberAccess` where the shape is known. |
| `CommandArgument` | A literal passed as an argument to one of `OnCommand`. Anchored, so `Add-PSSnapin Foo` matches but `Write-Host 'Foo'` does not. |
| `MemberAccess` | A property or method name in `$x.Member` position. Only literal member names are checked; a computed `$x.$name` is skipped rather than guessed at. |
| `StaticMember` | A static member together with its owning type, written `Text.Encoding::Default`. `Match` is a dotted suffix, so it fires on both `[System.Text.Encoding]::Default` and `[Text.Encoding]::Default` without matching an unrelated `MyText.Encoding`. Use it instead of `MemberAccess` when the member name alone is too common to be meaningful — `::Default` on its own would match anything. |
| `Parameter` | A named parameter present on one of `OnCommand`. Prefixes resolve. |
| `ParameterValue` | `OnParameter` set to one of `Match`, on one of `OnCommand`. |
| `MissingParameter` | One of `OnCommand` invoked *without* the parameter. Splatted calls are never reported. |
| `Module` | A module name in `Import-Module`, `using module`, or `#Requires -Modules`. |
| `RequiresEdition` | `#Requires -PSEdition <value>`. |
| `RequiresVersion` | `#Requires -Version <major>`. |
| `NullComparison` | Structural: `-eq`/`-ne` with `$null` on the right. |
| `FileRedirection` | Structural: a `>` or `>>` redirection to a file. `Match` selects the operators. Stream merges (`2>&1`) are a different AST type and never match; `> $null` is excluded explicitly. Any stream that writes a file — including `2>` — is reported. |

`Supersedes` suppresses a more general rule when a specific one fires on the
same line — `exchange-snapin` supersedes `snapin`, so
`Add-PSSnapin Microsoft.Exchange.Management.PowerShell.E2010` is one finding,
not two. This is *intra-catalog*: both rules belong to this scan.

`SupersededBy` is the opposite direction and crosses tools. It names a
PSScriptAnalyzer rule that was **measured** to report the same sites, and it
takes the rule out of detection entirely: the rule no longer runs and emits
nothing. Its body becomes a knowledge record that
`Invoke-PSSACompatibilityScan.ps1` joins onto the analyzer's own findings, and a
source of profile contamination sentinels. Do not set it by guesswork — probe the
rule's targets against a validated profile first, with `-IncludeRule`, and only
tag what comes back fully covered. Tagging a rule PSSA does *not* report silently
deletes a detector.

`Skill` names the remediation skill to load for that bucket. The planner emits
it as a `#skill:` marker on the task.

## Organisation knowledge: contributed rules and snap-in maps

Writing a `.psd1` is fine for someone who has read this file. It is the wrong
ask for the person who actually knows the answer — the owner of an internal
snap-in. So a user contributes knowledge the same way they contribute anything
else in this product: **a skill in `.github/skills/`**, discovered
automatically. No flag to pass, nothing to tell the agent.

This mirrors the existing `upgrade-option:` and `provides: task-breakdown-hints`
conventions.

A contribution skill declares `provides: powershell-compatibility-rules` in its
description:

```markdown
---
name: contoso-powershell-map
description: >
  Contoso snap-in and module inventory for the PowerShell 5.1 → 7 migration.
  provides: powershell-compatibility-rules
metadata:
  discovery: lazy
  traits: PowerShell
---

## Snapin Module Map

| Snap-in | Replacement module | Notes |
|---|---|---|
| Contoso.Foo.Snapin | Contoso.Foo.Management | 3.x or later |
| Contoso.Bar.Snapin | — | No module. Use implicit remoting. |
```

**Before running the scan**, check Available Skills for that marker. For each
matching skill, read its `## Snapin Module Map` and project every row into a
rule, then pass the projected file as `-AdditionalRulesPath`:

```powershell
@{
    Id          = 'contoso-foo-snapin'          # stable, derived from the snap-in name
    Kind        = 'StringLiteral'
    Match       = @('Contoso.Foo.Snapin')
    MatchMode   = 'Contains'
    Category    = 'PSSnapin'
    Severity    = 'Blocker'
    Supersedes  = @('snapin')                   # so the generic rule does not double-count
    Remediation = 'Replace Add-PSSnapin Contoso.Foo.Snapin with Import-Module Contoso.Foo.Management (3.x or later).'
    Skill       = 'handling-removed-snapins'
}
```

Write the projected catalog to the operation folder
(`.github/upgrades/<scenarioId>/contributed-rules.psd1`), not into the source
tree.

A `—`, `none`, or empty Replacement column is **meaningful, not missing**: it
says a module replacement was looked for and does not exist. Project it with a
remediation naming implicit remoting or the Windows PowerShell compatibility
layer rather than telling the migrator to go find a module. This is the main
thing the shipped catalog cannot express — it only knows that *some* snap-in was
loaded, never which one or what replaces it.

A snap-in with no row falls through to the generic `snapin` rule, which is the
correct outcome: it is still reported as a Blocker, just without a specific
remediation.

Other sections a contribution skill may carry:

- `## Compatibility Rules` — a fenced `powershell` block containing raw rule
  hashtables, for knowledge that is not a snap-in mapping. Pass it through as-is.

Use the same `Id` as a shipped rule to correct one in place — severity, wording,
or an internal policy call. The scan reports what was added and what was
overridden, so a merged catalog never silently changes the result.

### A mapping given in conversation

A skill is the right shape for an inventory an organisation maintains. It is
overkill for someone who knows two snap-ins and wants to say so. If the user
states a mapping in conversation — "`Contoso.Foo.Snapin` is `ContosoFoo` now",
"`Contoso.Legacy.Snapin` has no replacement" — project it into the **same**
`contributed-rules.psd1` and pass it the same way.

Do this rather than just remembering it. A mapping that only lives in the
conversation changes how you *remediate* but not what the scan *reports*, so the
CSV still says `snapin`, the assessment still counts an unnamed blocker, and the
execution re-scan gate compares against a baseline that disagrees with what the
user told you. Every artifact must reflect the same knowledge.

Precedence, most specific last: shipped catalog → contribution skills → what the
user said in this conversation. The user is in front of you and knows their
estate; if they contradict a contributed skill, they win — but say that you are
overriding it, and name the skill.

Conversation-sourced rules are **per operation**, not permanent: they live in the
operation folder and a fresh clone starts without them. When the user gives you
one, offer once to promote it into a `provides: powershell-compatibility-rules`
skill so it survives. Do not nag — offer, and drop it if declined.

### Asking for the mappings you are missing

Do not expect the user to know upfront which snap-ins matter. Let the scan find
out, then ask.

After the scan, if there are generic `snapin` findings, pull the distinct
snap-in names out of their `Snippet` column and present that list. It is short,
concrete, and it is the one question in this whole assessment where the user
holds information you cannot derive. Ask for a replacement module or an explicit
"no replacement" for each, project the answers, and re-run the scan so the
findings carry the specific rule ids.

Re-run only if you actually received mappings — a re-scan that changes nothing
is pure cost on a large estate.
